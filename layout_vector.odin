package oni

// Snapshot storage belongs to the layout frame arena. No pointer to caller
// configuration or a shared SVG asset survives Layout.
Layout_Vector :: struct {
	active: bool,
	viewport, content, src, dst: Rect,
	fit: Texture_Fit,
	snapshot: rawptr,
	error: Vector_Error,
}
layout_set_vector :: proc(node: ^Layout_Node, viewport: Rect, fit: Texture_Fit, snapshot: rawptr) {
	node.vector = {active = true, viewport = viewport, fit = fit, snapshot = snapshot}
}
@(private)
layout_vector_has_intrinsics :: proc(node: ^Layout_Node) -> bool {
	viewport := node.vector.viewport
	return node.vector.active && viewport.w > 0 && viewport.w <= 1 << 20 && viewport.h > 0 && viewport.h <= 1 << 20
}

@(private)
layout_vector_apply_aspect_ratio :: proc(node: ^Layout_Node, size: ^Vec2) {
	if !layout_vector_has_intrinsics(node) { return }
	inset_x := node.padding.l + node.padding.r + node.border.l + node.border.r
	inset_y := node.padding.t + node.padding.b + node.border.t + node.border.b
	width, height := node.config.width, node.config.height
	viewport := node.vector.viewport
	if length_height_expands_with_content(height) && (length_is_definite(width) || length_fills_free_space(width)) {
		size.y = layout_clamp_axis(max(0, size.x - inset_x) * viewport.h / viewport.w + inset_y, node.config.min_h, node.config.max_h)
	} else if !length_is_definite(width) && !length_fills_free_space(width) && (length_is_definite(height) || length_fills_free_space(height) || length_height_fills_parent(height)) {
		size.x = layout_clamp_axis(max(0, size.y - inset_y) * viewport.w / viewport.h + inset_x, node.config.min_w, node.config.max_w)
	}
}

// Vector/SVG viewports contribute intrinsic size; composable children paint inside
// the solved content box and must not replace that measurement. Percent, inherit
// and auto aspect-ratio axes resolve later in layout_resolve_node_size.
@(private)
layout_vector_measure :: proc(node: ^Layout_Node, children: Vec2) -> Vec2 {
	if !layout_vector_has_intrinsics(node) { return children }
	_ = children
	size := Vec2{
		node.vector.viewport.w + node.padding.l + node.padding.r + node.border.l + node.border.r,
		node.vector.viewport.h + node.padding.t + node.padding.b + node.border.t + node.border.b,
	}
	if node.config.width.kind == .FIXED { size.x = length_resolve(node.config.width, 0) }
	if node.config.height.kind == .FIXED { size.y = length_resolve(node.config.height, 0) }
	size.x = layout_clamp_axis(size.x, node.config.min_w, node.config.max_w)
	size.y = layout_clamp_axis(size.y, node.config.min_h, node.config.max_h)
	return size
}
@(private)
layout_finalize_vector_node :: proc(node: ^Layout_Node) {
	if !node.vector.active { return }
	content := layout_inner_rect(node.rect, node.border, node.padding)
	src, dst := texture_fit_rects(node.vector.viewport, content, node.vector.fit, {x = .5, y = .5})
	node.vector.content, node.vector.src, node.vector.dst = content, src, dst
}
layout_vector_result :: proc(id: UI_Id) -> ^Layout_Vector {
	if index, found := state.ui.layout.id_to_node[id]; found && state.ui.layout.nodes[index].vector.active { return &state.ui.layout.nodes[index].vector }
	return nil
}
