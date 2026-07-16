# Layout

Oni layout is an immediate-mode flex engine. Widgets declare a tree during the **Layout** pass; closing a screen/artboard space solves rects; the same tree is rewalked on **Draw** and paints from those rects.

Coordinates are logical design pixels. DPI scale is applied by the engine outside layout. Layout is flex-like (row/column ± wrap), not CSS Grid.

## Mental model

1. App calls [`o.Render`](oni/api.odin#L52) once per frame with a UI builder (`main_ui`, …).
2. [`render`](oni/ui.odin#L179) runs each builder **twice in sequence**: Layout, then Draw.
3. During Layout, containers push nodes via [`Children`](oni/style.odin#L1311) / [`layout_push_node`](oni/layout.odin#L1117); leaves attach text/image measure hints.
4. [`End_Screen`](oni/api.odin#L51) / [`End_Artboard`](oni/api.odin#L49) call [`layout_end_space`](oni/layout.odin#L2489), which **solves** all parentless roots in that space.
5. [`ui_end_layout_pass`](oni/ui.odin#L132) finalizes paint order and pointer hit, then switches to Draw.
6. Draw widgets read [`ui_layout_rect`](oni/ui.odin#L201) (and text/image results) — they do not re-solve layout.

**Critical timing:** flex solve runs when a draw space ends during Layout (`layout_end_space`), not at `ui_end_layout_pass`. Stack order and hit-test run after the tree is fully solved, between each builder’s Layout and Draw passes.

**Multiple builders:** when `Render` receives more than one proc, each builder gets its own Layout → `ui_end_layout_pass` → Draw → `ui_end_frame` cycle. Stack/hit and widget pruning run per builder, not once for the whole frame.

## Frame flow

```
run_frame                          oni/runtime.odin
  input / poll
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
            layout_end_space       ★ SOLVE ★
        ui_end_layout_pass         stack order, hit, tab nav → Draw
        u()                        Draw pass
          same tree; ui_layout_rect + paint + events
        ui_end_frame               prune stale widgets for this builder
  end_frame
```

### Host shell

| Proc | Role |
|------|------|
| [`run_frame`](oni/runtime.odin#L22) | One host frame: begin UI → tick → present |
| [`present_frame`](oni/present.odin#L16) | GPU present; invokes the app draw callback |
| [`ui_begin_frame`](oni/ui.odin#L84) | New frame, Layout pass, [`layout_reset`](oni/layout.odin#L227) |
| [`render`](oni/ui.odin#L179) / [`Render`](oni/api.odin#L52) | Per-builder Layout + Draw, with pass transitions |
| [`ui_end_layout_pass`](oni/ui.odin#L132) | Snapshot ids, stack/hit, focus/tab, switch to Draw |
| [`ui_end_frame`](oni/ui.odin#L157) | Prune widgets not touched this builder pass |

App code should call `o.Render(...)` once. Only call `ui_end_layout_pass` / `ui_end_frame` manually if you are not using `Render`. Widgets package mirrors this in [`Render`](oni/widgets/widget_types.odin#L158).

## Two passes

| Concern | Layout (`ui_pass() == .Layout`) | Draw |
|--------|----------------------------------|------|
| Build tree | [`layout_push_node`](oni/layout.odin#L1117) / [`Children`](oni/style.odin#L1311) | No new nodes |
| Measure / solve | Yes (on space end) | No |
| Mount / unmount | [`widget_run_layout_lifecycle`](oni/widgets/widget_lifecycle.odin#L37) | Sync via [`widget_prepare_draw`](oni/widgets/widget_lifecycle.odin#L118) |
| Tab order | [`widget_register_tab_order`](oni/widgets/widget_focus.odin#L8) | Consume focus transitions |
| Scope / style stacks | Push/pop | Push/pop again (same structure) |
| Static / auto ids | Cleared at begin + again at end of layout pass | Regenerated identically |
| GPU draw | Avoid | `Draw_*`, events |
| Rects | Written to `Layout_Node.rect` | Read via [`ui_layout_rect`](oni/ui.odin#L201) |

[`Children`](oni/style.odin#L1311) pushes scope + style on both passes; **only Layout** pushes/pops layout nodes. `visibility: NONE` skips the whole `Children` body (no nested registration).

### Invariants

1. **Same tree both passes** — same widgets, children order, conditionals, and ids so Layout ids match Draw lookups.
2. **No layout mutation on Draw** — [`layout_push_node`](oni/layout.odin#L1117) only when `ui_pass() == .Layout`.
3. **Solve before Draw** — rects exist only after `End_Screen` / `End_Artboard` in Layout, then stack/hit finalization.
4. **Id regeneration** — auto/static id maps cleared at layout-pass end so Draw rebuilds the same keys.
5. **Lifecycle** — mount/unmount run on Layout; completed unmount / `visibility: NONE` can skip layout; Draw skips if no layout node.

## Frame arena (per-frame memory)

Layout-owned transient data (child index lists, shaped text lines, glyph quads, decoration strokes, table track arrays) allocates through a **frame arena** reset at each [`layout_reset`](oni/layout.odin#L227).

| Proc | Role |
|------|------|
| [`layout_frame_allocator`](oni/layout.odin#L169) | Preferred allocator for frame-owned layout data |
| [`layout_frame_allocator_for`](oni/layout.odin#L157) | Same, on a specific `Layout_State` |
| [`layout_uses_frame_arena`](oni/layout.odin#L150) | Whether arena mode is active |
| [`layout_uses_frame_arena_in`](oni/layout.odin#L143) | Arena check on a specific state |
| [`layout_release_node_children`](oni/layout.odin#L205) | Skips per-node `delete` when arena is active |
| [`layout_shutdown`](oni/layout.odin#L280) | Frees persistent layout storage + arena backing |

When the arena is active, [`layout_reset`](oni/layout.odin#L227) clears node vectors/maps and resets the arena instead of deleting each child list and text buffer. Arena backing grows when peak use exceeds 75% of capacity.

## Spaces (Screen / Artboard / Popover)

A **space** is a layout region tied to a draw space (`.SCREEN`, `.ARTBOARD`, or `.POPOVER`).

| Proc | Role |
|------|------|
| [`Begin_Screen`](oni/api.odin#L50) → [`draw_push_screen`](oni/draw.odin#L245) | Enter screen space; Layout → [`layout_begin_space`](oni/layout.odin#L2479) |
| [`End_Screen`](oni/api.odin#L51) → [`draw_pop_screen`](oni/draw.odin#L257) | Leave screen; Layout → [`layout_end_space`](oni/layout.odin#L2489) |
| [`Begin_Artboard`](oni/api.odin#L48) → [`begin_artboard`](oni/draw.odin#L221) | Same for artboard (zoom-scaled bounds) |
| [`End_Artboard`](oni/api.odin#L49) → [`end_artboard`](oni/draw.odin#L234) | End artboard space + solve |
| [`Popover_Begin`](oni/api.odin) → [`begin_popover`](oni/draw.odin) | Popover overlay space (screen coords; paints above screen/artboard) |
| [`Popover_End`](oni/api.odin) → [`end_popover`](oni/draw.odin) | End popover space + solve |
| [`layout_space_bounds`](oni/layout.odin#L2464) | Logical bounds; artboard divides by cached zoom |
| [`layout_artboard_zoom`](oni/layout.odin#L254) | Effective artboard zoom, cached per layout pass |
| [`layout_invalidate_artboard_zoom`](oni/layout.odin#L270) | Drop zoom cache after view transform changes |
| [`style_root`](oni/style.odin#L1228) | Root style context for the space |

Widgets can also opt into popover with `space = set.Space(.POPOVER)` without a begin/end scope.

[`layout_begin_space`](oni/layout.odin#L2479) records a node-index marker. [`layout_end_space`](oni/layout.odin#L2489) solves every node since that marker with `parent == -1` against the space bounds.

Artboard bounds use [`layout_artboard_zoom`](oni/layout.odin#L254), cached for the layout pass and invalidated in [`layout_reset`](oni/layout.odin#L227) or via [`layout_invalidate_artboard_zoom`](oni/layout.odin#L270) when the view zoom changes.

## How widgets register

### Stable ids

[`ui_id`](oni/ui.odin#L259) = CRC32(label) XOR [`ui_parent_hash`](oni/ui.odin#L244) (FNV over the scope stack). Nested scopes keep ids hierarchical via [`ui_push_scope`](oni/ui.odin#L226) / [`ui_pop_scope`](oni/ui.odin#L233). Label CRC32 values are memoized on first use ([`ui_label_crc32`](oni/ui.odin#L266)) so repeated ids avoid rehashing.

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

[`Children`](oni/style.odin#L1311) → [`being_children`](oni/style.odin#L1288) → (Layout: [`layout_push_node`](oni/layout.odin#L1117)) → child builder → [`end_children`](oni/style.odin#L1299) → (Layout: [`layout_pop_node`](oni/layout.odin#L1191) → measure).

### Leaves

- **Text:** [`layout_push_node`](oni/layout.odin#L1117) → [`layout_set_measure_text`](oni/layout.odin#L1176) → [`layout_pop_node`](oni/layout.odin#L1191). Draw paints from [`layout_text_result`](oni/layout.odin#L944).
- **Image:** push node → optional [`layout_set_measure_size`](oni/layout.odin#L1184) → [`layout_set_image`](oni/layout.odin#L890) (stores author inputs in `image_input`) → pop. Fit finalized in [`layout_finalize_image_node`](oni/layout.odin#L903) after rects exist; draw reads [`layout_image_result`](oni/layout.odin#L955).

## Measure then solve

Inside each space there are two phases:

### 1. Measure (bottom-up on pop)

[`layout_pop_node`](oni/layout.odin#L1191) → [`layout_measure`](oni/layout.odin#L1018):

- **Leaf:** [`layout_measure_leaf`](oni/layout.odin#L977) — text shape or width/height/min.
- **Container:** sum in-flow children’s desired sizes + gaps; wrap uses [`layout_wrap_measure`](oni/layout.odin#L452). Flex children without a definite main size are skipped when summing.

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
| [`layout_solve`](oni/layout.odin#L2457) | Solve a root within bounds |
| [`layout_solve_node`](oni/layout.odin#L2419) | Size, place, recurse |
| [`layout_resolve_node_size`](oni/layout.odin#L1204) | Width/height vs bounds, min/max clamp |
| [`layout_apply_definite_size`](oni/layout.odin#L1224) | Apply definite length axes |
| [`layout_position_children`](oni/layout.odin#L2177) | Main flex placer |
| [`layout_position_children_wrap`](oni/layout.odin#L1900) | Wrap line placement |
| [`layout_position_out_of_flow_children`](oni/layout.odin#L1889) | Absolute/fixed after in-flow |
| [`layout_finalize_node`](oni/layout.odin#L936) | Text + image post-rect finalize |

## Flex sizing and positioning

### Main axis

- Definite width/height wins ([`length_resolve`](oni/style.odin#L11) / [`length_is_definite`](oni/style.odin#L28)).
- Else `flex > 0`: share remaining main space by weight via [`layout_child_main_size`](oni/layout.odin#L1233) (`max(desired, flex_unit * flex)`).
- Else desired size from measure.

### Cross axis

[`layout_child_cross_size`](oni/layout.odin#L1268): definite size, else stretch (justify STRETCH / flex), else desired. `self` justify can pull a child out of main flow ([`layout_child_in_main_flow`](oni/layout.odin#L1254)).

### Justify / gap / order

| Proc | Role |
|------|------|
| [`layout_config_direction`](oni/layout.odin#L303) / [`layout_direction_info`](oni/layout.odin#L320) | Axis, wrap, reverse |
| [`layout_config_gap_main`](oni/layout.odin#L498) / [`layout_config_gap_cross`](oni/layout.odin#L506) | Gaps |
| [`layout_config_justify`](oni/layout.odin#L514) / [`layout_merge_justify`](oni/layout.odin#L521) | Parent + self |
| [`layout_main_justify_align`](oni/layout.odin#L1616) / [`layout_cross_justify_align`](oni/layout.odin#L1632) | Axis aligns |
| [`layout_space_leading`](oni/layout.odin#L1648) / [`layout_space_between_items`](oni/layout.odin#L1775) / [`layout_space_positions`](oni/layout.odin#L1792) | space-between/around/evenly |
| [`layout_content_align_target`](oni/layout.odin#L1668) / [`layout_apply_content_align_sizes`](oni/layout.odin#L1763) | MAX/MIN_CONTENT |
| [`layout_sort_children_by_order`](oni/layout.odin#L1097) | Flex `order` |
| [`layout_mirror_in_available`](oni/layout.odin#L364) | Reverse-axis mirror |
| [`layout_position_child_rect`](oni/layout.odin#L1824) | Write one child’s rect + recurse |

### Wrap

| Proc | Role |
|------|------|
| [`layout_wrap_main_limit_from_config`](oni/layout.odin#L381) | Main limit for line breaks |
| [`layout_wrap_child_main`](oni/layout.odin#L401) / [`layout_wrap_child_cross`](oni/layout.odin#L408) | Axis extractors |
| [`layout_wrap_build_lines`](oni/layout.odin#L415) | Pack wrap lines |
| [`layout_wrap_measure`](oni/layout.odin#L452) | Intrinsic wrap size |
| [`layout_wrap_apply_auto_cross_size`](oni/layout.odin#L2151) | Grow wrap container after place |

### Boxes and clamps

| Proc | Role |
|------|------|
| [`layout_clamp_axis`](oni/layout.odin#L530) | min/max clamp |
| [`layout_content_rect`](oni/layout.odin#L540) | Outer − padding |
| [`layout_inner_rect`](oni/layout.odin#L552) | Outer − border − padding (content box for children) |

## Out of flow, visibility, clipping

| Mode | Containing block | Notes |
|------|------------------|-------|
| RELATIVE / STICKY | In flex flow | Sticky clamps into clip |
| ABSOLUTE | Parent padding box | Pins: `x` / `y` / `right` / `bottom` |
| FIXED | Space bounds (popover uses viewport) | Same pins; out of flex gap |

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

After a builder’s layout tree is solved, [`ui_end_layout_pass`](oni/ui.odin#L132) runs:

1. [`layout_finalize_stack_order`](oni/layout_stack.odin#L376) — clips, paint lists, `stack_index`
2. [`layout_resolve_pointer_hit`](oni/layout_stack.odin#L466) — topmost hittable under pointer

Paint list order: artboard roots → screen roots → popover roots. Within siblings: negative `z` under parent chrome, then parent, then non-negative `z`; tie-break `order` then node index. Each popover root is its own stacking context. Hit test walks paint lists front-to-back: popover → screen → artboard.

| Proc | Role |
|------|------|
| [`layout_assign_stack`](oni/layout_stack.odin#L327) | Assign stack indices into a paint list |
| [`layout_is_popover_subtree_root`](oni/layout_stack.odin#L290) | Popover root detection |
| [`layout_stack_child_less`](oni/layout_stack.odin#L298) / [`layout_sort_stack_children`](oni/layout_stack.odin#L311) | Sibling sort |
| [`layout_hit_point_in_node`](oni/layout_stack.odin#L433) / [`layout_hit_test_list`](oni/layout_stack.odin#L445) | Hit helpers |
| [`begin_popover`](oni/draw.odin) / [`end_popover`](oni/draw.odin) | Popover space scope (`Popover_Begin` / `End`) |
| [`ui_layout_stack_index`](oni/layout_stack.odin#L130) | Draw query |
| [`ui_layout_paint_skip`](oni/layout_stack.odin#L140) / [`ui_layout_hit_skip`](oni/layout_stack.odin#L150) | Skip flags |
| [`ui_layout_clip_rect`](oni/layout_stack.odin#L160) | Clip query |

## Tables

`justify: TABLE_CELL` equalizes column widths / row heights across head/body/foot rows.

| Proc | Role |
|------|------|
| [`layout_find_table_ancestor`](oni/layout.odin#L1351) | Walk to TABLE |
| [`layout_node_is_table_cell`](oni/layout.odin#L1358) | Cell kind check |
| [`layout_node_participates_in_table_collapse`](oni/layout.odin#L1365) | Collapse participants |
| [`layout_justify_uses_TABLE_CELL_x`](oni/layout.odin#L1376) / [`_y`](oni/layout.odin#L1384) | Axis flags |
| [`layout_table_cell_intrinsic_axis`](oni/layout.odin#L1392) | Intrinsic cell size |
| [`layout_table_collect_rows_in`](oni/layout.odin#L1408) | Collect rows |
| [`layout_table_prepare`](oni/layout.odin#L1515) | Build shared tracks |
| [`layout_table_apply_cell_size`](oni/layout.odin#L1522) | Apply track size to cell |
| [`layout_table_finalize`](oni/layout.odin#L1609) | Assign cell positions |

`Layout_Table_Tracks` stores `col_count`, shared `col_widths` / `row_heights`, `cell_positions`, and per-cell `collapsed_borders` when border collapse is active. Track arrays allocate through the frame arena.

Collapsed gaps zero layout borders on push; paint conflict resolution lives in [`table_border.odin`](oni/table_border.odin) ([`table_gaps_are_collapsed`](oni/table_border.odin#L3), [`table_layout_resolve_collapsed_borders`](oni/table_border.odin#L189), …). Draw reads [`layout_collapsed_borders_result`](oni/layout.odin#L966).

## Text and image (layout-owned geometry)

| Proc | Role |
|------|------|
| [`layout_text_resolve_wrap_w`](oni/layout.odin#L594) | Wrap width |
| [`layout_text_build`](oni/layout.odin#L608) | Shape text |
| [`layout_text_position_lines`](oni/layout.odin#L660) | Line origins |
| [`layout_text_position_glyphs`](oni/layout.odin#L695) | Glyph quads |
| [`layout_text_append_decoration_stroke`](oni/layout.odin#L763) / [`layout_text_position_decorations`](oni/layout.odin#L814) | Underline etc. |
| [`layout_finalize_text_node`](oni/layout.odin#L870) | Post-rect text finalize |
| [`layout_set_image`](oni/layout.odin#L890) | Capture author image inputs into `image_input` |
| [`layout_finalize_image_node`](oni/layout.odin#L903) | Object-fit into content box → `image` |
| [`layout_text_result`](oni/layout.odin#L944) / [`layout_image_result`](oni/layout.odin#L955) | Draw queries |

Shaped text, glyph quads, and decoration strokes live in arena-owned slices on `Layout_Text`. `Layout_Node` keeps author image params in `image_input` during measure; finalized paint geometry is in `image`.

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
| `UI_Pass` | [oni/ui.odin](oni/ui.odin#L7) | `.Layout` / `.Draw` |
| `Layout_State` | [oni/layout.odin](oni/layout.odin#L119) | Nodes, stacks, id map, paint lists, space, frame arena, artboard zoom |
| `Layout_Node` | [oni/layout.odin](oni/layout.odin#L79) | Style, desired, rect, children, text/image, stack/hit/clip |
| `Layout_Measure` | [oni/layout.odin](oni/layout.odin#L10) | Author text + max_w hint |
| `Layout_Glyph_Paint` / `Layout_Decoration_Stroke` | [oni/layout.odin](oni/layout.odin#L18) | Layout-owned glyph quads and decoration segments |
| `Layout_Text` / `Layout_Image_Input` / `Layout_Image` / `Layout_Collapsed_Borders` | [oni/layout.odin](oni/layout.odin#L34) | Layout-owned paint geometry |
| `Layout_Table_Tracks` | [oni/layout.odin](oni/layout.odin#L106) | Shared col/row sizes, cell positions, collapsed borders |
| `Resolved_Widget_Style` / `Resolved_Widget_Config` | [oni/types.odin](oni/types.odin#L287) | Concrete style for layout |
| `Length` / `Direction_Layout` / `Justify_Pos` / `Position` | [oni/types.odin](oni/types.odin#L224) | Sizing, direction, justify, position |
| `Draw_Space` / `Rect` | [oni/types.odin](oni/types.odin#L863) | SCREEN / ARTBOARD / POPOVER; logical rect |
| `Style_Context` | [oni/types.odin](oni/types.odin#L364) | Style + content_w/h for percent/text wrap |
| `Layout_Position_Kind` | [oni/layout_stack.odin](oni/layout_stack.odin#L8) | Resolved position mode |

## UI query helpers

| Proc | Role |
|------|------|
| [`ui_pass`](oni/ui.odin#L192) | Current pass |
| [`ui_layout_rect`](oni/ui.odin#L201) | Solved rect by id |
| [`ui_was_laid_out_prev`](oni/ui.odin#L211) | Present last frame |
| [`ui_has_layout_node`](oni/ui.odin#L218) | Present this frame |
| [`ui_init`](oni/ui.odin#L17) / [`ui_shutdown`](oni/ui.odin#L42) | Allocate / tear down UI + layout |
| [`layout_reset`](oni/layout.odin#L227) / [`layout_shutdown`](oni/layout.odin#L280) | Per-frame clear / free dynamics |
| [`layout_release_node_children`](oni/layout.odin#L205) | Free child lists + text (skipped under arena) |
| [`layout_is_ancestor_of`](oni/layout.odin#L1321) | Ancestry check |
| [`layout_node_index`](oni/layout.odin#L1314) | Node → index |

## Style / Children helpers

| Proc | Role |
|------|------|
| [`length_resolve`](oni/style.odin#L11) / [`length_is_definite`](oni/style.odin#L28) | Axis length math |
| [`style_root`](oni/style.odin#L1228) / [`style_child_context`](oni/style.odin#L1237) | Root/child style contexts |
| [`ui_style_current`](oni/style.odin#L1258) / [`ui_push_style`](oni/style.odin#L1269) / [`ui_pop_style`](oni/style.odin#L1278) | Style stack |
| [`being_children`](oni/style.odin#L1288) / [`end_children`](oni/style.odin#L1299) | Enter/leave container |
| [`Children`](oni/style.odin#L1311) | Scoped child builder |

## Widget entry points

These branch on [`ui_pass`](oni/ui.odin#L192) and use `Children` and/or `layout_push_node`:

[`Button`](oni/widgets/button.odin), [`Rectangle`](oni/widgets/rectangle.odin), [`Text`](oni/widgets/text.odin), [`Image`](oni/widgets/image.odin), [`Table`](oni/widgets/table.odin), [`Table_Caption`](oni/widgets/table_caption.odin), [`Table_Head`](oni/widgets/table_head.odin), [`Table_Heading`](oni/widgets/table_heading.odin), [`Table_Body`](oni/widgets/table_body.odin), [`Table_Row`](oni/widgets/table_row.odin), [`Table_Cell`](oni/widgets/table_cell.odin), [`Table_Foot`](oni/widgets/table_foot.odin).

## Complete proc index (`oni/layout.odin`)

Frame arena / reset: [`layout_uses_frame_arena_in`](oni/layout.odin#L143), [`layout_uses_frame_arena`](oni/layout.odin#L150), [`layout_frame_allocator_for`](oni/layout.odin#L157), [`layout_frame_allocator`](oni/layout.odin#L169), [`layout_frame_arena_ensure`](oni/layout.odin#L175), [`layout_frame_arena_reset`](oni/layout.odin#L184), [`layout_frame_arena_destroy`](oni/layout.odin#L198), [`layout_release_node_children`](oni/layout.odin#L205), [`layout_reset`](oni/layout.odin#L227), [`layout_artboard_zoom`](oni/layout.odin#L254), [`layout_invalidate_artboard_zoom`](oni/layout.odin#L270), [`layout_shutdown`](oni/layout.odin#L280).

Lifecycle / tree: [`layout_push_node`](oni/layout.odin#L1117), [`layout_pop_node`](oni/layout.odin#L1191), [`layout_set_measure_text`](oni/layout.odin#L1176), [`layout_set_measure_size`](oni/layout.odin#L1184), [`layout_begin_space`](oni/layout.odin#L2479), [`layout_end_space`](oni/layout.odin#L2489), [`layout_space_bounds`](oni/layout.odin#L2464).

Direction / wrap / gap / justify: [`layout_config_direction`](oni/layout.odin#L303), [`layout_direction_info`](oni/layout.odin#L320), [`layout_direction_is_horizontal`](oni/layout.odin#L350), [`layout_direction_is_wrap`](oni/layout.odin#L357), [`layout_mirror_in_available`](oni/layout.odin#L364), [`layout_wrap_main_limit_from_config`](oni/layout.odin#L381), [`layout_wrap_child_main`](oni/layout.odin#L401), [`layout_wrap_child_cross`](oni/layout.odin#L408), [`layout_wrap_build_lines`](oni/layout.odin#L415), [`layout_wrap_measure`](oni/layout.odin#L452), [`layout_config_gap_main`](oni/layout.odin#L498), [`layout_config_gap_cross`](oni/layout.odin#L506), [`layout_config_justify`](oni/layout.odin#L514), [`layout_merge_justify`](oni/layout.odin#L521).

Boxes / measure / size: [`layout_clamp_axis`](oni/layout.odin#L530), [`layout_content_rect`](oni/layout.odin#L540), [`layout_inner_rect`](oni/layout.odin#L552), [`layout_measure_leaf`](oni/layout.odin#L977), [`layout_measure`](oni/layout.odin#L1018), [`layout_sort_children_by_order`](oni/layout.odin#L1097), [`layout_resolve_node_size`](oni/layout.odin#L1204), [`layout_apply_definite_size`](oni/layout.odin#L1224), [`layout_child_main_size`](oni/layout.odin#L1233), [`layout_child_in_main_flow`](oni/layout.odin#L1254), [`layout_child_cross_size`](oni/layout.odin#L1268).

Text / image: [`layout_node_has_text`](oni/layout.odin#L567), [`layout_text_release`](oni/layout.odin#L576), [`layout_text_resolve_wrap_w`](oni/layout.odin#L594), [`layout_text_build`](oni/layout.odin#L608), [`layout_text_position_lines`](oni/layout.odin#L660), [`layout_text_position_glyphs`](oni/layout.odin#L695), [`layout_text_append_decoration_stroke`](oni/layout.odin#L763), [`layout_text_position_decorations`](oni/layout.odin#L814), [`layout_finalize_text_node`](oni/layout.odin#L870), [`layout_set_image`](oni/layout.odin#L890), [`layout_finalize_image_node`](oni/layout.odin#L903), [`layout_finalize_node`](oni/layout.odin#L936), [`layout_text_result`](oni/layout.odin#L944), [`layout_image_result`](oni/layout.odin#L955), [`layout_collapsed_borders_result`](oni/layout.odin#L966).

Index / ancestry: [`layout_node_index_in`](oni/layout.odin#L1304), [`layout_node_index`](oni/layout.odin#L1314), [`layout_is_ancestor_of`](oni/layout.odin#L1321).

Tables: [`layout_find_table_ancestor_in`](oni/layout.odin#L1338), [`layout_find_table_ancestor`](oni/layout.odin#L1351), [`layout_node_is_table_cell`](oni/layout.odin#L1358), [`layout_node_participates_in_table_collapse`](oni/layout.odin#L1365), [`layout_justify_uses_TABLE_CELL_x`](oni/layout.odin#L1376), [`layout_justify_uses_TABLE_CELL_y`](oni/layout.odin#L1384), [`layout_table_cell_intrinsic_axis`](oni/layout.odin#L1392), [`layout_table_collect_rows_in`](oni/layout.odin#L1408), [`layout_table_row_track_index`](oni/layout.odin#L1437), [`layout_table_prepare_in`](oni/layout.odin#L1447), [`layout_table_prepare`](oni/layout.odin#L1515), [`layout_table_apply_cell_size`](oni/layout.odin#L1522), [`layout_table_finalize_in`](oni/layout.odin#L1550), [`layout_table_finalize`](oni/layout.odin#L1609).

Justify / place / solve: [`layout_main_justify_align`](oni/layout.odin#L1616), [`layout_cross_justify_align`](oni/layout.odin#L1632), [`layout_space_leading`](oni/layout.odin#L1648), [`layout_content_align_target`](oni/layout.odin#L1668), [`layout_sibling_axis_extrema`](oni/layout.odin#L1681), [`layout_apply_content_align_axis`](oni/layout.odin#L1696), [`layout_apply_content_align_sizes_indices`](oni/layout.odin#L1709), [`layout_apply_content_align_sizes`](oni/layout.odin#L1763), [`layout_space_between_items`](oni/layout.odin#L1775), [`layout_space_positions`](oni/layout.odin#L1792), [`layout_position_child_rect`](oni/layout.odin#L1824), [`layout_position_out_of_flow_children`](oni/layout.odin#L1889), [`layout_position_children_wrap`](oni/layout.odin#L1900), [`layout_wrap_apply_auto_cross_size`](oni/layout.odin#L2151), [`layout_position_children`](oni/layout.odin#L2177), [`layout_solve_node`](oni/layout.odin#L2419), [`layout_solve`](oni/layout.odin#L2457).

## Complete proc index (`oni/layout_stack.odin`)

[`layout_position_kind`](oni/layout_stack.odin#L31), [`layout_visibility_is_none`](oni/layout_stack.odin#L45), [`layout_visibility_is_hidden`](oni/layout_stack.odin#L53), [`layout_pointer_events_none`](oni/layout_stack.odin#L61), [`layout_overflow_clips`](oni/layout_stack.odin#L69), [`layout_overflow_is_scrollport`](oni/layout_stack.odin#L78), [`layout_padding_box`](oni/layout_stack.odin#L87), [`layout_clip_box`](oni/layout_stack.odin#L97), [`layout_position_in_flex_flow`](oni/layout_stack.odin#L104), [`ui_layout_stack_index`](oni/layout_stack.odin#L130), [`ui_layout_paint_skip`](oni/layout_stack.odin#L140), [`ui_layout_hit_skip`](oni/layout_stack.odin#L150), [`ui_layout_clip_rect`](oni/layout_stack.odin#L160), [`layout_place_against_containing_block`](oni/layout_stack.odin#L172), [`layout_place_out_of_flow`](oni/layout_stack.odin#L231), [`layout_resolve_clips`](oni/layout_stack.odin#L249), [`layout_is_popover_subtree_root`](oni/layout_stack.odin#L290), [`layout_stack_child_less`](oni/layout_stack.odin#L298), [`layout_sort_stack_children`](oni/layout_stack.odin#L311), [`layout_assign_stack`](oni/layout_stack.odin#L327), [`layout_finalize_stack_order`](oni/layout_stack.odin#L376), [`layout_hit_point_in_node`](oni/layout_stack.odin#L433), [`layout_hit_test_list`](oni/layout_stack.odin#L445), [`layout_resolve_pointer_hit`](oni/layout_stack.odin#L466).
