package oni

import "core:math"
import sdl "vendor:sdl3"
import v "./vector"

// Borrowed scene data is validated and copied when Draw_Vector_Scene records it.
Vector_Mesh :: struct {
	vertices: []Vec2,
	indices:  []u32,
}

Vector_Node_Kind :: enum {
	Mesh,
	Path,
	Group,
	Clip,
	Mask,
}

Vector_Mask_Kind :: enum {
	Alpha,
	Luminance,
}

// Coordinate units for mask regions and mask/clip content, matching SVG.
Vector_Units :: enum {
	User_Space_On_Use,
	Object_Bounding_Box,
}

Vector_Node :: struct {
	kind:               Vector_Node_Kind,
	mesh:               Vector_Mesh,
	path:               Vector_Path_Draw,
	colour:             RGBA,
	opacity:            f32,
	clip:               Rect,
	children:           []Vector_Node,
	mask:               []Vector_Node,
	mask_kind:          Vector_Mask_Kind,
	mask_units:         Vector_Units,
	mask_content_units: Vector_Units,
	mask_region:        Rect,
}

Vector_Scene :: struct {
	nodes:   []Vector_Node,
	opacity: f32,
}

Vector_Error :: enum {
	None,
	Invalid_Mesh,
	Invalid_Value,
	Limit_Exceeded,
	Allocation_Failed,
	GPU_Failed,
	Invalid_Handle,
	Invalid_Path,
}

@(private)
VECTOR_MAX_FRAME_VERTICES :: 4_000_000
@(private)
VECTOR_MAX_FRAME_INDICES :: 12_000_000
@(private)
VECTOR_MAX_FRAME_NODES :: 100_000
@(private)
VECTOR_MAX_COORDINATE :: f32(1 << 20)
@(private)
VECTOR_MAX_CLIP_DEPTH :: 64
@(private)
VECTOR_MAX_NODE_DEPTH :: 256
@(private)
VECTOR_MAX_ENCODE_ATTEMPTS :: 3
@(private)
VECTOR_MAX_COMMAND_VISITS :: 1_000_000
@(private)
VECTOR_MAX_SAMPLE_WORK :: u64(64_000_000)

@(private)
VECTOR_MAX_NEW_SEGMENTS :: 1_000_000
@(private)
VECTOR_MAX_NEW_TRIANGLES :: 4_000_000

@(private)
Vector_Vertex :: struct {
	pos:    Vec2,
	uv:     Vec2,
}

@(private)
Vector_Instance :: struct {
	colour:               [4]f32,
	origin:               Vec2,
	morph_linear:         [4]f32,
	morph_shift:          Vec2,
	paint:                [4]f32, // mode, spread, ramp_row, _
	grad0:                [4]f32,
	combined_linear:      [4]f32,
	combined_shift_focal: [4]f32, // e, f, focal_x, focal_y
}

@(private)
Vector_Geometry_Range :: struct {
	first_index, index_count: u32,
}

@(private)
Vector_Record :: struct {
	kind:             Vector_Node_Kind,
	first_child:      int,
	first_mask:       int,
	next:             int,
	command:          u32,
	bounds:           Rect,
	geometry_bounds:  Rect,
	clip:             Rect,
	opacity:          f32,
	mask_kind:        Vector_Mask_Kind,
	geometric:        bool,
}

@(private)
Vector_Submission :: struct {
	first:   int,
	opacity: f32,
	clip:    Rect,
	failed:  bool,
	merged_commands: u32,
}

@(private)
Vector_Frame :: struct {
	vertices: [dynamic]Vector_Vertex,
	indices:  [dynamic]u32,
	instances: [dynamic]Vector_Instance,
	commands: [dynamic]sdl.GPUIndexedIndirectDrawCommand,
	geometry: map[u64]Vector_Geometry_Range,
	records:  [dynamic]Vector_Record,
	draws:    [dynamic]Vector_Submission,
	ramp_pixels: [dynamic]u8,
	ramp_rows: int,
	new_segments, new_triangles: int,
	svg_usage: v.Svg_Instance_Usage,
	vertex_revision: u64,
}

Vector_State :: struct {
	frames: [2]Vector_Frame,
	gpu: Vector_GPU,
	last_error: Vector_Error,
	paths: [dynamic]Vector_Path_Entry,
	path_cache_bytes: u64,
	next_geometry_id: u64,
	tess_pool:    ^Vector_Tess_Pool,
	tess_workers: int,
}

Vector_Last_Error :: proc() -> Vector_Error {
	if state == nil {
		return .None
	}
	return state.vector.last_error
}

@(private)
vector_frame :: proc() -> ^Vector_Frame {
	return &state.vector.frames[state.gpu_state.batch_index]
}

@(private)
vector_scene_shutdown :: proc() {
	if state == nil {
		return
	}
	vector_paths_shutdown()

	for &frame in state.vector.frames {
		delete(frame.vertices)
		delete(frame.indices)
		delete(frame.instances)
		delete(frame.commands)
		delete(frame.geometry)
		delete(frame.records)
		delete(frame.draws)
		delete(frame.ramp_pixels)
		frame = {}
	}
}

@(private)
vector_scene_reset :: proc() {
	clear(&vector_frame().vertices)
	clear(&vector_frame().indices)
	clear(&vector_frame().instances)
	clear(&vector_frame().commands)
	clear(&vector_frame().geometry)
	clear(&vector_frame().records)
	clear(&vector_frame().draws)
	clear(&vector_frame().ramp_pixels)
	vector_frame().ramp_rows = 0
	vector_frame().new_segments = 0
	vector_frame().new_triangles = 0
	vector_frame().svg_usage = {}
	vector_frame().vertex_revision += 1
}

@(private)
vector_scene_bump_geometry :: proc() {
	vector_frame().vertex_revision += 1
}

// Restores frame recording arrays and drops geometry cache entries that point
// past the restored index buffer. Call after a mid-record failure so a later
// sibling submission cannot observe half-written geometry ids.
@(private)
vector_scene_rollback_recording :: proc(
	saved_vertices, saved_indices, saved_instances, saved_commands, saved_records, saved_draws, saved_ramps: int,
	saved_ramp_rows: int,
	saved_revision: u64,
	saved_segments: int,
) {
	f := vector_frame()
	if len(f.geometry) > 0 {
		stale := make([dynamic]u64, context.temp_allocator)
		for id, geometry in f.geometry {
			if int(geometry.first_index) >= saved_indices {
				append(&stale, id)
			}
		}
		for id in stale {
			delete_key(&f.geometry, id)
		}
	}
	resize(&f.vertices, saved_vertices)
	resize(&f.indices, saved_indices)
	resize(&f.instances, saved_instances)
	resize(&f.commands, saved_commands)
	resize(&f.records, saved_records)
	resize(&f.draws, saved_draws)
	resize(&f.ramp_pixels, saved_ramps)
	f.ramp_rows = saved_ramp_rows
	f.vertex_revision = saved_revision
	resize(&batch_current().segments, saved_segments)
}

@(private)
vector_mesh_point_device :: proc(
	source_point: Vec2,
	device_space: bool,
	offset: Vec2,
	obb_bounds: Rect,
	use_obb: bool,
) -> Vec2 {
	if use_obb {
		return {
			obb_bounds.x + source_point.x * obb_bounds.w,
			obb_bounds.y + source_point.y * obb_bounds.h,
		}
	}

	return vector_source_point(source_point, device_space, offset)
}

@(private)
vector_scene_validate_mesh :: proc(
	mesh: Vector_Mesh,
	vertex_count, index_count: ^int,
	device_space: bool,
	offset: Vec2,
	obb_bounds: Rect = {},
	use_obb: bool = false,
) -> Vector_Error {
	if len(mesh.indices) % 3 != 0 {
		return .Invalid_Mesh
	}

	for index in mesh.indices {
		if u64(index) >= u64(len(mesh.vertices)) {
			return .Invalid_Mesh
		}
	}

	for source_point in mesh.vertices {
		point := vector_mesh_point_device(source_point, device_space, offset, obb_bounds, use_obb)
		if !(abs(point.x) <= VECTOR_MAX_COORDINATE && abs(point.y) <= VECTOR_MAX_COORDINATE) {
			return .Invalid_Value
		}
	}

	vertex_count^ += len(mesh.vertices)
	index_count^ += len(mesh.indices)
	return .None
}

@(private)
vector_scene_logical_mesh_bounds :: proc(mesh: Vector_Mesh) -> Rect {
	if len(mesh.vertices) == 0 {
		return {}
	}

	lo := mesh.vertices[0]
	hi := mesh.vertices[0]
	for point in mesh.vertices[1:] {
		lo = {min(lo.x, point.x), min(lo.y, point.y)}
		hi = {max(hi.x, point.x), max(hi.y, point.y)}
	}
	return {lo.x, lo.y, hi.x - lo.x, hi.y - lo.y}
}

@(private)
vector_scene_logical_content_bounds :: proc(nodes: []Vector_Node) -> Rect {
	bounds: Rect
	for node in nodes {
		switch node.kind {
		case .Mesh:
			bounds = vector_bounds_union(bounds, vector_scene_logical_mesh_bounds(node.mesh))
		case .Path:
		case .Group, .Clip, .Mask:
			bounds = vector_bounds_union(bounds, vector_scene_logical_content_bounds(node.children))
		}
	}
	return bounds
}

@(private)
vector_scene_validate :: proc(
	nodes: []Vector_Node,
	depth: int,
	clip_depth: int,
	vertex_count, index_count, node_count: ^int,
	device_space: bool,
	offset: Vec2,
	obb_bounds: Rect = {},
	use_obb: bool = false,
) -> Vector_Error {
	if depth > VECTOR_MAX_NODE_DEPTH {
		return .Limit_Exceeded
	}

	for node in nodes {
		node_count^ += 1
		if node_count^ > VECTOR_MAX_FRAME_NODES {
			return .Limit_Exceeded
		}

		if !(node.opacity >= 0 && node.opacity <= 1) {
			return .Invalid_Value
		}

		child_clip_depth := clip_depth
		switch node.kind {
		case .Mesh:
			if len(node.children) > 0 || len(node.mask) > 0 || node.path.handle.index != 0 {
				return .Invalid_Value
			}
			if err := vector_scene_validate_mesh(
				node.mesh,
				vertex_count,
				index_count,
				device_space,
				offset,
				obb_bounds,
				use_obb,
			); err != .None {
				return err
			}
		case .Path:
			if len(node.children) > 0 ||
			   len(node.mask) > 0 ||
			   len(node.mesh.vertices) > 0 ||
			   len(node.mesh.indices) > 0 {
				return .Invalid_Value
			}
			if vector_path_entry(node.path.handle) == nil {
				return .Invalid_Handle
			}
			if !(node.path.opacity >= 0 && node.path.opacity <= 1) {
				return .Invalid_Value
			}
			for value in node.path.transform {
				if math.is_nan(value) || math.is_inf(value) {
					return .Invalid_Value
				}
			}
			if err := vector_stroke_validate_draw(node.path.op, node.path.stroke); err != .None {
				return err
			}
			// Conservatively reserve a filled quad; tessellation may use more and is
			// rechecked when the path is recorded into the scene.
			vertex_count^ += 4
			index_count^ += 6
		case .Group, .Mask:
			if len(node.mesh.vertices) > 0 ||
			   len(node.mesh.indices) > 0 ||
			   node.path.handle.index != 0 ||
			   (node.kind == .Group && len(node.mask) > 0) {
				return .Invalid_Value
			}
			vertex_count^ += 4
			index_count^ += 6
			if node.kind == .Mask {
				region := [4]f32{node.mask_region.x, node.mask_region.y, node.mask_region.w, node.mask_region.h}
				for value in region {
					if !(abs(value) <= VECTOR_MAX_COORDINATE) {
						return .Invalid_Value
					}
				}
			}
		case .Clip:
			if len(node.mask) > 0 || node.path.handle.index != 0 {
				return .Invalid_Value
			}
			has_rect := node.clip.w > 0 && node.clip.h > 0
			has_mesh := len(node.mesh.indices) > 0
			if !has_rect && !has_mesh {
				return .Invalid_Value
			}
			if has_rect {
				values := [4]f32{node.clip.x, node.clip.y, node.clip.w, node.clip.h}
				for value in values {
					if !(abs(value) <= VECTOR_MAX_COORDINATE) {
						return .Invalid_Value
					}
				}
			}
			if has_mesh {
				child_clip_depth = clip_depth + 1
				if child_clip_depth > VECTOR_MAX_CLIP_DEPTH {
					return .Limit_Exceeded
				}
				if err := vector_scene_validate_mesh(
					node.mesh,
					vertex_count,
					index_count,
					device_space,
					offset,
					obb_bounds,
					use_obb,
				); err != .None {
					return err
				}
			}
		}

		if vertex_count^ > VECTOR_MAX_FRAME_VERTICES || index_count^ > VECTOR_MAX_FRAME_INDICES {
			return .Limit_Exceeded
		}

		if err := vector_scene_validate(
			node.children,
			depth + 1,
			child_clip_depth,
			vertex_count,
			index_count,
			node_count,
			device_space,
			offset,
			obb_bounds,
			use_obb,
		); err != .None {
			return err
		}

		mask_obb_bounds := obb_bounds
		mask_use_obb := false
		if node.kind == .Mask && node.mask_content_units == .Object_Bounding_Box {
			logical := vector_scene_logical_content_bounds(node.children)
			if logical.w <= 0 || logical.h <= 0 {
				return .Invalid_Value
			}
			mask_obb_bounds = vector_logical_to_device_rect(logical, device_space, offset)
			mask_use_obb = true
		}
		if err := vector_scene_validate(
			node.mask,
			depth + 1,
			0,
			vertex_count,
			index_count,
			node_count,
			device_space,
			offset,
			mask_obb_bounds,
			mask_use_obb,
		); err != .None {
			return err
		}
	}

	return .None
}

@(private)
vector_bounds_union :: proc(a, b: Rect) -> Rect {
	if a.w <= 0 || a.h <= 0 {
		return b
	}
	if b.w <= 0 || b.h <= 0 {
		return a
	}
	x := min(a.x, b.x)
	y := min(a.y, b.y)
	return {x, y, max(a.x + a.w, b.x + b.w) - x, max(a.y + a.h, b.y + b.h) - y}
}

@(private)
vector_list_bounds :: proc(first: int) -> (bounds: Rect) {
	index := first
	for index >= 0 {
		record := vector_frame().records[index]
		bounds = vector_bounds_union(bounds, record.bounds)
		index = record.next
	}
	return
}

@(private)
vector_list_geometry_bounds :: proc(first: int) -> (bounds: Rect) {
	index := first
	for index >= 0 {
		record := vector_frame().records[index]
		geo := record.geometry_bounds
		if geo.w <= 0 || geo.h <= 0 {
			geo = record.bounds
		}
		bounds = vector_bounds_union(bounds, geo)
		index = record.next
	}
	return
}

@(private)
vector_record_quad :: proc(bounds: Rect, opacity: f32) -> (first: u32) {
	f := vector_frame()
	base := u32(len(f.vertices))
	first_index := u32(len(f.indices))
	append(&f.vertices,
		Vector_Vertex{pos = {bounds.x, bounds.y}, uv = {0, 0}},
		Vector_Vertex{pos = {bounds.x + bounds.w, bounds.y}, uv = {1, 0}},
		Vector_Vertex{pos = {bounds.x + bounds.w, bounds.y + bounds.h}, uv = {1, 1}},
		Vector_Vertex{pos = {bounds.x, bounds.y + bounds.h}, uv = {0, 1}},
	)
	append(&f.indices, base, base + 1, base + 2, base, base + 2, base + 3)
	vector_scene_bump_geometry()
	return vector_record_command(first_index, 6, {}, {colour = {1, 1, 1, opacity}})
}

@(private)
vector_record_command :: proc(
	first_index, index_count: u32,
	origin: Vec2,
	paint: Vector_Paint_GPU,
	morph: Vector_Transform = Vector_Identity,
) -> u32 {
	f := vector_frame()
	first := u32(len(f.commands))
	append(&f.commands, sdl.GPUIndexedIndirectDrawCommand{
		num_indices = index_count, num_instances = 1, first_index = first_index,
		first_instance = u32(len(f.instances)),
	})
	append(&f.instances, Vector_Instance{
		colour = paint.colour,
		origin = origin,
		morph_linear = {f32(morph[0]), f32(morph[1]), f32(morph[2]), f32(morph[3])},
		morph_shift = {f32(morph[4]), f32(morph[5])},
		paint = {paint.mode, paint.spread, paint.ramp_row, 0},
		grad0 = paint.grad0,
		combined_linear = {
			f32(paint.combined[0]),
			f32(paint.combined[1]),
			f32(paint.combined[2]),
			f32(paint.combined[3]),
		},
		combined_shift_focal = {
			f32(paint.combined[4]),
			f32(paint.combined[5]),
			paint.focal[0],
			paint.focal[1],
		},
	})
	return first
}

@(private)
vector_record_mesh_geometry :: proc(
	mesh: Vector_Mesh,
	colour: [4]f32,
	device_space: bool,
	offset: Vec2,
	obb_bounds: Rect,
	use_obb: bool,
) -> (command: u32, bounds: Rect) {
	f := vector_frame()
	base := u32(len(f.vertices))
	first_index := u32(len(f.indices))
	lo := Vec2{VECTOR_MAX_COORDINATE, VECTOR_MAX_COORDINATE}
	hi := -lo
	for source_point in mesh.vertices {
		point := vector_mesh_point_device(source_point, device_space, offset, obb_bounds, use_obb)
		lo = {min(lo.x, point.x), min(lo.y, point.y)}
		hi = {max(hi.x, point.x), max(hi.y, point.y)}
		append(&f.vertices, Vector_Vertex{pos = point})
	}
	for vertex_index in mesh.indices {
		append(&f.indices, base + vertex_index)
	}
	if len(mesh.vertices) > 0 || len(mesh.indices) > 0 {
		vector_scene_bump_geometry()
	}
	command = vector_record_command(first_index, u32(len(mesh.indices)), {}, {colour = colour})
	if len(mesh.indices) > 0 {
		bounds = {lo.x, lo.y, hi.x - lo.x, hi.y - lo.y}
	}
	return
}

@(private)
vector_logical_to_device_rect :: proc(rect: Rect, device_space: bool, offset: Vec2) -> Rect {
	if device_space {
		return {rect.x + offset.x, rect.y + offset.y, rect.w, rect.h}
	}

	transformed := view_transform_rect(rect)
	return {
		transformed.x * state.dpi.scale,
		transformed.y * state.dpi.scale,
		transformed.w * state.dpi.scale,
		transformed.h * state.dpi.scale,
	}
}

@(private)
vector_record_nodes :: proc(
	nodes: []Vector_Node,
	device_space: bool,
	offset: Vec2,
	obb_bounds: Rect = {},
	use_obb: bool = false,
) -> (first: int, err: Vector_Error) {
	first = -1
	last := -1
	f := vector_frame()
	for node in nodes {
		index := len(f.records)
		append(&f.records, Vector_Record{
			kind = node.kind,
			opacity = node.opacity,
			mask_kind = node.mask_kind,
			first_child = -1,
			first_mask = -1,
			next = -1,
		})
		if last >= 0 {
			f.records[last].next = index
		} else {
			first = index
		}
		last = index

		switch node.kind {
		case .Mesh:
			colour := color_to_f32(node.colour)
			colour[3] *= node.opacity
			command, bounds := vector_record_mesh_geometry(
				node.mesh,
				colour,
				device_space,
				offset,
				obb_bounds,
				use_obb,
			)
			f.records[index].command = command
			f.records[index].bounds = bounds
			f.records[index].geometry_bounds = bounds
		case .Path:
			if path_err := vector_record_path_node(&f.records[index], node.path, node.opacity); path_err != .None {
				return -1, path_err
			}
		case .Group, .Clip, .Mask:
		}

		child: int
		child, err = vector_record_nodes(node.children, device_space, offset, obb_bounds, use_obb)
		if err != .None {
			return -1, err
		}
		f.records[index].first_child = child

		if node.kind == .Mesh || node.kind == .Path {
			continue
		}

		bounds := vector_list_bounds(child)
		content_bounds := vector_list_geometry_bounds(child)
		if content_bounds.w <= 0 || content_bounds.h <= 0 {
			content_bounds = bounds
		}
		if node.kind == .Clip {
			has_rect := node.clip.w > 0 && node.clip.h > 0
			has_mesh := len(node.mesh.indices) > 0
			clip_bounds := bounds
			if has_rect {
				clip: Rect
				if use_obb {
					clip = {
						obb_bounds.x + node.clip.x * obb_bounds.w,
						obb_bounds.y + node.clip.y * obb_bounds.h,
						node.clip.w * obb_bounds.w,
						node.clip.h * obb_bounds.h,
					}
				} else {
					clip = vector_logical_to_device_rect(node.clip, device_space, offset)
				}
				f.records[index].clip = clip
				clip_bounds = rect_intersect(bounds, clip)
			}
			if has_mesh {
				command, mesh_bounds := vector_record_mesh_geometry(
					node.mesh,
					{1, 1, 1, 1},
					device_space,
					offset,
					obb_bounds,
					use_obb,
				)
				f.records[index].command = command
				f.records[index].geometric = true
				if has_rect {
					clip_bounds = rect_intersect(clip_bounds, mesh_bounds)
				} else {
					f.records[index].clip = mesh_bounds
					clip_bounds = rect_intersect(bounds, mesh_bounds)
				}
			}
			f.records[index].bounds = clip_bounds
			f.records[index].geometry_bounds = clip_bounds
		} else if node.kind == .Mask {
			mask_obb := node.mask_content_units == .Object_Bounding_Box
			mask: int
			mask, err = vector_record_nodes(
				node.mask,
				device_space,
				offset,
				content_bounds if mask_obb else {},
				mask_obb,
			)
			if err != .None {
				return -1, err
			}
			f.records[index].first_mask = mask
			mask_bounds := vector_list_bounds(mask)
			union_bounds := vector_bounds_union(content_bounds, mask_bounds)
			region := union_bounds
			if node.mask_region.w > 0 && node.mask_region.h > 0 {
				if node.mask_units == .Object_Bounding_Box {
					region = {
						content_bounds.x + node.mask_region.x * content_bounds.w,
						content_bounds.y + node.mask_region.y * content_bounds.h,
						node.mask_region.w * content_bounds.w,
						node.mask_region.h * content_bounds.h,
					}
				} else {
					region = vector_logical_to_device_rect(node.mask_region, device_space, offset)
				}
			} else if content_bounds.w > 0 && content_bounds.h > 0 {
				region = content_bounds
			}
			f.records[index].clip = region
			f.records[index].geometry_bounds = rect_intersect(union_bounds, region) if region.w > 0 && region.h > 0 else union_bounds
			if f.records[index].geometry_bounds.w <= 0 || f.records[index].geometry_bounds.h <= 0 {
				f.records[index].geometry_bounds = content_bounds
			}
			bounds = vector_target_bounds(f.records[index].geometry_bounds)
			f.records[index].bounds = bounds
			f.records[index].command = vector_record_quad(bounds, node.opacity)
		} else if node.kind == .Group {
			f.records[index].first_mask = -1
			f.records[index].geometry_bounds = content_bounds if content_bounds.w > 0 && content_bounds.h > 0 else bounds
			bounds = vector_target_bounds(f.records[index].geometry_bounds)
			f.records[index].bounds = bounds
			f.records[index].command = vector_record_quad(bounds, node.opacity)
		}
	}
	return
}

@(private)
vector_record_path_node :: proc(record: ^Vector_Record, draw: Vector_Path_Draw, node_opacity: f32) -> Vector_Error {
	entry := vector_path_entry(draw.handle)
	if entry == nil {
		return .Invalid_Handle
	}

	opacity := draw.opacity
	if opacity == 0 && node_opacity != 0 {
		opacity = node_opacity
	} else {
		opacity *= node_opacity
	}
	if opacity <= 0 {
		record.bounds = {}
		record.geometry_bounds = {}
		return .None
	}

	instance_morph := vector_path_normalize_morph(draw.instance_morph)
	linear := vector_path_draw_linear(draw.transform)
	morph := vector_stroke_draw_morph(entry, instance_morph) if draw.op == .Stroke else Vector_Identity
	cache_index := vector_path_find_cache_index(entry, linear, draw.rule, draw.op, draw.stroke, morph)
	if cache_index < 0 || !entry.cache[cache_index].valid {
		job, need, build_err := vector_path_build_miss_job(draw.handle, entry, linear, draw.rule, draw.op, draw.stroke, morph)
		if build_err != .None {
			return build_err
		}
		if need {
			jobs := [1]Vector_Tess_Job{job}
			vector_tessellate_jobs_serial(jobs[:])
			if install_err := vector_path_install_tess_job(&jobs[0]); install_err != .None {
				return install_err
			}
			cache_index = jobs[0].cache_index
		} else {
			cache_index = vector_path_find_cache_index(entry, linear, draw.rule, draw.op, draw.stroke, morph)
		}
	}
	if cache_index < 0 || !entry.cache[cache_index].valid {
		return .Invalid_Path
	}

	entry.cache[cache_index].last_used = state.ui.frame
	mesh := entry.cache[cache_index].mesh
	origin := view_transform_point({f32(draw.transform[4]), f32(draw.transform[5])}) * state.dpi.scale
	gpu_morph := Vector_Identity
	if entry.cache[cache_index].op != .Stroke {
		gpu_morph = v.Affine_Compose(entry.morph, instance_morph)
		if gpu_morph != Vector_Identity {
			linear_affine := v.Affine{
				entry.cache[cache_index].linear[0],
				entry.cache[cache_index].linear[1],
				entry.cache[cache_index].linear[2],
				entry.cache[cache_index].linear[3],
				0,
				0,
			}
			if linear_affine != v.IDENTITY {
				if inverse, ok := v.Affine_Invert(linear_affine); ok {
					gpu_morph = v.Affine_Compose(linear_affine, v.Affine_Compose(gpu_morph, inverse))
				} else {
					gpu_morph = Vector_Identity
				}
			}
		}
	}

	gpu_paint, skip, paint_err := vector_paint_resolve(
		draw.paint,
		opacity,
		entry.cache[cache_index].linear,
		entry.cache[cache_index].local_bounds,
		draw.current_color,
	)
	if paint_err != .None {
		return paint_err
	}
	if skip {
		record.bounds = {}
		record.geometry_bounds = {}
		return .None
	}

	f := vector_frame()
	geometry, shared := f.geometry[entry.cache[cache_index].geometry_id]
	if !shared {
		base := u32(len(f.vertices))
		geometry = {first_index = u32(len(f.indices)), index_count = u32(len(mesh.indices))}
		if !vector_reserve(&f.vertices, len(f.vertices) + len(mesh.vertices), VECTOR_MAX_FRAME_VERTICES) ||
		   !vector_reserve(&f.indices, len(f.indices) + len(mesh.indices), VECTOR_MAX_FRAME_INDICES) {
			return .Allocation_Failed
		}
		resize(&f.vertices, int(base) + len(mesh.vertices))
		resize(&f.indices, int(geometry.first_index) + len(mesh.indices))
		for point, i in mesh.vertices {
			f.vertices[int(base) + i] = {pos = point}
		}
		for index, i in mesh.indices {
			f.indices[int(geometry.first_index) + i] = base + index
		}
		if reserve(&f.geometry, len(f.geometry) + 1) != nil {
			return .Allocation_Failed
		}
		f.geometry[entry.cache[cache_index].geometry_id] = geometry
		vector_scene_bump_geometry()
	}

	bounds := entry.cache[cache_index].bounds
	morph_bounds := bounds
	if gpu_morph[0] != 1 || gpu_morph[1] != 0 || gpu_morph[2] != 0 || gpu_morph[3] != 1 || gpu_morph[4] != 0 || gpu_morph[5] != 0 {
		a, b, c, d := f32(gpu_morph[0]), f32(gpu_morph[1]), f32(gpu_morph[2]), f32(gpu_morph[3])
		e, fval := f32(gpu_morph[4]), f32(gpu_morph[5])
		x0, y0 := bounds.x, bounds.y
		x1, y1 := bounds.x + bounds.w, bounds.y + bounds.h
		p00 := Vec2{a * x0 + c * y0 + e, b * x0 + d * y0 + fval}
		p10 := Vec2{a * x1 + c * y0 + e, b * x1 + d * y0 + fval}
		p11 := Vec2{a * x1 + c * y1 + e, b * x1 + d * y1 + fval}
		p01 := Vec2{a * x0 + c * y1 + e, b * x0 + d * y1 + fval}
		lo := Vec2{min(p00.x, p10.x, p11.x, p01.x), min(p00.y, p10.y, p11.y, p01.y)}
		hi := Vec2{max(p00.x, p10.x, p11.x, p01.x), max(p00.y, p10.y, p11.y, p01.y)}
		morph_bounds = {lo.x, lo.y, hi.x - lo.x, hi.y - lo.y}
	}
	placed := Rect{morph_bounds.x + origin.x, morph_bounds.y + origin.y, morph_bounds.w, morph_bounds.h}
	record.command = vector_record_command(geometry.first_index, geometry.index_count, origin, gpu_paint, gpu_morph)
	record.bounds = placed
	record.geometry_bounds = placed
	record.kind = .Path
	return .None
}

/*
Records an immutable snapshot of a vector scene during Draw. Mesh coordinates
are logical pixels in the current draw space. Groups isolate opacity. Clips use
rectangular scissors and/or geometric stencil meshes. Masks support alpha or
luminance coverage with optional objectBoundingBox units. Invalid submissions
leave the frame unchanged.
*/
draw_vector_scene :: proc(scene: Vector_Scene) -> Vector_Error {
	return record_vector_scene(scene, false, {})
}

@(private)
vector_source_point :: proc(point: Vec2, device_space: bool, offset: Vec2) -> Vec2 {
	if device_space {
		return point + offset
	}
	return view_transform_point(point) * state.dpi.scale
}

// Only generated, validated cache meshes use this path. Bounds and frame limits
// are checked per instance; borrowed application meshes still use full validation.
// Consecutive mesh instances that share clip/space coalesce into one submission
// with contiguous indirect commands so encode/merge work stays O(batches).
@(private)
vector_record_cached_mesh :: proc(
	points: []Vec2,
	indices: []u32,
	bounds: Rect,
	origin: Vec2,
	paint: Vector_Paint_GPU,
	geometry_id: u64,
	morph: Vector_Transform = Vector_Identity,
) -> Vector_Error {
	if !(abs(bounds.x + origin.x) <= VECTOR_MAX_COORDINATE && abs(bounds.y + origin.y) <= VECTOR_MAX_COORDINATE &&
	     abs(bounds.x + bounds.w + origin.x) <= VECTOR_MAX_COORDINATE && abs(bounds.y + bounds.h + origin.y) <= VECTOR_MAX_COORDINATE) {
		return .Invalid_Value
	}
	if len(indices) == 0 || paint.colour[3] == 0 {
		return .None
	}
	f := vector_frame()
	geometry, shared := f.geometry[geometry_id]
	new_vertices := shared ? 0 : len(points)
	new_indices := shared ? 0 : len(indices)
	clip := batch_current_clip()
	draw_space := draw_current_space()
	stack_index := batch_current().current_stack
	coalesce := false
	if len(f.draws) > 0 && len(batch_current().segments) > 0 {
		draw := f.draws[len(f.draws) - 1]
		segment := batch_current().segments[len(batch_current().segments) - 1]
		if !draw.failed &&
		   segment.vector &&
		   segment.vector_index == len(f.draws) - 1 &&
		   draw.clip == clip &&
		   segment.key.clip == clip &&
		   segment.key.draw_space == draw_space &&
		   segment.key.stack_index == stack_index &&
		   draw.first >= 0 {
			record := f.records[draw.first]
			count := draw.merged_commands > 0 ? draw.merged_commands : 1
			coalesce = record.kind == .Mesh && record.next < 0 && record.command + count == u32(len(f.commands))
		}
	}
	if !vector_reserve(&f.vertices, len(f.vertices) + new_vertices, VECTOR_MAX_FRAME_VERTICES) ||
	   !vector_reserve(&f.indices, len(f.indices) + new_indices, VECTOR_MAX_FRAME_INDICES) ||
	   !vector_reserve(&f.instances, len(f.instances) + 1, VECTOR_MAX_FRAME_NODES) ||
	   !vector_reserve(&f.commands, len(f.commands) + 1, VECTOR_MAX_FRAME_NODES) ||
	   !vector_reserve(&f.records, len(f.records) + 1, VECTOR_MAX_FRAME_NODES) ||
	   (!coalesce &&
	    (!vector_reserve(&f.draws, len(f.draws) + 1, VECTOR_MAX_FRAME_NODES) ||
	     !vector_reserve(&batch_current().segments, len(batch_current().segments) + 1, max(VECTOR_MAX_FRAME_NODES * 2, len(batch_current().segments) + 1)))) {
		return .Allocation_Failed
	}
	if !shared && reserve(&f.geometry, len(f.geometry) + 1) != nil { return .Allocation_Failed }
	if !shared {
		base := u32(len(f.vertices))
		geometry = {first_index = u32(len(f.indices)), index_count = u32(len(indices))}
		resize(&f.vertices, int(base) + len(points))
		resize(&f.indices, int(geometry.first_index) + len(indices))
		for point, i in points { f.vertices[int(base) + i] = {pos = point} }
		for index, i in indices { f.indices[int(geometry.first_index) + i] = base + index }
		f.geometry[geometry_id] = geometry
		vector_scene_bump_geometry()
	}
	command := vector_record_command(geometry.first_index, geometry.index_count, origin, paint, morph)
	morph_bounds := bounds
	if morph[0] != 1 || morph[1] != 0 || morph[2] != 0 || morph[3] != 1 || morph[4] != 0 || morph[5] != 0 {
		a, b, c, d := f32(morph[0]), f32(morph[1]), f32(morph[2]), f32(morph[3])
		e, f := f32(morph[4]), f32(morph[5])
		x0, y0 := bounds.x, bounds.y
		x1, y1 := bounds.x + bounds.w, bounds.y + bounds.h
		p00 := Vec2{a * x0 + c * y0 + e, b * x0 + d * y0 + f}
		p10 := Vec2{a * x1 + c * y0 + e, b * x1 + d * y0 + f}
		p11 := Vec2{a * x1 + c * y1 + e, b * x1 + d * y1 + f}
		p01 := Vec2{a * x0 + c * y1 + e, b * x0 + d * y1 + f}
		lo := Vec2{min(p00.x, p10.x, p11.x, p01.x), min(p00.y, p10.y, p11.y, p01.y)}
		hi := Vec2{max(p00.x, p10.x, p11.x, p01.x), max(p00.y, p10.y, p11.y, p01.y)}
		morph_bounds = {lo.x, lo.y, hi.x - lo.x, hi.y - lo.y}
	}
	root := len(f.records)
	append(&f.records, Vector_Record{
		kind = .Mesh, first_child = -1, first_mask = -1, next = -1,
		bounds = {morph_bounds.x + origin.x, morph_bounds.y + origin.y, morph_bounds.w, morph_bounds.h},
		opacity = 1, command = command,
	})
	if coalesce {
		draw := &f.draws[len(f.draws) - 1]
		count := draw.merged_commands > 0 ? draw.merged_commands : 1
		draw.merged_commands = count + 1
		return .None
	}
	draw_index := len(f.draws)
	append(&f.draws, Vector_Submission{first = root, opacity = paint.colour[3], clip = clip, merged_commands = 1})
	batch_close_segment()
	append(&batch_current().segments, Batch_Segment{
		key = {clip = clip, draw_space = draw_space, stack_index = stack_index},
		first_index = u32(len(batch_current().indices)), vector = true, vector_index = draw_index,
		sequence = batch_current().next_sequence,
	})
	batch_current().next_sequence += 1
	return .None
}

@(private)
record_vector_scene :: proc(scene: Vector_Scene, device_space: bool, offset: Vec2) -> Vector_Error {
	if state == nil || ui_pass() != .Draw || len(scene.nodes) == 0 {
		return .None
	}
	if !(scene.opacity >= 0 && scene.opacity <= 1) {
		return .Invalid_Value
	}

	f := vector_frame()
	saved_vertices := len(f.vertices)
	saved_indices := len(f.indices)
	saved_instances := len(f.instances)
	saved_commands := len(f.commands)
	saved_records := len(f.records)
	saved_draws := len(f.draws)
	saved_ramps := len(f.ramp_pixels)
	saved_ramp_rows := f.ramp_rows
	saved_revision := f.vertex_revision
	saved_segments := len(batch_current().segments)
	vertex_count, index_count, node_count := saved_vertices, saved_indices, saved_records
	if err := vector_scene_validate(scene.nodes, 1, 0, &vertex_count, &index_count, &node_count, device_space, offset); err != .None {
		return err
	}
	opacity := scene.opacity * draw_effective_opacity()
	leaf := len(scene.nodes) == 1 && (scene.nodes[0].kind == .Mesh || scene.nodes[0].kind == .Path)
	isolated := opacity < 1 && !leaf
	if isolated {
		vertex_count += 4
		index_count += 6
		node_count += 1
	}
	if vertex_count > VECTOR_MAX_FRAME_VERTICES || index_count > VECTOR_MAX_FRAME_INDICES || node_count > VECTOR_MAX_FRAME_NODES {
		return .Limit_Exceeded
	}

	if !vector_reserve(&f.vertices, vertex_count, VECTOR_MAX_FRAME_VERTICES) || !vector_reserve(&f.indices, index_count, VECTOR_MAX_FRAME_INDICES) ||
	   !vector_reserve(&f.instances, node_count, VECTOR_MAX_FRAME_NODES) || !vector_reserve(&f.commands, node_count, VECTOR_MAX_FRAME_NODES) ||
	   !vector_reserve(&f.records, node_count, VECTOR_MAX_FRAME_NODES) || !vector_reserve(&f.draws, len(f.draws) + 1, VECTOR_MAX_FRAME_NODES) ||
	   !vector_reserve(&batch_current().segments, len(batch_current().segments) + 1, max(VECTOR_MAX_FRAME_NODES * 2, len(batch_current().segments) + 1)) {
		return .Allocation_Failed
	}

	first, record_err := vector_record_nodes(scene.nodes, device_space, offset)
	if record_err != .None {
		vector_scene_rollback_recording(saved_vertices, saved_indices, saved_instances, saved_commands, saved_records, saved_draws, saved_ramps, saved_ramp_rows, saved_revision, saved_segments)
		return record_err
	}
	if isolated {
		geo := vector_list_geometry_bounds(first)
		bounds := vector_target_bounds(geo)
		quad := vector_record_quad(bounds, opacity)
		root := len(f.records)
		append(&f.records, Vector_Record{
			kind = .Group,
			first_child = first,
			first_mask = -1,
			next = -1,
			bounds = bounds,
			geometry_bounds = geo,
			opacity = opacity,
			command = quad,
		})
		first = root
	} else if opacity < 1 {
		f.instances[f.commands[f.records[first].command].first_instance].colour[3] *= opacity
	}
	draw_index := len(f.draws)
	append(&f.draws, Vector_Submission{first = first, opacity = opacity, clip = batch_current_clip()})
	batch_close_segment()
	key := Batch_Key{clip = batch_current_clip(), draw_space = draw_current_space(), stack_index = batch_current().current_stack}
	append(&batch_current().segments, Batch_Segment{
		key = key, first_index = u32(len(batch_current().indices)), vector = true,
		vector_index = draw_index, sequence = batch_current().next_sequence,
	})
	batch_current().next_sequence += 1
	return .None
}

@(private)
vector_reserve :: proc(array: ^$T/[dynamic]$E, needed, limit: int) -> bool {
	if needed > limit {
		return false
	}
	if needed <= cap(array^) {
		return true
	}
	return reserve(array, min(limit, max(needed, max(64, cap(array^) * 2)))) == nil
}

@(private)
vector_merge_submissions :: proc(first, second: int) -> bool {
	f := vector_frame()
	a, b := f.draws[first], f.draws[second]
	if a.failed || b.failed || a.clip != b.clip || a.first < 0 || b.first < 0 {
		return false
	}
	ra, rb := f.records[a.first], f.records[b.first]
	if ra.kind != .Mesh || rb.kind != .Mesh || ra.next >= 0 || rb.next >= 0 ||
	   ra.bounds.w <= 0 || ra.bounds.h <= 0 || rb.bounds.w <= 0 || rb.bounds.h <= 0 || ra.opacity <= 0 || rb.opacity <= 0 {
		return false
	}
	count := a.merged_commands > 0 ? a.merged_commands : 1
	if ra.command + count != rb.command {
		return false
	}
	f.draws[first].merged_commands = count + (b.merged_commands > 0 ? b.merged_commands : 1)
	return true
}

@(private)
vector_target_bounds :: proc(bounds: Rect) -> Rect {
	if bounds.w <= 0 || bounds.h <= 0 {
		return {}
	}
	x := max(f32(0), math.floor(bounds.x) - 1)
	y := max(f32(0), math.floor(bounds.y) - 1)
	right := min(f32(state.dpi.logical_w) * state.dpi.scale, math.ceil(bounds.x + bounds.w) + 1)
	bottom := min(f32(state.dpi.logical_h) * state.dpi.scale, math.ceil(bounds.y + bounds.h) + 1)
	return {x, y, max(f32(0), right - x), max(f32(0), bottom - y)}
}
