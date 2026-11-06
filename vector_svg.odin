package oni

import v "./vector"
import "core:hash"
import "core:mem"
import "core:strings"
import "core:fmt"
import "core:math"

Svg_Asset :: ^v.Svg_Asset
Svg_Load_Result :: v.Svg_Load_Result
Svg_Diagnostic :: v.Svg_Diagnostic
Svg_Diagnostic_Category :: v.Svg_Diagnostic_Category
Svg_Element_Handle :: v.Svg_Element_Handle
Svg_Occurrence_Handle :: v.Svg_Occurrence_Handle
Svg_Override :: v.Svg_Override
Svg_Override_Property :: v.Svg_Override_Property
Svg_Instance :: v.Svg_Instance
Svg_Limits :: v.Svg_Limits
Svg_Load_Options :: v.Svg_Load_Options
DEFAULT_SVG_LIMITS :: v.DEFAULT_SVG_LIMITS

load_svg_file :: proc(path: string, opts := Svg_Load_Options{}, allocator := context.allocator) -> (Svg_Asset, Svg_Load_Result) {
	return v.Load_Svg_From_File(path, opts, allocator)
}
load_svg_memory :: proc(source: string, opts := Svg_Load_Options{}, allocator := context.allocator) -> (Svg_Asset, Svg_Load_Result) {
	return v.Load_Svg_From_String(source, opts, allocator)
}
destroy_svg_asset :: proc(asset: Svg_Asset) { v.Destroy_Svg_Asset(asset) }
reload_svg_memory :: proc(asset: Svg_Asset, source: string, opts := Svg_Load_Options{}) -> Svg_Load_Result {
	return v.Reload_Svg_From_String(asset, source, opts)
}
reload_svg_file :: proc(asset: Svg_Asset, path: string, opts := Svg_Load_Options{}) -> Svg_Load_Result {
	return v.Reload_Svg_From_File(asset, path, opts)
}
destroy_svg_load_result :: proc(result: ^Svg_Load_Result) { v.Destroy_Svg_Load_Result(result) }
svg_intrinsic_size :: proc(asset: Svg_Asset) -> (f64, f64) { return v.Svg_Asset_Intrinsic_Size(asset) }
svg_lookup_element :: proc(asset: Svg_Asset, id: string) -> (Svg_Element_Handle, bool) { return v.Svg_Asset_Lookup(asset, id) }
Svg_Lookup_Occurrence :: v.Svg_Asset_Lookup_Occurrence
Destroy_Svg_Instance :: v.Destroy_Svg_Instance

// Produces an independent owner and charges compilation work to this frame.
// Callers destroy both returned owners. Layout snapshots use the registered
// Prepare_Svg_Frame_Instance path so cancellation also releases revision pins.
Prepare_Svg_Instance :: proc(asset: Svg_Asset, overrides: []Svg_Override = nil, allocator := context.allocator) -> (^Svg_Instance, Svg_Load_Result) {
	budget := v.DEFAULT_SVG_INSTANCE_BUDGET
	if state != nil {
		usage := vector_frame().svg_usage
		budget.nodes = min(budget.nodes, VECTOR_MAX_FRAME_NODES - usage.nodes)
		budget.selectors -= usage.selectors
		budget.decoded_bytes -= usage.decoded_bytes
	}
	usage: v.Svg_Instance_Usage
	instance, result := v.Svg_Prepare_Instance(asset, overrides, budget, allocator, &usage)
	if state != nil {
		vector_frame().svg_usage.nodes += usage.nodes
		vector_frame().svg_usage.selectors += usage.selectors
		vector_frame().svg_usage.decoded_bytes += usage.decoded_bytes
	}
	return instance, result
}

// Registers revision pins for release before the layout arena is reset, even
// when a frame is cancelled without running Draw.
Prepare_Svg_Frame_Instance :: proc(asset: Svg_Asset, overrides: []Svg_Override = nil, layout_key: u64 = 0, fit: u32 = 0) -> (^Svg_Instance, Svg_Load_Result) {
	if state == nil {

		return nil, {error = .Invalid_Handle}
	}

	if cached := vector_svg_layout_cache_get(layout_key, asset, fit, overrides); cached != nil {
		if _, err := append(&state.ui.layout.svg_instances, cached); err != nil {

			return nil, {error = .Allocation_Failed}
		}

		return cached, {ok = true}
	}

	// Cached snapshots outlive the layout arena; retain them on the heap.
	// Ephemeral (uncached) snapshots use the frame arena and die at reset.
	allocator := context.allocator if layout_key != 0 else layout_frame_allocator()
	instance, result := Prepare_Svg_Instance(asset, overrides, allocator)
	if instance != nil {
		if _, err := append(&state.ui.layout.svg_instances, instance); err != nil {
			Destroy_Svg_Instance(instance)
			Destroy_Svg_Load_Result(&result)

			return nil, {error = .Allocation_Failed, allocator = allocator}
		}

		if layout_key != 0 {
			vector_svg_layout_cache_store(layout_key, asset, fit, overrides, instance)
		}
	}

	return instance, result
}

@(private)
vector_svg_overrides_hash :: proc(asset: Svg_Asset, overrides: []Svg_Override) -> u64 {
	digest := u64(14695981039346656037)
	if asset != nil {
		revision := asset.revision
		digest = hash.fnv64a(([^]u8)(&revision)[:size_of(u32)], digest)
	}
	for &override in overrides {
		words := [7]u64{u64(override.target.index), u64(override.target.revision),
			u64(override.occurrence.element.index), u64(override.occurrence.element.revision),
			u64(override.occurrence.chain), u64(override.occurrence.depth), u64(override.property)}
		digest = hash.fnv64a(mem.slice_to_bytes(words[:]), digest)
		switch override.property {
		case .Transform: digest = hash.fnv64a(mem.slice_to_bytes(override.transform[:]), digest)
		case .Fill, .Stroke: digest = vector_svg_paint_hash(override.paint, digest)
		case .Color: digest = hash.fnv64a(mem.byte_slice(rawptr(&override.color), size_of(RGBA)), digest)
		case .Opacity, .Fill_Opacity, .Stroke_Opacity:
			digest = hash.fnv64a(mem.byte_slice(rawptr(&override.opacity), size_of(f64)), digest)
		case .Path:
			commands := v.Commands_Hash(override.commands)
			digest = hash.fnv64a(mem.slice_to_bytes(commands[:]), digest)
		case .Stroke_Settings:
			stroke := &override.stroke
			values := [8]u64{transmute(u64)stroke.width, u64(stroke.cap), u64(stroke.join),
				transmute(u64)stroke.miter_limit, transmute(u64)stroke.dash_offset,
				transmute(u64)stroke.path_length, u64(stroke.non_scaling), u64(len(stroke.dash))}
			digest = hash.fnv64a(mem.slice_to_bytes(values[:]), digest)
			digest = hash.fnv64a(mem.slice_to_bytes(stroke.dash), digest)
		}
	}

	return digest
}

@(private)
vector_svg_paint_hash :: proc(#by_ptr paint: Vector_Paint, digest: u64) -> u64 {
	digest := digest
	paint := paint
	kind := u64(paint.kind)
	digest = hash.fnv64a(mem.byte_slice(rawptr(&kind), size_of(u64)), digest)
	stops: []Vector_Gradient_Stop
	switch paint.kind {
	case .None, .Current_Color:
	case .Solid:
		digest = hash.fnv64a(mem.byte_slice(rawptr(&paint.solid), size_of(RGBA)), digest)
	case .Linear_Gradient:
		g := &paint.linear
		values := [7]u64{transmute(u64)g.x1, transmute(u64)g.y1, transmute(u64)g.x2, transmute(u64)g.y2,
			u64(g.units), u64(g.spread), u64(g.color_interpolation)}
		digest = hash.fnv64a(mem.slice_to_bytes(values[:]), digest)
		digest = hash.fnv64a(mem.slice_to_bytes(g.transform[:]), digest)
		stops = g.stops
	case .Radial_Gradient:
		g := &paint.radial
		values := [9]u64{transmute(u64)g.cx, transmute(u64)g.cy, transmute(u64)g.r,
			transmute(u64)g.fx, transmute(u64)g.fy, transmute(u64)g.fr,
			u64(g.units), u64(g.spread), u64(g.color_interpolation)}
		digest = hash.fnv64a(mem.slice_to_bytes(values[:]), digest)
		digest = hash.fnv64a(mem.slice_to_bytes(g.transform[:]), digest)
		stops = g.stops
	}
	for &stop in stops {
		digest = hash.fnv64a(mem.byte_slice(rawptr(&stop.offset), size_of(f64)), digest)
		digest = hash.fnv64a(mem.byte_slice(rawptr(&stop.color), size_of(RGBA)), digest)
	}
	return digest
}

@(private)
vector_svg_layout_cache_get :: proc(key: u64, asset: Svg_Asset, fit: u32, overrides: []Svg_Override) -> ^Svg_Instance {
	if state == nil || key == 0 || asset == nil {

		return nil
	}

	entry, found := state.vector.svg_layout_cache[key]
	if !found || entry.asset != asset || entry.revision != asset.revision || entry.fit != fit || entry.overrides_hash != vector_svg_overrides_hash(asset, overrides) {

		return nil
	}

	return entry.instance
}

@(private)
vector_svg_layout_cache_store :: proc(key: u64, asset: Svg_Asset, fit: u32, overrides: []Svg_Override, instance: ^Svg_Instance) {
	if state == nil || key == 0 || instance == nil {

		return
	}

	if old, found := state.vector.svg_layout_cache[key]; found && old.instance != instance {
		Destroy_Svg_Instance(old.instance)
	}

	state.vector.svg_layout_cache[key] = {
		asset = asset,
		revision = asset.revision,
		fit = fit,
		overrides_hash = vector_svg_overrides_hash(asset, overrides),
		instance = instance,
	}
}

// Cached layout instances survive the layout arena reset; transient pins do not.
@(private)
vector_svg_layout_frame_end :: proc() {
	if state == nil {

		return
	}

	layout := &state.ui.layout
	for instance in layout.svg_instances {
		cached := false
		for _, entry in state.vector.svg_layout_cache {
			if entry.instance == instance {
				cached = true

				break
			}
		}

		if !cached {
			Destroy_Svg_Instance(instance)
		}
	}

	clear(&layout.svg_instances)
}

@(private)
vector_svg_layout_cache_shutdown :: proc() {
	if state == nil {

		return
	}

	for _, entry in state.vector.svg_layout_cache {
		Destroy_Svg_Instance(entry.instance)
	}

	delete(state.vector.svg_layout_cache)
	state.vector.svg_layout_cache = nil
}

Svg_Result_Error :: proc(result: Svg_Load_Result) -> Vector_Error {
	#partial switch result.error {
	case .None: return .None
	case .Invalid_Handle: return .Invalid_Handle
	case .Allocation_Failed: return .Allocation_Failed
	case .Limit_Exceeded: return .Limit_Exceeded
	case .Rendering_Failed: return .GPU_Failed
	case: return .Invalid_Value
	}
}

@(private)
svg_draw_diagnostic :: proc(output: ^Svg_Load_Result, error: Vector_Error, property: string) -> Vector_Error {
	if output == nil || error == .None { return error }
	output.ok = false
	if output.error != .None { return error }
	#partial switch error {
	case .Invalid_Handle: output.error = .Invalid_Handle
	case .Limit_Exceeded: output.error = .Limit_Exceeded
	case .Allocation_Failed: output.error = .Allocation_Failed
	case .GPU_Failed: output.error = .Rendering_Failed
	case: output.error = .Invalid_Value
	}
	output.allocator = context.allocator
	output.diagnostics.allocator = context.allocator
	message := fmt.tprintf("SVG recording failed: %v", error)
	if error == .Limit_Exceeded && state != nil {
		f := vector_frame()
		message = fmt.tprintf("SVG limit exceeded: segments %d/%d, triangles %d/%d, edge pairs %d/%d, exact limb operations %d/%d, geometry cache bytes %d/%d, GPU bytes %d/%d; last build exact operations %d/%d", f.new_segments, VECTOR_MAX_NEW_SEGMENTS, f.new_triangles, VECTOR_MAX_NEW_TRIANGLES, f.pair_tests, VECTOR_MAX_FRAME_PAIR_TESTS, f.exact_ops, VECTOR_MAX_FRAME_EXACT_OPS, state.vector.path_cache_bytes, VECTOR_CPU_CACHE_BUDGET, state.vector.gpu.bytes, VECTOR_GPU_BUDGET, state.vector.last_build_usage.exact_ops, state.vector.last_build_limits.max_exact_ops)
	}
	diagnostic := Svg_Diagnostic{category = output.error, element = strings.clone("svg"), property = strings.clone(property), message = strings.clone(message)}
	if _, err := append(&output.diagnostics, diagnostic); err != nil {
		delete(diagnostic.element); delete(diagnostic.property); delete(diagnostic.message)
	}
	return error
}

draw_svg_asset :: proc(asset: Svg_Asset, transform := Vector_Identity, opacity := f32(1), overrides: []Svg_Override = nil, diagnostics: ^Svg_Load_Result = nil) -> Vector_Error {
	if diagnostics != nil {
		Destroy_Svg_Load_Result(diagnostics)
		diagnostics^ = {ok = true}
	}
	if asset == nil { return svg_draw_diagnostic(diagnostics, .Invalid_Handle, "asset") }
	if !(opacity >= 0 && opacity <= 1) { return svg_draw_diagnostic(diagnostics, .Invalid_Value, "opacity") }
	for component in transform { if !(abs(component) <= max(f64)) { return svg_draw_diagnostic(diagnostics, .Invalid_Value, "transform") } }
	if state == nil || ui_pass() != .Draw { return .None }
	if len(overrides) > 0 {
		instance, result := Prepare_Svg_Instance(asset, overrides)
		defer Destroy_Svg_Instance(instance)
		err := Svg_Result_Error(result)
		if diagnostics != nil { diagnostics^ = result } else { Destroy_Svg_Load_Result(&result) }
		if err != .None { return err }
		return svg_draw_diagnostic(diagnostics, Draw_Svg_Instance(instance, transform, opacity), "draw")
	}
	return svg_draw_diagnostic(diagnostics, draw_svg_roots(asset.roots, transform, opacity), "draw")
}

// Recording copies geometry and paints; the instance may be released on return.
Draw_Svg_Instance :: proc(instance: ^Svg_Instance, transform := Vector_Identity, opacity := f32(1)) -> Vector_Error {
	if instance == nil { return .Invalid_Handle }
	if !(opacity >= 0 && opacity <= 1) { return .Invalid_Value }
	for component in transform { if !(abs(component) <= max(f64)) { return .Invalid_Value } }
	if state == nil || ui_pass() != .Draw { return .None }
	return draw_svg_roots(instance.roots, transform, opacity)
}

@(private)
draw_svg_roots :: proc(roots: []v.Svg_Draw_Node, transform: Vector_Transform, opacity: f32) -> Vector_Error {
	flat_solid := len(roots) > 0
	for &root in roots {
		if root.kind != .Path || !root.item.draw_fill || root.item.draw_stroke || root.item.fill.kind != .Solid ||
		   root.item.transform != Vector_Identity { flat_solid = false; break }
	}
	if flat_solid { return draw_svg_flat_solid(roots, transform, opacity) }
	storage: [16]Vector_Path_Draw = ---
	path_count := v.svg_count_path_leaves(roots)
	items := mem.buffer_from_slice(storage[:])
	if path_count > len(storage) / 2 {
		items = make([dynamic]Vector_Path_Draw, 0, path_count * 2, context.temp_allocator)
	}
	if draw_svg_collect_paths(roots, transform, 1, &items) {
		if len(items) == 0 {

			return .None
		}

		for &item in items {
			item.opacity *= opacity
		}

		return Draw_Vector_Paths(items[:])
	}

	nodes := make([dynamic]Vector_Node, context.temp_allocator)
	if err := draw_svg_build_nodes(roots, transform, &nodes); err != .None { return err }

	return Draw_Vector_Scene({nodes = nodes[:], opacity = opacity})
}

// Returns false when clip/mask/opacity groups require full scene recording.
@(private)
draw_svg_collect_paths :: proc(
	nodes: []v.Svg_Draw_Node,
	root_transform: Vector_Transform,
	group_opacity: f32,
	out: ^[dynamic]Vector_Path_Draw,
) -> bool {
	for &node in nodes {
		switch node.kind {
		case .Path:
			item := &node.item
			if !item.draw_fill && !item.draw_stroke {

				continue
			}

			handle, err := vector_svg_path(item.commands, item.commands_hash, item.commands_structure)
			if err != .None {

				return false
			}

			transform := v.Affine_Compose(root_transform, item.transform)
			settings := Vector_Stroke{}
			if item.draw_stroke {
				settings, err = vector_stroke_from_cpu(item.stroke_settings)
				if err != .None {

					return false
				}
			}

			opacity := f32(node.opacity * f64(group_opacity))
			for pass in 0 ..< 2 {
				stroke_pass := (pass == 0) == (item.paint_order == .Stroke_Fill)
				if stroke_pass && !item.draw_stroke || !stroke_pass && !item.draw_fill { continue }
				index := len(out^)
				if resize(out, index + 1) != nil { return false }
				entry := &out^[index]
				entry.handle = handle
				entry.transform = transform
				entry.opacity = f32(item.stroke_opacity if stroke_pass else item.fill_opacity) * opacity
				paint := &item.fill
				if stroke_pass {
					paint = &item.stroke
					entry.op, entry.stroke = .Stroke, settings
				} else { entry.rule = item.fill_rule }
				if paint.kind == .Solid {
					entry.paint.kind, entry.paint.solid = .Solid, paint.solid
				} else { entry.paint = paint^ }
			}
		case .Group:
			if node.opacity != 1 {

				return false
			}

			if !draw_svg_collect_paths(node.children, root_transform, group_opacity * f32(node.opacity), out) {

				return false
			}
		case .Clip, .Mask:

			return false
		}
	}

	return true
}

@(private)
draw_svg_build_nodes :: proc(nodes: []v.Svg_Draw_Node, root_transform: Vector_Transform, out: ^[dynamic]Vector_Node) -> Vector_Error {
	for &node in nodes {
		switch node.kind {
		case .Path:
			item := &node.item
			if !item.draw_fill && !item.draw_stroke { continue }
			handle, err := vector_svg_path(item.commands, item.commands_hash, item.commands_structure)
			if err != .None { return err }

			transform := v.Affine_Compose(root_transform, item.transform)
			settings := Vector_Stroke{}
			if item.draw_stroke {
				settings, err = vector_stroke_from_cpu(item.stroke_settings)
				if err != .None {

					return err
				}
			}
			fill := Vector_Node{kind = .Path, opacity = 1, path = {handle = handle, paint = item.fill, transform = transform, rule = item.fill_rule, opacity = f32(item.fill_opacity)}}
			stroke := Vector_Node{kind = .Path, opacity = 1, path = {handle = handle, paint = item.stroke, transform = transform, opacity = f32(item.stroke_opacity), op = .Stroke, stroke = settings}}
			ordered := [2]Vector_Node{fill, stroke}
			enabled := [2]bool{item.draw_fill, item.draw_stroke}
			if item.paint_order == .Stroke_Fill { ordered = {stroke, fill}; enabled = {item.draw_stroke, item.draw_fill} }
			for entry, i in ordered {
				if enabled[i] {
					if _, allocation_error := append(out, entry); allocation_error != nil {

						return .Allocation_Failed
					}
				}
			}
		case .Group, .Clip, .Mask:
			children := make([dynamic]Vector_Node, context.temp_allocator)
			if err := draw_svg_build_nodes(node.children, root_transform, &children); err != .None { return err }
			if len(children) == 0 { continue }
			group := Vector_Node{kind = .Group, opacity = f32(node.opacity), children = children[:]}
			switch node.kind {
			case .Group:
			case .Clip:
				if clip, rectangular := draw_svg_rect_clip(node, root_transform); rectangular {
					group = {kind = .Clip, opacity = 1, clip = clip, children = children[:]}
					break
				}
				mesh, err := draw_svg_clip_geometry(node, root_transform)
				if err != .None { return err }
				if len(mesh.indices) == 0 { continue }
				group = {kind = .Clip, opacity = 1, mesh = mesh, children = children[:]}
			case .Mask:
				mask := make([dynamic]Vector_Node, context.temp_allocator)
				if err := draw_svg_build_nodes(node.mask_nodes, root_transform, &mask); err != .None { return err }
				group = {kind = .Mask, opacity = 1, mask_kind = node.mask_alpha ? .Alpha : .Luminance, children = children[:], mask = mask[:]}
			case .Path:
			}
			if _, allocation_error := append(out, group); allocation_error != nil { return .Allocation_Failed }
		}
	}
	return .None
}

// Integer device-space rectangles have the same coverage under scissoring and
// stencil clipping. Fractional or rotated edges retain the MSAA geometry path.
@(private)
draw_svg_rect_clip :: proc(#by_ptr node: v.Svg_Draw_Node, root_transform: Vector_Transform) -> (Rect, bool) {
	if len(node.clip_nodes) != 0 || len(node.clip_items) != 1 { return {}, false }
	item := &node.clip_items[0]
	transform := v.Affine_Compose(root_transform, item.transform)
	points: [5]Vec2
	count := 0
	closed := false
	for &command in item.commands {
		if closed { return {}, false }
		switch command.kind {
		case .Close: closed = true; continue
		case .Move: if count != 0 { return {}, false }
		case .Line:
		case .Arc: if command.radii != {} { return {}, false }
		case .Quadratic, .Cubic: return {}, false
		}
		point := v.Transform_Point(transform, command.points[0])
		logical := Vec2{f32(point.x), f32(point.y)}
		if count > 0 && points[count - 1] == logical { continue }
		if count >= len(points) { return {}, false }
		points[count] = logical
		count += 1
	}
	if count == 5 && points[4] == points[0] { count -= 1 }
	if !closed || count != 4 { return {}, false }
	lo, hi := points[0], points[0]
	for point, i in points[:4] {
		next := points[(i + 1) % 4]
		if (point.x == next.x) == (point.y == next.y) { return {}, false }
		device := view_transform_point(point) * state.dpi.scale
		if device.x != math.floor(device.x) || device.y != math.floor(device.y) { return {}, false }
		lo = {min(lo.x, point.x), min(lo.y, point.y)}
		hi = {max(hi.x, point.x), max(hi.y, point.y)}
	}
	if hi.x <= lo.x || hi.y <= lo.y { return {}, false }
	return {lo.x, lo.y, hi.x - lo.x, hi.y - lo.y}, true
}
@(private)
draw_svg_clip_mesh :: proc(items: []v.Svg_Path_Item, root_transform: Vector_Transform) -> (Vector_Mesh, Vector_Error) {
	points := make([dynamic]Vec2, context.temp_allocator)
	indices := make([dynamic]u32, context.temp_allocator)
	scale := state.dpi.scale * view_artboard_zoom()
	if scale <= 0 { return {}, .Invalid_Value }
	for &item in items {
		transform := v.Affine_Compose(root_transform, item.transform)
		handle, path_error := vector_svg_path(item.commands, item.commands_hash, item.commands_structure)
		if path_error != .None { return {}, path_error }
		entry := vector_path_entry(handle)
		linear := [4]f64{f64(scale) * transform[0], f64(scale) * transform[1], f64(scale) * transform[2], f64(scale) * transform[3]}
		job, need, build_error := vector_path_build_miss_job(handle, entry, linear, item.fill_rule)
		if build_error != .None { return {}, build_error }
		if need {
			jobs := [1]Vector_Tess_Job{job}
			vector_tessellate_jobs_serial(jobs[:])
			if install_error := vector_path_install_tess_job(&jobs[0]); install_error != .None { return {}, install_error }
		}
		cache_index := vector_path_find_cache_index(entry, linear, item.fill_rule)
		if cache_index < 0 { return {}, .Invalid_Path }
		mesh := &entry.cache[cache_index].mesh
		if len(points) + len(mesh.vertices) > VECTOR_MAX_FRAME_VERTICES || len(indices) + len(mesh.indices) > VECTOR_MAX_FRAME_INDICES { return {}, .Limit_Exceeded }
		base := u32(len(points))
		if err := reserve(&points, len(points) + len(mesh.vertices)); err != nil { return {}, .Allocation_Failed }
		if err := reserve(&indices, len(indices) + len(mesh.indices)); err != nil { return {}, .Allocation_Failed }
		for point in mesh.vertices { append(&points, Vec2{point.x, point.y} / scale + Vec2{f32(transform[4]), f32(transform[5])}) }
		for index in mesh.indices { append(&indices, base + index) }
	}
	return {vertices = points[:], indices = indices[:]}, .None
}
@(private)
vector_stroke_from_cpu :: proc(stroke: v.Stroke) -> (Vector_Stroke, Vector_Error) {
	resolved := stroke
	if stroke.non_scaling {
		// The CPU non-scaling stroker operates in physical coordinates. SVG
		// stroke lengths remain CSS pixels across the output DPI conversion.
		scale := f64(state.dpi.scale)
		resolved.width *= scale
		if stroke.path_length == 0 {
			resolved.dash_offset *= scale
			if len(stroke.dash) > 0 {
				dash, allocation_error := make([]f64, len(stroke.dash), context.temp_allocator)
				if allocation_error != nil { return {}, .Allocation_Failed }
				resolved.dash = dash
				for value, index in stroke.dash { resolved.dash[index] = value * scale }
			}
		}
	}
	return resolved, .None
}

@(private)
draw_svg_clip_geometry :: proc(node: v.Svg_Draw_Node, root_transform: Vector_Transform) -> (Vector_Mesh, Vector_Error) {
	if len(node.clip_nodes) > 0 { return draw_svg_clip_tree(node.clip_nodes, root_transform) }
	return draw_svg_clip_mesh(node.clip_items, root_transform)
}

@(private)
draw_svg_clip_tree :: proc(nodes: []v.Svg_Draw_Node, root_transform: Vector_Transform) -> (Vector_Mesh, Vector_Error) {
	points := make([dynamic]Vec2, context.temp_allocator)
	indices := make([dynamic]u32, context.temp_allocator)
	for node in nodes {
		mesh: Vector_Mesh
		err: Vector_Error
		switch node.kind {
		case .Path:
			mesh, err = draw_svg_clip_mesh([]v.Svg_Path_Item{node.item}, root_transform)
		case .Group, .Mask:
			mesh, err = draw_svg_clip_tree(node.children, root_transform)
		case .Clip:
			content, content_err := draw_svg_clip_tree(node.children, root_transform)
			if content_err != .None { return {}, content_err }
			clip, clip_err := draw_svg_clip_geometry(node, root_transform)
			if clip_err != .None { return {}, clip_err }
			// Intersect in device space so the exact solver's quantization remains
			// translation-free at the renderer's physical-pixel policy.
			a, a_err := draw_svg_device_mesh(content)
			if a_err != .None { return {}, a_err }
			b, b_err := draw_svg_device_mesh(clip)
			if b_err != .None { return {}, b_err }
			intersection := v.Mesh{vertices = make([dynamic][2]f32, context.temp_allocator), indices = make([dynamic]u32, context.temp_allocator)}
			limits, limit_err := vector_path_frame_tess_limits()
			if limit_err != .None { return {}, limit_err }
			usage: v.Build_Usage
			intersect_err := v.Intersect_Meshes_Into(&intersection, a, b, limits, &usage)
			vector_frame().new_segments += usage.flattened_segments
			vector_frame().new_triangles += usage.triangles
			vector_frame().pair_tests += usage.pair_tests
			vector_frame().exact_ops += usage.exact_ops
			if intersect_err != .None { return {}, vector_path_error(intersect_err) }
			vertices, allocation_error := make([]Vec2, len(intersection.vertices), context.temp_allocator)
			if allocation_error != nil { return {}, .Allocation_Failed }
			scale := state.dpi.scale * view_artboard_zoom()
			offset := view_transform_point({}) * state.dpi.scale
			for point, index in intersection.vertices { vertices[index] = (Vec2{point.x, point.y} - offset) / scale }
			mesh = {vertices = vertices, indices = intersection.indices[:]}
		}
		if err != .None { return {}, err }
		if len(points) + len(mesh.vertices) > VECTOR_MAX_FRAME_VERTICES || len(indices) + len(mesh.indices) > VECTOR_MAX_FRAME_INDICES { return {}, .Limit_Exceeded }
		base := u32(len(points))
		if allocation_error := reserve(&points, len(points) + len(mesh.vertices)); allocation_error != nil { return {}, .Allocation_Failed }
		if allocation_error := reserve(&indices, len(indices) + len(mesh.indices)); allocation_error != nil { return {}, .Allocation_Failed }
		append(&points, ..mesh.vertices)
		for index in mesh.indices { append(&indices, base + index) }
	}
	return {vertices = points[:], indices = indices[:]}, .None
}

@(private)
draw_svg_device_mesh :: proc(mesh: Vector_Mesh) -> (v.Mesh, Vector_Error) {
	result := v.Mesh{vertices = make([dynamic][2]f32, context.temp_allocator), indices = make([dynamic]u32, context.temp_allocator)}
	if err := reserve(&result.vertices, len(mesh.vertices)); err != nil { return {}, .Allocation_Failed }
	if err := reserve(&result.indices, len(mesh.indices)); err != nil { return {}, .Allocation_Failed }
	for point in mesh.vertices {
		device := view_transform_point(point) * state.dpi.scale
		append(&result.vertices, [2]f32{device.x, device.y})
	}
	append(&result.indices, ..mesh.indices)
	return result, .None
}


