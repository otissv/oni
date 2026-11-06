package oni

import v "./vector"

@(private)
Vector_Recording_Checkpoint :: struct {
	vertices, indices, instances, commands, records, draws, ramps, ramp_rows, segments: int,
	revision: u64,
	last_draw: Vector_Submission,
	last_record: Vector_Record,
}

@(private)
vector_recording_checkpoint :: proc() -> (saved: Vector_Recording_Checkpoint) {
	f := vector_frame()
	saved = {vertices = len(f.vertices), indices = len(f.indices), instances = len(f.instances),
		commands = len(f.commands), records = len(f.records), draws = len(f.draws), ramps = len(f.ramp_pixels),
		ramp_rows = f.ramp_rows, segments = len(batch_current().segments), revision = f.vertex_revision}
	if saved.draws > 0 {
		saved.last_draw = f.draws[saved.draws - 1]
		if saved.last_draw.first >= 0 { saved.last_record = f.records[saved.last_draw.first] }
	}
	return
}

@(private)
vector_recording_restore :: proc(saved: ^Vector_Recording_Checkpoint) {
	vector_scene_rollback_recording(saved.vertices, saved.indices, saved.instances, saved.commands, saved.records,
		saved.draws, saved.ramps, saved.ramp_rows, saved.revision, saved.segments)
	f := vector_frame()
	if saved.draws > 0 {
		f.draws[saved.draws - 1] = saved.last_draw
		if saved.last_draw.first >= 0 { f.records[saved.last_draw.first] = saved.last_record }
	}
}

// Flat solid SVGs can record directly from their independently owned snapshot.
// This avoids building and validating a second array of identical draw props.
@(private)
draw_svg_flat_solid :: proc(roots: []v.Svg_Draw_Node, transform: Vector_Transform, opacity: f32) -> (err: Vector_Error) {
	saved := vector_recording_checkpoint()
	defer if err != .None { vector_recording_restore(&saved) }
	f := vector_frame()
	if !vector_reserve(&f.instances, len(f.instances) + len(roots), VECTOR_MAX_FRAME_NODES) ||
	   !vector_reserve(&f.commands, len(f.commands) + len(roots), VECTOR_MAX_FRAME_NODES) { return .Allocation_Failed }
	recording := Vector_Path_Record_Context{clip = batch_current_clip(), draw_space = draw_current_space(),
		stack_index = batch_current().current_stack, capacity_reserved = true}
	linear := vector_path_fill_tess_linear()
	dpi_zoom := f64(state.dpi.scale * view_artboard_zoom())
	draw_opacity := draw_effective_opacity()
	origin := view_transform_point({f32(transform[4]), f32(transform[5])}) * state.dpi.scale
	for &root in roots {
		if path_error := draw_svg_flat_path(&root, transform, opacity, linear, dpi_zoom, draw_opacity, origin, &recording); path_error != .None { return path_error }
	}
	return .None
}

@(private)
draw_svg_flat_path :: #force_inline proc(root: ^v.Svg_Draw_Node, transform: Vector_Transform, opacity: f32, linear: [4]f64, dpi_zoom: f64, draw_opacity: f32, origin: Vec2, recording: ^Vector_Path_Record_Context) -> Vector_Error {
	item := &root.item
	handle, path_error := vector_svg_path(item.commands, item.commands_hash, item.commands_structure, mesh_only = true)
	if path_error != .None { return path_error }
	entry := vector_path_entry(handle)
	defer if entry.svg_mesh_only { entry.commands = nil }
	cached := vector_path_find_cache_index(entry, linear, item.fill_rule)
	if cached < 0 {
		refreshed, handled, refresh_error := vector_path_refresh_cached_fill(entry, linear, item.fill_rule)
		if refresh_error != .None { return refresh_error }
		if handled { cached = refreshed } else {
			job, need, build_error := vector_path_build_miss_job(handle, entry, linear, item.fill_rule)
			if build_error != .None { return build_error }
			if need {
				jobs := [1]Vector_Tess_Job{job}
				vector_tessellate_jobs_serial(jobs[:])
				if install_error := vector_path_install_tess_job(&jobs[0]); install_error != .None { return install_error }
				cached = jobs[0].cache_index
			} else { cached = vector_path_find_cache_index(entry, linear, item.fill_rule) }
			if cached < 0 { return .Invalid_Path }
		}
	}
	alpha := f32(root.opacity * item.fill_opacity) * opacity
	if entry.svg_mesh_only {
		if !(alpha >= 0 && alpha <= 1) { return .Invalid_Value }
		if item.fill.solid.a == 0 || alpha * draw_opacity == 0 { return .None }
		paint := Vector_Paint_GPU{colour = rgba_to_f32(item.fill.solid)}
		paint.colour[3] *= alpha * draw_opacity
		geometry := &entry.cache[cached]
		geometry.last_used = state.ui.frame
		morph := Vector_Transform{transform[0], transform[1], transform[2], transform[3], 0, 0}
		return vector_record_cached_mesh(geometry.mesh.vertices[:], geometry.mesh.indices[:], geometry.bounds,
			origin, paint, geometry.geometry_id, morph, &geometry.recorded_geometry, recording)
	}
	if record_error := vector_path_record_cached_fast(entry, cached, item.fill, transform, alpha,
		Vector_Identity, {}, dpi_zoom, draw_opacity, recording); record_error != .None { return record_error }
	return .None
}
