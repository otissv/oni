# Draw

Oni draw is a **CPU-recorded, GPU-batched** immediate-mode painter. During the **Draw** pass (the second walk inside `o.Render`, which itself runs in the [`present_frame`](../present.odin#L16) draw callback), widgets read solved layout rects and emit geometry into a frame batch; after `Render` returns, `present_frame` uploads and flushes the GPU.

Coordinates are logical design pixels. DPI scale is applied at clip/scissor conversion and in the orthographic projection — not inside individual `draw_*` calls. Artboard content is zoomed/panned via [`view_transform_rect`](../view.odin#L162) / [`view_transform_point`](../view.odin#L180) when the draw space stack is `.ARTBOARD`.

## Mental model

1. Host [`present_frame`](../present.odin#L16) wraps the app draw callback. The app usually calls [`o.Render`](../api.odin#L118) once; each builder runs Layout, then Draw ([`render`](../ui.odin#L213)).
2. On **Draw**, widgets call [`widget_prepare_draw`](../widgets/widget_lifecycle.odin#L118), read [`ui_layout_rect`](../ui.odin#L255) (and layout-owned text/image results), set [`draw_set_stack_index`](../widget.odin#L765), then emit `Draw_*` commands.
3. Inside [`present_frame`](../present.odin#L16):
   - [`draw_record_begin`](../draw.odin#L87) → app/`Render` records (Layout + Draw) into the current ping-pong [`Batch_State`](../batch.odin#L55)
   - [`draw_record_end`](../draw.odin#L98) → [`batch_finalize_segments`](../batch.odin#L718) (sort by draw space, stack index and submission order)
   - deferred texture uploads → swapchain acquire → [`batch_upload`](../batch.odin#L766) → render pass → [`draw_flush`](../draw.odin#L119) → [`batch_reset`](../batch.odin#L253) + [`batch_flip`](../batch.odin#L99)
4. Primitives never talk to SDL directly — they append [`UI_Vertex`](../gpu.odin#L14) data and segment keys; the UI shader ([`../shaders/ui.vert`](../shaders/ui.vert), [`../shaders/ui.frag`](../shaders/ui.frag)) rasterizes solid, textured, line, rounded, and text-coverage modes ([`Draw_Mode`](../batch.odin#L8)).

When vector submissions are present, `vector_gpu_present` interleaves UI and vectors in a content-bounded shared 4× MSAA target, prepares isolated composition targets, resolves and blits to the swapchain. UI-only frames use `present_ui_frame` directly. Vector preparation failures can omit the failed submission and replay within bounded budgets, preserving UI where possible. See [VECTOR.md](VECTOR.md) for resource limits and release status.

**Critical timing:** `o.Render` runs **inside** `present_frame`’s draw callback (Layout then Draw). Geometry is recorded on Draw **before** GPU upload. Layout must be solved and stack order finalized ([`ui_end_layout_pass`](../ui.odin#L156)) before paint.

**Stack order:** layout assigns `stack_index` per node ([`layout_finalize_stack_order`](../layout_stack.odin#L444)); widgets set it via [`draw_set_stack_index`](../widget.odin#L765) before emitting geometry. Segments sort by draw space first, then `stack_index`, then submission sequence (with `first_index` as a tie-break). Compatible adjacent vector submissions may merge after sorting.

## Frame flow

```
run_frame                          oni/runtime.odin
  input_begin_frame / poll
  ui_begin_frame                   pass = Layout
  tick(dt)
  present_frame(draw)
    assets_io_drain                adopt completed image decodes
    draw_record_begin
    draw()                         app_draw → o.Render(main_ui)
      Layout pass                  first u(); End_* → layout_end_space
      ui_end_layout_pass           stack / hit / tab → Draw
      Draw pass                    second u(); paint + input on_*
        Begin_Screen / Begin_Artboard
          draw_push_space          SCREEN or ARTBOARD
        widgets:
          widget_prepare_draw
          draw_set_stack_index     from ui_layout_stack_index
          Draw_Rectangle / Draw_Texture / font_draw_layout_text / …
            batch_push_*           CPU vertices + indices
          Children                 same tree as Layout
        End_Screen / End_Artboard
      ui_end_frame                 prune widgets for this builder
    draw_record_end                batch_finalize_segments (sort)
    assets_io_drain / texture_uploads_flush   publish uploaded assets Ready
    vector_gpu_present?            shared MSAA path when vectors were recorded
    otherwise present_ui_frame:
      AcquireGPUCommandBuffer
      WaitAndAcquireGPUSwapchainTexture
      batch_upload                 transfer VB/IB
      BeginGPURenderPass
        draw_begin
        draw_flush                 batch_flush_draws (per segment)
        draw_end
      SubmitGPUCommandBuffer
    batch_reset + batch_flip       ping-pong to other Batch_State slot
  end_frame
```

### Host shell

| Proc | Role |
|------|------|
| [`run_frame`](../runtime.odin#L27) | One host frame: begin UI → tick → present → end |
| [`present_frame`](../present.odin#L16) | Record draw (incl. `Render`), upload, flush GPU, flip batch |
| [`render`](../ui.odin#L213) / [`Render`](../api.odin#L118) | Per-builder Layout + Draw |
| [`ui_end_layout_pass`](../ui.odin#L156) | Layer/anchor, stack, hit, focus/tab → Draw |
| [`draw_record_begin`](../draw.odin#L87) / [`draw_record_end`](../draw.odin#L98) | Frame batch recording boundaries |
| [`draw_begin`](../draw.odin#L107) / [`draw_flush`](../draw.odin#L119) / [`draw_end`](../draw.odin#L128) | Bind GPU pass, issue draws, unbind |

The proc tables below are a navigation reference, not an exhaustive inventory; the linked source is authoritative. App code should call `o.Render(...)` once. Low-level `draw_record_*` / `draw_begin` / `draw_flush` run inside [`present_frame`](../present.odin#L16).

## Two passes (draw side)

| Concern | Layout | Draw |
|--------|--------|------|
| Tree walk | Register nodes, measure, solve | Same structure; no new layout nodes |
| Rects | Written | Read via [`ui_layout_rect`](../ui.odin#L255) |
| Text / image geometry | Shaped in layout | Read via [`layout_text_result`](../layout.odin#L2400) / [`layout_image_result`](../layout.odin#L2423) |
| GPU | Avoid | `Draw_*`, events |
| Opacity / space stacks | `Begin_Screen` / `Begin_Artboard` push draw space + style | Same pushes (must match Layout) |
| Paint skip | `visibility: HIDDEN` → `paint_skip` | [`ui_layout_paint_skip`](../layout_stack.odin#L125) |
| Stack index | Assigned in [`layout_finalize_stack_order`](../layout_stack.odin#L444) | [`ui_layout_stack_index`](../layout_stack.odin#L115) → [`draw_set_stack_index`](../widget.odin#L765) |

### Widget draw pattern

Canonical shape in [`Button`](../widgets/button.odin#L70):

```odin
if o.ui_pass() == .Layout {
	// widget_run_layout_lifecycle → Children → return
	return
}
if !widget_prepare_draw(...) do return
rect := o.ui_layout_rect(layout_id)
// resolve colors, borders, radius from config + event
got_focus, lost_focus := widget_handle_interaction(...)  // sets stack index
o.Draw_Push_Opacity(config.opacity)
defer o.Draw_Pop_Opacity()
if !o.ui_layout_paint_skip(layout_id) {
	o.Draw_Rectangle(rect, ...)
}
o.Children(child, ...)
widget_dispatch_events(...)
```

Leaf [`Text`](../widgets/text.odin#L129) dispatches events **before** paint so early returns still deliver handlers. Parents dispatch **after** `Children` so pointer bubbling is child → parent.

## Coordinate spaces

| Space | Draw stack | Layout bounds | Transform at paint |
|-------|------------|---------------|-------------------|
| `.SCREEN` | [`draw_push_screen`](../draw.odin#L323) | Window logical size | Identity |
| `.ARTBOARD` | [`begin_artboard`](../draw.odin#L299) | Content area ÷ zoom | [`view_transform_rect`](../view.odin#L162) / [`view_transform_point`](../view.odin#L180) |
| `.OVERLAY` | `begin_overlay` | Window logical size | Identity; above popovers (Dialog/framework chrome) |
| `.POPOVER` | [`begin_popover`](../draw.odin#L348) | Window logical size | Identity (paints/hits above screen + artboard) |

| Proc | Role |
|------|------|
| [`draw_push_space`](../draw.odin#L205) / [`draw_pop_space`](../draw.odin#L223) | Batch space stack |
| [`draw_current_space`](../draw.odin#L164) | Active space (default `.SCREEN`) |
| [`Begin_Screen`](../api.odin#L112) → [`draw_push_screen`](../draw.odin#L323) | Screen space + layout region (Layout only) |
| [`End_Screen`](../api.odin#L113) → [`draw_pop_screen`](../draw.odin#L335) | Pop screen |
| [`Begin_Artboard`](../api.odin#L110) → [`begin_artboard`](../draw.odin#L299) | Artboard space + layout region |
| [`End_Artboard`](../api.odin#L111) → [`end_artboard`](../draw.odin#L312) | Pop artboard |
| [`Popover_Begin`](../api.odin#L114) → [`begin_popover`](../draw.odin#L348) | Popover overlay space + layout region |
| [`Popover_End`](../api.odin#L115) → [`end_popover`](../draw.odin#L360) | Pop popover |
| [`view_artboard_zoom`](../view.odin#L188) | Scale radii / borders / line thickness on artboard |
| [`draw_space_to_logical`](../view.odin#L200) | Screen point → artboard logical (rounded UV local space) |
| [`screen_to_logical`](../draw.odin#L20) / [`logical_to_screen`](../draw.odin#L31) | DPI pixel ↔ logical (input / hit helpers) |

View camera (pan/zoom) lives in [`View`](../view.odin#L8). Changing zoom/pan invalidates batch view cache and layout artboard zoom ([`view_set_zoom`](../view.odin#L67), [`view_set_pan`](../view.odin#L77), [`view_zoom_at_screen`](../view.odin#L114), [`view_reset`](../view.odin#L150)).

## Batch recording

CPU-side batching groups geometry into **segments** keyed by texture/sampler bindings, scissor clip, and `stack_index` ([`Batch_Key`](../batch.odin#L30)).

```
draw_rect / draw_texture / draw_line / font_draw_layout_text
  batch_check_key(texture_id)     split segment on key change
  batch_push_axis_quad / batch_push_quad / batch_push_atlas_quads
    view_transform_rect             artboard → screen
    batch_current_clip              intersect clip stack + viewport
    draw_effective_opacity          multiply vertex alpha
    append UI_Vertex + indices
draw_record_end
  batch_finalize_segments           close last segment; sort by space/stack/sequence
present_frame
  batch_upload                      copy VB/IB to GPU
  batch_flush_draws                 bind pipeline, texture, scissor; indexed draw per segment
```

### Ping-pong buffers

[`GPU_State.batches`](../gpu.odin) holds two [`Batch_State`](../batch.odin#L55) slots. [`batch_flip`](../batch.odin#L99) toggles after each successful present so frame N+1 records into the other slot while frame N's GPU buffers may still be in flight. Swapchain acquire ([`WaitAndAcquireGPUSwapchainTexture`](../present.odin)) is the sync point.

### Clip and opacity stacks

| Proc | Role |
|------|------|
| [`draw_push_clip`](../draw.odin#L139) / [`draw_pop_clip`](../draw.odin#L149) | Logical clip stack (intersected in [`batch_current_clip`](../batch.odin#L338)) |
| [`batch_current_clip`](../batch.odin#L338) | Top clip ∩ viewport, view-transformed; cached until invalidation |
| [`clip_to_scissor`](../batch.odin#L837) | Logical clip → SDL scissor pixels for each segment |
| [`draw_push_opacity`](../draw.odin#L247) / [`draw_pop_opacity`](../draw.odin#L265) | CSS-like nested opacity multiply |
| [`draw_effective_opacity`](../draw.odin#L289) / [`Draw_Effective_Opacity`](../api.odin#L103) | Product of opacity stack |
| [`clamp_opacity`](../style.odin#L208) | Clamp to [0, 1] |

`Layout_Clip_Rect` exposes the solved cumulative overflow clip. `Draw_Push_Layout_Clip(layout_id)` pushes it and returns whether a matching `Draw_Pop_Clip` is required. Shared widget scroll-content handling uses this around descendants; custom draw code must balance its own clip scopes. Textured quads additionally trim geometry/UVs against the active clip, and GPU segments use scissor rectangles.

### Segment key and ordering

| Proc | Role |
|------|------|
| [`batch_set_stack_index`](../batch.odin#L370) | Set `current_stack` for subsequent geometry |
| [`batch_check_key`](../batch.odin#L381) | Start new segment when texture / clip / stack changes |
| [`batch_finalize_segments`](../batch.odin#L718) | Finalize index counts; sort by draw space, `stack_index`, submission `sequence`, then `first_index` |
| [`batch_flush_draws`](../batch.odin#L868) | Draw each segment with its texture + scissor |

## Primitives (`oni/draw.odin`)

Public API aliases in [`oni/api.odin`](../api.odin).

| Proc | Role |
|------|------|
| [`draw_rect`](../draw.odin#L397) / [`Draw_Rectangle`](../api.odin#L83) | Filled and/or bordered rounded rect (white texture, `.Solid`) |
| [`draw_line`](../draw.odin#L443) / [`Draw_Line`](../api.odin#L95) | Thick line segment as a quad (`.Line`) |
| [`draw_texture`](../draw.odin#L472) / [`Draw_Texture`](../api.odin#L96) | Textured rect; falls back to `draw_rect`; `.Textured` or `.Textured_Rounded` |
| [`draw_texture_fitted`](../draw.odin#L567) / [`Draw_Texture_Fitted`](../api.odin#L97) | Object-fit paint from layout `content` / `image_dst`; clips to content |
| [`draw_atlas_region`](../draw.odin#L528) / [`Draw_Atlas`](../api.odin#L98) | Atlas sub-rect → `draw_texture` |

Helpers:

| Proc | Role |
|------|------|
| [`rect_contains`](../draw.odin#L43) | Half-open point-in-rect |
| [`rect_intersect`](../draw.odin#L52) | Axis-aligned overlap (used for fitted texture clip) |

Radii and border widths are multiplied by [`view_artboard_zoom`](../view.odin#L188) before reaching the shader.

## Batch internals (`oni/batch.odin`)

| Proc | Role |
|------|------|
| [`batch_current`](../batch.odin#L89) | Active ping-pong `Batch_State` |
| [`batch_init`](../batch.odin#L137) / [`batch_destroy`](../batch.odin#L198) | Allocate / free CPU + GPU batch resources |
| [`batch_create_gpu_buffers`](../batch.odin#L153) | Create/resize VB/IB |
| [`batch_reset`](../batch.odin#L253) | Clear per-frame CPU data (keeps GPU capacity) |
| [`batch_delete_cpu_arrays`](../batch.odin#L108) | Test teardown helper |
| [`batch_ensure_capacity`](../batch.odin#L318) | Grow VB/IB when vertex count exceeds capacity |
| [`batch_invalidate_clip_cache`](../batch.odin#L276) / [`batch_invalidate_view_cache`](../batch.odin#L284) | Drop cached clip/view products |
| [`batch_cached_view`](../batch.odin#L295) | Cached artboard zoom + pan for transforms |
| [`draw_mode_f32`](../batch.odin#L19) | Pack `Draw_Mode` into vertex `params` |
| [`batch_push_vertex`](../batch.odin#L458) | Append one `UI_Vertex` |
| [`batch_push_indices`](../batch.odin#L441) | Two triangles for a quad |
| [`batch_push_quad`](../batch.odin#L494) | Four corners + indices; applies opacity |
| [`batch_push_axis_quad`](../batch.odin#L592) | Axis-aligned rect; textured modes clip to `batch_current_clip` and adjust UVs |
| [`batch_push_atlas_quads`](../batch.odin#L672) | Many atlas quads, one `batch_check_key` |
| [`batch_upload`](../batch.odin#L766) | Transfer VB/IB to GPU |

## GPU pipeline (`oni/gpu.odin`)

| Proc | Role |
|------|------|
| [`gpu_init`](../gpu.odin#L610) | Pipeline, sampler, 1×1 white texture, batches, projection |
| [`gpu_reload`](../gpu.odin#L698) | Recreate GPU resources after hot reload |
| [`gpu_destroy`](../gpu.odin#L573) | Release pipeline, sampler, textures, batch buffers |
| [`gpu_create_pipeline`](../gpu.odin#L345) | UI graphics pipeline from backend-matched embedded shaders ([SHADERS.md](SHADERS.md)) |
| [`gpu_load_shader`](../gpu.odin#L70) | Load vert/frag bytecode |
| [`gpu_ui_vertex_layout`](../gpu.odin#L204) | Vertex attribute layout matching `UI_Vertex` |
| [`gpu_blend_state`](../gpu.odin#L152) | Straight-alpha UI blending; vector fragments use separate premultiplied blending |
| [`gpu_create_sampler`](../gpu.odin#L428) | Linear sampler for UI textures |
| [`gpu_create_white_texture`](../gpu.odin#L494) | 1×1 white for solid draws |
| [`gpu_upload_white_pixel`](../gpu.odin#L457) | Upload opaque white texel |
| [`gpu_update_projection`](../gpu.odin#L560) | Ortho matrix from logical viewport + DPI |

## Text draw (`oni/font.odin`)

Layout owns line positions, glyph quads and decoration segments, and obtains shaped lines through the persistent shape cache ([`Layout_Text`](../layout.odin#L55)). Draw ensures missing glyphs and emits quads. A warm shape-cache lookup avoids HarfBuzz work for unchanged face/text/spacing/tab/wrap/direction inputs; layout marks borrowed lines so frame teardown does not free them. DPI changes, font changes and reload invalidate cached shaping.

Gray and LCD glyphs have separate cache keys. LCD uses the dual-source pipeline only when `Should_Use_Lcd` permits it for the current opacity/transform/DPI; other text uses gray coverage. The SDL GPU device must still support dual-source blending at initialization. Atlas recovery, worker ownership and prefetch are documented in [ATLAS.md](ATLAS.md).

| Proc | Role |
|------|------|
| [`font_draw_layout_text`](../font.odin#L1908) | Paint layout glyphs via atlas; underline/strike via `draw_line` |
| [`font_ensure_glyphs_from_paint`](../font.odin#L2101) | Rasterize uncached glyphs referenced by layout paint quads |
| [`font_ensure_glyphs`](../font.odin#L810) | Ensure shaped glyph set is in atlas |
| [`font_rasterize_glyph`](../font.odin#L1570) / [`font_rasterize_and_cache_missing`](../font.odin#L1511) | FreeType rasterize → atlas pack |
| [`font_resolve`](../font.odin#L143) | Resolve face + size (artboard applies zoom / layout scale) |
| [`snap_logical`](../font.odin#L1848) | Device-pixel snap for glyph placement (`round(v * dpi) / dpi`) |
| [`font_glyph_paint_from_entry`](../font.odin#L1860) | Atlas bitmap size/bearings → logical paint quad |
| [`font_text_uses_nearest_filter`](../font_shaper.odin#L877) | NEAREST atlas sampling when integer DPI + no artboard zoom |

[`Text`](../widgets/text.odin#L129) widget: [`layout_text_result`](../layout.odin#L2400) → [`font_draw_layout_text`](../font.odin#L1908) with resolved text and decoration colors.

## Textures and atlas (`oni/texture.odin`)

| Proc | Role |
|------|------|
| [`texture_uploads_flush`](../texture.odin#L743) | Upload deferred textures before GPU geometry (called from `present_frame`) |
| [`texture_register_surface`](../texture.odin#L392) | Register image asset |
| [`texture_upload_surface`](../texture.odin#L879) / [`texture_upload_surface_deferred`](../texture.odin#L626) | Immediate vs deferred GPU upload |
| [`texture_get_gpu`](../texture.odin#L937) | `GPUTexture` for batch flush |
| [`texture_handle`](../texture.odin#L952) | Logical `Texture_Handle` for `draw_texture` |
| [`atlas_region_from`](../texture.odin#L1122) / [`atlas_region_handle`](../texture.odin#L1131) | Atlas sub-region helpers |
| [`texture_atlas_init`](../texture.odin#L1432) / [`texture_atlas_alloc`](../texture.odin#L1757) / [`texture_atlas_upload`](../texture.odin#L1825) | Font/glyph shelf atlas |
| [`texture_atlas_pack`](../texture.odin#L1912) | Pack arbitrary surface into atlas |

`Load_Texture` is asynchronous: acceptance does not imply pixels are ready. Retain the generation-checked handle, wait for `Texture_Status(handle) == .Ready`, and fetch current dimensions with `Get_Texture(handle.id)`. Pending/Failed textures have zero intrinsic size. Balance every accepted load with `Unload_Texture`, including duplicate path loads; use `Retry_Texture` for failures and release `Texture_Error` diagnostics with `Texture_Error_Free`. Worker decode completion and GPU upload publication are separate steps. See [APP.md#section-4--assets--gpu-textures](APP.md#section-4--assets--gpu-textures).

[`Image`](../widgets/image.odin#L177): chrome via `Draw_Rectangle`; fitted bitmap via [`layout_image_result`](../layout.odin#L2423) → [`Draw_Texture_Fitted`](../api.odin#L97). Author-side fit math: [`texture_fit_rects`](../widget.odin#L1856).

## Table borders (draw path)

Layout resolves collapsed border winners ([`table_layout_resolve_collapsed_borders`](../table_border.odin#L189)); draw paints strips and rounded fills.

| Proc | Role |
|------|------|
| [`table_widget_draw_chrome`](../widgets/table_shared.odin#L22) | Table widget family paint entry |
| [`table_draw_collapsed_cell`](../table_border.odin#L648) | Collapsed cell fill + strip borders |
| [`table_draw_border_strip`](../table_border.odin#L409) | Single border segment → `draw_rect` |
| [`table_descendant_outer_radius`](../table_border.odin#L501) | Inherit table corner radii on descendants |
| [`table_merge_radius_corners`](../table_border.odin#L428) | Max per-corner radius |
| [`table_collapsed_border_color`](../table_border.odin#L391) | Resolve winning border color |
| [`table_layout_borders_collapsed_for_widget`](../table_border.odin#L303) | Whether widget uses collapsed path |

## Style colors (draw inputs)

| Proc | Role |
|------|------|
| [`to_rgba`](../colors.odin#L78) | Resolve `Colors` (theme tokens, procs, concrete) |
| [`style_color_rgba`](../colors.odin#L206) | Text color |
| [`style_background_rgba`](../colors.odin#L218) | Background fill |
| [`style_border_color_rgba`](../colors.odin#L230) | Border stroke |
| [`style_text_decoration_color_rgba`](../colors.odin#L242) | Underline / strike color |
| [`style_cache_concrete_rgba`](../colors.odin#L192) | Cache resolved concrete colors on style |
| [`color_to_f32`](../colors.odin#L130) / [`rgba_to_f32`](../colors.odin#L23) | Pack for vertices |

## Interaction during draw

Draw pass updates hover/focus and dispatches events (not layout).

| Proc | Role |
|------|------|
| [`widget_handle_interaction`](../widgets/widget_interaction.odin#L91) | Hit test, press state, stack index, focus transitions |
| [`widget_dispatch_events`](../widgets/widget_interaction.odin#L159) | Pointer, focus, keyboard handlers |
| [`pointer_hits`](../widget.odin#L728) / [`pointer_is_target`](../widget.odin#L739) | Hit vs layout-resolved pointer target |
| [`stop_propagation`](../widget.odin#L757) / [`Stop_Propagation`](../api.odin#L269) | Block bubbled pointer events this frame |
| [`consume_hover_transition`](../widget.odin#L787) | Enter/leave edges |

## Key types

| Type | File | Role |
|------|------|------|
| `Draw_Mode` | [oni/batch.odin](../batch.odin) | `.Solid`, `.Textured`, `.Line`, `.Textured_Rounded`, `.Textured_Text` (gray/LCD sampling selected by segment state) |
| `UI_Vertex` | [oni/gpu.odin](../gpu.odin) | pos, uv, local_uv, colors, radii, border, mode params |
| `Batch_State` / `Batch_Key` / `Batch_Segment` | [oni/batch.odin](../batch.odin) | CPU record + segment metadata |
| `GPU_State` / `GPU_Proj_UBO` | [oni/gpu.odin](../gpu.odin) | Pipeline, sampler, projection, ping-pong batches |
| `Draw_Space` | [oni/types.odin](../types.odin) | `.SCREEN`, `.ARTBOARD`, `.POPOVER`, `.OVERLAY` |
| `Texture_Handle` / `Atlas_Region` | [oni/types.odin](../types.odin) | Bitmap sources for `draw_texture` |
| `View` | [oni/view.odin](../view.odin) | Artboard camera zoom/pan/clamps |
| `Layout_Glyph_Paint` / `Layout_Decoration_Stroke` | [oni/layout.odin](../layout.odin) | Layout-owned text paint inputs |
| `Layout_Text` / `Layout_Image` | [oni/layout.odin](../layout.odin) | Layout-owned text/image paint geometry |
| `Draw_Proc` | [oni/present.odin](../present.odin) | `proc()` app draw callback type |

## Public API aliases (`oni/api.odin`)

| Alias | Target |
|-------|--------|
| [`Draw_Rectangle`](../api.odin#L83) | `draw_rect` |
| [`Draw_Line`](../api.odin#L95) | `draw_line` |
| [`Draw_Texture`](../api.odin#L96) | `draw_texture` |
| [`Draw_Texture_Fitted`](../api.odin#L97) | `draw_texture_fitted` |
| [`Draw_Atlas`](../api.odin#L98) | `draw_atlas_region` |
| [`Draw_Push_Opacity`](../api.odin#L99) / [`Draw_Pop_Opacity`](../api.odin#L100) | opacity stack |
| [`Draw_Effective_Opacity`](../api.odin#L103) | effective opacity product |
| [`Draw_Set_Stack_Index`](../api.odin#L268) | `draw_set_stack_index` |
| [`Layout_Stack_Index`](../api.odin#L234) / [`Layout_Paint_Skip`](../api.odin#L235) / [`Layout_Clip_Rect`](../api.odin#L237) | draw-time layout queries |
| [`View_*`](../api.odin) | artboard camera controls |

## Widget entry points

These branch on [`ui_pass`](../ui.odin#L246) and paint on Draw:

[`Button`](../widgets/button.odin#L70), [`Rectangle`](../widgets/rectangle.odin#L64) ([`draw_widget_rectangle`](../widgets/rectangle.odin#L211)), [`Text`](../widgets/text.odin#L129), [`Image`](../widgets/image.odin#L177), [`Tabs`](../widgets/tabs.odin#L113), [`Tabs_List`](../widgets/tabs_list.odin#L127), [`Tabs_Trigger`](../widgets/tabs_trigger.odin#L185), [`Tabs_Content`](../widgets/tabs_content.odin#L117), [`Table`](../widgets/table.odin#L69), [`Table_Caption`](../widgets/table_caption.odin#L66), [`Table_Head`](../widgets/table_head.odin#L72), [`Table_Heading`](../widgets/table_heading.odin#L72), [`Table_Body`](../widgets/table_body.odin#L72), [`Table_Row`](../widgets/table_row.odin#L73), [`Table_Cell`](../widgets/table_cell.odin#L71), [`Table_Foot`](../widgets/table_foot.odin#L72) — table family chrome via [`table_widget_draw_chrome`](../widgets/table_shared.odin#L22).

## Proc reference (`oni/draw.odin`)

Coordinates: [`screen_to_logical`](../draw.odin#L20), [`logical_to_screen`](../draw.odin#L31), [`rect_contains`](../draw.odin#L43), [`rect_intersect`](../draw.odin#L52).

Recording / GPU bridge: [`draw_record_begin`](../draw.odin#L87), [`draw_record_end`](../draw.odin#L98), [`draw_begin`](../draw.odin#L107), [`draw_flush`](../draw.odin#L119), [`draw_end`](../draw.odin#L128).

Stacks: [`draw_push_clip`](../draw.odin#L139), [`draw_pop_clip`](../draw.odin#L149), [`draw_current_space`](../draw.odin#L164), [`draw_push_space`](../draw.odin#L205), [`draw_pop_space`](../draw.odin#L223), [`draw_push_opacity`](../draw.odin#L247), [`draw_pop_opacity`](../draw.odin#L265), [`draw_effective_opacity`](../draw.odin#L289).

Spaces: [`begin_artboard`](../draw.odin#L299), [`end_artboard`](../draw.odin#L312), [`draw_push_screen`](../draw.odin#L323), [`draw_pop_screen`](../draw.odin#L335), [`begin_popover`](../draw.odin#L348), [`end_popover`](../draw.odin#L360).

Primitives: [`draw_rect`](../draw.odin#L397), [`draw_line`](../draw.odin#L443), [`draw_texture`](../draw.odin#L472), [`draw_atlas_region`](../draw.odin#L528), [`draw_texture_fitted`](../draw.odin#L567).

## Proc reference (`oni/batch.odin`)

Lifecycle: [`draw_mode_f32`](../batch.odin#L19), [`batch_flip`](../batch.odin#L99), [`batch_delete_cpu_arrays`](../batch.odin#L108), [`batch_init`](../batch.odin#L137), [`batch_create_gpu_buffers`](../batch.odin#L153), [`batch_destroy`](../batch.odin#L198), [`batch_reset`](../batch.odin#L253).

Cache / clip: [`batch_invalidate_clip_cache`](../batch.odin#L276), [`batch_invalidate_view_cache`](../batch.odin#L284), [`batch_cached_view`](../batch.odin#L295), [`batch_current_clip`](../batch.odin#L338), [`clip_to_scissor`](../batch.odin#L837).

Record: [`batch_ensure_capacity`](../batch.odin#L318), [`batch_set_stack_index`](../batch.odin#L370), [`batch_check_key`](../batch.odin#L381), [`batch_push_indices`](../batch.odin#L441), [`batch_push_vertex`](../batch.odin#L458), [`batch_push_quad`](../batch.odin#L494), [`batch_push_axis_quad`](../batch.odin#L592), [`batch_push_atlas_quads`](../batch.odin#L672).

Upload / draw: [`batch_finalize_segments`](../batch.odin#L718), [`batch_upload`](../batch.odin#L766), [`batch_flush_draws`](../batch.odin#L868).

## Proc reference (`oni/view.odin`)

Defaults / zoom: [`view_default`](../view.odin#L24), [`view_quantize_zoom`](../view.odin#L31), [`view_quantize_zoom_with_step`](../view.odin#L41), [`view_effective_zoom`](../view.odin#L49), [`view_clamp_zoom`](../view.odin#L58), [`view_set_zoom`](../view.odin#L67), [`view_zoom_at_screen`](../view.odin#L114), [`view_zoom_by_screen`](../view.odin#L128), [`view_zoom_in_screen`](../view.odin#L136), [`view_zoom_out_screen`](../view.odin#L143), [`view_reset`](../view.odin#L150).

Pan: [`view_set_pan`](../view.odin#L77), [`view_pan_by`](../view.odin#L86).

Transforms: [`view_screen_to_world`](../view.odin#L95), [`view_world_to_screen`](../view.odin#L105), [`view_transform_rect`](../view.odin#L162), [`view_transform_point`](../view.odin#L180), [`view_artboard_zoom`](../view.odin#L188), [`draw_space_to_logical`](../view.odin#L200).

## Proc reference (`oni/present.odin`)

[`present_frame`](../present.odin#L16).

## Proc reference (`oni/gpu.odin`)

[`gpu_load_shader`](../gpu.odin#L70), [`gpu_blend_state`](../gpu.odin#L152), [`gpu_ui_vertex_layout`](../gpu.odin#L204), [`gpu_create_pipeline`](../gpu.odin#L345), [`gpu_create_sampler`](../gpu.odin#L428), [`gpu_upload_white_pixel`](../gpu.odin#L457), [`gpu_create_white_texture`](../gpu.odin#L494), [`gpu_update_projection`](../gpu.odin#L560), [`gpu_destroy`](../gpu.odin#L573), [`gpu_init`](../gpu.odin#L610), [`gpu_reload`](../gpu.odin#L698).

## Proc reference (`oni/font.odin` — draw path)

[`font_draw_layout_text`](../font.odin#L1908), [`font_ensure_glyphs_from_paint`](../font.odin#L2101), [`font_ensure_glyphs`](../font.odin#L810), [`font_rasterize_and_cache_missing`](../font.odin#L1511), [`font_rasterize_glyph`](../font.odin#L1570), [`font_resolve`](../font.odin#L143), [`font_atlas_reset`](../font.odin#L237), [`snap_logical`](../font.odin#L1848).

## Proc reference (`oni/texture.odin`)

[`texture_init`](../texture.odin#L298), [`texture_shutdown`](../texture.odin#L312), [`texture_release_gpu`](../texture.odin#L350), [`texture_reload_gpu`](../texture.odin#L371), [`texture_register_surface`](../texture.odin#L392), [`texture_upload_record`](../texture.odin#L456), [`texture_surface_as_rgba8888`](../texture.odin#L514), [`texture_fill_transfer_from_surface`](../texture.odin#L542), [`texture_create_filled_transfer`](../texture.odin#L596), [`texture_upload_surface_deferred`](../texture.odin#L626), [`texture_uploads_flush`](../texture.odin#L743), [`texture_upload_surface`](../texture.odin#L879), [`texture_get_gpu`](../texture.odin#L937), [`texture_handle`](../texture.odin#L952), [`atlas_region_from`](../texture.odin#L1122), [`atlas_region_handle`](../texture.odin#L1131), [`texture_atlas_init`](../texture.odin#L1432), [`texture_atlas_shutdown`](../texture.odin#L1471), [`texture_atlas_rebuild_gpu`](../texture.odin#L1506), [`texture_atlas_alloc`](../texture.odin#L1757), [`texture_atlas_upload`](../texture.odin#L1825), [`texture_atlas_pack`](../texture.odin#L1912).

## Proc reference (`oni/table_border.odin` — draw path)

[`table_draw_border_strip`](../table_border.odin#L409), [`table_draw_collapsed_cell`](../table_border.odin#L648), [`table_descendant_outer_radius`](../table_border.odin#L501), [`table_merge_radius_corners`](../table_border.odin#L428), [`table_collapsed_border_color`](../table_border.odin#L391), [`table_side_is_straight`](../table_border.odin#L564), [`table_layout_borders_collapsed_for_widget`](../table_border.odin#L303).

Layout-side collapse (inputs to draw): [`table_gaps_are_collapsed`](../table_border.odin#L3), [`table_border_source_rank`](../table_border.odin#L7), [`table_border_compare`](../table_border.odin#L21), [`table_border_pick_winner`](../table_border.odin#L42), [`table_border_side_width`](../table_border.odin#L53), [`table_border_side_from_node`](../table_border.odin#L67), [`table_layout_cell_ancestors`](../table_border.odin#L83), [`table_layout_append_side_candidates`](../table_border.odin#L113), [`table_layout_collect_edge_candidates`](../table_border.odin#L127), [`table_border_strip_rect`](../table_border.odin#L174), [`table_layout_resolve_collapsed_borders`](../table_border.odin#L189), [`table_layout_find_cell_neighbor`](../table_border.odin#L316), [`table_f32_max`](../table_border.odin#L416), [`table_corners_touch`](../table_border.odin#L420).

## Draw-adjacent (`oni/widget.odin`, `oni/widgets/`)

| Proc | Role |
|------|------|
| [`draw_set_stack_index`](../widget.odin#L765) | Public batch stack setter |
| [`texture_fit_rects`](../widget.odin#L1856) | Object-fit rect math (layout + image draw) |
| [`widget_prepare_draw`](../widgets/widget_lifecycle.odin#L118) | Draw gate + lifecycle sync |
| [`widget_handle_interaction`](../widgets/widget_interaction.odin#L91) | Draw-pass input + stack index |
| [`widget_dispatch_events`](../widgets/widget_interaction.odin#L159) | Handler dispatch |
| [`table_widget_draw_chrome`](../widgets/table_shared.odin#L22) | Shared table paint |
| [`draw_widget_rectangle`](../widgets/rectangle.odin#L211) | Rectangle chrome + children |
