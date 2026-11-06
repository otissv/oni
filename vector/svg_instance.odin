package oni_vector

import "core:mem"
import "core:slice"
import "core:fmt"
import "core:sync"
import "core:hash/xxhash"

// Occurrences are value handles: no borrowed chain survives lookup or recording.
// A use site itself belongs to the preceding chain; its target appends that site.
Svg_Occurrence_Handle :: struct {
	element: Svg_Element_Handle,
	chain: u32,
	depth: int,
}
@(private)
Svg_Use_Chain :: struct {
	sites: [128]u32,
	depth: int,
	index: u32,
	next: ^Svg_Use_Chain,
}
@(private)
Svg_Occurrence_Key :: struct {
	element: Svg_Element_Handle,
	use_chain: [128]u32,
	depth: int,
}
Svg_Override_Property :: enum { Transform, Fill, Stroke, Color, Opacity, Fill_Opacity, Stroke_Opacity, Stroke_Settings, Path }
Svg_Override :: struct {
	target: Svg_Element_Handle,
	occurrence: Svg_Occurrence_Handle,
	property: Svg_Override_Property,
	// Only the payload selected by property is live.
	using value: Svg_Override_Value,
}
@(private)
Svg_Override_Value :: struct #raw_union {
	transform: Affine,
	paint: Paint,
	color: Color,
	opacity: f64,
	stroke: Stroke,
	commands: []Command,
}

Svg_Instance_Budget :: struct { nodes, selectors, decoded_bytes: int }
DEFAULT_SVG_INSTANCE_BUDGET :: Svg_Instance_Budget{200_000, 16_000_000, 64 * 1024 * 1024}
Svg_Instance_Usage :: struct { nodes, selectors, decoded_bytes: int }
Svg_Instance :: struct {
	roots: []Svg_Draw_Node,
	width, height: f64,
	usage: Svg_Instance_Usage,
	arena: Scratch_Arena,
	allocator: mem.Allocator,
	revision_owner: ^Svg_Revision_Owner,
	reusable_storage: bool,
}
@(private)
Svg_Override_Key :: struct {
	occurrence: Svg_Occurrence_Key,
	property: Svg_Override_Property,
	definition: bool,
}
@(private)
svg_element_node :: proc(asset: ^Svg_Asset, handle: Svg_Element_Handle) -> ^Xml_Node {
	if asset == nil || handle.revision != asset.revision || handle.index == 0 || u64(handle.index) > u64(len(asset.elements)) { return nil }
	return asset.elements[handle.index - 1]
}
@(private)
svg_visual_element :: proc(node: ^Xml_Node) -> bool {
	return node != nil && (svg_is_shape_element(node.name) || node.name == "g" || node.name == "svg" || node.name == "symbol" || node.name == "use" || node.name == "clipPath" || node.name == "mask")
}
@(private)
svg_occurrence_contains :: proc(asset: ^Svg_Asset, boundary, target: ^Xml_Node) -> bool {
	for node := target; node != nil; node = asset.parents[node] {
		if node == boundary { return true }
		if !svg_visual_element(node) || node.name == "symbol" || node.name == "clipPath" || node.name == "mask" { return false }
	}
	return false
}
// Addresses a structural occurrence independently of visibility or instance size.
Svg_Asset_Lookup_Occurrence :: proc(asset: ^Svg_Asset, use_sites: []Svg_Element_Handle, terminal: Svg_Element_Handle) -> (Svg_Occurrence_Handle, bool) {
	if asset == nil || len(use_sites) > 128 || len(use_sites) > asset.limits.max_reference_depth { return {}, false }
	terminal_node := svg_element_node(asset, terminal)
	if !svg_visual_element(terminal_node) { return {}, false }
	result := Svg_Occurrence_Handle{element = terminal, depth = len(use_sites)}
	chain: [128]u32
	boundary := asset.source
	for site, i in use_sites {
		node := svg_element_node(asset, site)
		if node == nil || node.name != "use" || !svg_occurrence_contains(asset, boundary, node) { return {}, false }
		id, valid := svg_attr_href(node)
		if !valid { return {}, false }
		boundary = asset.ids[id]
		chain[i] = site.index
	}
	if !svg_occurrence_contains(asset, boundary, terminal_node) { return {}, false }
	if len(use_sites) == 0 { return result, true }
	index, interned := svg_intern_use_chain(asset, chain, len(use_sites))
	if !interned { return {}, false }
	result.chain = index
	return result, true
}
@(private)
svg_intern_use_chain :: proc(asset: ^Svg_Asset, #by_ptr sites: [128]u32, depth: int) -> (u32, bool) {
	owner := asset.owner
	sync.mutex_lock(&owner.occurrence_mutex)
	defer sync.mutex_unlock(&owner.occurrence_mutex)
	key := sites
	hash := transmute([2]u64)xxhash.XXH3_128_default(mem.slice_to_bytes(key[:depth]))
	for chain := owner.occurrence_heads[hash]; chain != nil; chain = chain.next {
		if chain.depth == depth && chain.sites == sites { return chain.index, true }
	}
	if owner.arena.failed || len(owner.occurrence_chains) >= asset.limits.max_elements { return 0, false }
	context.allocator = {procedure = scratch_allocator_proc, data = owner.arena}
	if reserve(&owner.occurrence_chains, len(owner.occurrence_chains) + 1) != nil ||
	   reserve(&owner.occurrence_heads, len(owner.occurrence_heads) + 1) != nil { return 0, false }
	chain, err := new(Svg_Use_Chain)
	if err != nil { return 0, false }
	chain^ = {sites = sites, depth = depth, index = u32(len(owner.occurrence_chains) + 1), next = owner.occurrence_heads[hash]}
	if _, append_error := append(&owner.occurrence_chains, chain); append_error != nil { return 0, false }
	owner.occurrence_heads[hash] = chain
	return chain.index, true
}

@(private)
svg_resolve_use_chain :: proc(asset: ^Svg_Asset, occurrence: Svg_Occurrence_Handle) -> ([128]u32, bool) {
	if occurrence.depth == 0 { return {}, occurrence.chain == 0 }
	if occurrence.depth < 0 || occurrence.depth > 128 || occurrence.chain == 0 { return {}, false }
	owner := asset.owner
	sync.mutex_lock(&owner.occurrence_mutex)
	defer sync.mutex_unlock(&owner.occurrence_mutex)
	if u64(occurrence.chain) > u64(len(owner.occurrence_chains)) { return {}, false }
	chain := owner.occurrence_chains[occurrence.chain - 1]
	return chain.sites, chain.depth == occurrence.depth
}

@(private)
svg_occurrence_valid :: proc(asset: ^Svg_Asset, occurrence: Svg_Occurrence_Handle) -> bool {
	if occurrence.depth < 0 || occurrence.depth > 128 { return false }
	chain, found := svg_resolve_use_chain(asset, occurrence)
	if !found { return false }
	sites: [128]Svg_Element_Handle
	for i in 0 ..< occurrence.depth { sites[i] = {revision = occurrence.element.revision, index = chain[i]} }
	canonical, valid := Svg_Asset_Lookup_Occurrence(asset, sites[:occurrence.depth], occurrence.element)
	return valid && canonical == occurrence
}
@(private)
svg_override_key :: proc(asset: ^Svg_Asset, #by_ptr override: Svg_Override) -> Svg_Override_Key {
	if override.target != {} { return {occurrence = {element = override.target}, property = override.property, definition = true} }
	chain, _ := svg_resolve_use_chain(asset, override.occurrence)
	return {occurrence = {element = override.occurrence.element, depth = override.occurrence.depth, use_chain = chain}, property = override.property}
}
@(private)
svg_find_override :: proc(ctx: ^Svg_Build_Ctx, node: ^Xml_Node, property: Svg_Override_Property) -> (Svg_Override_Value, bool) {
	index := ctx.element_indices[node]
	if len(ctx.overrides) > 0 {
		key := Svg_Override_Key{occurrence = {element = {index = index}, use_chain = ctx.use_chain, depth = ctx.use_depth}, property = property}
		if value, found := ctx.overrides[key]; found { return value, true }
	}
	return ctx.definition_overrides[[2]u32{index, u32(property)}]
}
@(private)
svg_apply_overrides :: proc(ctx: ^Svg_Build_Ctx, node: ^Xml_Node, style: ^Computed_Style) -> bool {
	for property in Svg_Override_Property {
		value, found := svg_find_override(ctx, node, property)
		if !found { continue }
		switch property {
		case .Transform: style.transform = value.transform
		case .Fill: style.fill, style.fill_value = value.paint, ""
		case .Stroke: style.stroke, style.stroke_value = value.paint, ""
		case .Color: style.color = value.color
		case .Opacity: style.opacity = value.opacity
		case .Fill_Opacity: style.fill_opacity = value.opacity
		case .Stroke_Opacity: style.stroke_opacity = value.opacity
		case .Stroke_Settings:
			style.stroke_width, style.stroke_cap, style.stroke_join = value.stroke.width, value.stroke.cap, value.stroke.join
			style.stroke_miter, style.dash, style.dash_offset = value.stroke.miter_limit, value.stroke.dash, value.stroke.dash_offset
			style.path_length, style.non_scaling = value.stroke.path_length, value.stroke.non_scaling
		case .Path:
		}
	}
	return !ctx.arena.failed
}
@(private)
svg_validate_override :: proc(asset: ^Svg_Asset, value: ^Svg_Override, result: ^Svg_Load_Result) -> bool {
	handle := value.target
	if handle == {} { handle = value.occurrence.element }
	node := svg_element_node(asset, handle)
	if !svg_visual_element(node) || value.target != {} && value.occurrence != {} || value.target == {} && !svg_occurrence_valid(asset, value.occurrence) {
		svg_push(result, .Invalid_Handle, "invalid or stale SVG override target", 0, 0)
		return false
	}
	valid := true
	switch value.property {
	case .Transform: for component in value.transform { valid = valid && finite(component) }
	case .Fill, .Stroke: valid = Validate_Paint(value.paint) == .None
	case .Color:
	case .Opacity, .Fill_Opacity, .Stroke_Opacity: valid = finite(value.opacity) && value.opacity >= 0 && value.opacity <= 1
	case .Stroke_Settings: valid = svg_is_shape_element(node.name) && Validate_Stroke(value.stroke) == .None && value.stroke.cap >= .Butt && value.stroke.cap <= .Square && value.stroke.join >= .Miter && value.stroke.join <= .Bevel
	case .Path: valid = svg_is_shape_element(node.name) && Validate_Commands(value.commands) == .None
	case: valid = false
	}
	if !valid { svg_push(result, .Invalid_Value, "invalid SVG override value or property for element", node.line, node.column, node.name, fmt.tprintf("%v", value.property)) }
	return valid
}

@(private)
svg_compiled_override_payload_valid :: #force_inline proc(value: ^Svg_Override) -> bool {
	switch value.property {
	case .Transform:
		for component in value.transform { if !finite(component) { return false } }
		return true
	case .Fill, .Stroke: return Validate_Paint(value.paint) == .None
	case .Opacity, .Fill_Opacity, .Stroke_Opacity: return finite(value.opacity) && value.opacity >= 0 && value.opacity <= 1
	case .Path: return Validate_Commands(value.commands) == .None
	case .Color, .Stroke_Settings: return false
	}
	return false
}

@(private)
svg_prepare_leaf_patches :: proc(
	asset: ^Svg_Asset,
	overrides: []Svg_Override,
	budget: Svg_Instance_Budget,
	allocator: mem.Allocator,
	usage: ^Svg_Instance_Usage,
	result: ^Svg_Load_Result,
) -> (^Svg_Instance, bool) {
	// Small leaf patches need no temporary hash table. Bound the linear scan;
	// large override sets retain the indexed path.
	definition_overrides: map[[2]u32]Svg_Override_Value
	if len(overrides) > 16 { definition_overrides = make(map[[2]u32]Svg_Override_Value, context.temp_allocator) }
	selector_ops := 0
	max_selector_ops := min(asset.limits.max_selector_ops, budget.selectors)
	for &override, i in overrides {
		depth := override.target == {} ? override.occurrence.depth : 0
		if depth < 0 || depth > 128 {
			svg_push(result, .Invalid_Handle, "invalid occurrence depth", 0, 0)

			return nil, false
		}
		work := (depth + 1) * (asset.limits.max_xml_depth + 1)
		payload := 0
		#partial switch override.property {
		case .Path: payload = len(override.commands)
		case .Stroke_Settings: payload = len(override.stroke.dash)
		case .Fill, .Stroke:
			if override.paint.kind == .Linear_Gradient { payload = len(override.paint.linear.stops) }
			if override.paint.kind == .Radial_Gradient { payload = len(override.paint.radial.stops) }
		}
		remaining := max_selector_ops - selector_ops
		if work > remaining || payload > remaining - work {
			svg_push(result, .Limit_Exceeded, "SVG override validation budget exceeded", 0, 0)

			return nil, false
		}
		selector_ops += work + payload
		// Target identity and element compatibility were checked by the compiled
		// patch classifier. Preserve detailed diagnostics on rejected payloads.
		if !svg_compiled_override_payload_valid(&override) {
			svg_validate_override(asset, &override, result)

			return nil, false
		}
		definition_key := [2]u32{override.target.index, u32(override.property)}
		if override.target == {} {
			svg_push(result, .Invalid_Handle, "compiled patches require definition targets", 0, 0)

			return nil, false
		}

		duplicate := false
		if len(overrides) > 16 {
			duplicate = definition_key in definition_overrides
		} else {
			for &previous in overrides[:i] {
				if previous.target == override.target && previous.property == override.property { duplicate = true; break }
			}
		}
		if duplicate {
			svg_push(result, .Duplicate_Override, "duplicate SVG override target/property", 0, 0)

			return nil, false
		}

		// Borrow caller paints; svg_prepare_patched_instance clones into the instance arena.
		if len(overrides) > 16 { definition_overrides[definition_key] = override.value }
	}

	instance, fast := svg_prepare_patched_instance(asset, definition_overrides, overrides, budget, allocator, usage)
	result^ = fast

	return instance, fast.ok
}

// Compiles an immutable instance, pinning the exact source revision for shared
// parsed geometry. Destroy it explicitly even when its storage uses an arena.
Svg_Prepare_Instance :: proc(asset: ^Svg_Asset, overrides: []Svg_Override = nil, budget := DEFAULT_SVG_INSTANCE_BUDGET, allocator := context.allocator, usage: ^Svg_Instance_Usage = nil) -> (instance: ^Svg_Instance, result: Svg_Load_Result) {
	result.allocator = allocator
	result.diagnostics = make([dynamic]Svg_Diagnostic, allocator)
	if usage != nil {
		usage^ = {}
	}

	if asset == nil {
		svg_push(&result, .Invalid_Handle, "nil SVG asset", 0, 0)

		return
	}

	if budget.nodes <= 0 || budget.selectors <= 0 || budget.decoded_bytes <= 0 || len(overrides) > asset.limits.max_elements {
		svg_push(&result, .Limit_Exceeded, fmt.tprintf("SVG instance requires positive allowances; remaining nodes %d, selector/validation operations %d, decoded bytes %d; overrides consumed %d, allowed %d", budget.nodes, budget.selectors, budget.decoded_bytes, len(overrides), asset.limits.max_elements), 0, 0)

		return
	}

	owner_bytes := size_of(Svg_Instance)
	allowance := min(budget.decoded_bytes, asset.limits.max_decoded_bytes)
	if allowance <= owner_bytes {
		svg_push(&result, .Limit_Exceeded, fmt.tprintf("instance owner bytes required %d, allowed %d", owner_bytes, allowance), 0, 0)

		return
	}

	// Leaf patches retain the compiled cascade and share immutable source geometry.
	if len(overrides) == 0 || svg_overrides_can_patch_compiled_roots(asset, overrides) {
		Destroy_Svg_Load_Result(&result)
		paint_instance, ok := svg_prepare_leaf_patches(asset, overrides, budget, allocator, usage, &result)
		if !ok && paint_instance != nil {
			Destroy_Svg_Instance(paint_instance)
			paint_instance = nil
		}

		return paint_instance, result
	}

	sync.atomic_add(&asset.owner.refs, 1)
	retained := false
	defer if !retained {
		svg_revision_release(asset.owner)
	}

	arena := Scratch_Arena{backing = allocator, limit = allowance}
	success := false
	defer if !success { scratch_arena_destroy(&arena) }
	context.allocator = {procedure = scratch_allocator_proc, data = &arena}
	context.temp_allocator = context.allocator
	ctx := Svg_Build_Ctx{result = &result, arena = &arena, limits = asset.limits, viewport = {asset.width, asset.height}, ids = asset.ids, parents = asset.parents, css = asset.css, element_indices = asset.element_indices, max_compile_nodes = budget.nodes}
	ctx.geometry = asset.geometry
	ctx.cascade_cache = asset.cascade_cache
	ctx.limits.max_selector_ops = min(ctx.limits.max_selector_ops, budget.selectors)
	defer if usage != nil { usage^ = {ctx.expanded_nodes, ctx.selector_ops, arena.reserved} }
	for &override in overrides {
		depth := override.target == {} ? override.occurrence.depth : 0
		if depth < 0 || depth > 128 { svg_push(&result, .Invalid_Handle, "invalid occurrence depth", 0, 0); return }
		work := (depth + 1) * (asset.limits.max_xml_depth + 1)
		payload := 0
		#partial switch override.property {
		case .Path: payload = len(override.commands)
		case .Stroke_Settings: payload = len(override.stroke.dash)
		case .Fill, .Stroke:
			if override.paint.kind == .Linear_Gradient { payload = len(override.paint.linear.stops) }
			if override.paint.kind == .Radial_Gradient { payload = len(override.paint.radial.stops) }
		}
		remaining := ctx.limits.max_selector_ops - ctx.selector_ops
		if work > remaining || payload > remaining - work { svg_push(&result, .Limit_Exceeded, fmt.tprintf("SVG override validation requires %d address and %d payload operations with %d remaining of %d allowed", work, payload, remaining, ctx.limits.max_selector_ops), 0, 0); return }
		work += payload
		ctx.selector_ops += work
		if !svg_validate_override(asset, &override, &result) { return }
		definition := override.target != {}
		key: Svg_Override_Key
		if !definition {
			key = svg_override_key(asset, override)
			key.occurrence.element.revision = 0
		}
		definition_key := [2]u32{override.target.index, u32(override.property)}
		duplicate := definition ? definition_key in ctx.definition_overrides : key in ctx.overrides
		if duplicate {
			handle := override.target
			if handle == {} { handle = override.occurrence.element }
			node := svg_element_node(asset, handle)
			svg_push(&result, .Duplicate_Override, "duplicate SVG override target/property", node.line, node.column, node.name, fmt.tprintf("%v", override.property))
			return
		}
		copy := override.value
		if override.property == .Fill || override.property == .Stroke {
			copy.paint, _ = Clone_Paint(override.paint)
		}
		if override.property == .Stroke_Settings { copy.stroke.dash = slice.clone(override.stroke.dash) }
		if override.property == .Path { copy.commands = slice.clone(override.commands) }
		if definition { ctx.definition_overrides[definition_key] = copy } else { ctx.overrides[key] = copy }
		if arena.failed { svg_load_failure(&result, &arena, allocator); return }
	}
	if !svg_compile_node(&ctx, asset.source, Default_Computed_Style(), IDENTITY) || arena.failed { svg_load_failure(&result, &arena, allocator); return }
	err: mem.Allocator_Error
	instance, err = new(Svg_Instance)
	if err != nil { svg_push(&result, .Allocation_Failed, "cannot allocate SVG instance", 0, 0); return }
	instance^ = {roots = ctx.roots[:], width = asset.width, height = asset.height, usage = {ctx.expanded_nodes, ctx.selector_ops, arena.reserved}, arena = arena, allocator = allocator}
	instance.revision_owner = asset.owner
	retained = true
	success, result.ok = true, true

	return
}
Destroy_Svg_Instance :: proc(instance: ^Svg_Instance) {
	if instance == nil { return }
	owner := instance.revision_owner
	arena := instance.arena
	// Keep at most one small allocation per revision. A custom instance
	// allocator never leaves storage behind in an unrelated owner.
	if instance.reusable_storage && arena.block != nil && arena.block.next == nil && arena.block.capacity <= 64 * 1024 {
		_, retained := sync.atomic_compare_exchange_strong(&owner.instance_block, nil, arena.block)
		if retained { arena.block = nil }
	}
	scratch_arena_destroy(&arena)
	svg_revision_release(owner)
}
