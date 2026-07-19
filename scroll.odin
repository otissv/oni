package oni

SCROLL_BAR_DEFAULT_SIZE :: f32(12)
SCROLL_BAR_MIN_THUMB :: f32(24)
SCROLL_WHEEL_SCALE :: f32(40)

/*
Returns whether a resolved overflow mode creates a scrollport on that axis.
*/
layout_node_scrolls_axis :: proc(overflow: Overflow) -> bool {
	return layout_overflow_is_scrollport(overflow)
}

/*
Returns whether resolved style overflow makes this node a scrollport.
*/
style_is_scrollport :: proc(overflow_x, overflow_y: Overflow) -> bool {
	return layout_node_scrolls_axis(overflow_x) || layout_node_scrolls_axis(overflow_y)
}

/*
Returns whether a layout node is a scrollport on either axis.
*/
layout_node_is_scrollport :: proc(node: ^Layout_Node) -> bool {
	if node == nil do return false
	return style_is_scrollport(node.config.overflow_x, node.config.overflow_y)
}

/*
Returns whether a child participates in scrolled content (not a scrollbar chrome).
*/
layout_child_is_scroll_content :: proc(child: ^Layout_Node) -> bool {
	return child != nil && child.kind != .SCROLL_BAR
}

/*
Offsets layout-owned paint geometry that was finalized in absolute coordinates.

Node rects are scrolled separately; text glyphs, decorations, image dst, and
collapsed-border strips must move with the same delta or they paint unmoved.
*/
layout_offset_paint_geometry :: proc(node: ^Layout_Node, dx, dy: f32) {
	if node == nil || (dx == 0 && dy == 0) do return

	for &origin in node.text.line_origins {
		origin.x += dx
		origin.y += dy
	}
	for &glyph in node.text.glyphs {
		glyph.dst.x += dx
		glyph.dst.y += dy
	}
	for &stroke in node.text.decoration_strokes {
		stroke.a.x += dx
		stroke.a.y += dy
		stroke.b.x += dx
		stroke.b.y += dy
	}

	if node.image.active {
		node.image.content.x += dx
		node.image.content.y += dy
		node.image.dst.x += dx
		node.image.dst.y += dy
	}

	if node.collapsed_borders.active {
		for &strip in node.collapsed_borders.strips {
			strip.x += dx
			strip.y += dy
		}
	}
}

/*
Offsets a layout subtree's rects by (dx, dy).
*/
layout_offset_subtree :: proc(node_index: int, dx, dy: f32) {
	if dx == 0 && dy == 0 do return
	node := &state.ui.layout.nodes[node_index]
	node.rect.x += dx
	node.rect.y += dy
	layout_offset_paint_geometry(node, dx, dy)
	for child_index in node.child_indices {
		layout_offset_subtree(child_index, dx, dy)
	}
}

/*
Measures unscrolled content size from non-scrollbar children relative to content origin.
*/
layout_measure_scroll_content :: proc(node: ^Layout_Node, content: Rect) -> Vec2 {
	max_r := content.x
	max_b := content.y
	has_content := false

	for child_index in node.child_indices {
		child := &state.ui.layout.nodes[child_index]
		if !layout_child_is_scroll_content(child) do continue
		has_content = true
		max_r = max(max_r, child.rect.x + child.rect.w)
		max_b = max(max_b, child.rect.y + child.rect.h)
	}

	if !has_content {
		return {content.w, content.h}
	}
	return {max(content.w, max_r - content.x), max(content.h, max_b - content.y)}
}

/*
Clamps config scroll, records metrics, and offsets scrollable children of a scrollport.

Scroll offsets come from `node.config.scroll_x` / `scroll_y`, which widgets fill from
widget-context state (optionally overwritten by author `Scroll_Value` config).
Call after in-flow and out-of-flow children have been positioned in unscrolled space.
*/
layout_finalize_scrollport :: proc(node: ^Layout_Node, content: Rect) {
	if !layout_node_is_scrollport(node) do return

	content_size := layout_measure_scroll_content(node, content)
	viewport := Vec2{content.w, content.h}
	max_scroll := Vec2 {
		max(0, content_size.x - viewport.x),
		max(0, content_size.y - viewport.y),
	}

	scroll_x := node.config.scroll_x
	scroll_y := node.config.scroll_y
	if !layout_node_scrolls_axis(node.config.overflow_x) {
		scroll_x = 0
		max_scroll.x = 0
	}
	if !layout_node_scrolls_axis(node.config.overflow_y) {
		scroll_y = 0
		max_scroll.y = 0
	}
	scroll_x = clamp(scroll_x, 0, max_scroll.x)
	scroll_y = clamp(scroll_y, 0, max_scroll.y)

	node.config.scroll_x = scroll_x
	node.config.scroll_y = scroll_y
	node.content_size = content_size
	node.viewport_size = viewport
	node.scroll = {scroll_x, scroll_y}
	node.max_scroll = max_scroll

	scroll_store_metrics(
		node.ui_id,
		{
			content_size = content_size,
			viewport_size = viewport,
			scroll = node.scroll,
			max_scroll = max_scroll,
		},
	)

	if scroll_x == 0 && scroll_y == 0 do return
	for child_index in node.child_indices {
		child := &state.ui.layout.nodes[child_index]
		if !layout_child_is_scroll_content(child) do continue
		layout_offset_subtree(child_index, -scroll_x, -scroll_y)
	}
}

/*
Persists scrollport metrics for the next frame (AUTO bar visibility, APIs).
*/
scroll_store_metrics :: proc(id: UI_Id, metrics: Scrollport_Metrics) {
	if state == nil do return
	if state.ui.scrollports == nil {
		state.ui.scrollports = make(map[UI_Id]Scrollport_Metrics)
	}
	state.ui.scrollports[id] = metrics
}

/*
Returns last known scrollport metrics for a UI id.

During the layout pass, prefer the previous-frame store: the live node is not
finalized while its children (and AUTO scrollbars) are still being built.
After finalize, the store matches the live node. Draw uses the live node.
*/
ui_scrollport_metrics :: proc(id: UI_Id) -> (Scrollport_Metrics, bool) {
	if state == nil do return {}, false

	if ui_pass() == .Layout {
		if state.ui.scrollports != nil {
			if m, ok := state.ui.scrollports[id]; ok {
				return m, true
			}
		}
	}

	if node_index, ok := state.ui.layout.id_to_node[id]; ok {
		node := &state.ui.layout.nodes[node_index]
		if layout_node_is_scrollport(node) {
			return {
					content_size = node.content_size,
					viewport_size = node.viewport_size,
					scroll = node.scroll,
					max_scroll = node.max_scroll,
				},
				true
		}
	}

	if state.ui.scrollports == nil do return {}, false
	m, ok := state.ui.scrollports[id]
	return m, ok
}

/*
Clamps a scroll offset into [0, max_scroll] for one axis.
*/
scroll_clamp_axis :: proc(value, max_scroll: f32) -> f32 {
	return clamp(value, 0, max(0, max_scroll))
}

/*
Computes thumb size and offset along a track for the given scroll metrics.
*/
scroll_bar_thumb_geometry :: proc(
	track_len, viewport, content, scroll, min_thumb: f32,
) -> (
	thumb_len, thumb_pos: f32,
) {
	if track_len <= 0 do return 0, 0
	max_scroll := max(0, content - viewport)
	if max_scroll <= 0 || content <= 0 {
		return track_len, 0
	}
	floor := min_thumb > 0 ? min_thumb : SCROLL_BAR_MIN_THUMB
	thumb_len = max(floor, track_len * (viewport / content))
	thumb_len = min(thumb_len, track_len)
	travel := track_len - thumb_len
	t := scroll / max_scroll
	thumb_pos = clamp(t, 0, 1) * travel
	return thumb_len, thumb_pos
}

/*
Maps a pointer position along the track to a scroll value.
*/
scroll_bar_scroll_from_pointer :: proc(
	pointer, track_origin, track_len, thumb_len, grab_offset, max_scroll: f32,
) -> f32 {
	if track_len <= thumb_len || max_scroll <= 0 do return 0
	travel := track_len - thumb_len
	pos := pointer - track_origin - grab_offset
	t := clamp(pos / travel, 0, 1)
	return t * max_scroll
}

/*
Returns or creates scrollbar drag state for a layout id.
*/
scroll_bar_drag_entry :: proc(id: UI_Id) -> ^Scroll_Bar_Drag {
	if state == nil do return nil
	if state.ui.scroll_bar_drags == nil {
		state.ui.scroll_bar_drags = make(map[UI_Id]Scroll_Bar_Drag)
	}
	if _, ok := state.ui.scroll_bar_drags[id]; !ok {
		state.ui.scroll_bar_drags[id] = {}
	}
	return &state.ui.scroll_bar_drags[id]
}

/*
Clears scrollbar drag state when the pointer is released.
*/
scroll_bar_drag_clear :: proc(id: UI_Id) {
	if state == nil || state.ui.scroll_bar_drags == nil do return
	delete_key(&state.ui.scroll_bar_drags, id)
}

/*
Applies wheel deltas to scroll offsets and returns whether scroll changed.
*/
scroll_apply_wheel :: proc(
	scroll_x, scroll_y: ^f32,
	max_scroll: Vec2,
	wheel_x, wheel_y: f32,
	overflow_x, overflow_y: Overflow,
) -> bool {
	if scroll_x == nil || scroll_y == nil do return false
	changed := false
	if layout_node_scrolls_axis(overflow_x) && wheel_x != 0 && max_scroll.x > 0 {
		next := scroll_clamp_axis(scroll_x^ - wheel_x * SCROLL_WHEEL_SCALE, max_scroll.x)
		if next != scroll_x^ {
			scroll_x^ = next
			changed = true
		}
	}
	if layout_node_scrolls_axis(overflow_y) && wheel_y != 0 && max_scroll.y > 0 {
		next := scroll_clamp_axis(scroll_y^ - wheel_y * SCROLL_WHEEL_SCALE, max_scroll.y)
		if next != scroll_y^ {
			scroll_y^ = next
			changed = true
		}
	}
	return changed
}

/*
Pushes the layout clip rect for a UI id when the node has overflow clipping.

Returns whether a clip was pushed (caller must pop).
*/
draw_push_layout_clip :: proc(id: UI_Id) -> bool {
	if node_index, ok := state.ui.layout.id_to_node[id]; ok {
		node := &state.ui.layout.nodes[node_index]
		if node.has_clip {
			draw_push_clip(node.clip_rect)
			return true
		}
	}
	return false
}

@(private)
scroll_shutdown :: proc() {
	if state == nil do return
	if state.ui.scrollports != nil {
		delete(state.ui.scrollports)
		state.ui.scrollports = nil
	}
	if state.ui.scroll_bar_drags != nil {
		delete(state.ui.scroll_bar_drags)
		state.ui.scroll_bar_drags = nil
	}
}
