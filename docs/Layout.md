# Layout

Oni layout is an immediate-mode flex (+ CSS-like grid) engine. Widgets declare a tree during the **Layout** pass; closing a screen/artboard space solves rects; the same tree is rewalked on **Draw** and paints from those rects.

Coordinates are logical design pixels. DPI scale is applied by the engine outside layout. Default containers are flex-like (row/column ± wrap). Nodes with `kind = .GRID` use the track solver in [`layout_grid.odin`](../layout_grid.odin) (see `w.Grid`).

The proc tables are a navigation reference; source files contain the full current inventory.

## Mental model

1. App calls [`o.Render`](../api.odin#L118) once per frame with a UI builder (`main_ui`, …), usually inside the `present_frame` draw callback.
2. [`render`](../ui.odin#L213) runs each builder **twice in sequence**: Layout, then Draw.
3. During Layout, containers push nodes via [`Children`](../style.odin#L1691) / [`layout_push_node`](../layout.odin#L2757); leaves attach text/image measure hints.
4. [`End_Screen`](../api.odin#L113) / [`End_Artboard`](../api.odin#L111) call [`layout_end_space`](../layout.odin#L4988), which **solves** all parentless roots in that space (flex or grid).
5. [`ui_end_layout_pass`](../ui.odin#L156) runs layer/anchor follow-up solve, stack order, pointer hit, focus/tab, shortcuts, then switches to Draw.
6. Draw widgets read [`ui_layout_rect`](../ui.odin#L255) (and text/image results) — they do not re-solve layout.

**Critical timing:** primary flex/grid solve runs when a draw space ends during Layout (`layout_end_space`). `ui_end_layout_pass` still runs [`layout_solve_layer_subtree_roots`](../layout_stack.odin#L426), [`layout_resolve_anchors`](../layout.odin#L4895), stack order, and hit-test before Draw. Do not treat pass end as “no layout work.”

**Multiple builders:** when `Render` receives more than one proc, each builder gets its own Layout → `ui_end_layout_pass` → Draw → `ui_end_frame` cycle. Stack/hit and widget pruning run per builder, not once for the whole frame.

## Frame flow

```
run_frame                          oni/runtime.odin
  input_begin_frame / poll (+ settings_poll)
  ui_begin_frame                   pass = Layout; layout_reset (+ frame arena reset)
  tick(dt)
  present_frame(draw)              app draw → o.Render(main_ui)
    render(ui...)
      for each builder u:
        u()                        Layout pass
          Begin_Screen / Begin_Artboard
            layout_begin_space
            widgets → Children / layout_push_node / measure hints
          End_Screen / End_Artboard
            layout_end_space       ★ primary SOLVE ★
        ui_end_layout_pass         layer/anchor, stack, hit, tab → Draw
        u()                        Draw pass
          same tree; ui_layout_rect + paint + events
        ui_end_frame               prune stale widgets for this builder
  end_frame                        ui_end_frame again (usually no-op)
```

### Host shell

| Proc | Role |
|------|------|
| [`run_frame`](../runtime.odin#L27) | One host frame: begin UI → tick → present → end |
| [`present_frame`](../present.odin#L16) | Record draw (incl. `Render`), upload, flush GPU |
| [`ui_begin_frame`](../ui.odin#L94) | New frame, Layout pass, [`layout_reset`](../layout.odin#L547) |
| [`render`](../ui.odin#L213) / [`Render`](../api.odin#L118) | Per-builder Layout + Draw, with pass transitions |
| [`ui_end_layout_pass`](../ui.odin#L156) | Layer/anchor, stack/hit, focus/tab, switch to Draw |
| [`ui_end_frame`](../ui.odin#L184) | Prune widgets not touched this builder pass |

App code should call `o.Render(...)` once. Only call `ui_end_layout_pass` / `ui_end_frame` manually if you are not using `Render`. Widgets package mirrors this in [`Render`](../widgets/widget_types.odin#L199).

## Two passes

| Concern | Layout (`ui_pass() == .Layout`) | Draw |
|--------|----------------------------------|------|
| Build tree | [`layout_push_node`](../layout.odin#L2757) / [`Children`](../style.odin#L1691) | No new nodes |
| Measure / solve | Yes (on space end) | No |
| Mount / unmount | [`widget_run_layout_lifecycle`](../widgets/widget_lifecycle.odin#L37) | Sync via [`widget_prepare_draw`](../widgets/widget_lifecycle.odin#L118) |
| Tab order | [`widget_register_tab_order`](../widgets/widget_focus.odin#L8) | Consume focus transitions |
| Scope / style stacks | Push/pop | Push/pop again (same structure) |
| Static / auto ids | Cleared at begin + again at end of layout pass | Regenerated identically |
| GPU draw | Avoid | `Draw_*`, events |
| Rects | Written to `Layout_Node.rect` | Read via [`ui_layout_rect`](../ui.odin#L255) |

[`Children`](../style.odin#L1691) pushes scope + style on both passes; **only Layout** pushes/pops layout nodes. `visibility: NONE` skips the whole `Children` body (no nested registration).

### Invariants

1. **Same tree both passes** — same widgets, children order, conditionals, and ids so Layout ids match Draw lookups.
2. **No layout mutation on Draw** — [`layout_push_node`](../layout.odin#L2757) only when `ui_pass() == .Layout`.
3. **Solve before Draw** — rects exist only after `End_Screen` / `End_Artboard` in Layout, then stack/hit finalization.
4. **Id regeneration** — auto/static id maps cleared at layout-pass end so Draw rebuilds the same keys.
5. **Lifecycle** — mount/unmount run on Layout; completed unmount / `visibility: NONE` can skip layout; Draw skips if no layout node.

## Frame arena (per-frame memory)

Layout-owned transient data (child index lists, shaped text lines, glyph quads, decoration strokes, table track arrays) allocates through a **frame arena** reset at each [`layout_reset`](../layout.odin#L547).

| Proc | Role |
|------|------|
| [`layout_frame_allocator`](../layout.odin#L467) | Preferred allocator for frame-owned layout data |
| [`layout_frame_allocator_for`](../layout.odin#L453) | Same, on a specific `Layout_State` |
| [`layout_uses_frame_arena`](../layout.odin#L446) | Whether arena mode is active |
| [`layout_uses_frame_arena_in`](../layout.odin#L439) | Arena check on a specific state |
| [`layout_release_node_children`](../layout.odin#L522) | Skips per-node `delete` when arena is active |
| [`layout_shutdown`](../layout.odin#L611) | Frees persistent layout storage + arena backing |

When the arena is active, [`layout_reset`](../layout.odin#L547) clears node vectors/maps and resets the arena instead of deleting each child list and text buffer. The arena starts with an 8 MiB block and appends blocks on demand without moving existing allocations. At reset, use above half the retained capacity grows the next backing to at least twice capacity/use; multiple blocks otherwise consolidate after their contents are released. Uncached SVG frame instances release revision pins before arena reset. Stable-key snapshots are heap-owned by the SVG layout cache and survive reset until replacement or shutdown. `Render` also reuses a separate scratch block chain when the caller uses Odin's default temp allocator; caller-supplied allocator semantics are preserved.

## Spaces (Screen / Artboard / Popover / Overlay)

A **space** is a layout region tied to a draw space (`.SCREEN`, `.ARTBOARD`, `.POPOVER`, or `.OVERLAY`).

| Proc | Role |
|------|------|
| [`Begin_Screen`](../api.odin#L112) → [`draw_push_screen`](../draw.odin#L323) | Enter screen space; Layout → [`layout_begin_space`](../layout.odin#L4978) |
| [`End_Screen`](../api.odin#L113) → [`draw_pop_screen`](../draw.odin#L335) | Leave screen; Layout → [`layout_end_space`](../layout.odin#L4988) |
| [`Begin_Artboard`](../api.odin#L110) → [`begin_artboard`](../draw.odin#L299) | Same for artboard (zoom-scaled bounds) |
| [`End_Artboard`](../api.odin#L111) → [`end_artboard`](../draw.odin#L312) | End artboard space + solve |
| [`Popover_Begin`](../api.odin#L114) → [`begin_popover`](../draw.odin#L348) | Popover overlay space (screen coords; paints above screen/artboard) |
| [`Popover_End`](../api.odin#L115) → [`end_popover`](../draw.odin#L360) | End popover space + solve |
| [`layout_space_bounds`](../layout.odin#L4682) | Logical bounds; artboard divides by cached zoom |
| [`layout_artboard_zoom`](../layout.odin#L585) | Effective artboard zoom, cached per layout pass |
| [`layout_invalidate_artboard_zoom`](../layout.odin#L601) | Drop zoom cache after view transform changes |
| [`style_root`](../style.odin#L1554) | Root style context for the space |

Use `Begin_Overlay` / `End_Overlay` for the topmost screen-coordinate layer; Dialog and framework error chrome use `.OVERLAY`. Widgets can also opt into popover with `space = set.Space(.POPOVER)` without a begin/end scope.

[`layout_begin_space`](../layout.odin#L4978) records a node-index marker. [`layout_end_space`](../layout.odin#L4988) solves every node since that marker with `parent == -1` against the space bounds.

Artboard bounds use [`layout_artboard_zoom`](../layout.odin#L585), cached for the layout pass and invalidated in [`layout_reset`](../layout.odin#L547) or via [`layout_invalidate_artboard_zoom`](../layout.odin#L601) when the view zoom changes.

## How widgets register

### Stable ids

[`ui_id`](../ui.odin#L313) = CRC32(label) XOR [`ui_parent_hash`](../ui.odin#L298) (FNV over the scope stack). Nested scopes keep ids hierarchical via [`ui_push_scope`](../ui.odin#L280) / [`ui_pop_scope`](../ui.odin#L287). Label CRC32 values are memoized on first use ([`ui_label_crc32`](../ui.odin#L320)) so repeated ids avoid rehashing.

### Container pattern

Canonical shape in [`Button`](../widgets/button.odin#L70):

```odin
if o.ui_pass() == .Layout {
	// widget_run_layout_lifecycle → maybe skip
	// widget_register_tab_order
	o.Children(child, layout_id, config, frame_state)
	return
}
// Draw: widget_prepare_draw, ui_layout_rect, paint, events, Children(...)
```

[`Children`](../style.odin#L1691) → [`being_children`](../style.odin#L1648) → (Layout: [`layout_push_node`](../layout.odin#L2757)) → child builder → [`end_children`](../style.odin#L1667) → (Layout: [`layout_pop_node`](../layout.odin#L2899) → measure).

### Leaves

- **Text:** [`layout_push_node`](../layout.odin#L2757) → [`layout_set_measure_text`](../layout.odin#L2846) → [`layout_pop_node`](../layout.odin#L2899). Draw paints from [`layout_text_result`](../layout.odin#L2400).
- **Image:** push node → optional [`layout_set_measure_size`](../layout.odin#L2891) → [`layout_set_image`](../layout.odin#L2306) (stores author inputs in `image_input`) → pop. Fit finalized in [`layout_finalize_image_node`](../layout.odin#L2325) after rects exist; draw reads [`layout_image_result`](../layout.odin#L2423).

## Measure then solve

Inside each space there are two phases:

### 1. Measure (bottom-up on pop)

[`layout_pop_node`](../layout.odin#L2899) → [`layout_measure`](../layout.odin#L2543):

- **Leaf:** [`layout_measure_leaf`](../layout.odin#L2445) — text shape or width/height/min.
- **Container:** sum in-flow children’s desired sizes + gaps; wrap uses [`layout_wrap_measure`](../layout.odin#L802). Flex children without a definite main size are skipped when summing.

### 2. Solve (top-down on space end)

```
layout_end_space
  layout_solve
    layout_solve_node
      ABSOLUTE/FIXED → layout_place_against_containing_block
      else:
        layout_resolve_node_size → assign rect
        layout_finalize_node (text/image)
        layout_position_children
          TABLE → layout_table_prepare
          wrap → layout_position_children_wrap
          else flex place + recursive layout_solve_node
        layout_wrap_apply_auto_cross_size (if wrap)
      layout_position_out_of_flow_children
```

| Proc | Role |
|------|------|
| [`layout_solve`](../layout.odin#L4675) | Solve a root within bounds |
| [`layout_solve_node`](../layout.odin#L4645) | Size, place, recurse |
| [`layout_resolve_node_size`](../layout.odin#L2987) | Width/height vs bounds, min/max clamp |
| [`layout_apply_definite_size`](../layout.odin#L3027) | Apply definite length axes |
| [`layout_position_children`](../layout.odin#L4335) | Main flex placer |
| [`layout_position_children_wrap`](../layout.odin#L4000) | Wrap line placement |
| [`layout_position_out_of_flow_children`](../layout.odin#L3826) | Absolute/fixed after in-flow |
| [`layout_finalize_node`](../layout.odin#L2358) | Text + image post-rect finalize |

## Flex sizing and positioning

### Main axis

- Definite width/height wins ([`length_resolve`](../style.odin#L12) / [`length_is_definite`](../style.odin#L29)).
- Else `flex > 0` or axis `.GROW` / `.SHRINK`: share remaining main space by weight via [`layout_child_main_size`](../layout.odin). Positive leftover uses grow weights only; deficit uses shrink weights ([`layout_flex_unit_from_remaining`](../layout.odin)). Explicit `flex` uses a zero basis (CSS `flex: 1 1 0%`). Axis `.GROW` uses content desired as basis and takes leftover (and yields on overflow). Axis `.SHRINK` uses content desired as basis, shares deficit with siblings, and ignores leftover. Unset widget `width` resolves to `.GROW`; unset `height` is content-sized (`Length_Kind.UNSET`).
- Else height `.AUTO`: fill the parent content area (scrollport viewport; does not expand with content).
- Else `.FIT`: shrink to content, clamped to available (CSS `fit-content`) via [`layout_resolve_axis_size`](../layout.odin). Measure-indefinite axes (`.FIT` / `.SHRINK` / `.GROW` / min/max-content) zero descendant `content_w`/`content_h`. BALANCE text on indefinite widths uses `min(max-content, provisional)` for desired width (soft-wrap height still uses provisional) so width modes do not require `wrap = .NONE`.
- Else `.MAX_CONTENT`: CSS `max-content` — content size without soft-wrap; never clamps to available or stretches when empty. Intrinsic axes zero descendant content size like `.FIT`.
- Else `.MIN_CONTENT`: CSS `min-content` — smallest size without avoidable overflow (text: longest unbreakable run; flex: sum/max of child `intrinsic_min`). Stored on [`Layout_Node.intrinsic_min`](../layout.odin); never clamps to available.
- Else desired size from measure (width `.AUTO` may stretch to bounds when content is empty).

`Justify_Align.MAX_CONTENT` / `MIN_CONTENT` are unrelated: they equalize sibling sizes on an axis.

### Cross axis

[`layout_child_cross_size`](../layout.odin#L3188): definite size, else stretch (justify STRETCH / `flex` / `.GROW` / height `.AUTO`), else `.FIT` clamp, else `.MIN_CONTENT` / desired. `self` justify can pull a child out of main flow ([`layout_child_in_main_flow`](../layout.odin#L3172)).

### Justify / gap / order

| Proc | Role |
|------|------|
| [`layout_config_direction`](../layout.odin#L640) / [`layout_direction_info`](../layout.odin#L657) | Axis, wrap, reverse |
| [`layout_config_gap_main`](../layout.odin#L853) / [`layout_config_gap_cross`](../layout.odin#L861) | Gaps |
| [`layout_config_justify`](../layout.odin#L869) / [`layout_merge_justify`](../layout.odin#L876) | Parent + self |
| [`layout_main_justify_align`](../layout.odin#L3560) / [`layout_cross_justify_align`](../layout.odin#L3576) | Axis aligns |
| [`layout_space_leading`](../layout.odin#L3592) / [`layout_space_between_items`](../layout.odin#L3719) / [`layout_space_positions`](../layout.odin#L3736) | space-between/around/evenly |
| [`layout_content_align_target`](../layout.odin#L3612) / [`layout_apply_content_align_sizes`](../layout.odin#L3707) | MAX/MIN_CONTENT |
| [`layout_sort_children_by_order`](../layout.odin#L2729) | Flex `order` |
| [`layout_mirror_in_available`](../layout.odin#L701) | Reverse-axis mirror |
| [`layout_position_child_rect`](../layout.odin#L3768) | Write one child’s rect + recurse |

### Wrap

| Proc | Role |
|------|------|
| [`layout_wrap_main_limit_from_config`](../layout.odin#L718) | Main limit for line breaks |
| [`layout_wrap_child_main`](../layout.odin#L738) / [`layout_wrap_child_cross`](../layout.odin#L745) | Axis extractors |
| [`layout_wrap_build_lines`](../layout.odin#L752) | Pack wrap lines |
| [`layout_wrap_measure`](../layout.odin#L802) | Intrinsic wrap size |
| [`layout_wrap_apply_auto_cross_size`](../layout.odin#L4308) | Grow wrap container after place |

### Boxes and clamps

| Proc | Role |
|------|------|
| [`layout_clamp_axis`](../layout.odin#L885) | min/max clamp |
| [`layout_content_rect`](../layout.odin#L895) | Outer − padding |
| [`layout_inner_rect`](../layout.odin#L907) | Outer − border − padding (content box for children) |
| [`layout_margin_box`](../layout.odin#L945) | Border box expanded by margin (flow allocation; not paint/hit) |

## Out of flow, visibility, clipping

| Mode | Containing block | Notes |
|------|------------------|-------|
| RELATIVE / STICKY | In flex flow | Sticky clamps into clip |
| ABSOLUTE | Parent padding box | Pins: `x` / `y` / `right` / `bottom` |
| FIXED | Space bounds (popover uses viewport) | Same pins; out of flex gap |

| Proc | Role |
|------|------|
| [`layout_position_kind`](../layout_stack.odin#L33) | Resolve position mode |
| [`layout_position_in_flex_flow`](../layout_stack.odin#L107) | Relative/sticky in flow |
| [`layout_place_against_containing_block`](../layout_stack.odin#L157) | Absolute/fixed geometry |
| [`layout_place_out_of_flow`](../layout_stack.odin#L237) | Choose CB + place |
| [`layout_visibility_is_none`](../layout_stack.odin#L47) / [`layout_visibility_is_hidden`](../layout_stack.odin#L55) | Visibility |
| [`layout_pointer_events_none`](../layout_stack.odin#L63) | Hit policy |
| [`layout_overflow_clips`](../layout_stack.odin#L71) / [`layout_overflow_is_scrollport`](../layout_stack.odin#L81) | Overflow |
| [`layout_padding_box`](../layout_stack.odin#L90) / [`layout_clip_box`](../layout_stack.odin#L100) | Boxes |
| [`layout_resolve_clips`](../layout_stack.odin#L256) | Cumulative clips + sticky |

- `visibility: NONE` — omitted from tree (`Children` early-out).
- `visibility: HIDDEN` — keeps layout space; `paint_skip` + `hit_skip`.
- `pointer_events: NONE` — hit skip only.

## CSS-like grid

Containers with `kind = .GRID` (via `w.Grid`) measure and position with [`layout_grid_measure`](../layout_grid.odin#L456) / [`layout_grid_position_children`](../layout_grid.odin#L524) and helpers in [`layout_grid.odin`](../layout_grid.odin). Children use grid placement fields on their own config. Flex layout is unchanged for non-grid nodes.

## Stack order and pointer hit

After a builder’s layout tree is primarily solved on space end, [`ui_end_layout_pass`](../ui.odin#L156) runs:

1. [`layout_solve_layer_subtree_roots`](../layout_stack.odin#L426) / [`layout_resolve_anchors`](../layout.odin#L4895) — follow-up solve
2. [`layout_finalize_stack_order`](../layout_stack.odin#L444) — clips, paint lists, `stack_index`
3. [`layout_resolve_pointer_hit`](../layout_stack.odin#L562) — topmost hittable under pointer
4. Focus prune, tab navigation, shortcuts — then `pass = .Draw`

Paint list order: artboard roots → screen roots → popover roots → overlay roots. Within siblings: negative `z` under parent chrome, then parent, then non-negative `z`; tie-break `order` then node index. Each popover/overlay root is its own stacking context. Hit test walks paint lists front-to-back: overlay → popover → screen → artboard.

| Proc | Role |
|------|------|
| [`layout_assign_stack`](../layout_stack.odin#L373) | Assign stack indices into a paint list |
| [`layout_is_layer_subtree_root`](../layout_stack.odin#L326) | Popover root detection |
| [`layout_stack_child_less`](../layout_stack.odin#L334) / [`layout_sort_stack_children`](../layout_stack.odin#L347) | Sibling sort |
| [`layout_hit_point_in_node`](../layout_stack.odin#L521) / [`layout_hit_test_list`](../layout_stack.odin#L541) | Hit helpers |
| [`begin_popover`](../draw.odin#L348) / [`end_popover`](../draw.odin#L360) | Popover space scope (`Popover_Begin` / `End`) |
| [`ui_layout_stack_index`](../layout_stack.odin#L115) | Draw query |
| [`ui_layout_paint_skip`](../layout_stack.odin#L125) / [`ui_layout_hit_skip`](../layout_stack.odin#L135) | Skip flags |
| [`ui_layout_clip_rect`](../layout_stack.odin#L145) | Clip query |

## Tables

`justify: TABLE_CELL` equalizes column widths / row heights across head/body/foot rows.

| Proc | Role |
|------|------|
| [`layout_find_table_ancestor`](../layout.odin#L3289) | Walk to TABLE |
| [`layout_node_is_table_cell`](../layout.odin#L3296) | Cell kind check |
| [`layout_node_participates_in_table_collapse`](../layout.odin#L3303) | Collapse participants |
| [`layout_justify_uses_TABLE_CELL_x`](../layout.odin#L3314) / [`layout_justify_uses_TABLE_CELL_y`](../layout.odin#L3322) | Axis flags |
| [`layout_table_cell_intrinsic_axis`](../layout.odin#L3330) | Intrinsic cell size |
| [`layout_table_collect_rows_in`](../layout.odin#L3352) | Collect rows |
| [`layout_table_prepare`](../layout.odin#L3459) | Build shared tracks |
| [`layout_table_apply_cell_size`](../layout.odin#L3466) | Apply track size to cell |
| [`layout_table_finalize`](../layout.odin#L3553) | Assign cell positions |

`Layout_Table_Tracks` stores `col_count`, shared `col_widths` / `row_heights`, `cell_positions`, and per-cell `collapsed_borders` when border collapse is active. Track arrays allocate through the frame arena.

Collapsed gaps zero layout borders on push; paint conflict resolution lives in [`table_border.odin`](../table_border.odin) ([`table_gaps_are_collapsed`](../table_border.odin#L3), [`table_layout_resolve_collapsed_borders`](../table_border.odin#L189), …). Draw reads [`layout_collapsed_borders_result`](../layout.odin#L2434).

## Text and image (layout-owned geometry)

| Proc | Role |
|------|------|
| [`layout_text_resolve_wrap_w`](../layout.odin#L1009) | Wrap width |
| [`layout_text_build`](../layout.odin#L1328) | Shape text |
| [`layout_text_position_lines`](../layout.odin#L1469) | Line origins |
| [`layout_text_position_glyphs`](../layout.odin#L1635) | Glyph quads |
| [`layout_text_append_decoration_stroke`](../layout.odin#L2038) / [`layout_text_position_decorations`](../layout.odin#L2096) | Underline etc. |
| [`layout_finalize_text_node`](../layout.odin#L2280) | Post-rect text finalize |
| [`layout_set_image`](../layout.odin#L2306) | Capture author image inputs into `image_input` |
| [`layout_finalize_image_node`](../layout.odin#L2325) | Object-fit into content box → `image` |
| [`layout_text_result`](../layout.odin#L2400) / [`layout_image_result`](../layout.odin#L2423) | Draw queries |

Shaped lines may borrow the persistent font shape cache (`Layout_Text.lines_borrowed`); do not free these slices. Cache keys include face, text, spacing, tab size, wrap width/mode and direction, and DPI/font reload invalidates cached entries. Glyph quads, line origins and decoration strokes remain frame-owned. `Layout_Node` keeps author image params in `image_input` during measure; finalized paint geometry is in `image`.

## Vector geometry and snapshots

[`layout_vector.odin`](../layout_vector.odin) stores the viewport, fitted source/destination rectangles and immutable frame snapshot/reference for `w.Vector` and `w.Svg`. Stable layout keys can reuse a heap-owned SVG instance when asset revision, fit and overrides match. SVG intrinsic dimensions participate in measure; a single definite axis can determine the other from the intrinsic ratio. Draw reads `layout_vector_result` and uses the captured viewport/instance rather than recomputing it from potentially changed app state. This does not add a general `aspect_ratio` style field.

## Lifecycle and focus (layout-adjacent)

| Proc | Role |
|------|------|
| [`widget_run_layout_lifecycle`](../widgets/widget_lifecycle.odin#L37) | Mount/unmount on Layout |
| [`widget_prepare_draw`](../widgets/widget_lifecycle.odin#L118) | Draw gate + phase sync |
| [`widget_can_interact`](../widgets/widget_lifecycle.odin#L23) | Interaction during mount/unmount |
| [`widget_lifecycle_entry`](../widget.odin#L1707) / [`widget_lifecycle_remove`](../widget.odin#L1725) | Persist mount state |
| [`widget_prune_focus`](../widget.odin#L480) | Post-layout focus prune |
| [`widget_process_tab_navigation`](../widget.odin#L541) | Tab order after layout |
| [`widget_register_tab_order`](../widgets/widget_focus.odin#L8) | Register during Layout |
| [`widget_prune_element_maps`](../widget.odin#L378) | End-of-frame map prune |

## Key types

| Type | File | Role |
|------|------|------|
| `UI_Pass` | [oni/ui.odin](../ui.odin) | `.Layout` / `.Draw` |
| `Layout_State` | [oni/layout.odin](../layout.odin) | Nodes, stacks, id map, paint lists, space, frame arena, artboard zoom |
| `Layout_Node` | [oni/layout.odin](../layout.odin) | Style, desired, rect, children, text/image, stack/hit/clip |
| `Layout_Measure` | [oni/layout.odin](../layout.odin) | Author text + max_w hint |
| `Layout_Glyph_Paint` / `Layout_Decoration_Stroke` | [oni/layout.odin](../layout.odin) | Layout-owned glyph quads and decoration segments |
| `Layout_Text` / `Layout_Image_Input` / `Layout_Image` / `Layout_Collapsed_Borders` | [oni/layout.odin](../layout.odin) | Layout-owned paint geometry |
| `Layout_Table_Tracks` | [oni/layout.odin](../layout.odin) | Shared col/row sizes, cell positions, collapsed borders |
| `Resolved_Widget_Style` / `Resolved_Widget_Config` | [oni/types.odin](../types.odin) | Concrete style for layout |
| `Length` / `Direction_Layout` / `Justify_Pos` / `Position` | [oni/types.odin](../types.odin) | Sizing, direction, justify, position |
| `Draw_Space` / `Rect` | [oni/types.odin](../types.odin) | SCREEN / ARTBOARD / POPOVER / OVERLAY; logical rect |
| `Style_Context` | [oni/types.odin](../types.odin) | Style + content_w/h for percent/text wrap |
| `Layout_Position_Kind` | [oni/layout_stack.odin](../layout_stack.odin) | Resolved position mode |

## UI query helpers

| Proc | Role |
|------|------|
| [`ui_pass`](../ui.odin#L246) | Current pass |
| [`ui_layout_rect`](../ui.odin#L255) | Solved rect by id |
| [`ui_was_laid_out_prev`](../ui.odin#L265) | Present last frame |
| [`ui_has_layout_node`](../ui.odin#L272) | Present this frame |
| [`ui_init`](../ui.odin#L18) / [`ui_shutdown`](../ui.odin#L43) | Allocate / tear down UI + layout |
| [`layout_reset`](../layout.odin#L547) / [`layout_shutdown`](../layout.odin#L611) | Per-frame clear / free dynamics |
| [`layout_release_node_children`](../layout.odin#L522) | Free child lists + text (skipped under arena) |
| [`layout_is_ancestor_of`](../layout.odin#L3259) | Ancestry check |
| [`layout_node_index`](../layout.odin#L3252) | Node → index |

## Style / Children helpers

| Proc | Role |
|------|------|
| [`length_resolve`](../style.odin#L12) / [`length_is_definite`](../style.odin#L29) | Axis length math |
| [`style_root`](../style.odin#L1554) / [`style_child_context`](../style.odin#L1574) | Root/child style contexts |
| [`ui_style_current`](../style.odin#L1618) / [`ui_push_style`](../style.odin#L1629) / [`ui_pop_style`](../style.odin#L1638) | Style stack |
| [`being_children`](../style.odin#L1648) / [`end_children`](../style.odin#L1667) | Enter/leave container |
| [`Children`](../style.odin#L1691) | Scoped child builder |

## Widget entry points

These branch on [`ui_pass`](../ui.odin#L246) and use `Children` and/or `layout_push_node`:

[`Button`](../widgets/button.odin#L70), [`Rectangle`](../widgets/rectangle.odin#L64), [`Text`](../widgets/text.odin#L129), [`Image`](../widgets/image.odin#L177), [`Table`](../widgets/table.odin#L69), [`Table_Caption`](../widgets/table_caption.odin#L66), [`Table_Head`](../widgets/table_head.odin#L72), [`Table_Heading`](../widgets/table_heading.odin#L72), [`Table_Body`](../widgets/table_body.odin#L72), [`Table_Row`](../widgets/table_row.odin#L73), [`Table_Cell`](../widgets/table_cell.odin#L71), [`Table_Foot`](../widgets/table_foot.odin#L72).

## Proc reference (`oni/layout.odin`)

Frame arena / reset: [`layout_uses_frame_arena_in`](../layout.odin#L439), [`layout_uses_frame_arena`](../layout.odin#L446), [`layout_frame_allocator_for`](../layout.odin#L453), [`layout_frame_allocator`](../layout.odin#L467), [`layout_frame_arena_ensure`](../layout.odin#L473), [`layout_frame_arena_reset`](../layout.odin#L481), [`layout_frame_arena_destroy`](../layout.odin#L508), [`layout_release_node_children`](../layout.odin#L522), [`layout_reset`](../layout.odin#L547), [`layout_artboard_zoom`](../layout.odin#L585), [`layout_invalidate_artboard_zoom`](../layout.odin#L601), [`layout_shutdown`](../layout.odin#L611).

Lifecycle / tree: [`layout_push_node`](../layout.odin#L2757), [`layout_pop_node`](../layout.odin#L2899), [`layout_set_measure_text`](../layout.odin#L2846), [`layout_set_measure_size`](../layout.odin#L2891), [`layout_begin_space`](../layout.odin#L4978), [`layout_end_space`](../layout.odin#L4988), [`layout_space_bounds`](../layout.odin#L4682).

Direction / wrap / gap / justify: [`layout_config_direction`](../layout.odin#L640), [`layout_direction_info`](../layout.odin#L657), [`layout_direction_is_horizontal`](../layout.odin#L687), [`layout_direction_is_wrap`](../layout.odin#L694), [`layout_mirror_in_available`](../layout.odin#L701), [`layout_wrap_main_limit_from_config`](../layout.odin#L718), [`layout_wrap_child_main`](../layout.odin#L738), [`layout_wrap_child_cross`](../layout.odin#L745), [`layout_wrap_build_lines`](../layout.odin#L752), [`layout_wrap_measure`](../layout.odin#L802), [`layout_config_gap_main`](../layout.odin#L853), [`layout_config_gap_cross`](../layout.odin#L861), [`layout_config_justify`](../layout.odin#L869), [`layout_merge_justify`](../layout.odin#L876).

Boxes / measure / size: [`layout_clamp_axis`](../layout.odin#L885), [`layout_content_rect`](../layout.odin#L895), [`layout_inner_rect`](../layout.odin#L907), [`layout_measure_leaf`](../layout.odin#L2445), [`layout_measure`](../layout.odin#L2543), [`layout_sort_children_by_order`](../layout.odin#L2729), [`layout_resolve_node_size`](../layout.odin#L2987), [`layout_apply_definite_size`](../layout.odin#L3027), [`layout_child_main_size`](../layout.odin#L3103), [`layout_child_in_main_flow`](../layout.odin#L3172), [`layout_child_cross_size`](../layout.odin#L3188).

Text / image: [`layout_node_has_text`](../layout.odin#L959), [`layout_text_release`](../layout.odin#L990), [`layout_text_resolve_wrap_w`](../layout.odin#L1009), [`layout_text_build`](../layout.odin#L1328), [`layout_text_position_lines`](../layout.odin#L1469), [`layout_text_position_glyphs`](../layout.odin#L1635), [`layout_text_append_decoration_stroke`](../layout.odin#L2038), [`layout_text_position_decorations`](../layout.odin#L2096), [`layout_finalize_text_node`](../layout.odin#L2280), [`layout_set_image`](../layout.odin#L2306), [`layout_finalize_image_node`](../layout.odin#L2325), [`layout_finalize_node`](../layout.odin#L2358), [`layout_text_result`](../layout.odin#L2400), [`layout_image_result`](../layout.odin#L2423), [`layout_collapsed_borders_result`](../layout.odin#L2434).

Index / ancestry: [`layout_node_index_in`](../layout.odin#L3243), [`layout_node_index`](../layout.odin#L3252), [`layout_is_ancestor_of`](../layout.odin#L3259).

Tables: [`layout_find_table_ancestor_in`](../layout.odin#L3276), [`layout_find_table_ancestor`](../layout.odin#L3289), [`layout_node_is_table_cell`](../layout.odin#L3296), [`layout_node_participates_in_table_collapse`](../layout.odin#L3303), [`layout_justify_uses_TABLE_CELL_x`](../layout.odin#L3314), [`layout_justify_uses_TABLE_CELL_y`](../layout.odin#L3322), [`layout_table_cell_intrinsic_axis`](../layout.odin#L3330), [`layout_table_collect_rows_in`](../layout.odin#L3352), [`layout_table_row_track_index`](../layout.odin#L3381), [`layout_table_prepare_in`](../layout.odin#L3391), [`layout_table_prepare`](../layout.odin#L3459), [`layout_table_apply_cell_size`](../layout.odin#L3466), [`layout_table_finalize_in`](../layout.odin#L3494), [`layout_table_finalize`](../layout.odin#L3553).

Justify / place / solve: [`layout_main_justify_align`](../layout.odin#L3560), [`layout_cross_justify_align`](../layout.odin#L3576), [`layout_space_leading`](../layout.odin#L3592), [`layout_content_align_target`](../layout.odin#L3612), [`layout_sibling_axis_extrema`](../layout.odin#L3625), [`layout_apply_content_align_axis`](../layout.odin#L3640), [`layout_apply_content_align_sizes_indices`](../layout.odin#L3653), [`layout_apply_content_align_sizes`](../layout.odin#L3707), [`layout_space_between_items`](../layout.odin#L3719), [`layout_space_positions`](../layout.odin#L3736), [`layout_position_child_rect`](../layout.odin#L3768), [`layout_position_out_of_flow_children`](../layout.odin#L3826), [`layout_position_children_wrap`](../layout.odin#L4000), [`layout_wrap_apply_auto_cross_size`](../layout.odin#L4308), [`layout_position_children`](../layout.odin#L4335), [`layout_solve_node`](../layout.odin#L4645), [`layout_solve`](../layout.odin#L4675).

## Proc reference (`oni/layout_stack.odin`)

[`layout_position_kind`](../layout_stack.odin#L33), [`layout_visibility_is_none`](../layout_stack.odin#L47), [`layout_visibility_is_hidden`](../layout_stack.odin#L55), [`layout_pointer_events_none`](../layout_stack.odin#L63), [`layout_overflow_clips`](../layout_stack.odin#L71), [`layout_overflow_is_scrollport`](../layout_stack.odin#L81), [`layout_padding_box`](../layout_stack.odin#L90), [`layout_clip_box`](../layout_stack.odin#L100), [`layout_position_in_flex_flow`](../layout_stack.odin#L107), [`ui_layout_stack_index`](../layout_stack.odin#L115), [`ui_layout_paint_skip`](../layout_stack.odin#L125), [`ui_layout_hit_skip`](../layout_stack.odin#L135), [`ui_layout_clip_rect`](../layout_stack.odin#L145), [`layout_place_against_containing_block`](../layout_stack.odin#L157), [`layout_place_out_of_flow`](../layout_stack.odin#L237), [`layout_resolve_clips`](../layout_stack.odin#L256), [`layout_is_layer_subtree_root`](../layout_stack.odin#L326), [`layout_stack_child_less`](../layout_stack.odin#L334), [`layout_sort_stack_children`](../layout_stack.odin#L347), [`layout_assign_stack`](../layout_stack.odin#L373), [`layout_finalize_stack_order`](../layout_stack.odin#L444), [`layout_hit_point_in_node`](../layout_stack.odin#L521), [`layout_hit_test_list`](../layout_stack.odin#L541), [`layout_resolve_pointer_hit`](../layout_stack.odin#L562).
