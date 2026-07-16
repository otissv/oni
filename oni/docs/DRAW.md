# Draw

Oni draw is a **CPU-recorded, GPU-batched** immediate-mode painter. During the **Draw** pass, widgets read solved layout rects and emit geometry into a frame batch; [`present_frame`](oni/present.odin#L16) uploads and flushes it after the UI tree returns.

Coordinates are logical design pixels. DPI scale is applied at clip/scissor conversion and in the orthographic projection — not inside individual `draw_*` calls. Artboard content is zoomed/panned via [`view_transform_rect`](oni/view.odin#L162) / [`view_transform_point`](oni/view.odin#L180) when the draw space stack is `.ARTBOARD`.

## Mental model

1. App calls [`o.Render`](oni/api.odin#L52) once per frame; each builder runs Layout, then Draw ([`render`](oni/ui.odin#L179)).
2. On **Draw**, widgets call [`widget_prepare_draw`](oni/widgets/widget_lifecycle.odin#L118), read [`ui_layout_rect`](oni/ui.odin#L201) (and layout-owned text/image results), set [`draw_set_stack_index`](oni/widget.odin#L445), then emit `Draw_*` commands.
3. [`present_frame`](oni/present.odin#L16) wraps the app draw callback:
   - [`draw_record_begin`](oni/draw.odin#L57) → app/UI records vertices into the current ping-pong [`Batch_State`](oni/batch.odin#L45)
   - [`draw_record_end`](oni/draw.odin#L68) → [`batch_finalize_segments`](oni/batch.odin#L561) (sort by `stack_index`)
   - deferred texture uploads → swapchain acquire → [`batch_upload`](oni/batch.odin#L590) → render pass → [`draw_flush`](oni/draw.odin#L89) → [`batch_reset`](oni/batch.odin#L224) + [`batch_flip`](oni/batch.odin#L85)
4. Primitives never talk to SDL directly — they append [`UI_Vertex`](oni/gpu.odin#L13) data and segment keys; the UI shader ([`oni/shaders/ui.vert`](oni/shaders/ui.vert), [`oni/shaders/ui.frag`](oni/shaders/ui.frag)) rasterizes solid, textured, line, and rounded modes ([`Draw_Mode`](oni/batch.odin#L8)).

**Critical timing:** geometry is recorded during the Draw pass inside `present_frame`'s callback, **before** GPU upload. Layout must be solved and stack order finalized ([`ui_end_layout_pass`](oni/ui.odin#L132)) before any paint runs.

**Stack order:** layout assigns `stack_index` per node ([`layout_finalize_stack_order`](oni/layout_stack.odin#L376)); widgets set it via [`draw_set_stack_index`](oni/widget.odin#L445) before emitting geometry. Segments with a higher `stack_index` are sorted to draw later (on top).

## Frame flow

```
run_frame                          oni/runtime.odin
  ui_begin_frame                   pass = Layout
  tick(dt)
  present_frame(draw)              app draw → o.Render(main_ui)
    draw_record_begin
    draw()                         Draw pass (inside Render's second u())
      Begin_Screen / Begin_Artboard
        draw_push_space            SCREEN or ARTBOARD
      widgets:
        widget_prepare_draw
        draw_set_stack_index       from ui_layout_stack_index
        Draw_Rectangle / Draw_Texture / font_draw_layout_text / …
          batch_push_*               CPU vertices + indices
        Children                     same tree as Layout
      End_Screen / End_Artboard
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
| [`run_frame`](oni/runtime.odin#L22) | One host frame: begin UI → tick → present |
| [`present_frame`](oni/present.odin#L16) | Record draw, upload, flush GPU, flip batch slot |
| [`render`](oni/ui.odin#L179) / [`Render`](oni/api.odin#L52) | Per-builder Layout + Draw |
| [`ui_end_layout_pass`](oni/ui.odin#L132) | Stack order, hit test, focus → switch to Draw |
| [`draw_record_begin`](oni/draw.odin#L57) / [`draw_record_end`](oni/draw.odin#L68) | Frame batch recording boundaries |
| [`draw_begin`](oni/draw.odin#L77) / [`draw_flush`](oni/draw.odin#L89) / [`draw_end`](oni/draw.odin#L98) | Bind GPU pass, issue draws, unbind |

App code should call `o.Render(...)` once. Low-level `draw_record_*` / `draw_begin` / `draw_flush` run inside [`present_frame`](oni/present.odin#L16).

## Two passes (draw side)

| Concern | Layout | Draw |
|--------|--------|------|
| Tree walk | Register nodes, measure, solve | Same structure; no new layout nodes |
| Rects | Written | Read via [`ui_layout_rect`](oni/ui.odin#L201) |
| Text / image geometry | Shaped in layout | Read via [`layout_text_result`](oni/layout.odin#L944) / [`layout_image_result`](oni/layout.odin#L955) |
| GPU | Avoid | `Draw_*`, events |
| Opacity / space stacks | `Begin_Screen` / `Begin_Artboard` push draw space + style | Same pushes (must match Layout) |
| Paint skip | `visibility: HIDDEN` → `paint_skip` | [`ui_layout_paint_skip`](oni/layout_stack.odin#L140) |
| Stack index | Assigned in [`layout_finalize_stack_order`](oni/layout_stack.odin#L376) | [`ui_layout_stack_index`](oni/layout_stack.odin#L130) → [`draw_set_stack_index`](oni/widget.odin#L445) |

### Widget draw pattern

Canonical shape in [`Button`](oni/widgets/button.odin#L66):

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

Leaf [`Text`](oni/widgets/text.odin#L107) dispatches events **before** paint so early returns still deliver handlers. Parents dispatch **after** `Children` so pointer bubbling is child → parent.

## Coordinate spaces

| Space | Draw stack | Layout bounds | Transform at paint |
|-------|------------|---------------|-------------------|
| `.SCREEN` | [`draw_push_screen`](oni/draw.odin#L245) | Window logical size | Identity |
| `.ARTBOARD` | [`begin_artboard`](oni/draw.odin#L221) | Content area ÷ zoom | [`view_transform_rect`](oni/view.odin#L162) / [`view_transform_point`](oni/view.odin#L180) |
| `.POPOVER` | [`begin_popover`](oni/draw.odin) | Window logical size | Identity (paints/hits above screen + artboard) |

| Proc | Role |
|------|------|
| [`draw_push_space`](oni/draw.odin#L144) / [`draw_pop_space`](oni/draw.odin#L154) | Batch space stack |
| [`draw_current_space`](oni/draw.odin#L134) | Active space (default `.SCREEN`) |
| [`Begin_Screen`](oni/api.odin#L50) → [`draw_push_screen`](oni/draw.odin#L245) | Screen space + layout region (Layout only) |
| [`End_Screen`](oni/api.odin#L51) → [`draw_pop_screen`](oni/draw.odin#L257) | Pop screen |
| [`Begin_Artboard`](oni/api.odin#L48) → [`begin_artboard`](oni/draw.odin#L221) | Artboard space + layout region |
| [`End_Artboard`](oni/api.odin#L49) → [`end_artboard`](oni/draw.odin#L234) | Pop artboard |
| [`Popover_Begin`](oni/api.odin) → [`begin_popover`](oni/draw.odin) | Popover overlay space + layout region |
| [`Popover_End`](oni/api.odin) → [`end_popover`](oni/draw.odin) | Pop popover |
| [`view_artboard_zoom`](oni/view.odin#L188) | Scale radii / borders / line thickness on artboard |
| [`draw_space_to_logical`](oni/view.odin#L200) | Screen point → artboard logical (rounded UV local space) |
| [`screen_to_logical`](oni/draw.odin#L11) / [`logical_to_screen`](oni/draw.odin#L22) | DPI pixel ↔ logical (input / hit helpers) |

View camera (pan/zoom) lives in [`View`](oni/view.odin#L8). Changing zoom/pan invalidates batch view cache and layout artboard zoom ([`view_set_zoom`](oni/view.odin#L67), [`view_set_pan`](oni/view.odin#L77), [`view_zoom_at_screen`](oni/view.odin#L114), [`view_reset`](oni/view.odin#L150)).

## Batch recording

CPU-side batching groups geometry into **segments** keyed by texture, scissor clip, and `stack_index` ([`Batch_Key`](oni/batch.odin#L27)).

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

[`GPU_State.batches`](oni/gpu.odin#L45) holds two [`Batch_State`](oni/batch.odin#L45) slots. [`batch_flip`](oni/batch.odin#L85) toggles after each successful present so frame N+1 records into the other slot while frame N's GPU buffers may still be in flight. Swapchain acquire ([`WaitAndAcquireGPUSwapchainTexture`](oni/present.odin#L51)) is the sync point.

### Clip and opacity stacks

| Proc | Role |
|------|------|
| [`draw_push_clip`](oni/draw.odin#L109) / [`draw_pop_clip`](oni/draw.odin#L119) | Logical clip stack (intersected in [`batch_current_clip`](oni/batch.odin#L303)) |
| [`batch_current_clip`](oni/batch.odin#L303) | Top clip ∩ viewport, view-transformed; cached until invalidation |
| [`clip_to_scissor`](oni/batch.odin#L651) | Logical clip → SDL scissor pixels for each segment |
| [`draw_push_opacity`](oni/draw.odin#L169) / [`draw_pop_opacity`](oni/draw.odin#L187) | CSS-like nested opacity multiply |
| [`draw_effective_opacity`](oni/draw.odin#L211) / [`Draw_Effective_Opacity`](oni/api.odin#L46) | Product of opacity stack |
| [`clamp_opacity`](oni/style.odin#L95) | Clamp to [0, 1] |

[`ui_layout_clip_rect`](oni/layout_stack.odin#L160) exposes layout-computed clips for queries; widgets do not yet push them via `draw_push_clip` — textured quads still clip against the viewport through [`batch_push_axis_quad`](oni/batch.odin#L473).

### Segment key and ordering

| Proc | Role |
|------|------|
| [`batch_set_stack_index`](oni/batch.odin#L335) | Set `current_stack` for subsequent geometry |
| [`batch_check_key`](oni/batch.odin#L344) | Start new segment when texture / clip / stack changes |
| [`batch_finalize_segments`](oni/batch.odin#L561) | Finalize index counts; sort segments by `stack_index` asc, then `first_index` |
| [`batch_flush_draws`](oni/batch.odin#L680) | Draw each segment with its texture + scissor |

## Primitives (`oni/draw.odin`)

Public API aliases in [`oni/api.odin`](oni/api.odin#L39).

| Proc | Role |
|------|------|
| [`draw_rect`](oni/draw.odin#L269) / [`Draw_Rectangle`](oni/api.odin#L39) | Filled and/or bordered rounded rect (white texture, `.Solid`) |
| [`draw_line`](oni/draw.odin#L315) / [`Draw_Line`](oni/api.odin#L40) | Thick line segment as a quad (`.Line`) |
| [`draw_texture`](oni/draw.odin#L344) / [`Draw_Texture`](oni/api.odin#L41) | Textured rect; falls back to `draw_rect`; `.Textured` or `.Textured_Rounded` |
| [`draw_texture_fitted`](oni/draw.odin#L414) / [`Draw_Texture_Fitted`](oni/api.odin#L42) | Object-fit paint from layout `content` / `image_dst`; clips to content |
| [`draw_atlas_region`](oni/draw.odin#L400) / [`Draw_Atlas`](oni/api.odin#L43) | Atlas sub-rect → `draw_texture` |

Helpers:

| Proc | Role |
|------|------|
| [`rect_contains`](oni/draw.odin#L34) | Half-open point-in-rect |
| [`rect_intersect`](oni/draw.odin#L43) | Axis-aligned overlap (used for fitted texture clip) |

Radii and border widths are multiplied by [`view_artboard_zoom`](oni/view.odin#L188) before reaching the shader.

## Batch internals (`oni/batch.odin`)

| Proc | Role |
|------|------|
| [`batch_current`](oni/batch.odin#L75) | Active ping-pong `Batch_State` |
| [`batch_init`](oni/batch.odin#L118) / [`batch_destroy`](oni/batch.odin#L179) | Allocate / free CPU + GPU batch resources |
| [`batch_create_gpu_buffers`](oni/batch.odin#L134) | Create/resize VB/IB |
| [`batch_reset`](oni/batch.odin#L224) | Clear per-frame CPU data (keeps GPU capacity) |
| [`batch_delete_cpu_arrays`](oni/batch.odin#L94) | Test teardown helper |
| [`batch_ensure_capacity`](oni/batch.odin#L283) | Grow VB/IB when vertex count exceeds capacity |
| [`batch_invalidate_clip_cache`](oni/batch.odin#L241) / [`batch_invalidate_view_cache`](oni/batch.odin#L249) | Drop cached clip/view products |
| [`batch_cached_view`](oni/batch.odin#L260) | Cached artboard zoom + pan for transforms |
| [`draw_mode_f32`](oni/batch.odin#L18) | Pack `Draw_Mode` into vertex `params` |
| [`batch_push_vertex`](oni/batch.odin#L393) | Append one `UI_Vertex` |
| [`batch_push_indices`](oni/batch.odin#L376) | Two triangles for a quad |
| [`batch_push_quad`](oni/batch.odin#L428) | Four corners + indices; applies opacity |
| [`batch_push_axis_quad`](oni/batch.odin#L473) | Axis-aligned rect; textured modes clip to `batch_current_clip` and adjust UVs |
| [`batch_push_atlas_quads`](oni/batch.odin#L531) | Many atlas quads, one `batch_check_key` |
| [`batch_upload`](oni/batch.odin#L590) | Transfer VB/IB to GPU |

## GPU pipeline (`oni/gpu.odin`)

| Proc | Role |
|------|------|
| [`gpu_init`](oni/gpu.odin#L389) | Pipeline, sampler, 1×1 white texture, batches, projection |
| [`gpu_reload`](oni/gpu.odin#L423) | Recreate GPU resources after hot reload |
| [`gpu_destroy`](oni/gpu.odin#L363) | Release pipeline, sampler, textures, batch buffers |
| [`gpu_create_pipeline`](oni/gpu.odin#L164) | UI graphics pipeline from embedded SPIR-V |
| [`gpu_load_shader`](oni/gpu.odin#L54) | Load vert/frag bytecode |
| [`gpu_ui_vertex_layout`](oni/gpu.odin#L104) | Vertex attribute layout matching `UI_Vertex` |
| [`gpu_blend_state`](oni/gpu.odin#L87) | Premultiplied-friendly alpha compositing |
| [`gpu_create_sampler`](oni/gpu.odin#L222) | Linear sampler for UI textures |
| [`gpu_create_white_texture`](oni/gpu.odin#L284) | 1×1 white for solid draws |
| [`gpu_upload_white_pixel`](oni/gpu.odin#L247) | Upload opaque white texel |
| [`gpu_update_projection`](oni/gpu.odin#L350) | Ortho matrix from logical viewport + DPI |

## Text draw (`oni/font.odin`)

Layout owns shaping, line positions, glyph quads, and decoration segments ([`Layout_Text`](oni/layout.odin#L34)). Draw only rasterizes missing glyphs and emits quads.

| Proc | Role |
|------|------|
| [`font_draw_layout_text`](oni/font.odin#L603) | Paint layout glyphs via atlas; underline/strike via `draw_line` |
| [`font_ensure_glyphs_from_paint`](oni/font.odin#L667) | Rasterize uncached glyphs referenced by layout paint quads |
| [`font_ensure_glyphs`](oni/font.odin#L185) | Ensure shaped glyph set is in atlas |
| [`font_rasterize_glyph`](oni/font.odin#L491) / [`font_rasterize_and_cache_missing`](oni/font.odin#L401) | FreeType rasterize → atlas pack |
| [`font_resolve`](oni/font.odin#L110) | Resolve face + size (artboard applies zoom / layout scale) |
| [`snap_logical`](oni/font.odin#L594) | Half-pixel snap for glyph placement |

[`Text`](oni/widgets/text.odin#L107) widget: [`layout_text_result`](oni/layout.odin#L944) → [`font_draw_layout_text`](oni/font.odin#L603) with resolved text and decoration colors.

## Textures and atlas (`oni/texture.odin`)

| Proc | Role |
|------|------|
| [`texture_uploads_flush`](oni/texture.odin#L390) | Upload deferred textures before GPU geometry (called from `present_frame`) |
| [`texture_register_surface`](oni/texture.odin#L148) | Register image asset |
| [`texture_upload_surface`](oni/texture.odin#L466) / [`texture_upload_surface_deferred`](oni/texture.odin#L358) | Immediate vs deferred GPU upload |
| [`texture_get_gpu`](oni/texture.odin#L524) | `GPUTexture` for batch flush |
| [`texture_handle`](oni/texture.odin#L539) | Logical `Texture_Handle` for `draw_texture` |
| [`atlas_region_from`](oni/texture.odin#L555) / [`atlas_region_handle`](oni/texture.odin#L564) | Atlas sub-region helpers |
| [`texture_atlas_init`](oni/texture.odin#L573) / [`texture_atlas_alloc`](oni/texture.odin#L631) / [`texture_atlas_upload`](oni/texture.odin#L682) | Font/glyph shelf atlas |
| [`texture_atlas_pack`](oni/texture.odin#L739) | Pack arbitrary surface into atlas |

[`Image`](oni/widgets/image.odin#L167): chrome via `Draw_Rectangle`; fitted bitmap via [`layout_image_result`](oni/layout.odin#L955) → [`Draw_Texture_Fitted`](oni/api.odin#L42). Author-side fit math: [`texture_fit_rects`](oni/widget.odin#L1419).

## Table borders (draw path)

Layout resolves collapsed border winners ([`table_layout_resolve_collapsed_borders`](oni/table_border.odin#L189)); draw paints strips and rounded fills.

| Proc | Role |
|------|------|
| [`table_widget_draw_chrome`](oni/widgets/table_shared.odin#L13) | Table widget family paint entry |
| [`table_draw_collapsed_cell`](oni/table_border.odin#L513) | Collapsed cell fill + strip borders |
| [`table_draw_border_strip`](oni/table_border.odin#L409) | Single border segment → `draw_rect` |
| [`table_descendant_outer_radius`](oni/table_border.odin#L443) | Inherit table corner radii on descendants |
| [`table_merge_radius_corners`](oni/table_border.odin#L428) | Max per-corner radius |
| [`table_collapsed_border_color`](oni/table_border.odin#L391) | Resolve winning border color |
| [`table_layout_borders_collapsed_for_widget`](oni/table_border.odin#L303) | Whether widget uses collapsed path |

## Style colors (draw inputs)

| Proc | Role |
|------|------|
| [`to_rgba`](oni/colors.odin#L47) | Resolve `Colors` (theme tokens, procs, concrete) |
| [`style_color_rgba`](oni/colors.odin#L157) | Text color |
| [`style_background_rgba`](oni/colors.odin#L169) | Background fill |
| [`style_border_color_rgba`](oni/colors.odin#L181) | Border stroke |
| [`style_text_decoration_color_rgba`](oni/colors.odin#L193) | Underline / strike color |
| [`style_cache_concrete_rgba`](oni/colors.odin#L143) | Cache resolved concrete colors on style |
| [`color_to_f32`](oni/colors.odin#L93) / [`rgba_to_f32`](oni/colors.odin#L18) | Pack for vertices |

## Interaction during draw

Draw pass updates hover/focus and dispatches events (not layout).

| Proc | Role |
|------|------|
| [`widget_handle_interaction`](oni/widgets/widget_interaction.odin#L91) | Hit test, press state, stack index, focus transitions |
| [`widget_dispatch_events`](oni/widgets/widget_interaction.odin#L135) | Pointer, focus, keyboard handlers |
| [`pointer_hits`](oni/widget.odin#L408) / [`pointer_is_target`](oni/widget.odin#L419) | Hit vs layout-resolved pointer target |
| [`stop_propagation`](oni/widget.odin#L437) / [`Stop_Propagation`](oni/api.odin#L82) | Block bubbled pointer events this frame |
| [`consume_hover_transition`](oni/widget.odin#L467) | Enter/leave edges |

## Key types

| Type | File | Role |
|------|------|------|
| `Draw_Mode` | [oni/batch.odin](oni/batch.odin#L8) | `.Solid`, `.Textured`, `.Line`, `.Textured_Rounded` |
| `UI_Vertex` | [oni/gpu.odin](oni/gpu.odin#L13) | pos, uv, local_uv, colors, radii, border, mode params |
| `Batch_State` / `Batch_Key` / `Batch_Segment` | [oni/batch.odin](oni/batch.odin#L27) | CPU record + segment metadata |
| `GPU_State` / `GPU_Proj_UBO` | [oni/gpu.odin](oni/gpu.odin#L28) | Pipeline, sampler, projection, ping-pong batches |
| `Draw_Space` | [oni/types.odin](oni/types.odin#L867) | `.SCREEN`, `.ARTBOARD`, `.POPOVER` |
| `Texture_Handle` / `Atlas_Region` | [oni/types.odin](oni/types.odin#L915) | Bitmap sources for `draw_texture` |
| `View` | [oni/view.odin](oni/view.odin#L8) | Artboard camera zoom/pan/clamps |
| `Layout_Glyph_Paint` / `Layout_Decoration_Stroke` | [oni/layout.odin](oni/layout.odin#L18) | Layout-owned text paint inputs |
| `Layout_Text` / `Layout_Image` | [oni/layout.odin](oni/layout.odin#L34) | Layout-owned text/image paint geometry |
| `Draw_Proc` | [oni/present.odin](oni/present.odin#L6) | `proc()` app draw callback type |

## Public API aliases (`oni/api.odin`)

| Alias | Target |
|-------|--------|
| [`Draw_Rectangle`](oni/api.odin#L39) | `draw_rect` |
| [`Draw_Line`](oni/api.odin#L40) | `draw_line` |
| [`Draw_Texture`](oni/api.odin#L41) | `draw_texture` |
| [`Draw_Texture_Fitted`](oni/api.odin#L42) | `draw_texture_fitted` |
| [`Draw_Atlas`](oni/api.odin#L43) | `draw_atlas_region` |
| [`Draw_Push_Opacity`](oni/api.odin#L44) / [`Draw_Pop_Opacity`](oni/api.odin#L45) | opacity stack |
| [`Draw_Effective_Opacity`](oni/api.odin#L46) | effective opacity product |
| [`Draw_Set_Stack_Index`](oni/api.odin#L81) | `draw_set_stack_index` |
| [`Layout_Stack_Index`](oni/api.odin#L75) / [`Layout_Paint_Skip`](oni/api.odin#L76) / [`Layout_Clip_Rect`](oni/api.odin#L78) | draw-time layout queries |
| [`View_*`](oni/api.odin#L61) | artboard camera controls |

## Widget entry points

These branch on [`ui_pass`](oni/ui.odin#L192) and paint on Draw:

[`Button`](oni/widgets/button.odin#L66), [`Rectangle`](oni/widgets/rectangle.odin#L63) ([`draw_widget_rectangle`](oni/widgets/rectangle.odin#L174)), [`Text`](oni/widgets/text.odin#L107), [`Image`](oni/widgets/image.odin#L167), [`Table`](oni/widgets/table.odin), [`Table_Caption`](oni/widgets/table_caption.odin), [`Table_Head`](oni/widgets/table_head.odin), [`Table_Heading`](oni/widgets/table_heading.odin), [`Table_Body`](oni/widgets/table_body.odin), [`Table_Row`](oni/widgets/table_row.odin), [`Table_Cell`](oni/widgets/table_cell.odin), [`Table_Foot`](oni/widgets/table_foot.odin) — table family chrome via [`table_widget_draw_chrome`](oni/widgets/table_shared.odin#L13).

## Complete proc index (`oni/draw.odin`)

Coordinates: [`screen_to_logical`](oni/draw.odin#L11), [`logical_to_screen`](oni/draw.odin#L22), [`rect_contains`](oni/draw.odin#L34), [`rect_intersect`](oni/draw.odin#L43).

Recording / GPU bridge: [`draw_record_begin`](oni/draw.odin#L57), [`draw_record_end`](oni/draw.odin#L68), [`draw_begin`](oni/draw.odin#L77), [`draw_flush`](oni/draw.odin#L89), [`draw_end`](oni/draw.odin#L98).

Stacks: [`draw_push_clip`](oni/draw.odin#L109), [`draw_pop_clip`](oni/draw.odin#L119), [`draw_current_space`](oni/draw.odin#L134), [`draw_push_space`](oni/draw.odin#L144), [`draw_pop_space`](oni/draw.odin#L154), [`draw_push_opacity`](oni/draw.odin#L169), [`draw_pop_opacity`](oni/draw.odin#L187), [`draw_effective_opacity`](oni/draw.odin#L211).

Spaces: [`begin_artboard`](oni/draw.odin#L221), [`end_artboard`](oni/draw.odin#L234), [`draw_push_screen`](oni/draw.odin#L245), [`draw_pop_screen`](oni/draw.odin#L257), [`begin_popover`](oni/draw.odin), [`end_popover`](oni/draw.odin).

Primitives: [`draw_rect`](oni/draw.odin#L269), [`draw_line`](oni/draw.odin#L315), [`draw_texture`](oni/draw.odin#L344), [`draw_atlas_region`](oni/draw.odin#L400), [`draw_texture_fitted`](oni/draw.odin#L414).

## Complete proc index (`oni/batch.odin`)

Lifecycle: [`draw_mode_f32`](oni/batch.odin#L18), [`batch_flip`](oni/batch.odin#L85), [`batch_delete_cpu_arrays`](oni/batch.odin#L94), [`batch_init`](oni/batch.odin#L118), [`batch_create_gpu_buffers`](oni/batch.odin#L134), [`batch_destroy`](oni/batch.odin#L179), [`batch_reset`](oni/batch.odin#L224).

Cache / clip: [`batch_invalidate_clip_cache`](oni/batch.odin#L241), [`batch_invalidate_view_cache`](oni/batch.odin#L249), [`batch_cached_view`](oni/batch.odin#L260), [`batch_current_clip`](oni/batch.odin#L303), [`clip_to_scissor`](oni/batch.odin#L651).

Record: [`batch_ensure_capacity`](oni/batch.odin#L283), [`batch_set_stack_index`](oni/batch.odin#L335), [`batch_check_key`](oni/batch.odin#L344), [`batch_push_indices`](oni/batch.odin#L376), [`batch_push_vertex`](oni/batch.odin#L393), [`batch_push_quad`](oni/batch.odin#L428), [`batch_push_axis_quad`](oni/batch.odin#L473), [`batch_push_atlas_quads`](oni/batch.odin#L531).

Upload / draw: [`batch_finalize_segments`](oni/batch.odin#L561), [`batch_upload`](oni/batch.odin#L590), [`batch_flush_draws`](oni/batch.odin#L680).

## Complete proc index (`oni/view.odin`)

Defaults / zoom: [`view_default`](oni/view.odin#L24), [`view_quantize_zoom`](oni/view.odin#L31), [`view_quantize_zoom_with_step`](oni/view.odin#L41), [`view_effective_zoom`](oni/view.odin#L49), [`view_clamp_zoom`](oni/view.odin#L58), [`view_set_zoom`](oni/view.odin#L67), [`view_zoom_at_screen`](oni/view.odin#L114), [`view_zoom_by_screen`](oni/view.odin#L128), [`view_zoom_in_screen`](oni/view.odin#L136), [`view_zoom_out_screen`](oni/view.odin#L143), [`view_reset`](oni/view.odin#L150).

Pan: [`view_set_pan`](oni/view.odin#L77), [`view_pan_by`](oni/view.odin#L86).

Transforms: [`view_screen_to_world`](oni/view.odin#L95), [`view_world_to_screen`](oni/view.odin#L105), [`view_transform_rect`](oni/view.odin#L162), [`view_transform_point`](oni/view.odin#L180), [`view_artboard_zoom`](oni/view.odin#L188), [`draw_space_to_logical`](oni/view.odin#L200).

## Complete proc index (`oni/present.odin`)

[`present_frame`](oni/present.odin#L16).

## Complete proc index (`oni/gpu.odin`)

[`gpu_load_shader`](oni/gpu.odin#L54), [`gpu_blend_state`](oni/gpu.odin#L87), [`gpu_ui_vertex_layout`](oni/gpu.odin#L104), [`gpu_create_pipeline`](oni/gpu.odin#L164), [`gpu_create_sampler`](oni/gpu.odin#L222), [`gpu_upload_white_pixel`](oni/gpu.odin#L247), [`gpu_create_white_texture`](oni/gpu.odin#L284), [`gpu_update_projection`](oni/gpu.odin#L350), [`gpu_destroy`](oni/gpu.odin#L363), [`gpu_init`](oni/gpu.odin#L389), [`gpu_reload`](oni/gpu.odin#L423).

## Complete proc index (`oni/font.odin` — draw path)

[`font_draw_layout_text`](oni/font.odin#L603), [`font_ensure_glyphs_from_paint`](oni/font.odin#L667), [`font_ensure_glyphs`](oni/font.odin#L185), [`font_rasterize_and_cache_missing`](oni/font.odin#L401), [`font_rasterize_glyph`](oni/font.odin#L491), [`font_resolve`](oni/font.odin#L110), [`font_atlas_reset`](oni/font.odin#L161), [`snap_logical`](oni/font.odin#L594).

## Complete proc index (`oni/texture.odin`)

[`texture_init`](oni/texture.odin#L65), [`texture_shutdown`](oni/texture.odin#L79), [`texture_release_gpu`](oni/texture.odin#L107), [`texture_reload_gpu`](oni/texture.odin#L127), [`texture_register_surface`](oni/texture.odin#L148), [`texture_upload_record`](oni/texture.odin#L215), [`texture_surface_as_rgba8888`](oni/texture.odin#L265), [`texture_fill_transfer_from_surface`](oni/texture.odin#L280), [`texture_create_filled_transfer`](oni/texture.odin#L332), [`texture_upload_surface_deferred`](oni/texture.odin#L358), [`texture_uploads_flush`](oni/texture.odin#L390), [`texture_upload_surface`](oni/texture.odin#L466), [`texture_get_gpu`](oni/texture.odin#L524), [`texture_handle`](oni/texture.odin#L539), [`atlas_region_from`](oni/texture.odin#L555), [`atlas_region_handle`](oni/texture.odin#L564), [`texture_atlas_init`](oni/texture.odin#L573), [`texture_atlas_shutdown`](oni/texture.odin#L602), [`texture_atlas_rebuild_gpu`](oni/texture.odin#L612), [`texture_atlas_alloc`](oni/texture.odin#L631), [`texture_atlas_upload`](oni/texture.odin#L682), [`texture_atlas_pack`](oni/texture.odin#L739).

## Complete proc index (`oni/table_border.odin` — draw path)

[`table_draw_border_strip`](oni/table_border.odin#L409), [`table_draw_collapsed_cell`](oni/table_border.odin#L513), [`table_descendant_outer_radius`](oni/table_border.odin#L443), [`table_merge_radius_corners`](oni/table_border.odin#L428), [`table_collapsed_border_color`](oni/table_border.odin#L391), [`table_side_is_straight`](oni/table_border.odin#L499), [`table_layout_borders_collapsed_for_widget`](oni/table_border.odin#L303).

Layout-side collapse (inputs to draw): [`table_gaps_are_collapsed`](oni/table_border.odin#L3), [`table_border_source_rank`](oni/table_border.odin#L7), [`table_border_compare`](oni/table_border.odin#L21), [`table_border_pick_winner`](oni/table_border.odin#L42), [`table_border_side_width`](oni/table_border.odin#L53), [`table_border_side_from_node`](oni/table_border.odin#L67), [`table_layout_cell_ancestors`](oni/table_border.odin#L83), [`table_layout_append_side_candidates`](oni/table_border.odin#L113), [`table_layout_collect_edge_candidates`](oni/table_border.odin#L127), [`table_border_strip_rect`](oni/table_border.odin#L174), [`table_layout_resolve_collapsed_borders`](oni/table_border.odin#L189), [`table_layout_find_cell_neighbor`](oni/table_border.odin#L316), [`table_f32_max`](oni/table_border.odin#L416), [`table_corners_touch`](oni/table_border.odin#L420).

## Draw-adjacent (`oni/widget.odin`, `oni/widgets/`)

| Proc | Role |
|------|------|
| [`draw_set_stack_index`](oni/widget.odin#L445) | Public batch stack setter |
| [`texture_fit_rects`](oni/widget.odin#L1419) | Object-fit rect math (layout + image draw) |
| [`widget_prepare_draw`](oni/widgets/widget_lifecycle.odin#L118) | Draw gate + lifecycle sync |
| [`widget_handle_interaction`](oni/widgets/widget_interaction.odin#L91) | Draw-pass input + stack index |
| [`widget_dispatch_events`](oni/widgets/widget_interaction.odin#L135) | Handler dispatch |
| [`table_widget_draw_chrome`](oni/widgets/table_shared.odin#L13) | Shared table paint |
| [`draw_widget_rectangle`](oni/widgets/rectangle.odin#L174) | Rectangle chrome + children |
