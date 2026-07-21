package oni

import "core:slice"

/*
Helpers for position, visibility, pointer-events, overflow clip, and paint/hit
stack order. Layout owns stacking policy; draw only reads stack_index / flags.
*/

Layout_Position_Kind :: enum {
	RELATIVE,
	ABSOLUTE,
	FIXED,
	STICKY,
}

/*
Returns whether a Style_F32 Cfg was author-specified (including inherit-from-set).
*/
@(private)
cfg_f32_is_set :: proc(field: Cfg(Style_F32), parent_set: bool) -> bool {
	if field.mode != .Value do return false
	#partial switch v in field.value {
	case Inherit:
		return parent_set
	}
	return true
}

/*
Extracts the concrete position kind from a resolved Position union.
*/
layout_position_kind :: proc(position: Position) -> Layout_Position_Kind {
	if position == nil do return .RELATIVE
	abs: Position = .ABSOLUTE
	if position == abs do return .ABSOLUTE
	fixed: Position = .FIXED
	if position == fixed do return .FIXED
	sticky: Position = .STICKY
	if position == sticky do return .STICKY
	return .RELATIVE
}

/*
Returns whether visibility is NONE (removed from layout/draw tree).
*/
layout_visibility_is_none :: proc(visibility: Visibility) -> bool {
	none: Visibility = .NONE
	return visibility == none
}

/*
Returns whether visibility is HIDDEN (layout reserved, no paint/hit).
*/
layout_visibility_is_hidden :: proc(visibility: Visibility) -> bool {
	hidden: Visibility = .HIDDEN
	return visibility == hidden
}

/*
Returns whether pointer events are disabled for hit-testing.
*/
layout_pointer_events_none :: proc(pointer_events: Pointer_Events) -> bool {
	none: Pointer_Events = .NONE
	return pointer_events == none
}

/*
Returns whether overflow mode clips content (HIDDEN, SCROLL, or AUTO).
*/
layout_overflow_clips :: proc(overflow: Overflow) -> bool {
	hidden: Overflow = .HIDDEN
	scroll: Overflow = .SCROLL
	auto: Overflow = .AUTO
	return overflow == hidden || overflow == scroll || overflow == auto
}

/*
Returns whether overflow mode is a scrollport (SCROLL or AUTO).
*/
layout_overflow_is_scrollport :: proc(overflow: Overflow) -> bool {
	scroll: Overflow = .SCROLL
	auto: Overflow = .AUTO
	return overflow == scroll || overflow == auto
}

/*
Padding box of a layout node (border edge inward — absolute containing block).
*/
layout_padding_box :: proc(node: ^Layout_Node) -> Rect {
	return layout_content_rect(
		node.rect,
		{t = node.border.t, b = node.border.b, l = node.border.l, r = node.border.r},
	)
}

/*
Content box used as overflow clip viewport.
*/
layout_clip_box :: proc(node: ^Layout_Node) -> Rect {
	return layout_inner_rect(node.rect, node.border, node.padding)
}

/*
True when the position mode participates in flex main/cross distribution.
*/
layout_position_in_flex_flow :: proc(position: Position) -> bool {
	kind := layout_position_kind(position)
	return kind == .RELATIVE || kind == .STICKY
}

/*
Returns the layout-assigned paint stack index for a UI id.
*/
ui_layout_stack_index :: proc(id: UI_Id) -> u32 {
	if node_index, ok := state.ui.layout.id_to_node[id]; ok {
		return state.ui.layout.nodes[node_index].stack_index
	}
	return 0
}

/*
Returns whether paint should be skipped for a UI id (HIDDEN subtree).
*/
ui_layout_paint_skip :: proc(id: UI_Id) -> bool {
	if node_index, ok := state.ui.layout.id_to_node[id]; ok {
		return state.ui.layout.nodes[node_index].paint_skip
	}
	return true
}

/*
Returns whether hit-testing should skip a UI id.
*/
ui_layout_hit_skip :: proc(id: UI_Id) -> bool {
	if node_index, ok := state.ui.layout.id_to_node[id]; ok {
		return state.ui.layout.nodes[node_index].hit_skip
	}
	return true
}

/*
Returns the cumulative overflow clip rect for a UI id.
*/
ui_layout_clip_rect :: proc(id: UI_Id) -> Rect {
	if node_index, ok := state.ui.layout.id_to_node[id]; ok {
		node := &state.ui.layout.nodes[node_index]
		if node.has_clip do return node.clip_rect
		return node.rect
	}
	return {}
}

/*
Places an out-of-flow node against an explicit containing block.
*/
layout_place_against_containing_block :: proc(child: ^Layout_Node, cb: Rect) {
	left_set := child.config.x_set
	right_set := child.config.right_set
	top_set := child.config.y_set
	bottom_set := child.config.bottom_set
	left := child.config.x
	right := child.config.right
	top := child.config.y
	bottom := child.config.bottom

	width := length_resolve(child.config.width, cb.w)
	height := length_resolve(child.config.height, cb.h)
	if width <= 0 do width = child.desired.x
	if height <= 0 do height = child.desired.y

	if left_set && right_set {
		width = max(0, cb.w - left - right)
	}
	if top_set && bottom_set {
		height = max(0, cb.h - top - bottom)
	}

	width = layout_clamp_axis(width, child.config.min_w, child.config.max_w)
	height = layout_clamp_axis(height, child.config.min_h, child.config.max_h)

	x: f32
	y: f32
	switch {
	case left_set && right_set:
		x = cb.x + left
	case left_set:
		x = cb.x + left
	case right_set:
		x = cb.x + cb.w - right - width
	case:
		x = cb.x
	}
	switch {
	case top_set && bottom_set:
		y = cb.y + top
	case top_set:
		y = cb.y + top
	case bottom_set:
		y = cb.y + cb.h - bottom - height
	case:
		y = cb.y
	}

	child.rect = {x = x, y = y, w = width, h = height}
	layout_finalize_node(child)

	if len(child.child_indices) > 0 {
		layout_position_children(child, layout_inner_rect(child.rect, child.border, child.padding))
	}
}

/*
Places an out-of-flow (ABSOLUTE / FIXED) child against its containing block.
*/
layout_place_out_of_flow :: proc(child: ^Layout_Node, parent: ^Layout_Node) {
	kind := layout_position_kind(child.config.position)
	cb: Rect
	if kind == .FIXED {
		cb = layout_space_bounds(child.space)
	} else {
		cb = layout_padding_box(parent)
	}
	layout_place_against_containing_block(child, cb)
}

/*
Resolves cumulative clip rects for a subtree after geometry is known.
*/
layout_resolve_clips :: proc(node_index: int, parent_clip: Rect, parent_has_clip: bool) {
	node := &state.ui.layout.nodes[node_index]
	clip := parent_clip
	has_clip := parent_has_clip

	if layout_overflow_clips(node.config.overflow_x) ||
	   layout_overflow_clips(node.config.overflow_y) {
		box := layout_clip_box(node)
		if has_clip {
			clip = rect_intersect(clip, box)
		} else {
			clip = box
			has_clip = true
		}
	}

	node.clip_rect = clip
	node.has_clip = has_clip

	kind := layout_position_kind(node.config.position)
	if kind == .STICKY && has_clip {
		// Keep sticky boxes inside the nearest clip/scrollport viewport.
		r := node.rect
		if r.x < clip.x do r.x = clip.x
		if r.y < clip.y do r.y = clip.y
		if r.x + r.w > clip.x + clip.w do r.x = clip.x + clip.w - r.w
		if r.y + r.h > clip.y + clip.h do r.y = clip.y + clip.h - r.h
		node.rect = r
	}

	for child_index in node.child_indices {
		// Popover/overlay subtrees are not clipped by app-tree overflow.
		if layout_is_layer_subtree_root(child_index) {
			layout_resolve_clips(child_index, {}, false)
			continue
		}
		layout_resolve_clips(child_index, clip, has_clip)
	}
}

@(private)
layout_space_is_layer :: proc(space: Draw_Space) -> bool {
	return space == .POPOVER || space == .OVERLAY
}

@(private)
layout_is_layer_subtree_root :: proc(node_index: int) -> bool {
	node := &state.ui.layout.nodes[node_index]
	if !layout_space_is_layer(node.space) do return false
	if node.parent < 0 do return true
	return !layout_space_is_layer(state.ui.layout.nodes[node.parent].space)
}

@(private)
layout_stack_child_less :: proc(a_index, b_index: int) -> bool {
	a := &state.ui.layout.nodes[a_index]
	b := &state.ui.layout.nodes[b_index]
	if a.config.z_index != b.config.z_index {
		return a.config.z_index < b.config.z_index
	}
	if a.config.order != b.config.order {
		return a.config.order < b.config.order
	}
	return a_index < b_index
}

@(private)
layout_sort_stack_children :: proc(indices: []int) {
	n := len(indices)
	if n < 2 do return

	if n < LAYOUT_CHILD_SORT_INSERTION_THRESHOLD {
		for i in 1 ..< n {
			key := indices[i]
			j := i - 1
			for j >= 0 && layout_stack_child_less(key, indices[j]) {
				indices[j + 1] = indices[j]
				j -= 1
			}
			indices[j + 1] = key
		}

		return
	}

	slice.sort_by(indices, proc(a, b: int) -> bool {
		return layout_stack_child_less(a, b)
	})
}

/*
Assigns paint_skip / hit_skip and appends paint order for a subtree.
*/
layout_assign_stack :: proc(node_index: int, paint_list: ^[dynamic]int, ancestor_hidden: bool) {
	node := &state.ui.layout.nodes[node_index]
	hidden := ancestor_hidden || layout_visibility_is_hidden(node.config.visibility)
	node.paint_skip = hidden
	node.hit_skip = hidden || layout_pointer_events_none(node.config.pointer_events)

	neg := make([dynamic]int, context.temp_allocator)
	pos := make([dynamic]int, context.temp_allocator)

	for child_index in node.child_indices {
		if layout_is_layer_subtree_root(child_index) {
			continue
		}
		child := &state.ui.layout.nodes[child_index]
		if child.config.z_index < 0 {
			append(&neg, child_index)
		} else {
			append(&pos, child_index)
		}
	}
	layout_sort_stack_children(neg[:])
	layout_sort_stack_children(pos[:])

	if hidden {
		for c in neg {
			layout_assign_stack(c, paint_list, true)
		}
		for c in pos {
			layout_assign_stack(c, paint_list, true)
		}
		return
	}

	for c in neg {
		layout_assign_stack(c, paint_list, false)
	}

	node.stack_index = state.ui.layout.stack_counter
	state.ui.layout.stack_counter += 1
	append(paint_list, node_index)

	for c in pos {
		layout_assign_stack(c, paint_list, false)
	}
}

/*
Finalizes global stack ordering: artboard (back), screen, popover, overlay (front).

Each popover/overlay subtree root is its own stacking context; z_index sorts within
that context, then among sibling layer roots.
*/
layout_finalize_stack_order :: proc() {
	clear(&state.ui.layout.paint_list_artboard)
	clear(&state.ui.layout.paint_list_screen)
	clear(&state.ui.layout.paint_list_popover)
	clear(&state.ui.layout.paint_list_overlay)
	state.ui.layout.stack_counter = 0

	artboard_roots := make([dynamic]int, context.temp_allocator)
	screen_roots := make([dynamic]int, context.temp_allocator)

	for node_index in 0 ..< len(state.ui.layout.nodes) {
		node := &state.ui.layout.nodes[node_index]
		if node.parent >= 0 do continue
		if layout_space_is_layer(node.space) do continue
		layout_resolve_clips(node_index, {}, false)
		if node.space == .ARTBOARD {
			append(&artboard_roots, node_index)
		} else {
			append(&screen_roots, node_index)
		}
	}
	layout_sort_stack_children(artboard_roots[:])
	layout_sort_stack_children(screen_roots[:])

	for root in artboard_roots {
		layout_assign_stack(root, &state.ui.layout.paint_list_artboard, false)
	}
	for root in screen_roots {
		layout_assign_stack(root, &state.ui.layout.paint_list_screen, false)
	}

	popover_roots := make([dynamic]int, context.temp_allocator)
	for node_index in 0 ..< len(state.ui.layout.nodes) {
		node := &state.ui.layout.nodes[node_index]
		if node.space != .POPOVER do continue
		if !layout_is_layer_subtree_root(node_index) do continue
		layout_resolve_clips(node_index, {}, false)
		append(&popover_roots, node_index)
	}
	layout_sort_stack_children(popover_roots[:])
	for root in popover_roots {
		layout_assign_stack(root, &state.ui.layout.paint_list_popover, false)
	}

	overlay_roots := make([dynamic]int, context.temp_allocator)
	for node_index in 0 ..< len(state.ui.layout.nodes) {
		node := &state.ui.layout.nodes[node_index]
		if node.space != .OVERLAY do continue
		if !layout_is_layer_subtree_root(node_index) do continue
		layout_resolve_clips(node_index, {}, false)
		append(&overlay_roots, node_index)
	}
	layout_sort_stack_children(overlay_roots[:])
	for root in overlay_roots {
		layout_assign_stack(root, &state.ui.layout.paint_list_overlay, false)
	}

	state.ui.layout.stack_counter = 0
	for node_index in state.ui.layout.paint_list_artboard {
		state.ui.layout.nodes[node_index].stack_index = state.ui.layout.stack_counter
		state.ui.layout.stack_counter += 1
	}
	for node_index in state.ui.layout.paint_list_screen {
		state.ui.layout.nodes[node_index].stack_index = state.ui.layout.stack_counter
		state.ui.layout.stack_counter += 1
	}
	for node_index in state.ui.layout.paint_list_popover {
		state.ui.layout.nodes[node_index].stack_index = state.ui.layout.stack_counter
		state.ui.layout.stack_counter += 1
	}
	for node_index in state.ui.layout.paint_list_overlay {
		state.ui.layout.nodes[node_index].stack_index = state.ui.layout.stack_counter
		state.ui.layout.stack_counter += 1
	}
}

@(private)
layout_hit_point_in_node :: proc(node: ^Layout_Node, mouse: Vec2) -> bool {
	if node.rect.w <= 0 || node.rect.h <= 0 do return false
	if mouse.x < node.rect.x || mouse.x >= node.rect.x + node.rect.w do return false
	if mouse.y < node.rect.y || mouse.y >= node.rect.y + node.rect.h do return false
	if node.has_clip {
		if mouse.x < node.clip_rect.x || mouse.x >= node.clip_rect.x + node.clip_rect.w do return false
		if mouse.y < node.clip_rect.y || mouse.y >= node.clip_rect.y + node.clip_rect.h do return false
	}
	return true
}

@(private)
layout_hit_test_list :: proc(list: []int, space: Draw_Space) -> (UI_Id, bool) {
	mouse := Vec2{w_ctx.mouse_x, w_ctx.mouse_y}
	if space == .ARTBOARD {
		mouse = View_Screen_To_World(mouse)
	}

	for i := len(list) - 1; i >= 0; i -= 1 {
		node := &state.ui.layout.nodes[list[i]]
		if node.hit_skip do continue
		if node.space != space do continue
		if !layout_hit_point_in_node(node, mouse) do continue
		return node.ui_id, true
	}
	return {}, false
}

/*
Picks the topmost layout node under the pointer from paint lists.

Hit order (front → back): overlay → popover → screen → artboard.
*/
layout_resolve_pointer_hit :: proc() {
	w_ctx.pointer_hit_valid = false
	w_ctx.pointer_hit_ui_id = {}

	if id, ok := layout_hit_test_list(state.ui.layout.paint_list_overlay[:], .OVERLAY); ok {
		w_ctx.pointer_hit_ui_id = id
		w_ctx.pointer_hit_valid = true
		return
	}
	if id, ok := layout_hit_test_list(state.ui.layout.paint_list_popover[:], .POPOVER); ok {
		w_ctx.pointer_hit_ui_id = id
		w_ctx.pointer_hit_valid = true
		return
	}
	if id, ok := layout_hit_test_list(state.ui.layout.paint_list_screen[:], .SCREEN); ok {
		w_ctx.pointer_hit_ui_id = id
		w_ctx.pointer_hit_valid = true
		return
	}
	if id, ok := layout_hit_test_list(state.ui.layout.paint_list_artboard[:], .ARTBOARD); ok {
		w_ctx.pointer_hit_ui_id = id
		w_ctx.pointer_hit_valid = true
		return
	}
}
