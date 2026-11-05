package oni_vector

import "core:sync"
import "core:slice"

@(private)
svg_override_paint_only :: proc(property: Svg_Override_Property) -> bool {
	// Color can change inherited currentColor through the cascade; keep the
	// full compile path for those overrides.
	switch property {
	case .Fill, .Stroke, .Opacity, .Fill_Opacity, .Stroke_Opacity:
		return true
	case .Color, .Transform, .Stroke_Settings, .Path:
		return false
	}

	return false
}

@(private)
svg_overrides_can_patch_compiled_roots :: proc(asset: ^Svg_Asset, overrides: []Svg_Override) -> bool {
	has_path := false
	for &override in overrides {
		node := svg_element_node(asset, override.target)
		if node == nil || !svg_is_shape_element(node.name) {
			return false
		}
		if override.property == .Path {
			if len(override.commands) == 0 { return false }
			has_path = true
		} else if !svg_override_paint_only(override.property) {

			return false
		}

		// Definition targets only — occurrence chains need the full compile.
		if override.target == {} || override.occurrence.element != {} || override.occurrence.depth != 0 {

			return false
		}
	}
	if has_path {
		// Composition bounds and hidden/empty shapes require the full compiler.
		for &root in asset.roots { if root.kind != .Path { return false } }
		for &override in overrides {
			if override.property == .Opacity { return false }
			if override.property != .Path { continue }
			found := false
			for &root in asset.roots { found ||= root.item.element_index == override.target.index }
			if !found { return false }
		}
	}

	return true
}

@(private)
svg_clone_paint :: proc(#by_ptr paint: Paint) -> (Paint, bool) {
	owned, err := Clone_Paint(paint)

	return owned, err == .None
}

@(private)
svg_clone_path_item :: proc(#by_ptr item: Svg_Path_Item) -> (Svg_Path_Item, bool) {
	fill, fill_ok := svg_clone_paint(item.fill)
	if !fill_ok {

		return {}, false
	}

	stroke, stroke_ok := svg_clone_paint(item.stroke)
	if !stroke_ok {

		return {}, false
	}

	return {
		commands = item.commands,
		commands_hash = item.commands_hash,
		transform = item.transform,
		fill = fill,
		stroke = stroke,
		fill_rule = item.fill_rule,
		opacity = item.opacity,
		fill_opacity = item.fill_opacity,
		stroke_opacity = item.stroke_opacity,
		stroke_settings = item.stroke_settings,
		draw_fill = item.draw_fill,
		draw_stroke = item.draw_stroke,
		paint_order = item.paint_order,
		element_index = item.element_index,
	}, true
}

@(private)
svg_clone_draw_nodes :: proc(nodes: []Svg_Draw_Node, out: ^[dynamic]Svg_Draw_Node) -> bool {
	if reserve(out, len(out^) + len(nodes)) != nil { return false }
	for &node in nodes {
		clone := node
		clone.children = nil
		clone.clip_items = nil
		clone.clip_nodes = nil
		clone.mask_nodes = nil
		switch node.kind {
		case .Path:
			item, ok := svg_clone_path_item(node.item)
			if !ok {

				return false
			}

			clone.item = item
		case .Group, .Clip, .Mask:
			if len(node.children) > 0 {
				children := make([dynamic]Svg_Draw_Node, 0, context.allocator)
				if !svg_clone_draw_nodes(node.children, &children) {

					return false
				}

				clone.children = children[:]
			}

			if len(node.clip_items) > 0 {
				items := make([]Svg_Path_Item, len(node.clip_items), context.allocator)
				for item, i in node.clip_items {
					cloned, ok := svg_clone_path_item(item)
					if !ok {

						return false
					}

					items[i] = cloned
				}

				clone.clip_items = items
			}

			if len(node.clip_nodes) > 0 {
				clip_nodes := make([dynamic]Svg_Draw_Node, 0, context.allocator)
				if !svg_clone_draw_nodes(node.clip_nodes, &clip_nodes) {

					return false
				}

				clone.clip_nodes = clip_nodes[:]
			}

			if len(node.mask_nodes) > 0 {
				mask_nodes := make([dynamic]Svg_Draw_Node, 0, context.allocator)
				if !svg_clone_draw_nodes(node.mask_nodes, &mask_nodes) {

					return false
				}

				clone.mask_nodes = mask_nodes[:]
			}
		}

		if _, err := append(out, clone); err != nil {

			return false
		}
	}

	return true
}

@(private)
svg_apply_definition_paint_override :: proc(item: ^Svg_Path_Item, property: Svg_Override_Property, #by_ptr value: Svg_Override_Value) -> bool {
	switch property {
	case .Fill:
		paint, ok := svg_clone_paint(value.paint)
		if !ok {

			return false
		}

		item.fill = paint
		item.draw_fill = paint.kind != .None
	case .Stroke:
		paint, ok := svg_clone_paint(value.paint)
		if !ok {

			return false
		}

		item.stroke = paint
		item.draw_stroke = paint.kind != .None && item.stroke_settings.width > 0
	case .Color:
		// Color / currentColor needs the full cascade compile path.
	case .Opacity:
		item.opacity = value.opacity
	case .Fill_Opacity:
		item.fill_opacity = value.opacity
	case .Stroke_Opacity:
		item.stroke_opacity = value.opacity
	case .Path:
		item.commands = slice.clone(value.commands)
		item.commands_hash = Commands_Hash(value.commands)
	case .Transform, .Stroke_Settings:
	}

	return true
}

@(private)
svg_patch_paint_overrides :: proc(
	roots: []Svg_Draw_Node,
	definition_overrides: map[[2]u32]Svg_Override_Value,
) -> bool {
	for i in 0 ..< len(roots) {
		if !svg_patch_paint_node(&roots[i], definition_overrides) {

			return false
		}
	}

	return true
}

@(private)
svg_patch_paint_node :: proc(node: ^Svg_Draw_Node, definition_overrides: map[[2]u32]Svg_Override_Value) -> bool {
	switch node.kind {
	case .Path:
		index := node.item.element_index
		for property in Svg_Override_Property {
			if value, found := definition_overrides[[2]u32{index, u32(property)}]; found {
				if !svg_apply_definition_paint_override(&node.item, property, value) {

					return false
				}
			}
		}
	case .Group, .Clip, .Mask:
		for i in 0 ..< len(node.children) {
			if !svg_patch_paint_node(&node.children[i], definition_overrides) {

				return false
			}
		}

		for i in 0 ..< len(node.clip_nodes) {
			if !svg_patch_paint_node(&node.clip_nodes[i], definition_overrides) {

				return false
			}
		}

		for i in 0 ..< len(node.mask_nodes) {
			if !svg_patch_paint_node(&node.mask_nodes[i], definition_overrides) {

				return false
			}
		}
	}

	return true
}

// Reuses the compiled cascade and clones independently owned leaf patches.
@(private)
svg_prepare_patched_instance :: proc(
	asset: ^Svg_Asset,
	definition_overrides: map[[2]u32]Svg_Override_Value,
	budget: Svg_Instance_Budget,
	allocator := context.allocator,
	usage: ^Svg_Instance_Usage = nil,
) -> (instance: ^Svg_Instance, result: Svg_Load_Result) {
	result.allocator = allocator
	result.diagnostics = make([dynamic]Svg_Diagnostic, allocator)
	if usage != nil {
		usage^ = {}
	}

	if asset == nil {
		svg_push(&result, .Invalid_Handle, "nil SVG asset", 0, 0)

		return
	}

	sync.atomic_add(&asset.owner.refs, 1)
	retained := false
	defer if !retained {
		svg_revision_release(asset.owner)
	}

	owner_bytes := size_of(Svg_Instance) + size_of(Scratch_Arena)
	allowance := min(budget.decoded_bytes, asset.limits.max_decoded_bytes)
	if allowance <= owner_bytes {
		svg_push(&result, .Limit_Exceeded, "instance owner bytes exhausted", 0, 0)

		return
	}

	arena, err := new(Scratch_Arena, allocator)
	if err != nil {
		svg_push(&result, .Allocation_Failed, "cannot allocate SVG instance owner", 0, 0)

		return
	}

	arena^ = {backing = allocator, limit = allowance - owner_bytes}
	success := false
	defer if !success {
		scratch_arena_destroy(arena)
		free(arena, allocator)
	}

	context.allocator = {procedure = scratch_allocator_proc, data = arena}
	context.temp_allocator = context.allocator
	roots := make([dynamic]Svg_Draw_Node, 0, context.allocator)
	if !svg_clone_draw_nodes(asset.roots, &roots) || arena.failed {
		svg_load_failure(&result, arena, allocator)

		return
	}

	if len(definition_overrides) > 0 && !svg_patch_paint_overrides(roots[:], definition_overrides) {
		if arena.failed { svg_load_failure(&result, arena, allocator) } else { svg_push(&result, .Invalid_Value, "paint override patch failed", 0, 0) }

		return
	}
	if arena.failed { svg_load_failure(&result, arena, allocator); return }
	commands := 0
	for &root in roots {
		if root.kind == .Path {
			commands += len(root.item.commands)
			if commands > asset.limits.max_path_commands {
				svg_push(&result, .Limit_Exceeded, "expanded path command budget exceeded", 0, 0)
				return
			}
		}
	}

	nodes := svg_count_path_leaves(roots[:])
	if nodes > budget.nodes {
		svg_push(&result, .Limit_Exceeded, "paint instance node budget exceeded", 0, 0)

		return
	}

	instance, err = new(Svg_Instance, allocator)
	if err != nil {
		svg_push(&result, .Allocation_Failed, "cannot allocate SVG instance", 0, 0)

		return
	}

	instance^ = {
		roots = roots[:],
		width = asset.width,
		height = asset.height,
		usage = {nodes, 0, arena.reserved + owner_bytes},
		arena = arena,
		allocator = allocator,
		revision_owner = asset.owner,
	}
	if usage != nil {
		usage^ = instance.usage
	}

	retained = true
	success, result.ok = true, true

	return
}
