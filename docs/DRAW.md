# Draw

Oni draw is a **CPU-recorded, GPU-batched** immediate-mode painter. During the **Draw** pass (the second walk inside `o.Render`, which itself runs in the [`present_frame`](../present.odin#L16) draw callback), widgets read solved layout rects and emit geometry into a frame batch; after `Render` returns, `present_frame` uploads and flushes the GPU.

Coordinates are logical design pixels. DPI scale is applied at clip/scissor conversion and in the orthographic projection — not inside individual `draw_*` calls. Artboard content is zoomed/panned via [`view_transform_rect`](oni/view.odin#L162) / [`view_transform_point`](oni/view.odin#L180) when the draw space stack is `.ARTBOARD`.

## Mental model

1. Host [`present_frame`](../present.odin#L16) wraps the app draw callback. The app usually calls [`o.Render`](../api.odin#L102) once; each builder runs Layout, then Draw ([`render`](../ui.odin#L208)).
2. On **Draw**, widgets call [`widget_prepare_draw`](../widgets/widget_lifecycle.odin#L118), read [`ui_layout_rect`](../ui.odin#L240) (and layout-owned text/image results), set [`draw_set_stack_index`](../widget.odin#L742), then emit `Draw_*` commands.
3. Inside [`present_frame`](../present.odin#L16):
   - [`draw_record_begin`](../draw.odin#L66) → app/`Render` records (Layout + Draw) into the current ping-pong [`Batch_State`](../batch.odin#L52)
   - [`draw_record_end`](../draw.odin#L77) → [`batch_finalize_segments`](../batch.odin#L690) (sort by `stack_index`)
   - deferred texture uploads → swapchain acquire → [`batch_upload`](../batch.odin#L738) → render pass → [`draw_flush`](../draw.odin#L98) → [`batch_reset`](../batch.odin#L242) + [`batch_flip`](../batch.odin#L93)
4. Primitives never talk to SDL directly — they append [`UI_Vertex`](../gpu.odin#L14) data and segment keys; the UI shader ([`../shaders/ui.vert`](../shaders/ui.vert), [`../shaders/ui.frag`](../shaders/ui.frag)) rasterizes solid, textured, line, rounded, and text-coverage modes ([`Draw_Mode`](../batch.odin#L8)).

**Critical timing:** `o.Render` runs **inside** `present_frame`’s draw callback (Layout then Draw). Geometry is recorded on Draw **before** GPU upload. Layout must be solved and stack order finalized ([`ui_end_layout_pass`](../ui.odin#L151)) before paint.

**Stack order:** layout assigns `stack_index` per node ([`layout_finalize_stack_order`](oni/layout_stack.odin#L444)); widgets set it via [`draw_set_stack_index`](oni/widget.odin#L742) before emitting geometry. Segments with a higher `stack_index` are sorted to draw later (on top).

## Frame flow

```
run_frame                          oni/runtime.odin
  input_begin_frame / poll
  ui_begin_frame                   pass = Layout
  tick(dt)
  present_frame(draw)
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
    texture_uploads_flush          deferred GPU texture uploads
    AcquireGPUCommandBuffer
    WaitAndAcquireGPUSwapchainTexture
    batch_upload                   transfer VB/IB
    BeginGPURenderPass
      draw_begin
      draw_flush                   batch_flush_draws (per segment)
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
| [`render`](../ui.odin#L208) / [`Render`](../api.odin#L102) | Per-builder Layout + Draw |
| [`ui_end_layout_pass`](../ui.odin#L151) | Layer/anchor, stack, hit, focus/tab → Draw |
| [`draw_record_begin`](../draw.odin#L66) / [`draw_record_end`](../draw.odin#L77) | Frame batch recording boundaries |
| [`draw_begin`](../draw.odin#L86) / [`draw_flush`](../draw.odin#L98) / [`draw_end`](../draw.odin#L107) | Bind GPU pass, issue draws, unbind |

App code should call `o.Render(...)` once. Low-level `draw_record_*` / `draw_begin` / `draw_flush` run inside [`present_frame`](../present.odin#L16).

## Two passes (draw side)

| Concern | Layout | Draw |
|--------|--------|------|
| Tree walk | Register nodes, measure, solve | Same structure; no new layout nodes |
| Rects | Written | Read via [`ui_layout_rect`](oni/ui.odin#L240) |
| Text / image geometry | Shaped in layout | Read via [`layout_text_result`](oni/layout.odin#L2165) / [`layout_image_result`](oni/layout.odin#L2188) |
| GPU | Avoid | `Draw_*`, events |
| Opacity / space stacks | `Begin_Screen` / `Begin_Artboard` push draw space + style | Same pushes (must match Layout) |
| Paint skip | `visibility: HIDDEN` → `paint_skip` | [`ui_layout_paint_skip`](oni/layout_stack.odin#L125) |
| Stack index | Assigned in [`layout_finalize_stack_order`](oni/layout_stack.odin#L444) | [`ui_layout_stack_index`](oni/layout_stack.odin#L115) → [`draw_set_stack_index`](oni/widget.odin#L742) |

### Widget draw pattern

Canonical shape in [`Button`](oni/widgets/button.odin#L70):

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

Leaf [`Text`](oni/widgets/text.odin#L129) dispatches events **before** paint so early returns still deliver handlers. Parents dispatch **after** `Children` so pointer bubbling is child → parent.

## Coordinate spaces

| Space | Draw stack | Layout bounds | Transform at paint |
|-------|------------|---------------|-------------------|
| `.SCREEN` | [`draw_push_screen`](oni/draw.odin#L302) | Window logical size | Identity |
| `.ARTBOARD` | [`begin_artboard`](oni/draw.odin#L278) | Content area ÷ zoom | [`view_transform_rect`](oni/view.odin#L162) / [`view_transform_point`](oni/view.odin#L180) |
| `.POPOVER` | [`begin_popover`](oni/draw.odin#L327) | Window logical size | Identity (paints/hits above screen + artboard) |

| Proc | Role |
|------|------|
| [`draw_push_space`](oni/draw.odin#L184) / [`draw_pop_space`](oni/draw.odin#L202) | Batch space stack |
| [`draw_current_space`](oni/draw.odin#L143) | Active space (default `.SCREEN`) |
| [`Begin_Screen`](oni/api.odin#L96) → [`draw_push_screen`](oni/draw.odin#L302) | Screen space + layout region (Layout only) |
| [`End_Screen`](oni/api.odin#L97) → [`draw_pop_screen`](oni/draw.odin#L314) | Pop screen |
| [`Begin_Artboard`](oni/api.odin#L94) → [`begin_artboard`](oni/draw.odin#L278) | Artboard space + layout region |
| [`End_Artboard`](oni/api.odin#L95) → [`end_artboard`](oni/draw.odin#L291) | Pop artboard |
| [`Popover_Begin`](oni/api.odin#L98) → [`begin_popover`](oni/draw.odin#L327) | Popover overlay space + layout region |
| [`Popover_End`](oni/api.odin#L99) → [`end_popover`](oni/draw.odin#L339) | Pop popover |
| [`view_artboard_zoom`](oni/view.odin#L188) | Scale radii / borders / line thickness on artboard |
| [`draw_space_to_logical`](oni/view.odin#L200) | Screen point → artboard logical (rounded UV local space) |
| [`screen_to_logical`](oni/draw.odin#L20) / [`logical_to_screen`](oni/draw.odin#L31) | DPI pixel ↔ logical (input / hit helpers) |

View camera (pan/zoom) lives in [`View`](oni/view.odin#L8). Changing zoom/pan invalidates batch view cache and layout artboard zoom ([`view_set_zoom`](oni/view.odin#L67), [`view_set_pan`](oni/view.odin#L77), [`view_zoom_at_screen`](oni/view.odin#L114), [`view_reset`](oni/view.odin#L150)).

## Batch recording

CPU-side batching groups geometry into **segments** keyed by texture, scissor clip, and `stack_index` ([`Batch_Key`](oni/batch.odin#L30)).

```
draw_rect / draw_texture / draw_line / font_draw_layout_text
  batch_check_key(texture_id)     split segment on key change
  batch_push_axis_quad / batch_push_quad / batch_push_atlas_quads
    view_transform_rect             artboard → screen
    batch_current_clip              intersect clip stack + viewport
    draw_effective_opacity          multiply vertex alpha
    append UI_Vertex + indices
draw_record_end
  batch_finalize_segments           close last segment; sort by stack_index
present_frame
  batch_upload                      copy VB/IB to GPU
  batch_flush_draws                 bind pipeline, texture, scissor; indexed draw per segment
```

### Ping-pong buffers

[`GPU_State.batches`](oni/gpu.odin#L61) holds two [`Batch_State`](oni/batch.odin#L52) slots. [`batch_flip`](oni/batch.odin#L93) toggles after each successful present so frame N+1 records into the other slot while frame N's GPU buffers may still be in flight. Swapchain acquire ([`WaitAndAcquireGPUSwapchainTexture`](oni/present.odin#L52)) is the sync point.

### Clip and opacity stacks

| Proc | Role |
|------|------|
| [`draw_push_clip`](oni/draw.odin#L118) / [`draw_pop_clip`](oni/draw.odin#L128) | Logical clip stack (intersected in [`batch_current_clip`](oni/batch.odin#L325)) |
| [`batch_current_clip`](oni/batch.odin#L325) | Top clip ∩ viewport, view-transformed; cached until invalidation |
| [`clip_to_scissor`](oni/batch.odin#L799) | Logical clip → SDL scissor pixels for each segment |
| [`draw_push_opacity`](oni/draw.odin#L226) / [`draw_pop_opacity`](oni/draw.odin#L244) | CSS-like nested opacity multiply |
| [`draw_effective_opacity`](oni/draw.odin#L268) / [`Draw_Effective_Opacity`](oni/api.odin#L92) | Product of opacity stack |
| [`clamp_opacity`](oni/style.odin#L202) | Clamp to [0, 1] |

[`ui_layout_clip_rect`](oni/layout_stack.odin#L145) exposes layout-computed clips for queries; widgets do not yet push them via `draw_push_clip` — textured quads still clip against the viewport through [`batch_push_axis_quad`](oni/batch.odin#L564).

### Segment key and ordering

| Proc | Role |
|------|------|
| [`batch_set_stack_index`](oni/batch.odin#L357) | Set `current_stack` for subsequent geometry |
| [`batch_check_key`](oni/batch.odin#L368) | Start new segment when texture / clip / stack changes |
| [`batch_finalize_segments`](oni/batch.odin#L690) | Finalize index counts; sort segments by `stack_index` asc, then `first_index` |
| [`batch_flush_draws`](oni/batch.odin#L829) | Draw each segment with its texture + scissor |

## Primitives (`oni/draw.odin`)

Public API aliases in [`oni/api.odin`](oni/api.odin#L83).

| Proc | Role |
|------|------|
| [`draw_rect`](oni/draw.odin#L376) / [`Draw_Rectangle`](oni/api.odin#L83) | Filled and/or bordered rounded rect (white texture, `.Solid`) |
| [`draw_line`](oni/draw.odin#L422) / [`Draw_Line`](oni/api.odin#L84) | Thick line segment as a quad (`.Line`) |
| [`draw_texture`](oni/draw.odin#L451) / [`Draw_Texture`](oni/api.odin#L85) | Textured rect; falls back to `draw_rect`; `.Textured` or `.Textured_Rounded` |
| [`draw_texture_fitted`](oni/draw.odin#L546) / [`Draw_Texture_Fitted`](oni/api.odin#L86) | Object-fit paint from layout `content` / `image_dst`; clips to content |
| [`draw_atlas_region`](oni/draw.odin#L507) / [`Draw_Atlas`](oni/api.odin#L87) | Atlas sub-rect → `draw_texture` |

Helpers:

| Proc | Role |
|------|------|
| [`rect_contains`](oni/draw.odin#L43) | Half-open point-in-rect |
| [`rect_intersect`](oni/draw.odin#L52) | Axis-aligned overlap (used for fitted texture clip) |

Radii and border widths are multiplied by [`view_artboard_zoom`](oni/view.odin#L188) before reaching the shader.

## Batch internals (`oni/batch.odin`)

| Proc | Role |
|------|------|
| [`batch_current`](oni/batch.odin#L83) | Active ping-pong `Batch_State` |
| [`batch_init`](oni/batch.odin#L131) / [`batch_destroy`](oni/batch.odin#L192) | Allocate / free CPU + GPU batch resources |
| [`batch_create_gpu_buffers`](oni/batch.odin#L147) | Create/resize VB/IB |
| [`batch_reset`](oni/batch.odin#L242) | Clear per-frame CPU data (keeps GPU capacity) |
| [`batch_delete_cpu_arrays`](oni/batch.odin#L102) | Test teardown helper |
| [`batch_ensure_capacity`](oni/batch.odin#L305) | Grow VB/IB when vertex count exceeds capacity |
| [`batch_invalidate_clip_cache`](oni/batch.odin#L263) / [`batch_invalidate_view_cache`](oni/batch.odin#L271) | Drop cached clip/view products |
| [`batch_cached_view`](oni/batch.odin#L282) | Cached artboard zoom + pan for transforms |
| [`draw_mode_f32`](oni/batch.odin#L19) | Pack `Draw_Mode` into vertex `params` |
| [`batch_push_vertex`](oni/batch.odin#L430) | Append one `UI_Vertex` |
| [`batch_push_indices`](oni/batch.odin#L413) | Two triangles for a quad |
| [`batch_push_quad`](oni/batch.odin#L466) | Four corners + indices; applies opacity |
| [`batch_push_axis_quad`](oni/batch.odin#L564) | Axis-aligned rect; textured modes clip to `batch_current_clip` and adjust UVs |
| [`batch_push_atlas_quads`](oni/batch.odin#L644) | Many atlas quads, one `batch_check_key` |
| [`batch_upload`](oni/batch.odin#L738) | Transfer VB/IB to GPU |

## GPU pipeline (`oni/gpu.odin`)

| Proc | Role |
|------|------|
| [`gpu_init`](oni/gpu.odin#L547) | Pipeline, sampler, 1×1 white texture, batches, projection |
| [`gpu_reload`](oni/gpu.odin#L635) | Recreate GPU resources after hot reload |
| [`gpu_destroy`](oni/gpu.odin#L511) | Release pipeline, sampler, textures, batch buffers |
| [`gpu_create_pipeline`](oni/gpu.odin#L315) | UI graphics pipeline from embedded SPIR-V |
| [`gpu_load_shader`](oni/gpu.odin#L70) | Load vert/frag bytecode |
| [`gpu_ui_vertex_layout`](oni/gpu.odin#L186) | Vertex attribute layout matching `UI_Vertex` |
| [`gpu_blend_state`](oni/gpu.odin#L151) | Premultiplied-friendly alpha compositing |
| [`gpu_create_sampler`](oni/gpu.odin#L366) | Linear sampler for UI textures |
| [`gpu_create_white_texture`](oni/gpu.odin#L432) | 1×1 white for solid draws |
| [`gpu_upload_white_pixel`](oni/gpu.odin#L395) | Upload opaque white texel |
| [`gpu_update_projection`](oni/gpu.odin#L498) | Ortho matrix from logical viewport + DPI |

## Text draw (`oni/font.odin`)

Layout owns shaping, line positions, glyph quads, and decoration segments ([`Layout_Text`](oni/layout.odin#L55)). Draw only rasterizes missing glyphs and emits quads.

| Proc | Role |
|------|------|
| [`font_draw_layout_text`](oni/font.odin#L1902) | Paint layout glyphs via atlas; underline/strike via `draw_line` |
| [`font_ensure_glyphs_from_paint`](oni/font.odin#L2104) | Rasterize uncached glyphs referenced by layout paint quads |
| [`font_ensure_glyphs`](oni/font.odin#L810) | Ensure shaped glyph set is in atlas |
| [`font_rasterize_glyph`](oni/font.odin#L1570) / [`font_rasterize_and_cache_missing`](oni/font.odin#L1511) | FreeType rasterize → atlas pack |
| [`font_resolve`](oni/font.odin#L143) | Resolve face + size (artboard applies zoom / layout scale) |
| [`snap_logical`](oni/font.odin#L1850) | Device-pixel snap for glyph placement (`round(v * dpi) / dpi`) |
| [`font_glyph_paint_from_entry`](oni/font.odin#L1862) | Atlas bitmap size/bearings → logical paint quad |
| [`font_text_uses_nearest_filter`](oni/font_shaper.odin#L874) | NEAREST atlas sampling when integer DPI + no artboard zoom |

[`Text`](oni/widgets/text.odin#L129) widget: [`layout_text_result`](oni/layout.odin#L2165) → [`font_draw_layout_text`](oni/font.odin#L1902) with resolved text and decoration colors.

## Textures and atlas (`oni/texture.odin`)

| Proc | Role |
|------|------|
| [`texture_uploads_flush`](oni/texture.odin#L605) | Upload deferred textures before GPU geometry (called from `present_frame`) |
| [`texture_register_surface`](oni/texture.odin#L344) | Register image asset |
| [`texture_upload_surface`](oni/texture.odin#L680) / [`texture_upload_surface_deferred`](oni/texture.odin#L573) | Immediate vs deferred GPU upload |
| [`texture_get_gpu`](oni/texture.odin#L738) | `GPUTexture` for batch flush |
| [`texture_handle`](oni/texture.odin#L753) | Logical `Texture_Handle` for `draw_texture` |
| [`atlas_region_from`](oni/texture.odin#L825) / [`atlas_region_handle`](oni/texture.odin#L834) | Atlas sub-region helpers |
| [`texture_atlas_init`](oni/texture.odin#L1135) / [`texture_atlas_alloc`](oni/texture.odin#L1460) / [`texture_atlas_upload`](oni/texture.odin#L1528) | Font/glyph shelf atlas |
| [`texture_atlas_pack`](oni/texture.odin#L1615) | Pack arbitrary surface into atlas |

[`Image`](oni/widgets/image.odin#L168): chrome via `Draw_Rectangle`; fitted bitmap via [`layout_image_result`](oni/layout.odin#L2188) → [`Draw_Texture_Fitted`](oni/api.odin#L86). Author-side fit math: [`texture_fit_rects`](oni/widget.odin#L1833).

## Table borders (draw path)

Layout resolves collapsed border winners ([`table_layout_resolve_collapsed_borders`](oni/table_border.odin#L189)); draw paints strips and rounded fills.

| Proc | Role |
|------|------|
| [`table_widget_draw_chrome`](oni/widgets/table_shared.odin#L22) | Table widget family paint entry |
| [`table_draw_collapsed_cell`](oni/table_border.odin#L648) | Collapsed cell fill + strip borders |
| [`table_draw_border_strip`](oni/table_border.odin#L409) | Single border segment → `draw_rect` |
| [`table_descendant_outer_radius`](oni/table_border.odin#L501) | Inherit table corner radii on descendants |
| [`table_merge_radius_corners`](oni/table_border.odin#L428) | Max per-corner radius |
| [`table_collapsed_border_color`](oni/table_border.odin#L391) | Resolve winning border color |
| [`table_layout_borders_collapsed_for_widget`](oni/table_border.odin#L303) | Whether widget uses collapsed path |

## Style colors (draw inputs)

| Proc | Role |
|------|------|
| [`to_rgba`](oni/colors.odin#L73) | Resolve `Colors` (theme tokens, procs, concrete) |
| [`style_color_rgba`](oni/colors.odin#L201) | Text color |
| [`style_background_rgba`](oni/colors.odin#L213) | Background fill |
| [`style_border_color_rgba`](oni/colors.odin#L225) | Border stroke |
| [`style_text_decoration_color_rgba`](oni/colors.odin#L237) | Underline / strike color |
| [`style_cache_concrete_rgba`](oni/colors.odin#L187) | Cache resolved concrete colors on style |
| [`color_to_f32`](oni/colors.odin#L125) / [`rgba_to_f32`](oni/colors.odin#L23) | Pack for vertices |

## Interaction during draw

Draw pass updates hover/focus and dispatches events (not layout).

| Proc | Role |
|------|------|
| [`widget_handle_interaction`](oni/widgets/widget_interaction.odin#L91) | Hit test, press state, stack index, focus transitions |
| [`widget_dispatch_events`](oni/widgets/widget_interaction.odin#L159) | Pointer, focus, keyboard handlers |
| [`pointer_hits`](oni/widget.odin#L705) / [`pointer_is_target`](oni/widget.odin#L716) | Hit vs layout-resolved pointer target |
| [`stop_propagation`](oni/widget.odin#L734) / [`Stop_Propagation`](oni/api.odin#L248) | Block bubbled pointer events this frame |
| [`consume_hover_transition`](oni/widget.odin#L764) | Enter/leave edges |

## Key types

| Type | File | Role |
|------|------|------|
| `Draw_Mode` | [oni/batch.odin](oni/batch.odin#L8) | `.Solid`, `.Textured`, `.Line`, `.Textured_Rounded`, `.Textured_Text` |
| `UI_Vertex` | [oni/gpu.odin](oni/gpu.odin#L14) | pos, uv, local_uv, colors, radii, border, mode params |
| `Batch_State` / `Batch_Key` / `Batch_Segment` | [oni/batch.odin](oni/batch.odin#L30) | CPU record + segment metadata |
| `GPU_State` / `GPU_Proj_UBO` | [oni/gpu.odin](oni/gpu.odin#L29) | Pipeline, sampler, projection, ping-pong batches |
| `Draw_Space` | [oni/types.odin](oni/types.odin#L1905) | `.SCREEN`, `.ARTBOARD`, `.POPOVER` |
| `Texture_Handle` / `Atlas_Region` | [oni/types.odin](oni/types.odin#L2006) | Bitmap sources for `draw_texture` |
| `View` | [oni/view.odin](oni/view.odin#L8) | Artboard camera zoom/pan/clamps |
| `Layout_Glyph_Paint` / `Layout_Decoration_Stroke` | [oni/layout.odin](oni/layout.odin#L32) | Layout-owned text paint inputs |
| `Layout_Text` / `Layout_Image` | [oni/layout.odin](oni/layout.odin#L55) | Layout-owned text/image paint geometry |
| `Draw_Proc` | [oni/present.odin](oni/present.odin#L5) | `proc()` app draw callback type |

## Public API aliases (`oni/api.odin`)

| Alias | Target |
|-------|--------|
| [`Draw_Rectangle`](oni/api.odin#L83) | `draw_rect` |
| [`Draw_Line`](oni/api.odin#L84) | `draw_line` |
| [`Draw_Texture`](oni/api.odin#L85) | `draw_texture` |
| [`Draw_Texture_Fitted`](oni/api.odin#L86) | `draw_texture_fitted` |
| [`Draw_Atlas`](oni/api.odin#L87) | `draw_atlas_region` |
| [`Draw_Push_Opacity`](oni/api.odin#L88) / [`Draw_Pop_Opacity`](oni/api.odin#L89) | opacity stack |
| [`Draw_Effective_Opacity`](oni/api.odin#L92) | effective opacity product |
| [`Draw_Set_Stack_Index`](oni/api.odin#L247) | `draw_set_stack_index` |
| [`Layout_Stack_Index`](oni/api.odin#L213) / [`Layout_Paint_Skip`](oni/api.odin#L214) / [`Layout_Clip_Rect`](oni/api.odin#L216) | draw-time layout queries |
| [`View_*`](oni/api.odin#L120) | artboard camera controls |

## Widget entry points

These branch on [`ui_pass`](oni/ui.odin#L231) and paint on Draw:

[`Button`](oni/widgets/button.odin#L70), [`Rectangle`](oni/widgets/rectangle.odin#L64) ([`draw_widget_rectangle`](oni/widgets/rectangle.odin#L208)), [`Text`](oni/widgets/text.odin#L129), [`Image`](oni/widgets/image.odin#L168), [`Tabs`](oni/widgets/tabs.odin#L112), [`Tabs_List`](oni/widgets/tabs_list.odin#L124), [`Tabs_Trigger`](oni/widgets/tabs_trigger.odin#L184), [`Tabs_Content`](oni/widgets/tabs_content.odin#L112), [`Table`](oni/widgets/table.odin#L69), [`Table_Caption`](oni/widgets/table_caption.odin#L66), [`Table_Head`](oni/widgets/table_head.odin#L72), [`Table_Heading`](oni/widgets/table_heading.odin#L72), [`Table_Body`](oni/widgets/table_body.odin#L72), [`Table_Row`](oni/widgets/table_row.odin#L73), [`Table_Cell`](oni/widgets/table_cell.odin#L71), [`Table_Foot`](oni/widgets/table_foot.odin#L72) — table family chrome via [`table_widget_draw_chrome`](oni/widgets/table_shared.odin#L22).

## Complete proc index (`oni/draw.odin`)

Coordinates: [`screen_to_logical`](oni/draw.odin#L20), [`logical_to_screen`](oni/draw.odin#L31), [`rect_contains`](oni/draw.odin#L43), [`rect_intersect`](oni/draw.odin#L52).

Recording / GPU bridge: [`draw_record_begin`](oni/draw.odin#L66), [`draw_record_end`](oni/draw.odin#L77), [`draw_begin`](oni/draw.odin#L86), [`draw_flush`](oni/draw.odin#L98), [`draw_end`](oni/draw.odin#L107).

Stacks: [`draw_push_clip`](oni/draw.odin#L118), [`draw_pop_clip`](oni/draw.odin#L128), [`draw_current_space`](oni/draw.odin#L143), [`draw_push_space`](oni/draw.odin#L184), [`draw_pop_space`](oni/draw.odin#L202), [`draw_push_opacity`](oni/draw.odin#L226), [`draw_pop_opacity`](oni/draw.odin#L244), [`draw_effective_opacity`](oni/draw.odin#L268).

Spaces: [`begin_artboard`](oni/draw.odin#L278), [`end_artboard`](oni/draw.odin#L291), [`draw_push_screen`](oni/draw.odin#L302), [`draw_pop_screen`](oni/draw.odin#L314), [`begin_popover`](oni/draw.odin#L327), [`end_popover`](oni/draw.odin#L339).

Primitives: [`draw_rect`](oni/draw.odin#L376), [`draw_line`](oni/draw.odin#L422), [`draw_texture`](oni/draw.odin#L451), [`draw_atlas_region`](oni/draw.odin#L507), [`draw_texture_fitted`](oni/draw.odin#L546).

## Complete proc index (`oni/batch.odin`)

Lifecycle: [`draw_mode_f32`](oni/batch.odin#L19), [`batch_flip`](oni/batch.odin#L93), [`batch_delete_cpu_arrays`](oni/batch.odin#L102), [`batch_init`](oni/batch.odin#L131), [`batch_create_gpu_buffers`](oni/batch.odin#L147), [`batch_destroy`](oni/batch.odin#L192), [`batch_reset`](oni/batch.odin#L242).

Cache / clip: [`batch_invalidate_clip_cache`](oni/batch.odin#L263), [`batch_invalidate_view_cache`](oni/batch.odin#L271), [`batch_cached_view`](oni/batch.odin#L282), [`batch_current_clip`](oni/batch.odin#L325), [`clip_to_scissor`](oni/batch.odin#L799).

Record: [`batch_ensure_capacity`](oni/batch.odin#L305), [`batch_set_stack_index`](oni/batch.odin#L357), [`batch_check_key`](oni/batch.odin#L368), [`batch_push_indices`](oni/batch.odin#L413), [`batch_push_vertex`](oni/batch.odin#L430), [`batch_push_quad`](oni/batch.odin#L466), [`batch_push_axis_quad`](oni/batch.odin#L564), [`batch_push_atlas_quads`](oni/batch.odin#L644).

Upload / draw: [`batch_finalize_segments`](oni/batch.odin#L690), [`batch_upload`](oni/batch.odin#L738), [`batch_flush_draws`](oni/batch.odin#L829).

## Complete proc index (`oni/view.odin`)

Defaults / zoom: [`view_default`](oni/view.odin#L24), [`view_quantize_zoom`](oni/view.odin#L31), [`view_quantize_zoom_with_step`](oni/view.odin#L41), [`view_effective_zoom`](oni/view.odin#L49), [`view_clamp_zoom`](oni/view.odin#L58), [`view_set_zoom`](oni/view.odin#L67), [`view_zoom_at_screen`](oni/view.odin#L114), [`view_zoom_by_screen`](oni/view.odin#L128), [`view_zoom_in_screen`](oni/view.odin#L136), [`view_zoom_out_screen`](oni/view.odin#L143), [`view_reset`](oni/view.odin#L150).

Pan: [`view_set_pan`](oni/view.odin#L77), [`view_pan_by`](oni/view.odin#L86).

Transforms: [`view_screen_to_world`](oni/view.odin#L95), [`view_world_to_screen`](oni/view.odin#L105), [`view_transform_rect`](oni/view.odin#L162), [`view_transform_point`](oni/view.odin#L180), [`view_artboard_zoom`](oni/view.odin#L188), [`draw_space_to_logical`](oni/view.odin#L200).

## Complete proc index (`oni/present.odin`)

[`present_frame`](oni/present.odin#L16).

## Complete proc index (`oni/gpu.odin`)

[`gpu_load_shader`](oni/gpu.odin#L70), [`gpu_blend_state`](oni/gpu.odin#L151), [`gpu_ui_vertex_layout`](oni/gpu.odin#L186), [`gpu_create_pipeline`](oni/gpu.odin#L315), [`gpu_create_sampler`](oni/gpu.odin#L366), [`gpu_upload_white_pixel`](oni/gpu.odin#L395), [`gpu_create_white_texture`](oni/gpu.odin#L432), [`gpu_update_projection`](oni/gpu.odin#L498), [`gpu_destroy`](oni/gpu.odin#L511), [`gpu_init`](oni/gpu.odin#L547), [`gpu_reload`](oni/gpu.odin#L635).

## Complete proc index (`oni/font.odin` — draw path)

[`font_draw_layout_text`](oni/font.odin#L1902), [`font_ensure_glyphs_from_paint`](oni/font.odin#L2104), [`font_ensure_glyphs`](oni/font.odin#L810), [`font_rasterize_and_cache_missing`](oni/font.odin#L1511), [`font_rasterize_glyph`](oni/font.odin#L1570), [`font_resolve`](oni/font.odin#L143), [`font_atlas_reset`](oni/font.odin#L237), [`snap_logical`](oni/font.odin#L1850).

## Complete proc index (`oni/texture.odin`)

[`texture_init`](oni/texture.odin#L261), [`texture_shutdown`](oni/texture.odin#L275), [`texture_release_gpu`](oni/texture.odin#L303), [`texture_reload_gpu`](oni/texture.odin#L323), [`texture_register_surface`](oni/texture.odin#L344), [`texture_upload_record`](oni/texture.odin#L411), [`texture_surface_as_rgba8888`](oni/texture.odin#L461), [`texture_fill_transfer_from_surface`](oni/texture.odin#L489), [`texture_create_filled_transfer`](oni/texture.odin#L543), [`texture_upload_surface_deferred`](oni/texture.odin#L573), [`texture_uploads_flush`](oni/texture.odin#L605), [`texture_upload_surface`](oni/texture.odin#L680), [`texture_get_gpu`](oni/texture.odin#L738), [`texture_handle`](oni/texture.odin#L753), [`atlas_region_from`](oni/texture.odin#L825), [`atlas_region_handle`](oni/texture.odin#L834), [`texture_atlas_init`](oni/texture.odin#L1135), [`texture_atlas_shutdown`](oni/texture.odin#L1174), [`texture_atlas_rebuild_gpu`](oni/texture.odin#L1209), [`texture_atlas_alloc`](oni/texture.odin#L1460), [`texture_atlas_upload`](oni/texture.odin#L1528), [`texture_atlas_pack`](oni/texture.odin#L1615).

## Complete proc index (`oni/table_border.odin` — draw path)

[`table_draw_border_strip`](oni/table_border.odin#L409), [`table_draw_collapsed_cell`](oni/table_border.odin#L648), [`table_descendant_outer_radius`](oni/table_border.odin#L501), [`table_merge_radius_corners`](oni/table_border.odin#L428), [`table_collapsed_border_color`](oni/table_border.odin#L391), [`table_side_is_straight`](oni/table_border.odin#L564), [`table_layout_borders_collapsed_for_widget`](oni/table_border.odin#L303).

Layout-side collapse (inputs to draw): [`table_gaps_are_collapsed`](oni/table_border.odin#L3), [`table_border_source_rank`](oni/table_border.odin#L7), [`table_border_compare`](oni/table_border.odin#L21), [`table_border_pick_winner`](oni/table_border.odin#L42), [`table_border_side_width`](oni/table_border.odin#L53), [`table_border_side_from_node`](oni/table_border.odin#L67), [`table_layout_cell_ancestors`](oni/table_border.odin#L83), [`table_layout_append_side_candidates`](oni/table_border.odin#L113), [`table_layout_collect_edge_candidates`](oni/table_border.odin#L127), [`table_border_strip_rect`](oni/table_border.odin#L174), [`table_layout_resolve_collapsed_borders`](oni/table_border.odin#L189), [`table_layout_find_cell_neighbor`](oni/table_border.odin#L316), [`table_f32_max`](oni/table_border.odin#L416), [`table_corners_touch`](oni/table_border.odin#L420).

## Draw-adjacent (`oni/widget.odin`, `oni/widgets/`)

| Proc | Role |
|------|------|
| [`draw_set_stack_index`](oni/widget.odin#L742) | Public batch stack setter |
| [`texture_fit_rects`](oni/widget.odin#L1833) | Object-fit rect math (layout + image draw) |
| [`widget_prepare_draw`](oni/widgets/widget_lifecycle.odin#L118) | Draw gate + lifecycle sync |
| [`widget_handle_interaction`](oni/widgets/widget_interaction.odin#L91) | Draw-pass input + stack index |
| [`widget_dispatch_events`](oni/widgets/widget_interaction.odin#L159) | Handler dispatch |
| [`table_widget_draw_chrome`](oni/widgets/table_shared.odin#L22) | Shared table paint |
| [`draw_widget_rectangle`](oni/widgets/rectangle.odin#L208) | Rectangle chrome + children |
