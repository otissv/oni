# Layout

Oni layout is an immediate-mode flex (+ CSS-like grid) engine. Widgets declare a tree during the **Layout** pass; closing a screen/artboard space solves rects; the same tree is rewalked on **Draw** and paints from those rects.

Coordinates are logical design pixels. DPI scale is applied by the engine outside layout. Default containers are flex-like (row/column ± wrap). Nodes with `kind = .GRID` use the track solver in [`layout_grid.odin`](../layout_grid.odin) (see `w.Grid`).

## Mental model

1. App calls [`o.Render`](../api.odin#L102) once per frame with a UI builder (`main_ui`, …), usually inside the `present_frame` draw callback.
2. [`render`](../ui.odin#L208) runs each builder **twice in sequence**: Layout, then Draw.
3. During Layout, containers push nodes via [`Children`](../style.odin#L1695) / [`layout_push_node`](../layout.odin#L2522); leaves attach text/image measure hints.
4. [`End_Screen`](../api.odin#L97) / [`End_Artboard`](../api.odin#L95) call [`layout_end_space`](../layout.odin#L4645), which **solves** all parentless roots in that space (flex or grid).
5. [`ui_end_layout_pass`](../ui.odin#L151) runs layer/anchor follow-up solve, stack order, pointer hit, focus/tab, shortcuts, then switches to Draw.
6. Draw widgets read [`ui_layout_rect`](../ui.odin#L240) (and text/image results) — they do not re-solve layout.

**Critical timing:** primary flex/grid solve runs when a draw space ends during Layout (`layout_end_space`). `ui_end_layout_pass` still runs [`layout_solve_layer_subtree_roots`](../layout_stack.odin#L426), [`layout_resolve_anchors`](../layout.odin#L4562), stack order, and hit-test before Draw. Do not treat pass end as “no layout work.”

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
| [`ui_begin_frame`](../ui.odin#L92) | New frame, Layout pass, [`layout_reset`](../layout.odin#L313) |
| [`render`](../ui.odin#L208) / [`Render`](../api.odin#L102) | Per-builder Layout + Draw, with pass transitions |
| [`ui_end_layout_pass`](../ui.odin#L151) | Layer/anchor, stack/hit, focus/tab, switch to Draw |
| [`ui_end_frame`](../ui.odin#L179) | Prune widgets not touched this builder pass |

App code should call `o.Render(...)` once. Only call `ui_end_layout_pass` / `ui_end_frame` manually if you are not using `Render`. Widgets package mirrors this in [`Render`](../widgets/widget_types.odin#L195).

## Two passes

| Concern | Layout (`ui_pass() == .Layout`) | Draw |
|--------|----------------------------------|------|
| Build tree | [`layout_push_node`](oni/layout.odin#L2522) / [`Children`](oni/style.odin#L1695) | No new nodes |
| Measure / solve | Yes (on space end) | No |
| Mount / unmount | [`widget_run_layout_lifecycle`](oni/widgets/widget_lifecycle.odin#L37) | Sync via [`widget_prepare_draw`](oni/widgets/widget_lifecycle.odin#L118) |
| Tab order | [`widget_register_tab_order`](oni/widgets/widget_focus.odin#L8) | Consume focus transitions |
| Scope / style stacks | Push/pop | Push/pop again (same structure) |
| Static / auto ids | Cleared at begin + again at end of layout pass | Regenerated identically |
| GPU draw | Avoid | `Draw_*`, events |
| Rects | Written to `Layout_Node.rect` | Read via [`ui_layout_rect`](oni/ui.odin#L240) |

[`Children`](oni/style.odin#L1695) pushes scope + style on both passes; **only Layout** pushes/pops layout nodes. `visibility: NONE` skips the whole `Children` body (no nested registration).

### Invariants

1. **Same tree both passes** — same widgets, children order, conditionals, and ids so Layout ids match Draw lookups.
2. **No layout mutation on Draw** — [`layout_push_node`](oni/layout.odin#L2522) only when `ui_pass() == .Layout`.
3. **Solve before Draw** — rects exist only after `End_Screen` / `End_Artboard` in Layout, then stack/hit finalization.
4. **Id regeneration** — auto/static id maps cleared at layout-pass end so Draw rebuilds the same keys.
5. **Lifecycle** — mount/unmount run on Layout; completed unmount / `visibility: NONE` can skip layout; Draw skips if no layout node.

## Frame arena (per-frame memory)

Layout-owned transient data (child index lists, shaped text lines, glyph quads, decoration strokes, table track arrays) allocates through a **frame arena** reset at each [`layout_reset`](oni/layout.odin#L313).

| Proc | Role |
|------|------|
| [`layout_frame_allocator`](oni/layout.odin#L250) | Preferred allocator for frame-owned layout data |
| [`layout_frame_allocator_for`](oni/layout.odin#L238) | Same, on a specific `Layout_State` |
| [`layout_uses_frame_arena`](oni/layout.odin#L231) | Whether arena mode is active |
| [`layout_uses_frame_arena_in`](oni/layout.odin#L224) | Arena check on a specific state |
| [`layout_release_node_children`](oni/layout.odin#L288) | Skips per-node `delete` when arena is active |
| [`layout_shutdown`](oni/layout.odin#L377) | Frees persistent layout storage + arena backing |

When the arena is active, [`layout_reset`](oni/layout.odin#L313) clears node vectors/maps and resets the arena instead of deleting each child list and text buffer. Arena backing grows when peak use exceeds 75% of capacity.

## Spaces (Screen / Artboard / Popover)

A **space** is a layout region tied to a draw space (`.SCREEN`, `.ARTBOARD`, or `.POPOVER`).

| Proc | Role |
|------|------|
| [`Begin_Screen`](oni/api.odin#L96) → [`draw_push_screen`](oni/draw.odin#L302) | Enter screen space; Layout → [`layout_begin_space`](oni/layout.odin#L4635) |
| [`End_Screen`](oni/api.odin#L97) → [`draw_pop_screen`](oni/draw.odin#L314) | Leave screen; Layout → [`layout_end_space`](oni/layout.odin#L4645) |
| [`Begin_Artboard`](oni/api.odin#L94) → [`begin_artboard`](oni/draw.odin#L278) | Same for artboard (zoom-scaled bounds) |
| [`End_Artboard`](oni/api.odin#L95) → [`end_artboard`](oni/draw.odin#L291) | End artboard space + solve |
| [`Popover_Begin`](oni/api.odin#L98) → [`begin_popover`](oni/draw.odin#L327) | Popover overlay space (screen coords; paints above screen/artboard) |
| [`Popover_End`](oni/api.odin#L99) → [`end_popover`](oni/draw.odin#L339) | End popover space + solve |
| [`layout_space_bounds`](oni/layout.odin#L4374) | Logical bounds; artboard divides by cached zoom |
| [`layout_artboard_zoom`](oni/layout.odin#L351) | Effective artboard zoom, cached per layout pass |
| [`layout_invalidate_artboard_zoom`](oni/layout.odin#L367) | Drop zoom cache after view transform changes |
| [`style_root`](oni/style.odin#L1558) | Root style context for the space |

Widgets can also opt into popover with `space = set.Space(.POPOVER)` without a begin/end scope.

[`layout_begin_space`](oni/layout.odin#L4635) records a node-index marker. [`layout_end_space`](oni/layout.odin#L4645) solves every node since that marker with `parent == -1` against the space bounds.

Artboard bounds use [`layout_artboard_zoom`](oni/layout.odin#L351), cached for the layout pass and invalidated in [`layout_reset`](oni/layout.odin#L313) or via [`layout_invalidate_artboard_zoom`](oni/layout.odin#L367) when the view zoom changes.

## How widgets register

### Stable ids

[`ui_id`](oni/ui.odin#L298) = CRC32(label) XOR [`ui_parent_hash`](oni/ui.odin#L283) (FNV over the scope stack). Nested scopes keep ids hierarchical via [`ui_push_scope`](oni/ui.odin#L265) / [`ui_pop_scope`](oni/ui.odin#L272). Label CRC32 values are memoized on first use ([`ui_label_crc32`](oni/ui.odin#L305)) so repeated ids avoid rehashing.

### Container pattern

Canonical shape in [`Button`](oni/widgets/button.odin#L70):

```odin
if o.ui_pass() == .Layout {
	// widget_run_layout_lifecycle → maybe skip
	// widget_register_tab_order
	o.Children(child, layout_id, config, frame_state)
	return
}
// Draw: widget_prepare_draw, ui_layout_rect, paint, events, Children(...)
```

[`Children`](oni/style.odin#L1695) → [`being_children`](oni/style.odin#L1652) → (Layout: [`layout_push_node`](oni/layout.odin#L2522)) → child builder → [`end_children`](oni/style.odin#L1671) → (Layout: [`layout_pop_node`](oni/layout.odin#L2664) → measure).

### Leaves

- **Text:** [`layout_push_node`](oni/layout.odin#L2522) → [`layout_set_measure_text`](oni/layout.odin#L2611) → [`layout_pop_node`](oni/layout.odin#L2664). Draw paints from [`layout_text_result`](oni/layout.odin#L2165).
- **Image:** push node → optional [`layout_set_measure_size`](oni/layout.odin#L2656) → [`layout_set_image`](oni/layout.odin#L2072) (stores author inputs in `image_input`) → pop. Fit finalized in [`layout_finalize_image_node`](oni/layout.odin#L2091) after rects exist; draw reads [`layout_image_result`](oni/layout.odin#L2188).

## Measure then solve

Inside each space there are two phases:

### 1. Measure (bottom-up on pop)

[`layout_pop_node`](oni/layout.odin#L2664) → [`layout_measure`](oni/layout.odin#L2308):

- **Leaf:** [`layout_measure_leaf`](oni/layout.odin#L2210) — text shape or width/height/min.
- **Container:** sum in-flow children’s desired sizes + gaps; wrap uses [`layout_wrap_measure`](oni/layout.odin#L568). Flex children without a definite main size are skipped when summing.

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
| [`layout_solve`](oni/layout.odin#L4367) | Solve a root within bounds |
| [`layout_solve_node`](oni/layout.odin#L4337) | Size, place, recurse |
| [`layout_resolve_node_size`](oni/layout.odin#L2745) | Width/height vs bounds, min/max clamp |
| [`layout_apply_definite_size`](oni/layout.odin#L2783) | Apply definite length axes |
| [`layout_position_children`](oni/layout.odin#L4030) | Main flex placer |
| [`layout_position_children_wrap`](oni/layout.odin#L3698) | Wrap line placement |
| [`layout_position_out_of_flow_children`](oni/layout.odin#L3527) | Absolute/fixed after in-flow |
| [`layout_finalize_node`](oni/layout.odin#L2124) | Text + image post-rect finalize |

## Flex sizing and positioning

### Main axis

- Definite width/height wins ([`length_resolve`](oni/style.odin#L13) / [`length_is_definite`](oni/style.odin#L30)).
- Else `flex > 0` or axis `.GROW`: share remaining main space by weight via [`layout_child_main_size`](oni/layout.odin#L2831). Explicit `flex` uses a zero basis (CSS `flex: 1 1 0%`). Axis `.GROW` uses content desired as basis, then adds `flex_unit * weight` (weight 1 when `flex` unset). Unset widget `width` resolves to `.GROW`; unset `height` is content-sized (`Length_Kind.UNSET`).
- Else height `.AUTO`: fill the parent content area (scrollport viewport; does not expand with content).
- Else `.FIT`: shrink to content, clamped to available (CSS `fit-content`) via [`layout_resolve_axis_size`](oni/layout.odin#L2705). Measure-indefinite axes (`.FIT` / `.GROW` / min/max-content) zero descendant `content_w`/`content_h`. BALANCE text on indefinite widths uses `min(max-content, provisional)` for desired width (soft-wrap height still uses provisional) so width modes do not require `wrap = .NONE`.
- Else `.MAX_CONTENT`: CSS `max-content` — content size without soft-wrap; never clamps to available or stretches when empty. Intrinsic axes zero descendant content size like `.FIT`.
- Else `.MIN_CONTENT`: CSS `min-content` — smallest size without avoidable overflow (text: longest unbreakable run; flex: sum/max of child `intrinsic_min`). Stored on [`Layout_Node.intrinsic_min`](oni/layout.odin#L115); never clamps to available.
- Else desired size from measure (width `.AUTO` may stretch to bounds when content is empty).

`Justify_Align.MAX_CONTENT` / `MIN_CONTENT` are unrelated: they equalize sibling sizes on an axis.

### Cross axis

[`layout_child_cross_size`](oni/layout.odin#L2889): definite size, else stretch (justify STRETCH / `flex` / `.GROW` / height `.AUTO`), else `.FIT` clamp, else `.MIN_CONTENT` / desired. `self` justify can pull a child out of main flow ([`layout_child_in_main_flow`](oni/layout.odin#L2873)).

### Justify / gap / order

| Proc | Role |
|------|------|
| [`layout_config_direction`](oni/layout.odin#L406) / [`layout_direction_info`](oni/layout.odin#L423) | Axis, wrap, reverse |
| [`layout_config_gap_main`](oni/layout.odin#L619) / [`layout_config_gap_cross`](oni/layout.odin#L627) | Gaps |
| [`layout_config_justify`](oni/layout.odin#L635) / [`layout_merge_justify`](oni/layout.odin#L642) | Parent + self |
| [`layout_main_justify_align`](oni/layout.odin#L3261) / [`layout_cross_justify_align`](oni/layout.odin#L3277) | Axis aligns |
| [`layout_space_leading`](oni/layout.odin#L3293) / [`layout_space_between_items`](oni/layout.odin#L3420) / [`layout_space_positions`](oni/layout.odin#L3437) | space-between/around/evenly |
| [`layout_content_align_target`](oni/layout.odin#L3313) / [`layout_apply_content_align_sizes`](oni/layout.odin#L3408) | MAX/MIN_CONTENT |
| [`layout_sort_children_by_order`](oni/layout.odin#L2494) | Flex `order` |
| [`layout_mirror_in_available`](oni/layout.odin#L467) | Reverse-axis mirror |
| [`layout_position_child_rect`](oni/layout.odin#L3469) | Write one child’s rect + recurse |

### Wrap

| Proc | Role |
|------|------|
| [`layout_wrap_main_limit_from_config`](oni/layout.odin#L484) | Main limit for line breaks |
| [`layout_wrap_child_main`](oni/layout.odin#L504) / [`layout_wrap_child_cross`](oni/layout.odin#L511) | Axis extractors |
| [`layout_wrap_build_lines`](oni/layout.odin#L518) | Pack wrap lines |
| [`layout_wrap_measure`](oni/layout.odin#L568) | Intrinsic wrap size |
| [`layout_wrap_apply_auto_cross_size`](oni/layout.odin#L4003) | Grow wrap container after place |

### Boxes and clamps

| Proc | Role |
|------|------|
| [`layout_clamp_axis`](oni/layout.odin#L651) | min/max clamp |
| [`layout_content_rect`](oni/layout.odin#L661) | Outer − padding |
| [`layout_inner_rect`](oni/layout.odin#L673) | Outer − border − padding (content box for children) |
| [`layout_margin_box`](oni/layout.odin#L711) | Border box expanded by margin (flow allocation; not paint/hit) |

## Out of flow, visibility, clipping

| Mode | Containing block | Notes |
|------|------------------|-------|
| RELATIVE / STICKY | In flex flow | Sticky clamps into clip |
| ABSOLUTE | Parent padding box | Pins: `x` / `y` / `right` / `bottom` |
| FIXED | Space bounds (popover uses viewport) | Same pins; out of flex gap |

| Proc | Role |
|------|------|
| [`layout_position_kind`](oni/layout_stack.odin#L33) | Resolve position mode |
| [`layout_position_in_flex_flow`](oni/layout_stack.odin#L107) | Relative/sticky in flow |
| [`layout_place_against_containing_block`](oni/layout_stack.odin#L157) | Absolute/fixed geometry |
| [`layout_place_out_of_flow`](oni/layout_stack.odin#L237) | Choose CB + place |
| [`layout_visibility_is_none`](oni/layout_stack.odin#L47) / [`layout_visibility_is_hidden`](oni/layout_stack.odin#L55) | Visibility |
| [`layout_pointer_events_none`](oni/layout_stack.odin#L63) | Hit policy |
| [`layout_overflow_clips`](oni/layout_stack.odin#L71) / [`layout_overflow_is_scrollport`](oni/layout_stack.odin#L81) | Overflow |
| [`layout_padding_box`](oni/layout_stack.odin#L90) / [`layout_clip_box`](oni/layout_stack.odin#L100) | Boxes |
| [`layout_resolve_clips`](oni/layout_stack.odin#L256) | Cumulative clips + sticky |

- `visibility: NONE` — omitted from tree (`Children` early-out).
- `visibility: HIDDEN` — keeps layout space; `paint_skip` + `hit_skip`.
- `pointer_events: NONE` — hit skip only.

## CSS-like grid

Containers with `kind = .GRID` (via `w.Grid`) measure and position with [`layout_grid_measure`](../layout_grid.odin#L456) / [`layout_grid_position_children`](../layout_grid.odin#L524) and helpers in [`layout_grid.odin`](../layout_grid.odin). Children use grid placement fields on their own config. Flex layout is unchanged for non-grid nodes.

## Stack order and pointer hit

After a builder’s layout tree is primarily solved on space end, [`ui_end_layout_pass`](../ui.odin#L151) runs:

1. [`layout_solve_layer_subtree_roots`](../layout_stack.odin#L426) / [`layout_resolve_anchors`](../layout.odin#L4562) — follow-up solve
2. [`layout_finalize_stack_order`](../layout_stack.odin#L444) — clips, paint lists, `stack_index`
3. [`layout_resolve_pointer_hit`](../layout_stack.odin#L562) — topmost hittable under pointer
4. Focus prune, tab navigation, shortcuts — then `pass = .Draw`

Paint list order: artboard roots → screen roots → popover roots. Within siblings: negative `z` under parent chrome, then parent, then non-negative `z`; tie-break `order` then node index. Each popover root is its own stacking context. Hit test walks paint lists front-to-back: popover → screen → artboard.

| Proc | Role |
|------|------|
| [`layout_assign_stack`](oni/layout_stack.odin#L373) | Assign stack indices into a paint list |
| [`layout_is_layer_subtree_root`](oni/layout_stack.odin#L326) | Popover root detection |
| [`layout_stack_child_less`](oni/layout_stack.odin#L334) / [`layout_sort_stack_children`](oni/layout_stack.odin#L347) | Sibling sort |
| [`layout_hit_point_in_node`](oni/layout_stack.odin#L521) / [`layout_hit_test_list`](oni/layout_stack.odin#L541) | Hit helpers |
| [`begin_popover`](oni/draw.odin#L327) / [`end_popover`](oni/draw.odin#L339) | Popover space scope (`Popover_Begin` / `End`) |
| [`ui_layout_stack_index`](oni/layout_stack.odin#L115) | Draw query |
| [`ui_layout_paint_skip`](oni/layout_stack.odin#L125) / [`ui_layout_hit_skip`](oni/layout_stack.odin#L135) | Skip flags |
| [`ui_layout_clip_rect`](oni/layout_stack.odin#L145) | Clip query |

## Tables

`justify: TABLE_CELL` equalizes column widths / row heights across head/body/foot rows.

| Proc | Role |
|------|------|
| [`layout_find_table_ancestor`](oni/layout.odin#L2990) | Walk to TABLE |
| [`layout_node_is_table_cell`](oni/layout.odin#L2997) | Cell kind check |
| [`layout_node_participates_in_table_collapse`](oni/layout.odin#L3004) | Collapse participants |
| [`layout_justify_uses_TABLE_CELL_x`](oni/layout.odin#L3015) / [`layout_justify_uses_TABLE_CELL_y`](oni/layout.odin#L3023) | Axis flags |
| [`layout_table_cell_intrinsic_axis`](oni/layout.odin#L3031) | Intrinsic cell size |
| [`layout_table_collect_rows_in`](oni/layout.odin#L3053) | Collect rows |
| [`layout_table_prepare`](oni/layout.odin#L3160) | Build shared tracks |
| [`layout_table_apply_cell_size`](oni/layout.odin#L3167) | Apply track size to cell |
| [`layout_table_finalize`](oni/layout.odin#L3254) | Assign cell positions |

`Layout_Table_Tracks` stores `col_count`, shared `col_widths` / `row_heights`, `cell_positions`, and per-cell `collapsed_borders` when border collapse is active. Track arrays allocate through the frame arena.

Collapsed gaps zero layout borders on push; paint conflict resolution lives in [`table_border.odin`](oni/table_border.odin) ([`table_gaps_are_collapsed`](oni/table_border.odin#L3), [`table_layout_resolve_collapsed_borders`](oni/table_border.odin#L189), …). Draw reads [`layout_collapsed_borders_result`](oni/layout.odin#L2199).

## Text and image (layout-owned geometry)

| Proc | Role |
|------|------|
| [`layout_text_resolve_wrap_w`](oni/layout.odin#L775) | Wrap width |
| [`layout_text_build`](oni/layout.odin#L1094) | Shape text |
| [`layout_text_position_lines`](oni/layout.odin#L1235) | Line origins |
| [`layout_text_position_glyphs`](oni/layout.odin#L1401) | Glyph quads |
| [`layout_text_append_decoration_stroke`](oni/layout.odin#L1804) / [`layout_text_position_decorations`](oni/layout.odin#L1862) | Underline etc. |
| [`layout_finalize_text_node`](oni/layout.odin#L2046) | Post-rect text finalize |
| [`layout_set_image`](oni/layout.odin#L2072) | Capture author image inputs into `image_input` |
| [`layout_finalize_image_node`](oni/layout.odin#L2091) | Object-fit into content box → `image` |
| [`layout_text_result`](oni/layout.odin#L2165) / [`layout_image_result`](oni/layout.odin#L2188) | Draw queries |

Shaped text, glyph quads, and decoration strokes live in arena-owned slices on `Layout_Text`. `Layout_Node` keeps author image params in `image_input` during measure; finalized paint geometry is in `image`.

## Lifecycle and focus (layout-adjacent)

| Proc | Role |
|------|------|
| [`widget_run_layout_lifecycle`](oni/widgets/widget_lifecycle.odin#L37) | Mount/unmount on Layout |
| [`widget_prepare_draw`](oni/widgets/widget_lifecycle.odin#L118) | Draw gate + phase sync |
| [`widget_can_interact`](oni/widgets/widget_lifecycle.odin#L23) | Interaction during mount/unmount |
| [`widget_lifecycle_entry`](oni/widget.odin#L1684) / [`widget_lifecycle_remove`](oni/widget.odin#L1702) | Persist mount state |
| [`widget_prune_focus`](oni/widget.odin#L457) | Post-layout focus prune |
| [`widget_process_tab_navigation`](oni/widget.odin#L518) | Tab order after layout |
| [`widget_register_tab_order`](oni/widgets/widget_focus.odin#L8) | Register during Layout |
| [`widget_prune_element_maps`](oni/widget.odin#L355) | End-of-frame map prune |

## Key types

| Type | File | Role |
|------|------|------|
| `UI_Pass` | [oni/ui.odin](oni/ui.odin#L7) | `.Layout` / `.Draw` |
| `Layout_State` | [oni/layout.odin](oni/layout.odin#L197) | Nodes, stacks, id map, paint lists, space, frame arena, artboard zoom |
| `Layout_Node` | [oni/layout.odin](oni/layout.odin#L105) | Style, desired, rect, children, text/image, stack/hit/clip |
| `Layout_Measure` | [oni/layout.odin](oni/layout.odin#L15) | Author text + max_w hint |
| `Layout_Glyph_Paint` / `Layout_Decoration_Stroke` | [oni/layout.odin](oni/layout.odin#L32) | Layout-owned glyph quads and decoration segments |
| `Layout_Text` / `Layout_Image_Input` / `Layout_Image` / `Layout_Collapsed_Borders` | [oni/layout.odin](oni/layout.odin#L55) | Layout-owned paint geometry |
| `Layout_Table_Tracks` | [oni/layout.odin](oni/layout.odin#L153) | Shared col/row sizes, cell positions, collapsed borders |
| `Resolved_Widget_Style` / `Resolved_Widget_Config` | [oni/types.odin](oni/types.odin#L838) | Concrete style for layout |
| `Length` / `Direction_Layout` / `Justify_Pos` / `Position` | [oni/types.odin](oni/types.odin#L682) | Sizing, direction, justify, position |
| `Draw_Space` / `Rect` | [oni/types.odin](oni/types.odin#L1891) | SCREEN / ARTBOARD / POPOVER; logical rect |
| `Style_Context` | [oni/types.odin](oni/types.odin#L1021) | Style + content_w/h for percent/text wrap |
| `Layout_Position_Kind` | [oni/layout_stack.odin](oni/layout_stack.odin#L10) | Resolved position mode |

## UI query helpers

| Proc | Role |
|------|------|
| [`ui_pass`](oni/ui.odin#L231) | Current pass |
| [`ui_layout_rect`](oni/ui.odin#L240) | Solved rect by id |
| [`ui_was_laid_out_prev`](oni/ui.odin#L250) | Present last frame |
| [`ui_has_layout_node`](oni/ui.odin#L257) | Present this frame |
| [`ui_init`](oni/ui.odin#L17) / [`ui_shutdown`](oni/ui.odin#L42) | Allocate / tear down UI + layout |
| [`layout_reset`](oni/layout.odin#L313) / [`layout_shutdown`](oni/layout.odin#L377) | Per-frame clear / free dynamics |
| [`layout_release_node_children`](oni/layout.odin#L288) | Free child lists + text (skipped under arena) |
| [`layout_is_ancestor_of`](oni/layout.odin#L2960) | Ancestry check |
| [`layout_node_index`](oni/layout.odin#L2953) | Node → index |

## Style / Children helpers

| Proc | Role |
|------|------|
| [`length_resolve`](oni/style.odin#L13) / [`length_is_definite`](oni/style.odin#L30) | Axis length math |
| [`style_root`](oni/style.odin#L1558) / [`style_child_context`](oni/style.odin#L1578) | Root/child style contexts |
| [`ui_style_current`](oni/style.odin#L1622) / [`ui_push_style`](oni/style.odin#L1633) / [`ui_pop_style`](oni/style.odin#L1642) | Style stack |
| [`being_children`](oni/style.odin#L1652) / [`end_children`](oni/style.odin#L1671) | Enter/leave container |
| [`Children`](oni/style.odin#L1695) | Scoped child builder |

## Widget entry points

These branch on [`ui_pass`](oni/ui.odin#L231) and use `Children` and/or `layout_push_node`:

[`Button`](oni/widgets/button.odin#L70), [`Rectangle`](oni/widgets/rectangle.odin#L64), [`Text`](oni/widgets/text.odin#L129), [`Image`](oni/widgets/image.odin#L168), [`Table`](oni/widgets/table.odin#L69), [`Table_Caption`](oni/widgets/table_caption.odin#L66), [`Table_Head`](oni/widgets/table_head.odin#L72), [`Table_Heading`](oni/widgets/table_heading.odin#L72), [`Table_Body`](oni/widgets/table_body.odin#L72), [`Table_Row`](oni/widgets/table_row.odin#L73), [`Table_Cell`](oni/widgets/table_cell.odin#L71), [`Table_Foot`](oni/widgets/table_foot.odin#L72).

## Complete proc index (`oni/layout.odin`)

Frame arena / reset: [`layout_uses_frame_arena_in`](oni/layout.odin#L224), [`layout_uses_frame_arena`](oni/layout.odin#L231), [`layout_frame_allocator_for`](oni/layout.odin#L238), [`layout_frame_allocator`](oni/layout.odin#L250), [`layout_frame_arena_ensure`](oni/layout.odin#L256), [`layout_frame_arena_reset`](oni/layout.odin#L265), [`layout_frame_arena_destroy`](oni/layout.odin#L281), [`layout_release_node_children`](oni/layout.odin#L288), [`layout_reset`](oni/layout.odin#L313), [`layout_artboard_zoom`](oni/layout.odin#L351), [`layout_invalidate_artboard_zoom`](oni/layout.odin#L367), [`layout_shutdown`](oni/layout.odin#L377).

Lifecycle / tree: [`layout_push_node`](oni/layout.odin#L2522), [`layout_pop_node`](oni/layout.odin#L2664), [`layout_set_measure_text`](oni/layout.odin#L2611), [`layout_set_measure_size`](oni/layout.odin#L2656), [`layout_begin_space`](oni/layout.odin#L4635), [`layout_end_space`](oni/layout.odin#L4645), [`layout_space_bounds`](oni/layout.odin#L4374).

Direction / wrap / gap / justify: [`layout_config_direction`](oni/layout.odin#L406), [`layout_direction_info`](oni/layout.odin#L423), [`layout_direction_is_horizontal`](oni/layout.odin#L453), [`layout_direction_is_wrap`](oni/layout.odin#L460), [`layout_mirror_in_available`](oni/layout.odin#L467), [`layout_wrap_main_limit_from_config`](oni/layout.odin#L484), [`layout_wrap_child_main`](oni/layout.odin#L504), [`layout_wrap_child_cross`](oni/layout.odin#L511), [`layout_wrap_build_lines`](oni/layout.odin#L518), [`layout_wrap_measure`](oni/layout.odin#L568), [`layout_config_gap_main`](oni/layout.odin#L619), [`layout_config_gap_cross`](oni/layout.odin#L627), [`layout_config_justify`](oni/layout.odin#L635), [`layout_merge_justify`](oni/layout.odin#L642).

Boxes / measure / size: [`layout_clamp_axis`](oni/layout.odin#L651), [`layout_content_rect`](oni/layout.odin#L661), [`layout_inner_rect`](oni/layout.odin#L673), [`layout_measure_leaf`](oni/layout.odin#L2210), [`layout_measure`](oni/layout.odin#L2308), [`layout_sort_children_by_order`](oni/layout.odin#L2494), [`layout_resolve_node_size`](oni/layout.odin#L2745), [`layout_apply_definite_size`](oni/layout.odin#L2783), [`layout_child_main_size`](oni/layout.odin#L2831), [`layout_child_in_main_flow`](oni/layout.odin#L2873), [`layout_child_cross_size`](oni/layout.odin#L2889).

Text / image: [`layout_node_has_text`](oni/layout.odin#L725), [`layout_text_release`](oni/layout.odin#L756), [`layout_text_resolve_wrap_w`](oni/layout.odin#L775), [`layout_text_build`](oni/layout.odin#L1094), [`layout_text_position_lines`](oni/layout.odin#L1235), [`layout_text_position_glyphs`](oni/layout.odin#L1401), [`layout_text_append_decoration_stroke`](oni/layout.odin#L1804), [`layout_text_position_decorations`](oni/layout.odin#L1862), [`layout_finalize_text_node`](oni/layout.odin#L2046), [`layout_set_image`](oni/layout.odin#L2072), [`layout_finalize_image_node`](oni/layout.odin#L2091), [`layout_finalize_node`](oni/layout.odin#L2124), [`layout_text_result`](oni/layout.odin#L2165), [`layout_image_result`](oni/layout.odin#L2188), [`layout_collapsed_borders_result`](oni/layout.odin#L2199).

Index / ancestry: [`layout_node_index_in`](oni/layout.odin#L2944), [`layout_node_index`](oni/layout.odin#L2953), [`layout_is_ancestor_of`](oni/layout.odin#L2960).

Tables: [`layout_find_table_ancestor_in`](oni/layout.odin#L2977), [`layout_find_table_ancestor`](oni/layout.odin#L2990), [`layout_node_is_table_cell`](oni/layout.odin#L2997), [`layout_node_participates_in_table_collapse`](oni/layout.odin#L3004), [`layout_justify_uses_TABLE_CELL_x`](oni/layout.odin#L3015), [`layout_justify_uses_TABLE_CELL_y`](oni/layout.odin#L3023), [`layout_table_cell_intrinsic_axis`](oni/layout.odin#L3031), [`layout_table_collect_rows_in`](oni/layout.odin#L3053), [`layout_table_row_track_index`](oni/layout.odin#L3082), [`layout_table_prepare_in`](oni/layout.odin#L3092), [`layout_table_prepare`](oni/layout.odin#L3160), [`layout_table_apply_cell_size`](oni/layout.odin#L3167), [`layout_table_finalize_in`](oni/layout.odin#L3195), [`layout_table_finalize`](oni/layout.odin#L3254).

Justify / place / solve: [`layout_main_justify_align`](oni/layout.odin#L3261), [`layout_cross_justify_align`](oni/layout.odin#L3277), [`layout_space_leading`](oni/layout.odin#L3293), [`layout_content_align_target`](oni/layout.odin#L3313), [`layout_sibling_axis_extrema`](oni/layout.odin#L3326), [`layout_apply_content_align_axis`](oni/layout.odin#L3341), [`layout_apply_content_align_sizes_indices`](oni/layout.odin#L3354), [`layout_apply_content_align_sizes`](oni/layout.odin#L3408), [`layout_space_between_items`](oni/layout.odin#L3420), [`layout_space_positions`](oni/layout.odin#L3437), [`layout_position_child_rect`](oni/layout.odin#L3469), [`layout_position_out_of_flow_children`](oni/layout.odin#L3527), [`layout_position_children_wrap`](oni/layout.odin#L3698), [`layout_wrap_apply_auto_cross_size`](oni/layout.odin#L4003), [`layout_position_children`](oni/layout.odin#L4030), [`layout_solve_node`](oni/layout.odin#L4337), [`layout_solve`](oni/layout.odin#L4367).

## Complete proc index (`oni/layout_stack.odin`)

[`layout_position_kind`](oni/layout_stack.odin#L33), [`layout_visibility_is_none`](oni/layout_stack.odin#L47), [`layout_visibility_is_hidden`](oni/layout_stack.odin#L55), [`layout_pointer_events_none`](oni/layout_stack.odin#L63), [`layout_overflow_clips`](oni/layout_stack.odin#L71), [`layout_overflow_is_scrollport`](oni/layout_stack.odin#L81), [`layout_padding_box`](oni/layout_stack.odin#L90), [`layout_clip_box`](oni/layout_stack.odin#L100), [`layout_position_in_flex_flow`](oni/layout_stack.odin#L107), [`ui_layout_stack_index`](oni/layout_stack.odin#L115), [`ui_layout_paint_skip`](oni/layout_stack.odin#L125), [`ui_layout_hit_skip`](oni/layout_stack.odin#L135), [`ui_layout_clip_rect`](oni/layout_stack.odin#L145), [`layout_place_against_containing_block`](oni/layout_stack.odin#L157), [`layout_place_out_of_flow`](oni/layout_stack.odin#L237), [`layout_resolve_clips`](oni/layout_stack.odin#L256), [`layout_is_layer_subtree_root`](oni/layout_stack.odin#L326), [`layout_stack_child_less`](oni/layout_stack.odin#L334), [`layout_sort_stack_children`](oni/layout_stack.odin#L347), [`layout_assign_stack`](oni/layout_stack.odin#L373), [`layout_finalize_stack_order`](oni/layout_stack.odin#L444), [`layout_hit_point_in_node`](oni/layout_stack.odin#L521), [`layout_hit_test_list`](oni/layout_stack.odin#L541), [`layout_resolve_pointer_hit`](oni/layout_stack.odin#L562).
