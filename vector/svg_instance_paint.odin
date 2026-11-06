package oni_vector

import "core:sync"
import "core:mem"

// Upper bound for one independently owned clone of the immutable compiled tree.
// Geometry and stroke dashes stay pinned to the source revision.
@(private)
svg_instance_storage_bytes :: proc(nodes: []Svg_Draw_Node) -> int {
	bytes := len(nodes) * size_of(Svg_Draw_Node) + mem.DEFAULT_ALIGNMENT
	for &node in nodes {
		switch node.kind {
		case .Path:
		case .Group, .Clip, .Mask:
			bytes += svg_instance_storage_bytes(node.children)
			bytes += svg_instance_storage_bytes(node.clip_nodes)
			bytes += svg_instance_storage_bytes(node.mask_nodes)
		}
	}
	return bytes
}

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
svg_compiled_effect_target :: proc(nodes: []Svg_Draw_Node, index: u32, property: Svg_Override_Property, transform: Affine) -> (found, valid: bool) {
	valid = true
	for &node in nodes {
		if property == .Transform && node.kind == .Path && node.item.element_index == index {
			found = true
			valid &&= node.item.can_patch_transform
			combined := Affine_Compose(node.item.parent_transform, transform)
			for component in combined { valid &&= finite(component) }
		}
		if property == .Opacity && node.kind == .Group && node.opacity_element == index { found = true }
		for subtree in ([3][]Svg_Draw_Node{node.children, node.clip_nodes, node.mask_nodes}) {
			child_found, child_valid := svg_compiled_effect_target(subtree, index, property, transform)
			found ||= child_found
			valid &&= child_valid
		}
	}
	return
}

@(private)
svg_overrides_can_patch_compiled_roots :: proc(asset: ^Svg_Asset, overrides: []Svg_Override) -> bool {
	if len(asset.flat_patch_indices) > 0 {
		has_path, has_opacity := false, false
		for &override in overrides {
			index := override.target.index
			if override.target.revision != asset.revision || index == 0 || u64(index) >= u64(len(asset.flat_patch_indices)) ||
			   asset.flat_patch_indices[index] < 0 || override.occurrence != {} { return false }
			switch override.property {
			case .Fill, .Stroke, .Fill_Opacity, .Stroke_Opacity:
			case .Opacity: has_opacity = true
			case .Path:
				if len(override.commands) == 0 { return false }
				has_path = true
			case .Transform:
				if !asset.user_space_effects || !asset.roots[asset.flat_patch_indices[index]].item.can_patch_transform ||
				   override.transform[0] * override.transform[3] - override.transform[1] * override.transform[2] == 0 { return false }
				combined := Affine_Compose(asset.roots[asset.flat_patch_indices[index]].item.parent_transform, override.transform)
				for component in combined { if !finite(component) { return false } }
			case .Color, .Stroke_Settings: return false
			}
		}
		return !has_path || !has_opacity
	}
	has_path := false
	for &override in overrides {
		node := svg_element_node(asset, override.target)
		if node == nil { return false }
		if override.target == {} || override.occurrence != {} { return false }
		if override.property == .Transform || override.property == .Opacity && node.name == "g" {
			if override.property == .Transform && (!asset.user_space_effects || !svg_is_shape_element(node.name) ||
			   override.transform[0] * override.transform[3] - override.transform[1] * override.transform[2] == 0) { return false }
			transform := override.transform if override.property == .Transform else IDENTITY
			found, valid := svg_compiled_effect_target(asset.roots, override.target.index, override.property, transform)
			if !found || !valid { return false }
			continue
		}
		if !svg_is_shape_element(node.name) {
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
svg_clone_draw_nodes :: proc(nodes: []Svg_Draw_Node, out: ^[dynamic]Svg_Draw_Node) -> bool {
	first := len(out^)
	if non_zero_reserve(out, first + len(nodes)) != nil { return false }
	if _, err := non_zero_append(out, ..nodes); err != nil { return false }
	for &clone, i in out^[first:] {
		node := &nodes[i]
		switch node.kind {
		case .Path:
			// The revision pin owns immutable geometry, paints and stroke dashes.
		case .Group, .Clip, .Mask:
			if len(node.children) > 0 {
				children := make([dynamic]Svg_Draw_Node, 0, context.allocator)
				if !svg_clone_draw_nodes(node.children, &children) {

					return false
				}

				clone.children = children[:]
			}

			clone.clip_items = node.clip_items

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
	}

	return true
}

@(private)
svg_apply_definition_paint_override :: #force_inline proc(item: ^Svg_Path_Item, property: Svg_Override_Property, value: ^Svg_Override_Value) -> bool {
	switch property {
	case .Fill:
		if value.paint.kind == .Solid || value.paint.kind == .None || value.paint.kind == .Current_Color {
			item.fill.kind = value.paint.kind
			if value.paint.kind == .Solid { item.fill.solid = value.paint.solid }
			item.draw_fill = value.paint.kind != .None
			return true
		}
		paint, ok := svg_clone_paint(value.paint)
		if !ok {

			return false
		}

		item.fill = paint
		item.draw_fill = paint.kind != .None
	case .Stroke:
		if value.paint.kind == .Solid || value.paint.kind == .None || value.paint.kind == .Current_Color {
			item.stroke.kind = value.paint.kind
			if value.paint.kind == .Solid { item.stroke.solid = value.paint.solid }
			item.draw_stroke = value.paint.kind != .None && item.stroke_settings.width > 0
			return true
		}
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
		commands := make([dynamic]Command, context.allocator)
		if _, err := non_zero_append(&commands, ..value.commands); err != nil { return false }
		item.commands = commands[:]
		item.commands_hash = commands_owned_hash(item.commands, &item.commands_structure)
	case .Transform:
		item.transform = Affine_Compose(item.parent_transform, value.transform)
	case .Stroke_Settings:
	}

	return true
}

@(private)
svg_patch_paint_overrides :: proc(
	roots: []Svg_Draw_Node,
	definition_overrides: map[[2]u32]Svg_Override_Value,
	overrides: []Svg_Override,
) -> bool {
	for i in 0 ..< len(roots) {
		if !svg_patch_paint_node(&roots[i], definition_overrides, overrides) {

			return false
		}
	}

	return true
}

@(private)
svg_patch_paint_node :: proc(node: ^Svg_Draw_Node, definition_overrides: map[[2]u32]Svg_Override_Value, overrides: []Svg_Override) -> bool {
	switch node.kind {
	case .Path:
		index := node.item.element_index
		if len(overrides) <= 16 {
			for &override in overrides {
				if override.target.index == index && !svg_apply_definition_paint_override(&node.item, override.property, &override.value) { return false }
			}
			return true
		}
		for property in Svg_Override_Property {
			if value, found := definition_overrides[[2]u32{index, u32(property)}]; found {
				if !svg_apply_definition_paint_override(&node.item, property, &value) {

					return false
				}
			}
		}
	case .Group, .Clip, .Mask:
		if node.kind == .Group && node.opacity_element != 0 {
			if len(overrides) <= 16 {
				for &override in overrides {
					if override.target.index == node.opacity_element && override.property == .Opacity { node.opacity = override.opacity }
				}
			} else if value, found := definition_overrides[[2]u32{node.opacity_element, u32(Svg_Override_Property.Opacity)}]; found { node.opacity = value.opacity }
		}
		for i in 0 ..< len(node.children) {
			if !svg_patch_paint_node(&node.children[i], definition_overrides, overrides) {

				return false
			}
		}

		for i in 0 ..< len(node.clip_nodes) {
			if !svg_patch_paint_node(&node.clip_nodes[i], definition_overrides, overrides) {

				return false
			}
		}

		for i in 0 ..< len(node.mask_nodes) {
			if !svg_patch_paint_node(&node.mask_nodes[i], definition_overrides, overrides) {

				return false
			}
		}
	}

	return true
}

@(private)
svg_pack_flat_snapshot :: proc(asset: ^Svg_Asset, overrides: []Svg_Override, bytes: int) -> (instance: ^Svg_Instance, roots: []Svg_Draw_Node, ok: bool) {
	storage, err := mem.alloc_bytes_non_zeroed(bytes, max(align_of(Svg_Instance), align_of(Svg_Draw_Node), align_of(Command)))
	if err != nil { return }
	instance = cast(^Svg_Instance)raw_data(storage)
	root_offset := mem.align_forward_int(size_of(Svg_Instance), align_of(Svg_Draw_Node))
	roots = (cast([^]Svg_Draw_Node)rawptr(uintptr(raw_data(storage)) + uintptr(root_offset)))[:len(asset.roots)]
	copy(roots, asset.roots)
	command_offset := mem.align_forward_int(root_offset + len(roots) * size_of(Svg_Draw_Node), align_of(Command))
	for &override in overrides {
		index := asset.flat_patch_indices[override.target.index]
		if index < 0 { return }
		item := &roots[index].item
		if override.property != .Path {
			if !svg_apply_definition_paint_override(item, override.property, &override.value) { return }
			continue
		}
		commands := (cast([^]Command)rawptr(uintptr(raw_data(storage)) + uintptr(command_offset)))[:len(override.commands)]
		copy(commands, override.commands)
		command_offset += len(commands) * size_of(Command)
		item.commands = commands
		item.commands_hash = commands_owned_hash(commands, &item.commands_structure)
	}
	return instance, roots, true
}

// Reuses the compiled cascade and clones independently owned leaf patches.
@(private)
svg_prepare_patched_instance :: proc(
	asset: ^Svg_Asset,
	definition_overrides: map[[2]u32]Svg_Override_Value,
	overrides: []Svg_Override,
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

	owner_bytes := size_of(Svg_Instance)
	allowance := min(budget.decoded_bytes, asset.limits.max_decoded_bytes)
	if allowance <= owner_bytes {
		svg_push(&result, .Limit_Exceeded, "instance owner bytes exhausted", 0, 0)
		return
	}
	storage_bytes := asset.instance_storage_bytes + owner_bytes + size_of(Scratch_Block) + mem.DEFAULT_ALIGNMENT
	packed := len(asset.flat_patch_indices) > 0
	packed_bytes := mem.align_forward_int(owner_bytes, align_of(Svg_Draw_Node)) + len(asset.roots) * size_of(Svg_Draw_Node)
	packed_bytes = mem.align_forward_int(packed_bytes, align_of(Command))
	for &override in overrides {
		#partial switch override.property {
		case .Path:
			storage_bytes += len(override.commands) * size_of(Command) + mem.DEFAULT_ALIGNMENT
			packed_bytes += len(override.commands) * size_of(Command)
		case .Fill, .Stroke:
			packed &&= override.paint.kind != .Linear_Gradient && override.paint.kind != .Radial_Gradient
			if override.paint.kind == .Linear_Gradient { storage_bytes += len(override.paint.linear.stops) * size_of(Gradient_Stop) + mem.DEFAULT_ALIGNMENT }
			if override.paint.kind == .Radial_Gradient { storage_bytes += len(override.paint.radial.stops) * size_of(Gradient_Stop) + mem.DEFAULT_ALIGNMENT }
		}
	}
	arena := Scratch_Arena{backing = allocator, limit = allowance, minimum_block_size = min(storage_bytes, allowance)}
	reusable := allocator == asset.allocator
	if reusable {
		block := sync.atomic_exchange(&asset.owner.instance_block, nil)
		if block != nil {
			if block.capacity >= storage_bytes && block.capacity <= allowance {
				block.used = size_of(Scratch_Block)
				arena.block, arena.reserved = block, block.capacity
			} else { free(block, allocator) }
		}
	}
	success := false
	defer if !success {
		scratch_arena_destroy(&arena)
		instance = nil
	}
	context.allocator = {procedure = scratch_allocator_proc, data = &arena}
	context.temp_allocator = context.allocator
	roots: []Svg_Draw_Node
	patched := true
	if packed {
		instance, roots, patched = svg_pack_flat_snapshot(asset, overrides, packed_bytes)
		if instance == nil || arena.failed { svg_load_failure(&result, &arena, allocator); return }
	} else {
		cloned := make([dynamic]Svg_Draw_Node, 0, context.allocator)
		if !svg_clone_draw_nodes(asset.roots, &cloned) || arena.failed { svg_load_failure(&result, &arena, allocator); return }
		roots = cloned[:]
	}
	if !packed && len(asset.flat_patch_indices) > 0 {
		for &override in overrides {
			index := asset.flat_patch_indices[override.target.index]
			if index >= 0 && !svg_apply_definition_paint_override(&roots[index].item, override.property, &override.value) { patched = false; break }
		}
	} else if !packed && len(overrides) > 0 { patched = svg_patch_paint_overrides(roots, definition_overrides, overrides) }
	if !patched {
		if arena.failed { svg_load_failure(&result, &arena, allocator) } else { svg_push(&result, .Invalid_Value, "paint override patch failed", 0, 0) }

		return
	}
	if arena.failed { svg_load_failure(&result, &arena, allocator); return }
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

	nodes := asset.path_leaf_count
	if nodes > budget.nodes {
		svg_push(&result, .Limit_Exceeded, "paint instance node budget exceeded", 0, 0)

		return
	}

	if instance == nil {
		err: mem.Allocator_Error
		instance, err = new(Svg_Instance)
		if err != nil {
			svg_push(&result, .Allocation_Failed, "cannot allocate SVG instance", 0, 0)
			return
		}
	}

	instance^ = {
		roots = roots[:],
		width = asset.width,
		height = asset.height,
		usage = {nodes, 0, arena.reserved},
		arena = arena,
		allocator = allocator,
		revision_owner = asset.owner,
		reusable_storage = reusable,
	}
	if usage != nil {
		usage^ = instance.usage
	}

	retained = true
	success, result.ok = true, true

	return
}
