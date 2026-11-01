package oni_vector

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sync"

Svg_Element_Handle :: struct { revision, index: u32 }
Svg_Path_Item :: struct {
	commands: []Command,
	transform: Affine,
	fill, stroke: Paint,
	fill_rule: Fill_Rule,
	opacity, fill_opacity, stroke_opacity: f64,
	stroke_settings: Stroke,
	draw_fill, draw_stroke: bool,
	paint_order: Svg_Paint_Order,
}
Svg_Asset :: struct {
	revision: u32,
	width, height: f64,
	view_box: [4]f64,
	roots: []Svg_Draw_Node,
	id_to_handle: map[string]Svg_Element_Handle,
	allocator: mem.Allocator,
	arena: ^Scratch_Arena,
	source: ^Xml_Node,
	elements: []^Xml_Node,
	element_indices: map[^Xml_Node]u32,
	parents: map[^Xml_Node]^Xml_Node,
	ids: map[string]^Xml_Node,
	css: Css_Table,
	limits: Svg_Limits,
}
Svg_Load_Options :: struct { limits: Svg_Limits }
@(private)
svg_global_revision: u32
@(private)
svg_push :: proc(result: ^Svg_Load_Result, category: Svg_Diagnostic_Category, message: string, line, column: int, element := "", property := "") {
	allocator := result.allocator
	if allocator.procedure == nil { allocator = context.allocator; result.allocator = allocator }
	result.ok = false
	if result.error == .None { result.error = category }
	diag := Svg_Diagnostic{category = category, message = strings.clone(message, allocator), line = line, column = column, element = strings.clone(element, allocator), property = strings.clone(property, allocator)}
	if _, err := append(&result.diagnostics, diag); err != nil {
		delete(diag.message, allocator); delete(diag.element, allocator); delete(diag.property, allocator)
	}
}
@(private)
svg_attr :: proc(node: ^Xml_Node, name: string) -> (string, bool) {
	for attr in node.attrs { if attr.name == name && attr.namespace == "" { return attr.value, true } }
	return "", false
}
@(private)
svg_attr_href :: proc(node: ^Xml_Node) -> (string, bool) {
	value, found := svg_attr(node, "href")
	if !found { for attr in node.attrs { if attr.name == "href" && attr.namespace == XLINK_NS { value, found = attr.value, true; break } } }
	if !found || len(value) < 2 || value[0] != '#' || strings.contains_any(value, " \t\r\n") { return "", false }
	return value[1:], true
}
@(private)
Svg_Build_Ctx :: struct {
	result: ^Svg_Load_Result,
	limits: Svg_Limits,
	arena: ^Scratch_Arena,
	roots: [dynamic]Svg_Draw_Node,
	ids: map[string]^Xml_Node,
	parents: map[^Xml_Node]^Xml_Node,
	references: map[^Xml_Node][dynamic]^Xml_Node,
	graph_state: map[^Xml_Node]u8,
	graph_height: map[^Xml_Node]int,
	ref_depth, ref_count, expanded_nodes, path_commands, emitted_commands: int,
	viewport: [2]f64,
	css: Css_Table,
	selector_ops: int,
	clip_mode: bool,
	definition_target, instance_target: ^Xml_Node,
	elements: [dynamic]^Xml_Node,
	element_indices: map[^Xml_Node]u32,
	overrides: map[Svg_Override_Key]Svg_Override,
	use_chain: [128]u32,
	use_depth: int,
	max_compile_nodes: int,
}
@(private)
svg_find_def :: proc(ctx: ^Svg_Build_Ctx, id: string) -> ^Xml_Node { return ctx.ids[id] }
@(private)
svg_index_tree :: proc(node, parent: ^Xml_Node, ctx: ^Svg_Build_Ctx) -> bool {
	if node.kind != .Element || node.in_metadata { return true }
	if ctx.arena.failed { return false }
	ctx.parents[node] = parent
	append(&ctx.elements, node)
	ctx.element_indices[node] = u32(len(ctx.elements))
	if id, found := svg_attr(node, "id"); found {
		if id == "" || strings.contains_any(id, " \t\r\n") { svg_push(ctx.result, .Invalid_Value, "invalid id", node.line, node.column, node.name, "id"); return false }
		if id in ctx.ids { svg_push(ctx.result, .Duplicate_Id, "duplicate id", node.line, node.column, id); return false }
		ctx.ids[id] = node
	}
	for &child in node.children { if !svg_index_tree(&child, node, ctx) { return false } }
	return true
}
@(private)
svg_reference :: proc(ctx: ^Svg_Build_Ctx, node: ^Xml_Node, id, expected, property: string) -> bool {
	target, found := ctx.ids[id]
	if !found { svg_push(ctx.result, .Missing_Reference, fmt.tprintf("missing reference #%s", id), node.line, node.column, node.name, property); return false }
	valid := true
	switch expected {
	case "gradient": valid = target.name == "linearGradient" || target.name == "radialGradient"
	case "use": valid = svg_is_shape_element(target.name) || target.name == "g" || target.name == "svg" || target.name == "symbol" || target.name == "use"
	case: valid = target.name == expected
	}
	if !valid { svg_push(ctx.result, .Invalid_Reference, "reference has incompatible element type", node.line, node.column, node.name, property); return false }
	deps := ctx.references[node]
	for dependency in deps { if dependency == target { return true } }
	append(&deps, target)
	ctx.references[node] = deps
	return true
}
@(private)
svg_check_graph :: proc(ctx: ^Svg_Build_Ctx, node: ^Xml_Node, depth := 0) -> (height: int, ok: bool) {
	if node.kind != .Element || node.in_metadata { return 0, true }
	if depth > ctx.limits.max_xml_depth + ctx.limits.max_reference_depth { svg_push(ctx.result, .Limit_Exceeded, "reference graph depth exceeded", node.line, node.column, node.name); return 0, false }
	switch ctx.graph_state[node] {
	case 1: svg_push(ctx.result, .Reference_Cycle, "local reference cycle", node.line, node.column, node.name); return 0, false
	case 2: return ctx.graph_height[node], true
	}
	ctx.graph_state[node] = 1
	for &child in node.children {
		h, valid := svg_check_graph(ctx, &child, depth + 1)
		if !valid { return 0, false }
		height = max(height, h)
	}
	dependencies := ctx.references[node]
	for dependency in dependencies {
		h, valid := svg_check_graph(ctx, dependency, depth + 1)
		if !valid { return 0, false }
		height = max(height, h + 1)
	}
	if height > ctx.limits.max_reference_depth {
		svg_push(ctx.result, .Limit_Exceeded, fmt.tprintf("reference depth consumed %d, allowed %d", height, ctx.limits.max_reference_depth), node.line, node.column, node.name)
		return height, false
	}
	ctx.graph_height[node] = height
	ctx.graph_state[node] = 2
	return height, true
}
@(private)
svg_load_limits :: proc(options: Svg_Load_Options) -> Svg_Limits {
	limits := options.limits
	if limits == {} { return DEFAULT_SVG_LIMITS }
	return limits
}
Load_Svg_From_String :: proc(source: string, opts := Svg_Load_Options{}, allocator := context.allocator) -> (asset: ^Svg_Asset, result: Svg_Load_Result) {
	result.allocator = allocator
	result.diagnostics = make([dynamic]Svg_Diagnostic, allocator)
	limits := svg_load_limits(opts)
	if limits.max_xml_depth > 256 || limits.max_reference_depth > 128 {
		svg_push(&result, .Invalid_Value, "configured XML/reference depth exceeds safe ceilings 256/128", 1, 1)
		return nil, result
	}
	if limits.max_source_bytes < 0 || limits.max_decoded_bytes <= 0 || len(source) > limits.max_source_bytes {
		svg_push(&result, .Limit_Exceeded, fmt.tprintf("source bytes consumed %d, allowed %d; decoded allowance %d", len(source), limits.max_source_bytes, limits.max_decoded_bytes), 1, 1)
		return nil, result
	}
	arena, alloc_err := new(Scratch_Arena, allocator)
	if alloc_err != nil { svg_push(&result, .Allocation_Failed, "cannot allocate SVG owner", 1, 1); return nil, result }
	arena^ = {backing = allocator, limit = limits.max_decoded_bytes}
	success := false
	defer if !success { scratch_arena_destroy(arena); free(arena, allocator) }
	context.allocator = {procedure = scratch_allocator_proc, data = arena}
	context.temp_allocator = context.allocator
	ctx := Svg_Build_Ctx{result = &result, limits = limits, arena = arena, viewport = {300, 150}}
	parsed, valid := Parse_Xml_Document(source, limits, &result)
	if !valid || arena.failed {
		if arena.failed { svg_push(&result, .Limit_Exceeded, "decoded SVG allocation budget exhausted", 1, 1) }
		svg_load_failure(&result, arena, allocator); return nil, result
	}
	root := new(Xml_Node)
	if root == nil { svg_load_failure(&result, arena, allocator); return nil, result }
	root^ = parsed
	ctx.max_compile_nodes = limits.max_elements + limits.max_expanded_references
	if root.namespace != SVG_NS || root.name != "svg" { svg_push(&result, .Malformed_Xml, "root must be a namespace-qualified svg element", root.line, root.column); svg_load_failure(&result, arena, allocator); return nil, result }
	if !svg_index_tree(root, nil, &ctx) { svg_load_failure(&result, arena, allocator); return nil, result }
	css_order := 0
	if !svg_collect_stylesheets(root, &ctx, &css_order) || !svg_validate_tree(root, &ctx, Default_Computed_Style()) { svg_load_failure(&result, arena, allocator); return nil, result }
	if _, graph_valid := svg_check_graph(&ctx, root); !graph_valid { svg_load_failure(&result, arena, allocator); return nil, result }
	width, height, view_box, size_ok := svg_root_size(root)
	if !size_ok { svg_push(&result, .Invalid_Value, "invalid root viewport", root.line, root.column, "svg"); svg_load_failure(&result, arena, allocator); return nil, result }
	ctx.viewport = {width, height}
	if !svg_validate_gradients(&ctx, root) { svg_load_failure(&result, arena, allocator); return nil, result }
	if !svg_compile_node(&ctx, root, Default_Computed_Style(), IDENTITY) || arena.failed {
		if arena.failed { svg_push(&result, .Limit_Exceeded, fmt.tprintf("decoded bytes reserved %d, allowed %d", arena.reserved, arena.limit), 0, 0) }
		svg_load_failure(&result, arena, allocator); return nil, result
	}
	asset, alloc_err = new(Svg_Asset, allocator)
	if alloc_err != nil { svg_push(&result, .Allocation_Failed, "cannot allocate SVG asset", 0, 0); svg_load_failure(&result, arena, allocator); return nil, result }
	asset^ = {revision = sync.atomic_add(&svg_global_revision, 1) + 1, width = width, height = height, view_box = view_box, roots = ctx.roots[:], allocator = allocator, arena = arena}
	asset.source, asset.elements, asset.element_indices = root, ctx.elements[:], ctx.element_indices
	asset.parents, asset.ids, asset.css, asset.limits = ctx.parents, ctx.ids, ctx.css, limits
	for id, node in ctx.ids { asset.id_to_handle[id] = {revision = asset.revision, index = ctx.element_indices[node]} }
	if arena.failed { free(asset, allocator); asset = nil; svg_push(&result, .Limit_Exceeded, "decoded SVG allocation budget exhausted", 0, 0); svg_load_failure(&result, arena, allocator); return nil, result }
	success, result.ok = true, true
	return asset, result
}
Load_Svg_From_File :: proc(path: string, opts := Svg_Load_Options{}, allocator := context.allocator) -> (asset: ^Svg_Asset, result: Svg_Load_Result) {
	result.allocator = allocator
	limits := svg_load_limits(opts)
	file, err := os.open(path)
	if err != nil { svg_push(&result, .Malformed_Xml, fmt.tprintf("cannot read SVG %s", path), 0, 0); return nil, result }
	defer os.close(file)
	data := make([dynamic]u8, allocator)
	defer delete(data)
	buffer: [4096]u8
	for {
		n, read_err := os.read(file, buffer[:])
		if n > limits.max_source_bytes - len(data) { svg_push(&result, .Limit_Exceeded, fmt.tprintf("source bytes exceed allowed %d", limits.max_source_bytes), 0, 0); return nil, result }
		if _, alloc_err := append(&data, ..buffer[:n]); alloc_err != nil { svg_push(&result, .Allocation_Failed, "cannot allocate source buffer", 0, 0); return nil, result }
		if read_err == .EOF || n == 0 { break }
		if read_err != nil { svg_push(&result, .Malformed_Xml, "source read failed", 0, 0); return nil, result }
	}
	return Load_Svg_From_String(string(data[:]), opts, allocator)
}
Destroy_Svg_Asset :: proc(asset: ^Svg_Asset) {
	if asset == nil { return }
	allocator := asset.allocator
	scratch_arena_destroy(asset.arena)
	free(asset.arena, allocator)
	free(asset, allocator)
}
Svg_Asset_Intrinsic_Size :: proc(asset: ^Svg_Asset) -> (f64, f64) {
	if asset == nil { return 300, 150 }
	return asset.width, asset.height
}
Svg_Asset_Lookup :: proc(asset: ^Svg_Asset, id: string) -> (Svg_Element_Handle, bool) {
	if asset == nil { return {}, false }
	handle, found := asset.id_to_handle[id]
	return handle, found
}
Destroy_Svg_Load_Result :: proc(result: ^Svg_Load_Result) {
	if result == nil { return }
	allocator := result.allocator
	if allocator.procedure == nil { allocator = context.allocator }
	for diag in result.diagnostics { delete(diag.message, allocator); delete(diag.element, allocator); delete(diag.property, allocator) }
	delete(result.diagnostics)
	result^ = {}
}


@(private)
svg_has_href :: proc(node: ^Xml_Node) -> bool {
	for attr in node.attrs { if attr.name == "href" && (attr.namespace == "" || attr.namespace == SVG_NS || attr.namespace == XLINK_NS) { return true } }
	return false
}

@(private)
svg_load_failure :: proc(result: ^Svg_Load_Result, arena: ^Scratch_Arena, allocator: mem.Allocator) {
	if arena.failed {
		Destroy_Svg_Load_Result(result)
		result.allocator = allocator
		result.diagnostics = make([dynamic]Svg_Diagnostic, allocator)
		svg_push(result, arena.limit_exceeded ? .Limit_Exceeded : .Allocation_Failed, fmt.tprintf("decoded bytes requested %d, reserved %d, allowed %d", arena.requested, arena.reserved, arena.limit), 0, 0)
	} else if len(result.diagnostics) == 0 {
		svg_push(result, .Invalid_Value, "SVG load transaction failed", 0, 0)
	}
}
