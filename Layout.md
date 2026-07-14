# Layout

Oni layout is an immediate-mode flex engine. Widgets declare a tree during the **Layout** pass; closing a screen/artboard space solves rects; the same tree is rewalked on **Draw** and paints from those rects.

Coordinates are logical design pixels. DPI scale is applied by the engine outside layout. Layout is flex-like (row/column ± wrap), not CSS Grid.

## Mental model

1. App calls [`o.Render`](oni/api.odin#L52) once per frame with a UI builder (`main_ui`, …).
2. The builder runs twice: Layout, then Draw ([`render`](oni/ui.odin#L170)).
3. During Layout, containers push nodes via [`Children`](oni/style.odin#L1267) / [`layout_push_node`](oni/layout.odin#L1003); leaves attach text/image measure hints.
4. [`End_Screen`](oni/api.odin#L51) / [`End_Artboard`](oni/api.odin#L49) call [`layout_end_space`](oni/layout.odin#L2407), which **solves** all parentless roots in that space.
5. [`ui_end_layout_pass`](oni/ui.odin#L123) finalizes paint order and pointer hit, then switches to Draw.
6. Draw widgets read [`ui_layout_rect`](oni/ui.odin#L192) (and text/image results) — they do not re-solve layout.

**Critical timing:** flex solve runs when a draw space ends during Layout (`layout_end_space`), not at `ui_end_layout_pass`. Stack order and hit-test run after the tree is fully solved.

## Frame flow

```
run_frame                          oni/runtime.odin
  input / poll
  ui_begin_frame                   pass = Layout; layout_reset
  tick(dt)
  present_frame(draw)              app draw → o.Render(main_ui)
    render
      builder()                    Layout pass
        Begin_Screen / Begin_Artboard
          layout_begin_space
          widgets → Children / layout_push_node / measure hints
        End_Screen / End_Artboard
          layout_end_space         ★ SOLVE ★
      ui_end_layout_pass           stack order, hit, tab nav → Draw
      builder()                    Draw pass
        same tree; ui_layout_rect + paint + events
      ui_end_frame                 prune stale widgets
  end_frame
```

### Host shell

| Proc | Role |
|------|------|
| [`run_frame`](oni/runtime.odin#L22) | One host frame: begin UI → tick → present |
| [`present_frame`](oni/present.odin#L14) | GPU present; invokes the app draw callback |
| [`ui_begin_frame`](oni/ui.odin#L76) | New frame, Layout pass, [`layout_reset`](oni/layout.odin#L143) |
| [`render`](oni/ui.odin#L170) / [`Render`](oni/api.odin#L52) | Layout + Draw each builder, then end frame |
| [`ui_end_layout_pass`](oni/ui.odin#L123) | Snapshot ids, stack/hit, focus/tab, switch to Draw |
| [`ui_end_frame`](oni/ui.odin#L148) | Prune widgets not touched this frame |

App code should call `o.Render(...)` once. Only call `ui_end_layout_pass` / `ui_end_frame` manually if you are not using `Render`. Widgets package mirrors this in [`Render`](oni/widgets/widget_types.odin#L158).

## Two passes

| Concern | Layout (`ui_pass() == .Layout`) | Draw |
|--------|----------------------------------|------|
| Build tree | [`layout_push_node`](oni/layout.odin#L1003) / [`Children`](oni/style.odin#L1267) | No new nodes |
| Measure / solve | Yes (on space end) | No |
| Mount / unmount | [`widget_run_layout_lifecycle`](oni/widgets/widget_lifecycle.odin#L37) | Sync via [`widget_prepare_draw`](oni/widgets/widget_lifecycle.odin#L118) |
| Tab order | [`widget_register_tab_order`](oni/widgets/widget_focus.odin#L8) | Consume focus transitions |
| Scope / style stacks | Push/pop | Push/pop again (same structure) |
| Static / auto ids | Cleared at begin + again at end of layout pass | Regenerated identically |
| GPU draw | Avoid | `Draw_*`, events |
| Rects | Written to `Layout_Node.rect` | Read via [`ui_layout_rect`](oni/ui.odin#L192) |

[`Children`](oni/style.odin#L1267) pushes scope + style on both passes; **only Layout** pushes/pops layout nodes. `visibility: NONE` skips the whole `Children` body (no nested registration).

### Invariants

1. **Same tree both passes** — same widgets, children order, conditionals, and ids so Layout ids match Draw lookups.
2. **No layout mutation on Draw** — [`layout_push_node`](oni/layout.odin#L1003) only when `ui_pass() == .Layout`.
3. **Solve before Draw** — rects exist only after `End_Screen` / `End_Artboard` in Layout, then stack/hit finalization.
4. **Id regeneration** — auto/static id maps cleared at layout-pass end so Draw rebuilds the same keys.
5. **Lifecycle** — mount/unmount run on Layout; completed unmount / `visibility: NONE` can skip layout; Draw skips if no layout node.

## Spaces (Screen / Artboard)

A **space** is a layout region tied to a draw space (`.SCREEN` or `.ARTBOARD`).

| Proc | Role |
|------|------|
| [`Begin_Screen`](oni/api.odin#L50) → [`draw_push_screen`](oni/draw.odin#L221) | Enter screen space; Layout → [`layout_begin_space`](oni/layout.odin#L2397) |
| [`End_Screen`](oni/api.odin#L51) → [`draw_pop_screen`](oni/draw.odin#L233) | Leave screen; Layout → [`layout_end_space`](oni/layout.odin#L2407) |
| [`Begin_Artboard`](oni/api.odin#L48) → [`begin_artboard`](oni/draw.odin#L197) | Same for artboard (zoom-scaled bounds) |
| [`End_Artboard`](oni/api.odin#L49) → [`end_artboard`](oni/draw.odin#L210) | End artboard space + solve |
| [`layout_space_bounds`](oni/layout.odin#L2381) | Logical bounds; artboard divides by zoom |
| [`style_root`](oni/style.odin#L1184) | Root style context for the space |

[`layout_begin_space`](oni/layout.odin#L2397) records a node-index marker. [`layout_end_space`](oni/layout.odin#L2407) solves every node since that marker with `parent == -1` against the space bounds.

## How widgets register

### Stable ids

[`ui_id`](oni/ui.odin#L249) = CRC32(label) XOR [`ui_parent_hash`](oni/ui.odin#L235) (FNV over the scope stack). Nested scopes keep ids hierarchical via [`ui_push_scope`](oni/ui.odin#L217) / [`ui_pop_scope`](oni/ui.odin#L224).

### Container pattern

Canonical shape in [`Button`](oni/widgets/button.odin#L66):

```odin
if o.ui_pass() == .Layout {
	// widget_run_layout_lifecycle → maybe skip
	// widget_register_tab_order
	o.Children(child, layout_id, config, frame_state)
	return
}
// Draw: widget_prepare_draw, ui_layout_rect, paint, events, Children(...)
```

[`Children`](oni/style.odin#L1267) → [`being_children`](oni/style.odin#L1244) → (Layout: [`layout_push_node`](oni/layout.odin#L1003)) → child builder → [`end_children`](oni/style.odin#L1255) → (Layout: [`layout_pop_node`](oni/layout.odin#L1076) → measure).

### Leaves

- **Text:** [`layout_push_node`](oni/layout.odin#L1003) → [`layout_set_measure_text`](oni/layout.odin#L1061) → [`layout_pop_node`](oni/layout.odin#L1076). Draw paints from [`layout_text_result`](oni/layout.odin#L827).
- **Image:** push node → optional [`layout_set_measure_size`](oni/layout.odin#L1069) → [`layout_set_image`](oni/layout.odin#L773) → pop. Fit finalized in [`layout_finalize_image_node`](oni/layout.odin#L786) after rects exist.

## Measure then solve

Inside each space there are two phases:

### 1. Measure (bottom-up on pop)

[`layout_pop_node`](oni/layout.odin#L1076) → [`layout_measure`](oni/layout.odin#L899):

- **Leaf:** [`layout_measure_leaf`](oni/layout.odin#L860) — text shape or width/height/min.
- **Container:** sum in-flow children’s desired sizes + gaps; wrap uses [`layout_wrap_measure`](oni/layout.odin#L342). Flex children without a definite main size are skipped when summing.

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
| [`layout_solve`](oni/layout.odin#L2374) | Solve a root within bounds |
| [`layout_solve_node`](oni/layout.odin#L2330) | Size, place, recurse |
| [`layout_resolve_node_size`](oni/layout.odin#L1089) | Width/height vs bounds, min/max clamp |
| [`layout_apply_definite_size`](oni/layout.odin#L1109) | Apply definite length axes |
| [`layout_position_children`](oni/layout.odin#L2080) | Main flex placer |
| [`layout_position_children_wrap`](oni/layout.odin#L1803) | Wrap line placement |
| [`layout_position_out_of_flow_children`](oni/layout.odin#L1792) | Absolute/fixed after in-flow |
| [`layout_finalize_node`](oni/layout.odin#L819) | Text + image post-rect finalize |

## Flex sizing and positioning

### Main axis

- Definite width/height wins ([`length_resolve`](oni/style.odin#L8) / [`length_is_definite`](oni/style.odin#L25)).
- Else `flex > 0`: share remaining main space by weight via [`layout_child_main_size`](oni/layout.odin#L1118) (`max(desired, flex_unit * flex)`).
- Else desired size from measure.

### Cross axis

[`layout_child_cross_size`](oni/layout.odin#L1153): definite size, else stretch (justify STRETCH / flex), else desired. `self` justify can pull a child out of main flow ([`layout_child_in_main_flow`](oni/layout.odin#L1139)).

### Justify / gap / order

| Proc | Role |
|------|------|
| [`layout_config_direction`](oni/layout.odin#L193) / [`layout_direction_info`](oni/layout.odin#L210) | Axis, wrap, reverse |
| [`layout_config_gap_main`](oni/layout.odin#L391) / [`layout_config_gap_cross`](oni/layout.odin#L399) | Gaps |
| [`layout_config_justify`](oni/layout.odin#L407) / [`layout_merge_justify`](oni/layout.odin#L414) | Parent + self |
| [`layout_main_justify_align`](oni/layout.odin#L1515) / [`layout_cross_justify_align`](oni/layout.odin#L1531) | Axis aligns |
| [`layout_space_leading`](oni/layout.odin#L1547) / [`layout_space_between_items`](oni/layout.odin#L1678) / [`layout_space_positions`](oni/layout.odin#L1695) | space-between/around/evenly |
| [`layout_content_align_target`](oni/layout.odin#L1567) / [`layout_apply_content_align_sizes`](oni/layout.odin#L1664) | MAX/MIN_CONTENT |
| [`layout_sort_children_by_order`](oni/layout.odin#L983) | Flex `order` |
| [`layout_mirror_in_available`](oni/layout.odin#L254) | Reverse-axis mirror |
| [`layout_position_child_rect`](oni/layout.odin#L1727) | Write one child’s rect + recurse |

### Wrap

| Proc | Role |
|------|------|
| [`layout_wrap_main_limit_from_config`](oni/layout.odin#L271) | Main limit for line breaks |
| [`layout_wrap_child_main`](oni/layout.odin#L291) / [`layout_wrap_child_cross`](oni/layout.odin#L298) | Axis extractors |
| [`layout_wrap_build_lines`](oni/layout.odin#L305) | Pack wrap lines |
| [`layout_wrap_measure`](oni/layout.odin#L342) | Intrinsic wrap size |
| [`layout_wrap_apply_auto_cross_size`](oni/layout.odin#L2054) | Grow wrap container after place |

### Boxes and clamps

| Proc | Role |
|------|------|
| [`layout_clamp_axis`](oni/layout.odin#L423) | min/max clamp |
| [`layout_content_rect`](oni/layout.odin#L433) | Outer − padding |
| [`layout_inner_rect`](oni/layout.odin#L445) | Outer − border − padding (content box for children) |

## Out of flow, visibility, clipping

| Mode | Containing block | Notes |
|------|------------------|-------|
| RELATIVE / STICKY | In flex flow | Sticky clamps into clip |
| ABSOLUTE | Parent padding box | Pins: `x` / `y` / `right` / `bottom` |
| FIXED | Space bounds (`top_layer` → SCREEN) | Same pins; out of flex gap |

| Proc | Role |
|------|------|
| [`layout_position_kind`](oni/layout_stack.odin#L31) | Resolve position mode |
| [`layout_position_in_flex_flow`](oni/layout_stack.odin#L104) | Relative/sticky in flow |
| [`layout_place_against_containing_block`](oni/layout_stack.odin#L172) | Absolute/fixed geometry |
| [`layout_place_out_of_flow`](oni/layout_stack.odin#L231) | Choose CB + place |
| [`layout_visibility_is_none`](oni/layout_stack.odin#L45) / [`layout_visibility_is_hidden`](oni/layout_stack.odin#L53) | Visibility |
| [`layout_pointer_events_none`](oni/layout_stack.odin#L61) | Hit policy |
| [`layout_overflow_clips`](oni/layout_stack.odin#L69) / [`layout_overflow_is_scrollport`](oni/layout_stack.odin#L78) | Overflow |
| [`layout_padding_box`](oni/layout_stack.odin#L87) / [`layout_clip_box`](oni/layout_stack.odin#L97) | Boxes |
| [`layout_resolve_clips`](oni/layout_stack.odin#L249) | Cumulative clips + sticky |

- `visibility: NONE` — omitted from tree (`Children` early-out).
- `visibility: HIDDEN` — keeps layout space; `paint_skip` + `hit_skip`.
- `pointer_events: NONE` — hit skip only.

## Stack order and pointer hit

After all spaces are solved, [`ui_end_layout_pass`](oni/ui.odin#L123) runs:

1. [`layout_finalize_stack_order`](oni/layout_stack.odin#L378) — clips, paint lists, `stack_index`
2. [`layout_resolve_pointer_hit`](oni/layout_stack.odin#L471) — topmost hittable under pointer

Paint list order: artboard roots → screen roots → top-layer roots. Within siblings: negative `z` under parent chrome, then parent, then non-negative `z`; tie-break `order` then node index. Hit test walks paint lists front-to-back: top layer → screen → artboard.

| Proc | Role |
|------|------|
| [`layout_assign_stack`](oni/layout_stack.odin#L327) | Assign stack indices into a paint list |
| [`layout_is_top_layer_subtree_root`](oni/layout_stack.odin#L290) | Top-layer root detection |
| [`layout_stack_child_less`](oni/layout_stack.odin#L298) / [`layout_sort_stack_children`](oni/layout_stack.odin#L311) | Sibling sort |
| [`layout_hit_point_in_node`](oni/layout_stack.odin#L438) / [`layout_hit_test_list`](oni/layout_stack.odin#L450) | Hit helpers |
| [`ui_top_layer_begin`](oni/layout_stack.odin#L112) / [`ui_top_layer_end`](oni/layout_stack.odin#L121) | Modal layer scope |
| [`ui_layout_stack_index`](oni/layout_stack.odin#L130) | Draw query |
| [`ui_layout_paint_skip`](oni/layout_stack.odin#L140) / [`ui_layout_hit_skip`](oni/layout_stack.odin#L150) | Skip flags |
| [`ui_layout_clip_rect`](oni/layout_stack.odin#L160) | Clip query |

## Tables

`justify: TABLE_CELL` equalizes column widths / row heights across head/body/foot rows.

| Proc | Role |
|------|------|
| [`layout_find_table_ancestor`](oni/layout.odin#L1236) | Walk to TABLE |
| [`layout_node_is_table_cell`](oni/layout.odin#L1243) | Cell kind check |
| [`layout_node_participates_in_table_collapse`](oni/layout.odin#L1250) | Collapse participants |
| [`layout_justify_uses_TABLE_CELL_x`](oni/layout.odin#L1261) / [`_y`](oni/layout.odin#L1269) | Axis flags |
| [`layout_table_cell_intrinsic_axis`](oni/layout.odin#L1277) | Intrinsic cell size |
| [`layout_table_collect_rows_in`](oni/layout.odin#L1293) | Collect rows |
| [`layout_table_prepare`](oni/layout.odin#L1414) | Build shared tracks |
| [`layout_table_apply_cell_size`](oni/layout.odin#L1421) | Apply track size to cell |
| [`layout_table_finalize`](oni/layout.odin#L1508) | Assign cell positions |

Collapsed gaps zero layout borders on push; paint conflict resolution lives in [`table_border.odin`](oni/table_border.odin) ([`table_gaps_are_collapsed`](oni/table_border.odin#L3), [`table_layout_resolve_collapsed_borders`](oni/table_border.odin#L193), …). Draw reads [`layout_collapsed_borders_result`](oni/layout.odin#L849).

## Text and image (layout-owned geometry)

| Proc | Role |
|------|------|
| [`layout_text_resolve_wrap_w`](oni/layout.odin#L483) | Wrap width |
| [`layout_text_build`](oni/layout.odin#L497) | Shape text |
| [`layout_text_position_lines`](oni/layout.odin#L547) | Line origins |
| [`layout_text_position_glyphs`](oni/layout.odin#L580) | Glyph quads |
| [`layout_text_append_decoration_stroke`](oni/layout.odin#L648) / [`layout_text_position_decorations`](oni/layout.odin#L699) | Underline etc. |
| [`layout_finalize_text_node`](oni/layout.odin#L753) | Post-rect text finalize |
| [`layout_set_image`](oni/layout.odin#L773) | Capture image inputs |
| [`layout_finalize_image_node`](oni/layout.odin#L786) | Object-fit into content box |
| [`layout_text_result`](oni/layout.odin#L827) / [`layout_image_result`](oni/layout.odin#L838) | Draw queries |

## Lifecycle and focus (layout-adjacent)

| Proc | Role |
|------|------|
| [`widget_run_layout_lifecycle`](oni/widgets/widget_lifecycle.odin#L37) | Mount/unmount on Layout |
| [`widget_prepare_draw`](oni/widgets/widget_lifecycle.odin#L118) | Draw gate + phase sync |
| [`widget_can_interact`](oni/widgets/widget_lifecycle.odin#L23) | Interaction during mount/unmount |
| [`widget_lifecycle_entry`](oni/widget.odin#L1265) / [`widget_lifecycle_remove`](oni/widget.odin#L1283) | Persist mount state |
| [`widget_prune_focus`](oni/widget.odin#L183) | Post-layout focus prune |
| [`widget_process_tab_navigation`](oni/widget.odin#L242) | Tab order after layout |
| [`widget_register_tab_order`](oni/widgets/widget_focus.odin#L8) | Register during Layout |
| [`widget_prune_element_maps`](oni/widget.odin#L122) | End-of-frame map prune |

## Key types

| Type | File | Role |
|------|------|------|
| `UI_Pass` | [oni/ui.odin](oni/ui.odin#L6) | `.Layout` / `.Draw` |
| `Layout_State` | [oni/layout.odin](oni/layout.odin#L114) | Nodes, stacks, id map, paint lists, space |
| `Layout_Node` | [oni/layout.odin](oni/layout.odin#L76) | Style, desired, rect, children, text/image, stack/hit/clip |
| `Layout_Measure` | [oni/layout.odin](oni/layout.odin#L6) | Author text + max_w hint |
| `Layout_Text` / `Layout_Image` / `Layout_Collapsed_Borders` | [oni/layout.odin](oni/layout.odin#L31) | Layout-owned paint geometry |
| `Layout_Table_Tracks` | [oni/layout.odin](oni/layout.odin#L103) | Shared col/row sizes |
| `Resolved_Widget_Style` / `Resolved_Widget_Config` | [oni/types.odin](oni/types.odin) | Concrete style for layout |
| `Length` / `Direction_Layout` / `Justify_Pos` / `Position` | [oni/types.odin](oni/types.odin) | Sizing, direction, justify, position |
| `Draw_Space` / `Rect` | [oni/types.odin](oni/types.odin) | SCREEN vs ARTBOARD; logical rect |
| `Style_Context` | [oni/types.odin](oni/types.odin) | Style + content_w/h for percent/text wrap |
| `Layout_Position_Kind` | [oni/layout_stack.odin](oni/layout_stack.odin#L8) | Resolved position mode |

## UI query helpers

| Proc | Role |
|------|------|
| [`ui_pass`](oni/ui.odin#L183) | Current pass |
| [`ui_layout_rect`](oni/ui.odin#L192) | Solved rect by id |
| [`ui_was_laid_out_prev`](oni/ui.odin#L202) | Present last frame |
| [`ui_has_layout_node`](oni/ui.odin#L209) | Present this frame |
| [`ui_init`](oni/ui.odin#L16) / [`ui_shutdown`](oni/ui.odin#L41) | Allocate / tear down UI + layout |
| [`layout_reset`](oni/layout.odin#L143) / [`layout_shutdown`](oni/layout.odin#L171) | Per-frame clear / free dynamics |
| [`layout_release_node_children`](oni/layout.odin#L131) | Free child lists + text |
| [`layout_is_ancestor_of`](oni/layout.odin#L1206) | Ancestry check |
| [`layout_node_index`](oni/layout.odin#L1199) | Node → index |

## Style / Children helpers

| Proc | Role |
|------|------|
| [`length_resolve`](oni/style.odin#L8) / [`length_is_definite`](oni/style.odin#L25) | Axis length math |
| [`style_root`](oni/style.odin#L1184) / [`style_child_context`](oni/style.odin#L1193) | Root/child style contexts |
| [`ui_style_current`](oni/style.odin#L1214) / [`ui_push_style`](oni/style.odin#L1225) / [`ui_pop_style`](oni/style.odin#L1234) | Style stack |
| [`being_children`](oni/style.odin#L1244) / [`end_children`](oni/style.odin#L1255) | Enter/leave container |
| [`Children`](oni/style.odin#L1267) | Scoped child builder |

## Widget entry points

These branch on [`ui_pass`](oni/ui.odin#L183) and use `Children` and/or `layout_push_node`:

[`Button`](oni/widgets/button.odin), [`Rectangle`](oni/widgets/rectangle.odin), [`Text`](oni/widgets/text.odin), [`Image`](oni/widgets/image.odin), [`Table`](oni/widgets/table.odin), [`Table_Caption`](oni/widgets/table_caption.odin), [`Table_Head`](oni/widgets/table_head.odin), [`Table_Heading`](oni/widgets/table_heading.odin), [`Table_Body`](oni/widgets/table_body.odin), [`Table_Row`](oni/widgets/table_row.odin), [`Table_Cell`](oni/widgets/table_cell.odin), [`Table_Foot`](oni/widgets/table_foot.odin).

## Complete proc index (`oni/layout.odin`)

Lifecycle / tree: [`layout_release_node_children`](oni/layout.odin#L131), [`layout_reset`](oni/layout.odin#L143), [`layout_shutdown`](oni/layout.odin#L171), [`layout_push_node`](oni/layout.odin#L1003), [`layout_pop_node`](oni/layout.odin#L1076), [`layout_set_measure_text`](oni/layout.odin#L1061), [`layout_set_measure_size`](oni/layout.odin#L1069), [`layout_begin_space`](oni/layout.odin#L2397), [`layout_end_space`](oni/layout.odin#L2407), [`layout_space_bounds`](oni/layout.odin#L2381).

Direction / wrap / gap / justify: [`layout_config_direction`](oni/layout.odin#L193), [`layout_direction_info`](oni/layout.odin#L210), [`layout_direction_is_horizontal`](oni/layout.odin#L240), [`layout_direction_is_wrap`](oni/layout.odin#L247), [`layout_mirror_in_available`](oni/layout.odin#L254), [`layout_wrap_main_limit_from_config`](oni/layout.odin#L271), [`layout_wrap_child_main`](oni/layout.odin#L291), [`layout_wrap_child_cross`](oni/layout.odin#L298), [`layout_wrap_build_lines`](oni/layout.odin#L305), [`layout_wrap_measure`](oni/layout.odin#L342), [`layout_config_gap_main`](oni/layout.odin#L391), [`layout_config_gap_cross`](oni/layout.odin#L399), [`layout_config_justify`](oni/layout.odin#L407), [`layout_merge_justify`](oni/layout.odin#L414).

Boxes / measure / size: [`layout_clamp_axis`](oni/layout.odin#L423), [`layout_content_rect`](oni/layout.odin#L433), [`layout_inner_rect`](oni/layout.odin#L445), [`layout_measure_leaf`](oni/layout.odin#L860), [`layout_measure`](oni/layout.odin#L899), [`layout_sort_children_by_order`](oni/layout.odin#L983), [`layout_resolve_node_size`](oni/layout.odin#L1089), [`layout_apply_definite_size`](oni/layout.odin#L1109), [`layout_child_main_size`](oni/layout.odin#L1118), [`layout_child_in_main_flow`](oni/layout.odin#L1139), [`layout_child_cross_size`](oni/layout.odin#L1153).

Text / image: [`layout_node_has_text`](oni/layout.odin#L460), [`layout_text_release`](oni/layout.odin#L467), [`layout_text_resolve_wrap_w`](oni/layout.odin#L483), [`layout_text_build`](oni/layout.odin#L497), [`layout_text_position_lines`](oni/layout.odin#L547), [`layout_text_position_glyphs`](oni/layout.odin#L580), [`layout_text_append_decoration_stroke`](oni/layout.odin#L648), [`layout_text_position_decorations`](oni/layout.odin#L699), [`layout_finalize_text_node`](oni/layout.odin#L753), [`layout_set_image`](oni/layout.odin#L773), [`layout_finalize_image_node`](oni/layout.odin#L786), [`layout_finalize_node`](oni/layout.odin#L819), [`layout_text_result`](oni/layout.odin#L827), [`layout_image_result`](oni/layout.odin#L838), [`layout_collapsed_borders_result`](oni/layout.odin#L849).

Index / ancestry: [`layout_node_index_in`](oni/layout.odin#L1189), [`layout_node_index`](oni/layout.odin#L1199), [`layout_is_ancestor_of`](oni/layout.odin#L1206).

Tables: [`layout_find_table_ancestor_in`](oni/layout.odin#L1223), [`layout_find_table_ancestor`](oni/layout.odin#L1236), [`layout_node_is_table_cell`](oni/layout.odin#L1243), [`layout_node_participates_in_table_collapse`](oni/layout.odin#L1250), [`layout_justify_uses_TABLE_CELL_x`](oni/layout.odin#L1261), [`layout_justify_uses_TABLE_CELL_y`](oni/layout.odin#L1269), [`layout_table_cell_intrinsic_axis`](oni/layout.odin#L1277), [`layout_table_collect_rows_in`](oni/layout.odin#L1293), [`layout_table_row_track_index`](oni/layout.odin#L1323), [`layout_table_prepare_in`](oni/layout.odin#L1333), [`layout_table_prepare`](oni/layout.odin#L1414), [`layout_table_apply_cell_size`](oni/layout.odin#L1421), [`layout_table_finalize_in`](oni/layout.odin#L1449), [`layout_table_finalize`](oni/layout.odin#L1508).

Justify / place / solve: [`layout_main_justify_align`](oni/layout.odin#L1515), [`layout_cross_justify_align`](oni/layout.odin#L1531), [`layout_space_leading`](oni/layout.odin#L1547), [`layout_content_align_target`](oni/layout.odin#L1567), [`layout_sibling_axis_extrema`](oni/layout.odin#L1580), [`layout_apply_content_align_axis`](oni/layout.odin#L1595), [`layout_apply_content_align_sizes_indices`](oni/layout.odin#L1608), [`layout_apply_content_align_sizes`](oni/layout.odin#L1664), [`layout_space_between_items`](oni/layout.odin#L1678), [`layout_space_positions`](oni/layout.odin#L1695), [`layout_position_child_rect`](oni/layout.odin#L1727), [`layout_position_out_of_flow_children`](oni/layout.odin#L1792), [`layout_position_children_wrap`](oni/layout.odin#L1803), [`layout_wrap_apply_auto_cross_size`](oni/layout.odin#L2054), [`layout_position_children`](oni/layout.odin#L2080), [`layout_solve_node`](oni/layout.odin#L2330), [`layout_solve`](oni/layout.odin#L2374).

## Complete proc index (`oni/layout_stack.odin`)

[`layout_position_kind`](oni/layout_stack.odin#L31), [`layout_visibility_is_none`](oni/layout_stack.odin#L45), [`layout_visibility_is_hidden`](oni/layout_stack.odin#L53), [`layout_pointer_events_none`](oni/layout_stack.odin#L61), [`layout_overflow_clips`](oni/layout_stack.odin#L69), [`layout_overflow_is_scrollport`](oni/layout_stack.odin#L78), [`layout_padding_box`](oni/layout_stack.odin#L87), [`layout_clip_box`](oni/layout_stack.odin#L97), [`layout_position_in_flex_flow`](oni/layout_stack.odin#L104), [`ui_top_layer_begin`](oni/layout_stack.odin#L112), [`ui_top_layer_end`](oni/layout_stack.odin#L121), [`ui_layout_stack_index`](oni/layout_stack.odin#L130), [`ui_layout_paint_skip`](oni/layout_stack.odin#L140), [`ui_layout_hit_skip`](oni/layout_stack.odin#L150), [`ui_layout_clip_rect`](oni/layout_stack.odin#L160), [`layout_place_against_containing_block`](oni/layout_stack.odin#L172), [`layout_place_out_of_flow`](oni/layout_stack.odin#L231), [`layout_resolve_clips`](oni/layout_stack.odin#L249), [`layout_is_top_layer_subtree_root`](oni/layout_stack.odin#L290), [`layout_stack_child_less`](oni/layout_stack.odin#L298), [`layout_sort_stack_children`](oni/layout_stack.odin#L311), [`layout_assign_stack`](oni/layout_stack.odin#L327), [`layout_finalize_stack_order`](oni/layout_stack.odin#L378), [`layout_hit_point_in_node`](oni/layout_stack.odin#L438), [`layout_hit_test_list`](oni/layout_stack.odin#L450), [`layout_resolve_pointer_hit`](oni/layout_stack.odin#L471).
