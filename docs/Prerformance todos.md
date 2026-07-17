# Prerformance todos

## Arenas
There is **no** `mem.Arena` in the tree. The only arena-like path is Odin’s `context.temp_allocator`, and it’s used sparingly (`fmt.tprintf`, a few `clone_to_cstring`s, map-key sweeps). The host already `free_all`s temp once per loop after the frame.

What should lean on arenas (or temp) harder:

### 1. Layout solve scratch — clearest win
`oni/layout.odin` is full of per-node, same-proc `[dynamic]` + `defer delete` noise during wrap/flex/table layout:

- `layout_wrap_measure` / `layout_wrap_build_lines`
- `layout_position_children_wrap` (`child_sizes`, `lines`, `line_cross_sizes`, `line_indices`, …)
- non-wrap position path (`child_sizes`, `child_nodes`, `in_flow`, `main_positions`, …)
- justify helpers (`sizes`, `indices`, `positions`)
- `layout_table_collect_rows_in` DFS `stack`

These never outlive the proc. They should be `context.temp_allocator` (or a layout scratch arena). Today they hit the tracking/default allocator every frame.

### 2. Frame-scoped layout / text ownership — bigger redesign
Also rebuilt every frame and wiped in `layout_reset` / `layout_text_release`:

| What | Where |
|------|--------|
| Shaped glyphs / lines | `font_shape`, `font_make_shaped_line`, wrap helpers in `font_shaper.odin` |
| Line origins, glyph paint quads, decoration strokes | `layout_text_position_*` |
| `child_indices` per node | allocated on push, `delete`d in `layout_release_node_children` |
| Table tracks (`rows`, col/row sizes, `cell_positions`) | `layout_table_prepare_in` |

A **layout/frame arena** reset in `layout_reset` (instead of dozens of `delete`s) fits this lifetime. Putting them on the global temp allocator as-is is unsafe: temp is wiped at end of the host loop, but `layout_text_release` still `delete`s those pointers at the start of the next frame.

Balance wrap is an especially bad heap churner: `font_shape_lines_balance` allocates trial soft-wraps and `font_destroy_shaped_lines`s them in a loop.

### 3. Already fine / not arena candidates
- **Batch** (`batch.odin`) — growing dynamics, cleared per frame; capacity reuse is enough.
- **Persistent maps** (widgets, glyph cache, assets, static ids) — long-lived; keep general allocator.
- **Tengu** timeline/keyframe `make(..., allocator)` — owned configs, not frame scratch.
- Places that **already** use temp correctly: auto element ids, widget map pruning, cstring path clones in shaping/assets.

**Bottom line:** the payoff is almost entirely in **layout + text shaping**. Start by routing layout-solve scratch to temp; step two is a dedicated frame arena reset from `layout_reset` for text/table/`child_indices` so you can stop per-object teardown.


## Pre-compute

Immediate-mode rebuilds the UI tree every frame — the wins are caching stable intermediates, not skipping layout/draw.

### Already precomputed
Shaders (glslc + #load), Tailwind palette, glyph atlas, font faces, texture path cache, ortho projection (on resize/DPI only), theme at init/reload, Tengu ease constants.

### Highest impact
HarfBuzz shaping (font_shape in oni/font_shaper.odin) — builds a buffer, shapes, allocates []Shaped_Glyph every call. Glyph raster is cached; shapes are not. Static labels reshape every frame via layout (layout_text_build / measure / wrap). Best candidate: cache by face + text + spacing + wrap + direction, invalidate on DPI/zoom/reload.

Style merge + resolve ×2–3 per widget (widget_refresh_merged → merge_widget_config / resolve_widget_config) — large config merges each layout and draw pass. Most props are static set.* literals; only proc colors / hover / parent inherit need live resolve.

theme_widget_style() (oni/style.odin) — rebuilds a full Resolved_Widget_Style on every resolve. Theme is nearly constant between reloads; memoize until theme swap.

### Medium
UI id hashes (ui_id CRC32 of stable string labels) — prehash/intern literals
Resolved RGBA — palette lookup is already O(1); avoid re-walking to_rgba at draw when resolve already fixed the color
Collapsed table borders (table_layout_resolve_collapsed_borders) — cache when grid + border styles unchanged
Tengu cubic ease (bezier_solve_t_for_x) — optional LUTs for fixed curves

### Must stay live
Hot-reload rebinds, DPI/window size, both UI passes, input-driven style procs, Tengu dt animation, artboard zoom for raster size.

**Priority:** shaped-text cache → memoize theme_widget_style / dirty-skip static resolve → prehash static UI ids.


## Bulk/Batch
Already batched strongly: GPU draw (oni/batch.odin) — quads merge by texture/clip/stack, one upload + segment draws per frame. Layout solves the whole tree; HarfBuzz shapes whole strings; Tengu already has parallel/sequence/timeline groups.
### Best batching opportunities:

| Area	      | What’s per-item today	| Could batch |
|-------------|-------------------------|-------------|
| Fonts/atlas | Each glyph miss → FT render + texture_upload_surface (own GPU submit)| Deferred atlas uploads / shared copy pass for miss sets |
| Texture reload | texture_reload_gpu uploads each record separately |One multi-upload / single command buffer after hot reload |
| Text draw CPU| N × draw_atlas_region / batch_push_*| Multi-glyph push helper (same atlas key usually merges anyway) |
| Tables| Nested cell/border walks| Collect borders once, emit strips (drawing already goes through the batch) |
| Tests| test_all.sh runs packages sequentially| Parallel odin test for colors, tengu, oni, oni/widgets |
| Build| Serial glslc for the two UI shaders| Parallel compile (small win) |


**Low leverage:** colors (palette already bulk; runtime N is tiny), input (SDL poll already coalesces), hot-reload DLL swap itself (one .so; the cost is the GPU rebind storm after).

**Highest ROI:** glyph/texture GPU uploads — draw batching is done; transfer submit count is the remaining bulk gap.

## Paralleism
Runtime is single-threaded today (sync.Mutex is only in tests). Here’s what can actually be parallelized vs what can’t.

### Easy wins (build / test)
test_all.sh — colors, oni, oni/widgets, tengu run serially; they’re independent processes and can run concurrently.
build_hot_reload.sh — after shaders, build_app and build_host can run in parallel; the two glslc jobs can too.

### Real runtime wins
Overlap UI with swapchain wait — WaitAndAcquireGPUSwapchainTexture happens before layout/draw/batch. Double-buffered batches let CPU work run while waiting on present (largest frame-pacing win; bigger redesign).
Glyph rasterization — font_rasterize_glyph is serial; FreeType work can fan out into temp bitmaps, then serial atlas pack/upload.
Text shaping — can batch/parallelize after collecting shape jobs, but needs a deferred-measure redesign (wrap width depends on parents).
Reload / assets — texture re-upload, font probing, preload/decode can parallelize on CPU I/O; GPU register/upload stays on the engine thread.

### Don’t parallelize

Layout then Draw — Draw needs solved rects; same tree both passes.
Flex measure/position — parent/child and sibling dependencies.
Batch emit / flush — paint order + shared clip/vertex streams.
Input / hot-reload host loop — must stay on the host thread.
Tengu Parallel_* — animation composition, not threads; work is too small for OS threads.

*Shortlist:** parallel package tests and app+host builds now; double-buffer around present wait and parallel glyph rasterize for runtime; leave the IM layout/draw walk alone.

## Hoist invariants

Highest-value hoist candidates, ranked by how often they re-run relative to how little they change:

### Draw / batch (hot per quad)

- **draw_effective_opacity() (draw.odin)** — multiplies the whole opacity stack on every batch_push_quad. Cache a running product; update only on push/pop.
- **batch_current_clip() (batch.odin)** — rebuilt on every batch_check_key (viewport from DPI + stack top + view_transform_rect). Clip only changes on push/pop/space change; cache it.
- **view_transform_rect / draw_current_space() (view.odin)** — space stack top + zoom/pan looked up per transform. Space/zoom/pan are invariants within a draw region; cache zoom/pan/space while recording.
-**draw_mode_f32(mode) inside batch_push_vertex** — same mode for all 4 corners; compute once in batch_push_quad.
- **batch_flush_draws** — state.gpu_state.sampler is segment-invariant; only texture/scissor change per seg.

### Style resolve (hot per widget × 2 passes)

- ** theme_widget_style() (style.odin)** — rebuilds a full Resolved_Widget_Style on every resolve_widget_config. Theme is effectively frame/session-stable; cache until theme mutates.
- ** Widgets’ double widget_refresh_merged → resolve_widget_config** — once at start, again after interaction on Draw. Second pass is needed when hover/focus/press changes stateful colors; hoist/skip when frame_state interaction bits did not change.
- ** Parent/ui_style_current()** for a widget is fixed for that call subtree; fields that don’t depend on state/event procs could resolve once and reuse.

### Layout

- **layout_direction_info(direction)** — often already local; layout_solve_node still recomputes it for wrap after layout_position_children already has it.
- **layout_measure_leaf** — length_resolve(width/height) done, then done again for definite overrides; keep first results.
- **layout_position_children_wrap** — parent gap_*, justify, main_available are already hoisted; per-line children still re-run layout_child_main_size / layout_merge_justify three times. Reuse first-pass sizes where flex didn’t change.

## Text / fonts
- ** Table track loops** — column count / collapsed-gap flags are table-level invariants reused across row/col walks.
- ** layout_text_position_glyphs** — face, face_id, scale, face.ascent * scale are loop-invariant (ascent×scale already partly used).
font_draw_layout_text — laid.font.id rebuilt into every Font_Glyph_Key; hoist face_id.
- ** Artboard view_effective_zoom() inside font_resolve** — constant for a whole artboard layout pass.

### Smaller / already mostly fine
- Gaps/padding/border insets in layout_measure / wrap measure — already outside child loops in the main path.
- ** ui_pass() — cheap; could be a local in widget entry, not worth much alone.

### Biggest wins: 
cached opacity + clip in the batch, cached theme_widget_style, and skipping the second style resolve when interaction state is unchanged.


## Cache-miss / separate-allocation patterns

A few places, plus a lot of heap churn that isn’t really a cache.

### True cache miss → work / alloc

1. Glyph atlas (font_ensure_glyphs in oni/font.odin) — miss → FreeType rasterize + atlas pack/upload, then insert into glyph_cache. Called out in your performance notes as the main transfer-batching gap.

2. Assets (assets_load_texture in oni/assets.odin) — miss → load surface, register texture, strings.clone(path) into the path map.

3. Widget lifecycle (widget_lifecycle_entry in oni/widget.odin) — miss → insert an empty UI_Widget_Entry into the widgets map (map growth / entry alloc, long-lived).

### Allocates every time (no shape cache)

HarfBuzz shaping (font_shape in oni/font_shaper.odin) — rasters are cached; shapes are not. Every call does make([]Shaped_Glyph, n) (and wrap/balance paths allocate more). That’s the main “separate heap allocation per use” cost, not a miss of an existing cache.

### Related (frame scratch, not a lookup miss)

Layout wrap/flex/table in oni/layout.odin does many same-proc [dynamic] + defer delete allocations — separate heaps each frame, which is the arena section of Prerformance todos.md.

So: glyph/asset/widget maps allocate (or heavier work) on miss; shaping and layout scratch allocate repeatedly with no hit path.
