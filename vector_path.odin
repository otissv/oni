package oni

import v "./vector"
import "core:math"
import "core:mem"

Vector_Path_Command :: v.Command
Vector_Transform :: v.Affine
Vector_Fill_Rule :: v.Fill_Rule
Vector_Identity :: v.IDENTITY

Vector_Path_Handle :: struct {
	index, generation: u32,
}

@(private)
Vector_Path_Cache :: struct {
	linear: [4]f64,
	rule: Vector_Fill_Rule,
	op: Vector_Path_Op,
	stroke: Vector_Stroke,
	morph: Vector_Transform,
	mesh: v.Mesh,
	last_used: u64,
	valid: bool,
	bounds: Rect, // tessellated mesh AABB (draw space)
	local_bounds: Rect, // path-local AABB for objectBoundingBox paints
	geometry_id: u64,
}

@(private)
Vector_Path_Entry :: struct {
	commands: []Vector_Path_Command,
	basis_commands: []Vector_Path_Command,
	morph: Vector_Transform,
	command_allocator: mem.Allocator,
	cache: [dynamic]Vector_Path_Cache,
	generation: u32,
	live: bool,
}

@(private)
VECTOR_CPU_CACHE_BUDGET :: u64(64 * 1024 * 1024)

// Bump when flatten / quantization / stroke approximation policy changes.
@(private)
VECTOR_GEOMETRY_POLICY_REVISION :: u64(2)

@(private)
vector_path_cache_rule :: proc(op: Vector_Path_Op, rule: Vector_Fill_Rule) -> Vector_Fill_Rule {
	// Stroke outlines always tessellate as nonzero coverage.
	return rule if op == .Fill else .Nonzero
}

@(private)
vector_path_miss_key :: proc(
	handle: Vector_Path_Handle,
	linear: [4]f64,
	rule: Vector_Fill_Rule,
	op: Vector_Path_Op = .Fill,
	stroke: Vector_Stroke = {},
	morph: Vector_Transform = Vector_Identity,
) -> [10]u64 {
	fp := vector_stroke_fingerprint(op, stroke, morph if op == .Stroke else Vector_Identity)
	cache_rule := vector_path_cache_rule(op, rule)
	return [10]u64 {
		u64(handle.index),
		u64(handle.generation),
		transmute(u64)linear[0],
		transmute(u64)linear[1],
		transmute(u64)linear[2],
		transmute(u64)linear[3],
		u64(cache_rule) | (u64(op) << 8) | (VECTOR_GEOMETRY_POLICY_REVISION << 16),
		fp[0],
		fp[1],
		VECTOR_GEOMETRY_POLICY_REVISION,
	}
}

@(private)
vector_path_job_burst_bytes :: proc(job: Vector_Tess_Job) -> u64 {
	// Admit on snapshot cost only; uninstalled mesh bytes are bounded by the
	// retained CPU cache budget at install time. Worker scratch is reserved once
	// per burst outside this helper.
	return u64(len(job.commands)) * u64(size_of(Vector_Path_Command))
}


@(private)
vector_path_error :: proc(err: v.Error) -> Vector_Error {
	switch err {
	case .None:
		return .None
	case .Invalid_Path:
		return .Invalid_Path
	case .Invalid_Value:
		return .Invalid_Value
	case .Limit_Exceeded, .Mesh_Memory_Limit:
		return .Limit_Exceeded
	case .Allocation_Failed:
		return .Allocation_Failed
	}
	return .Invalid_Path
}

@(private)
vector_path_entry :: proc(handle: Vector_Path_Handle) -> ^Vector_Path_Entry {
	if state == nil || handle.index == 0 || u64(handle.index) > u64(len(state.vector.paths)) {
		return nil
	}
	entry := &state.vector.paths[handle.index - 1]
	if !entry.live || entry.generation != handle.generation {
		return nil
	}
	return entry
}

@(private)
vector_path_cache_bytes :: proc(mesh: v.Mesh) -> u64 {
	return u64(cap(mesh.vertices)) * size_of([2]f32) + u64(cap(mesh.indices)) * size_of(u32)
}

@(private)
vector_path_clear_cache :: proc(entry: ^Vector_Path_Entry) {
	vector_owner_assert_no_tess_workers()
	state.vector.path_cache_bytes -= u64(cap(entry.cache)) * size_of(Vector_Path_Cache)
	for &cached in entry.cache {
		state.vector.path_cache_bytes -= vector_path_cache_bytes(cached.mesh)
		v.Destroy_Mesh(&cached.mesh)
		vector_stroke_release_dash(&cached.stroke)
	}
	delete(entry.cache)
	entry.cache = nil
}

@(private)
vector_paths_shutdown :: proc() {
	vector_tess_pool_shutdown()
	for &entry in state.vector.paths {
		vector_path_clear_cache(&entry)
		delete(entry.commands, entry.command_allocator)
		delete(entry.basis_commands, entry.command_allocator)
	}
	delete(state.vector.paths)
	state.vector.paths = nil
	state.vector.path_cache_bytes = 0
}

/*
Spec for Prefetch / Ensure: tessellate and cache the linear transform of `transform`.
*/
Vector_Path_Tess_Spec :: struct {
	handle:    Vector_Path_Handle,
	transform: Vector_Transform,
	rule:      Vector_Fill_Rule,
	op:        Vector_Path_Op,
	stroke:    Vector_Stroke,
}

/*
One path draw for `Draw_Vector_Paths` (batch miss tessellation then record).
*/
Vector_Path_Draw :: struct {
	handle:         Vector_Path_Handle,
	paint:          Vector_Paint,
	transform:      Vector_Transform,
	rule:           Vector_Fill_Rule,
	opacity:        f32,
	instance_morph: Vector_Transform,
	op:             Vector_Path_Op,
	stroke:         Vector_Stroke,
	current_color:  RGBA,
}

@(private)
vector_path_draw_linear :: proc(transform: Vector_Transform) -> [4]f64 {
	zoom := view_artboard_zoom()
	scale := f64(state.dpi.scale * zoom)
	return {transform[0] * scale, transform[1] * scale, transform[2] * scale, transform[3] * scale}
}

// Struct-zero Affine is not identity. Match Draw_Vector_Path's default parameter so
// unset Vector_Path_Draw.instance_morph does not collapse tessellated geometry.
@(private)
vector_path_normalize_morph :: proc(morph: Vector_Transform) -> Vector_Transform {
	if morph == {} {
		return Vector_Identity
	}

	return morph
}

@(private)
vector_path_find_cache_index :: proc(
	entry: ^Vector_Path_Entry,
	linear: [4]f64,
	rule: Vector_Fill_Rule,
	op: Vector_Path_Op = .Fill,
	stroke: Vector_Stroke = {},
	morph: Vector_Transform = Vector_Identity,
) -> int {
	cache_rule := vector_path_cache_rule(op, rule)
	for cached, i in entry.cache {
		if cached.linear == linear && cached.rule == cache_rule && cached.op == op {
			if op == .Fill {
				return i
			}

			if vector_stroke_same(cached.stroke, stroke) && cached.morph == morph {
				return i
			}
		}
	}

	return -1
}

@(private)
vector_path_invalidate_stroke_cache :: proc(entry: ^Vector_Path_Entry) {
	if entry == nil {
		return
	}

	vector_owner_assert_no_tess_workers()
	for &cached in entry.cache {
		if cached.op == .Stroke {
			cached.valid = false
		}
	}
}

@(private)
vector_path_mesh_bounds :: proc(mesh: v.Mesh) -> Rect {
	if len(mesh.vertices) == 0 {
		return {}
	}

	lo, hi := mesh.vertices[0], mesh.vertices[0]
	for point in mesh.vertices[1:] {
		lo = {min(lo.x, point.x), min(lo.y, point.y)}
		hi = {max(hi.x, point.x), max(hi.y, point.y)}
	}

	return {lo.x, lo.y, hi.x - lo.x, hi.y - lo.y}
}

@(private)
vector_path_ensure_basis_commands :: proc(entry: ^Vector_Path_Entry) -> Vector_Error {
	if len(entry.basis_commands) > 0 {
		return .None
	}

	basis_owned, basis_err := make([]Vector_Path_Command, len(entry.commands), entry.command_allocator)
	if basis_err != nil {
		return .Allocation_Failed
	}

	copy(basis_owned, entry.commands)
	entry.basis_commands = basis_owned

	return .None
}

/*
Reserves or reuses a cache slot for `linear`/`rule` without tessellating.

Returns the cache index, or a negative Vector_Error cast is not used — err on failure.
*/
@(private)
vector_path_prepare_cache_slot :: proc(
	handle: Vector_Path_Handle,
	entry: ^Vector_Path_Entry,
	linear: [4]f64,
	rule: Vector_Fill_Rule,
	op: Vector_Path_Op = .Fill,
	stroke: Vector_Stroke = {},
	morph: Vector_Transform = Vector_Identity,
) -> (
	cache_index: int,
	err: Vector_Error,
) {
	vector_owner_assert_no_tess_workers()
	cache_index = vector_path_find_cache_index(entry, linear, rule, op, stroke, morph)
	if cache_index >= 0 && entry.cache[cache_index].valid {
		return cache_index, .None
	}

	if state.vector.next_geometry_id == max(u64) {
		return -1, .Limit_Exceeded
	}

	owned_stroke: Vector_Stroke
	if op == .Stroke {
		owned_stroke, err = vector_stroke_copy_dash(stroke, context.allocator)
		if err != .None {
			return -1, err
		}
	}

	if cache_index < 0 {
		metadata_bytes := u64(max(4, cap(entry.cache) * 2) - cap(entry.cache)) * size_of(Vector_Path_Cache)
		if len(entry.cache) == cap(entry.cache) {
			if !vector_path_evict_cache(metadata_bytes, int(handle.index - 1)) {
				vector_stroke_release_dash(&owned_stroke)
				return -1, .Limit_Exceeded
			}

			if reserve(&entry.cache, max(4, cap(entry.cache) * 2)) != nil {
				vector_stroke_release_dash(&owned_stroke)
				return -1, .Allocation_Failed
			}

			state.vector.path_cache_bytes += metadata_bytes
		}

		cache_index = len(entry.cache)
		append(&entry.cache, Vector_Path_Cache{linear = linear, rule = vector_path_cache_rule(op, rule), op = op})
	}

	mesh := entry.cache[cache_index].mesh
	state.vector.path_cache_bytes -= vector_path_cache_bytes(mesh)
	v.Destroy_Mesh(&mesh)
	vector_stroke_release_dash(&entry.cache[cache_index].stroke)
	entry.cache[cache_index].mesh = {}
	entry.cache[cache_index].valid = false
	entry.cache[cache_index].linear = linear
	entry.cache[cache_index].rule = vector_path_cache_rule(op, rule)
	entry.cache[cache_index].op = op
	entry.cache[cache_index].stroke = owned_stroke
	entry.cache[cache_index].morph = morph if op == .Stroke else Vector_Identity

	return cache_index, .None
}

@(private)
vector_path_frame_tess_limits :: proc() -> (limits: v.Limits, err: Vector_Error) {
	limits = v.DEFAULT_LIMITS
	limits.max_flattened_segments = min(limits.max_flattened_segments, VECTOR_MAX_NEW_SEGMENTS - vector_frame().new_segments)
	limits.max_triangles = min(limits.max_triangles, VECTOR_MAX_NEW_TRIANGLES - vector_frame().new_triangles)
	if limits.max_flattened_segments <= 0 || limits.max_triangles <= 0 {
		return {}, .Limit_Exceeded
	}

	limits.max_mesh_bytes = int(VECTOR_CPU_CACHE_BUDGET - state.vector.path_cache_bytes)

	return limits, .None
}

@(private)
vector_path_install_tess_job :: proc(job: ^Vector_Tess_Job) -> Vector_Error {
	vector_owner_assert_no_tess_workers()
	entry := vector_path_entry(job.handle)
	if entry == nil || entry.generation != job.generation {
		v.Destroy_Mesh(&job.mesh)
		delete(job.commands)
		job.commands = nil
		vector_stroke_release_dash(&job.stroke)

		return .Invalid_Handle
	}

	slot := job.cache_index
	if slot < 0 ||
	   slot >= len(entry.cache) ||
	   entry.cache[slot].linear != job.linear ||
	   entry.cache[slot].rule != job.rule ||
	   entry.cache[slot].op != job.op ||
	   (job.op == .Stroke && (!vector_stroke_same(entry.cache[slot].stroke, job.stroke) || entry.cache[slot].morph != job.morph)) {
		// Slot was reused or key changed while workers ran — drop stale mesh.
		v.Destroy_Mesh(&job.mesh)
		delete(job.commands)
		job.commands = nil
		vector_stroke_release_dash(&job.stroke)

		return .Invalid_Handle
	}

	vector_frame().new_segments += job.usage.flattened_segments
	vector_frame().new_triangles += job.usage.triangles

	cache_index := job.cache_index
	protected_path := int(job.handle.index - 1)
	err := job.err

	if err == .Mesh_Memory_Limit {
		_ = vector_path_evict_cache(VECTOR_CPU_CACHE_BUDGET, protected_path, &cache_index)
		job.cache_index = cache_index
		limits := job.limits
		limits.max_mesh_bytes = int(VECTOR_CPU_CACHE_BUDGET - state.vector.path_cache_bytes)
		limits.max_flattened_segments = min(v.DEFAULT_LIMITS.max_flattened_segments, VECTOR_MAX_NEW_SEGMENTS - vector_frame().new_segments)
		limits.max_triangles = min(v.DEFAULT_LIMITS.max_triangles, VECTOR_MAX_NEW_TRIANGLES - vector_frame().new_triangles)
		if limits.max_flattened_segments > 0 && limits.max_triangles > 0 {
			usage: v.Build_Usage
			if job.op == .Stroke {
				stroke_transform := vector_stroke_tess_transform(job.linear, job.morph)
				err = v.Tessellate_Stroke_Into(&job.mesh, job.commands, stroke_transform, job.stroke, limits, context.temp_allocator, &usage)
			} else {
				linear := v.Affine{job.linear[0], job.linear[1], job.linear[2], job.linear[3], 0, 0}
				err = v.Tessellate_Into(&job.mesh, job.commands, linear, job.rule, limits, context.temp_allocator, &usage)
			}
			vector_frame().new_segments += usage.flattened_segments
			vector_frame().new_triangles += usage.triangles
		}
	}

	defer {
		delete(job.commands)
		job.commands = nil
		vector_stroke_release_dash(&job.stroke)
	}

	if err != .None {
		v.Destroy_Mesh(&job.mesh)

		return vector_path_error(err)
	}

	bytes := vector_path_cache_bytes(job.mesh)
	if !vector_path_evict_cache(bytes, protected_path, &cache_index) {
		v.Destroy_Mesh(&job.mesh)

		return .Limit_Exceeded
	}

	if basis_err := vector_path_ensure_basis_commands(entry); basis_err != .None {
		v.Destroy_Mesh(&job.mesh)

		return basis_err
	}

	local_bounds, local_err := vector_path_local_bounds(job.commands)
	if local_err != .None {
		v.Destroy_Mesh(&job.mesh)

		return vector_path_error(local_err)
	}

	state.vector.next_geometry_id += 1
	state.vector.gpu.geometry_epoch += 1
	entry.cache[cache_index].linear = job.linear
	entry.cache[cache_index].rule = vector_path_cache_rule(job.op, job.rule)
	entry.cache[cache_index].op = job.op
	entry.cache[cache_index].morph = job.morph if job.op == .Stroke else Vector_Identity
	entry.cache[cache_index].mesh = job.mesh
	entry.cache[cache_index].valid = true
	entry.cache[cache_index].bounds = vector_path_mesh_bounds(job.mesh)
	entry.cache[cache_index].local_bounds = local_bounds
	entry.cache[cache_index].geometry_id = state.vector.next_geometry_id
	entry.cache[cache_index].last_used = state.ui.frame
	// Stroke dash ownership stays on the cache slot from prepare.
	job.mesh = {}
	job.cache_index = cache_index
	state.vector.path_cache_bytes += bytes

	return .None
}

@(private)
vector_path_local_bounds :: proc(commands: []Vector_Path_Command) -> (Rect, v.Error) {
	bounds, err := v.Geometry_Bounds(commands)
	if err != .None { return {}, err }
	return vector_paint_bounds_to_rect(bounds), .None
}

@(private)
vector_path_copy_commands_for_job :: proc(commands: []Vector_Path_Command) -> ([]Vector_Path_Command, Vector_Error) {
	owned, allocation_error := make([]Vector_Path_Command, len(commands))
	if allocation_error != nil {
		return nil, .Allocation_Failed
	}

	copy(owned, commands)

	return owned, .None
}

@(private)
vector_path_build_miss_job :: proc(
	handle: Vector_Path_Handle,
	entry: ^Vector_Path_Entry,
	linear: [4]f64,
	rule: Vector_Fill_Rule,
	op: Vector_Path_Op = .Fill,
	stroke: Vector_Stroke = {},
	morph: Vector_Transform = Vector_Identity,
) -> (
	job: Vector_Tess_Job,
	ok: bool,
	err: Vector_Error,
) {
	if err = vector_stroke_validate_draw(op, stroke); err != .None {
		return {}, false, err
	}

	stroke_morph := morph if op == .Stroke else Vector_Identity
	cache_index, prep_err := vector_path_prepare_cache_slot(handle, entry, linear, rule, op, stroke, stroke_morph)
	if prep_err != .None {
		return {}, false, prep_err
	}

	if entry.cache[cache_index].valid {
		return {}, false, .None
	}

	limits, lim_err := vector_path_frame_tess_limits()
	if lim_err != .None {
		return {}, false, lim_err
	}

	_ = vector_path_evict_cache(u64(64 * 1024), int(handle.index - 1), &cache_index)
	limits.max_mesh_bytes = int(VECTOR_CPU_CACHE_BUDGET - state.vector.path_cache_bytes)

	commands, copy_err := vector_path_copy_commands_for_job(entry.commands)
	if copy_err != .None {
		return {}, false, copy_err
	}

	job_stroke: Vector_Stroke
	if op == .Stroke {
		job_stroke, err = vector_stroke_copy_dash(stroke, context.allocator)
		if err != .None {
			delete(commands)
			return {}, false, err
		}
	}

	job = Vector_Tess_Job {
		commands    = commands,
		linear      = linear,
		rule        = rule,
		op          = op,
		stroke      = job_stroke,
		morph       = stroke_morph,
		limits      = limits,
		handle      = handle,
		generation  = entry.generation,
		cache_index = cache_index,
	}

	return job, true, .None
}

/*
Ensures cached meshes exist for each spec (sync; parallel when miss count ≥ threshold).
*/
Vector_Ensure_Path_Meshes :: proc(specs: []Vector_Path_Tess_Spec) -> Vector_Error {
	return Vector_Prefetch_Paths(specs)
}

/*
Prefetches path meshes for the given transforms (sync; font-style worker burst).
*/
Vector_Prefetch_Paths :: proc(specs: []Vector_Path_Tess_Spec) -> Vector_Error {
	if state == nil {
		return .Invalid_Handle
	}

	if len(specs) == 0 {
		return .None
	}

	jobs := make([dynamic]Vector_Tess_Job, 0, len(specs), context.temp_allocator)
	defer {
		for &job in jobs {
			if job.commands != nil {
				delete(job.commands)
				job.commands = nil
			}

			vector_stroke_release_dash(&job.stroke)
			v.Destroy_Mesh(&job.mesh)
		}
	}

	seen := make(map[[10]u64]bool, context.temp_allocator)
	burst_bytes := u64(VECTOR_TESS_MAX_WORKERS) * u64(VECTOR_TESS_WORKER_SCRATCH)

	for spec in specs {
		for value in spec.transform {
			if math.is_nan(value) || math.is_inf(value) {
				return .Invalid_Value
			}
		}

		entry := vector_path_entry(spec.handle)
		if entry == nil {
			return .Invalid_Handle
		}

		if err := vector_stroke_validate_draw(spec.op, spec.stroke); err != .None {
			return err
		}

		linear := vector_path_draw_linear(spec.transform)
		morph := vector_stroke_draw_morph(entry, Vector_Identity) if spec.op == .Stroke else Vector_Identity
		key := vector_path_miss_key(spec.handle, linear, spec.rule, spec.op, spec.stroke, morph)
		if seen[key] {
			continue
		}

		seen[key] = true
		job, need, err := vector_path_build_miss_job(spec.handle, entry, linear, spec.rule, spec.op, spec.stroke, morph)
		if err != .None {
			return err
		}

		if need {
			if len(jobs) >= VECTOR_TESS_MAX_JOBS_PER_BURST {
				delete(job.commands)
				job.commands = nil
				vector_stroke_release_dash(&job.stroke)

				return .Limit_Exceeded
			}

			cost := vector_path_job_burst_bytes(job)
			if burst_bytes + cost > VECTOR_TESS_BURST_MEMORY {
				delete(job.commands)
				job.commands = nil
				vector_stroke_release_dash(&job.stroke)

				return .Limit_Exceeded
			}

			burst_bytes += cost
			append(&jobs, job)
		}
	}

	if len(jobs) == 0 {
		return .None
	}

	vector_tess_assign_exclusive_quotas(jobs[:])
	vector_tessellate_jobs(jobs[:])

	first_err := Vector_Error.None
	for &job in jobs {
		install_err := vector_path_install_tess_job(&job)
		if first_err == .None && install_err != .None {
			first_err = install_err
		}
	}

	return first_err
}

@(private)
vector_path_record_cached :: proc(
	handle: Vector_Path_Handle,
	entry: ^Vector_Path_Entry,
	cache_index: int,
	paint: Vector_Paint,
	transform: Vector_Transform,
	opacity: f32,
	instance_morph: Vector_Transform,
	current_color: RGBA = {0, 0, 0, 255},
) -> Vector_Error {
	entry.cache[cache_index].last_used = state.ui.frame
	mesh := entry.cache[cache_index].mesh
	origin := view_transform_point({f32(transform[4]), f32(transform[5])}) * state.dpi.scale
	normalized_morph := vector_path_normalize_morph(instance_morph)
	morph := Vector_Identity
	if entry.cache[cache_index].op != .Stroke {
		morph = v.Affine_Compose(entry.morph, normalized_morph)
		if morph != Vector_Identity {
			linear := v.Affine {
				entry.cache[cache_index].linear[0],
				entry.cache[cache_index].linear[1],
				entry.cache[cache_index].linear[2],
				entry.cache[cache_index].linear[3],
				0,
				0,
			}
			if linear != v.IDENTITY {
				if inverse, ok := v.Affine_Invert(linear); ok {
					morph = v.Affine_Compose(linear, v.Affine_Compose(morph, inverse))
				} else {
					morph = Vector_Identity
				}
			}
		}
	}

	gpu_paint, skip, paint_err := vector_paint_resolve(
		paint,
		opacity,
		entry.cache[cache_index].linear,
		entry.cache[cache_index].local_bounds,
		current_color,
	)
	if paint_err != .None {
		return paint_err
	}

	if skip {
		return .None
	}

	return vector_record_cached_mesh(
		mesh.vertices[:],
		mesh.indices[:],
		entry.cache[cache_index].bounds,
		origin,
		gpu_paint,
		entry.cache[cache_index].geometry_id,
		morph,
	)
}

/*
Draws many paths; unique cache misses tessellate in a parallel burst then record.
*/
Draw_Vector_Paths :: proc(items: []Vector_Path_Draw) -> Vector_Error {
	if state == nil || ui_pass() != .Draw {
		return .None
	}

	if len(items) == 0 {
		return .None
	}

	if len(items) == 1 {
		item := items[0]
		return Draw_Vector_Path(
			item.handle,
			item.paint,
			item.transform,
			item.rule,
			item.opacity,
			item.instance_morph,
			item.op,
			item.stroke,
			item.current_color,
		)
	}

	jobs: [dynamic]Vector_Tess_Job
	defer {
		for &job in jobs {
			if job.commands != nil {
				delete(job.commands)
				job.commands = nil
			}

			vector_stroke_release_dash(&job.stroke)
			v.Destroy_Mesh(&job.mesh)
		}
	}

	// Deduplicate miss keys (handle index + linear + rule) within this batch.
	seen: map[[10]u64]bool
	burst_bytes := u64(VECTOR_TESS_MAX_WORKERS) * u64(VECTOR_TESS_WORKER_SCRATCH)
	first_err := Vector_Error.None

	for item in items {
		for value in item.transform {
			if math.is_nan(value) || math.is_inf(value) {
				return .Invalid_Value
			}
		}

		if !(item.opacity >= 0 && item.opacity <= 1) {
			return .Invalid_Value
		}

		entry := vector_path_entry(item.handle)
		if entry == nil {
			return .Invalid_Handle
		}

		if err := vector_stroke_validate_draw(item.op, item.stroke); err != .None {
			return err
		}

		linear := vector_path_draw_linear(item.transform)
		morph := vector_stroke_draw_morph(entry, item.instance_morph) if item.op == .Stroke else Vector_Identity
		cache_index := vector_path_find_cache_index(entry, linear, item.rule, item.op, item.stroke, morph)
		if cache_index >= 0 && entry.cache[cache_index].valid {
			continue
		}

		if cap(jobs) == 0 {
			jobs = make([dynamic]Vector_Tess_Job, 0, min(len(items), VECTOR_TESS_MAX_JOBS_PER_BURST), context.temp_allocator)
			seen = make(map[[10]u64]bool, context.temp_allocator)
		}

		key := vector_path_miss_key(item.handle, linear, item.rule, item.op, item.stroke, morph)
		if seen[key] {
			continue
		}

		seen[key] = true
		job, need, err := vector_path_build_miss_job(item.handle, entry, linear, item.rule, item.op, item.stroke, morph)
		if err != .None {
			return err
		}

		if need {
			if len(jobs) >= VECTOR_TESS_MAX_JOBS_PER_BURST {
				delete(job.commands)
				job.commands = nil
				vector_stroke_release_dash(&job.stroke)
				if first_err == .None {
					first_err = .Limit_Exceeded
				}

				continue
			}

			cost := vector_path_job_burst_bytes(job)
			if burst_bytes + cost > VECTOR_TESS_BURST_MEMORY {
				delete(job.commands)
				job.commands = nil
				vector_stroke_release_dash(&job.stroke)
				if first_err == .None {
					first_err = .Limit_Exceeded
				}

				continue
			}

			burst_bytes += cost
			append(&jobs, job)
		}
	}

	if len(jobs) > 0 {
		vector_tess_assign_exclusive_quotas(jobs[:])
		vector_tessellate_jobs(jobs[:])
		for &job in jobs {
			if install_err := vector_path_install_tess_job(&job); install_err != .None {
				if first_err == .None {
					first_err = install_err
				}
			}
		}
	}

	for item in items {
		entry := vector_path_entry(item.handle)
		if entry == nil {
			if first_err == .None {
				first_err = .Invalid_Handle
			}

			continue
		}

		linear := vector_path_draw_linear(item.transform)
		morph := vector_stroke_draw_morph(entry, item.instance_morph) if item.op == .Stroke else Vector_Identity
		cache_index := vector_path_find_cache_index(entry, linear, item.rule, item.op, item.stroke, morph)
		if cache_index < 0 || !entry.cache[cache_index].valid {
			if err := Draw_Vector_Path(
				item.handle,
				item.paint,
				item.transform,
				item.rule,
				item.opacity,
				item.instance_morph,
				item.op,
				item.stroke,
				item.current_color,
			); err != .None && first_err == .None {
				first_err = err
			}

			continue
		}

		if err := vector_path_record_cached(
			item.handle,
			entry,
			cache_index,
			item.paint,
			item.transform,
			item.opacity,
			item.instance_morph,
			item.current_color,
		); err != .None && first_err == .None {
			first_err = err
		}
	}

	return first_err
}

@(private)
vector_copy_path_commands :: proc(commands: []Vector_Path_Command) -> (owned: []Vector_Path_Command, err: Vector_Error) {
	if len(commands) > v.DEFAULT_LIMITS.max_commands || len(commands) > (64 * 1024 * 1024) / size_of(Vector_Path_Command) {
		return {}, .Limit_Exceeded
	}
	validation_error := v.Validate_Commands(commands)
	if validation_error != .None {
		return {}, vector_path_error(validation_error)
	}
	var_owned, allocation_error := make([]Vector_Path_Command, len(commands))
	if allocation_error != nil {
		return {}, .Allocation_Failed
	}
	copy(var_owned, commands)
	return var_owned, .None
}

// Copies command data; the caller retains ownership of the supplied slice.
Vector_Create_Path :: proc(commands: []Vector_Path_Command) -> (handle: Vector_Path_Handle, err: Vector_Error) {
	if state == nil {
		return {}, .Invalid_Handle
	}
	owned, copy_error := vector_copy_path_commands(commands)
	if copy_error != .None {
		return {}, copy_error
	}
	for &entry, i in state.vector.paths {
		if !entry.live && entry.generation < max(u32) {
			entry.commands = owned
			entry.basis_commands = nil
			entry.morph = Vector_Identity
			entry.command_allocator = context.allocator
			entry.live = true
			return {index = u32(i + 1), generation = entry.generation}, .None
		}
	}
	if _, append_error := append(&state.vector.paths, Vector_Path_Entry{commands = owned, morph = Vector_Identity, command_allocator = context.allocator, generation = 1, live = true}); append_error != nil {
		delete(owned)
		return {}, .Allocation_Failed
	}
	return {index = u32(len(state.vector.paths)), generation = 1}, .None
}

// Sets an affine morph relative to the path's retained basis commands.
// Fill caches stay shared; Draw applies the morph on the GPU. Stroke geometry is
// baked with morph, so stroke cache slots are invalidated here.
Vector_Set_Path_Morph :: proc(handle: Vector_Path_Handle, morph: Vector_Transform) -> Vector_Error {
	entry := vector_path_entry(handle)
	if entry == nil {
		return .Invalid_Handle
	}
	for value in morph {
		if math.is_nan(value) || math.is_inf(value) {
			return .Invalid_Value
		}
	}
	entry.morph = morph
	vector_path_invalidate_stroke_cache(entry)
	return .None
}

Vector_Destroy_Path :: proc(handle: Vector_Path_Handle) -> Vector_Error {
	entry := vector_path_entry(handle)
	if entry == nil {
		return .Invalid_Handle
	}

	if state.vector.tess_workers != 0 {
		return .Invalid_Value
	}

	vector_path_clear_cache(entry)
	delete(entry.commands, entry.command_allocator)
	delete(entry.basis_commands, entry.command_allocator)
	entry.commands = nil
	entry.basis_commands = nil
	entry.command_allocator = {}
	entry.live = false
	if entry.generation < max(u32) {
		entry.generation += 1
	}
	return .None
}

// Validates and allocates the replacement before invalidating old geometry.
// Compatible control-point edits that are a single affine update `morph` so
// fill basis meshes stay shared (GPU morph). Stroke slots are invalidated because
// stroke meshes bake morph into tessellated outlines.
Vector_Update_Path :: proc(handle: Vector_Path_Handle, commands: []Vector_Path_Command) -> Vector_Error {
	entry := vector_path_entry(handle)
	if entry == nil {
		return .Invalid_Handle
	}

	if state.vector.tess_workers != 0 {
		return .Invalid_Value
	}

	if len(commands) > (64 * 1024 * 1024) / size_of(Vector_Path_Command) || len(commands) > v.DEFAULT_LIMITS.max_commands {
		return .Limit_Exceeded
	}
	basis := entry.basis_commands if len(entry.basis_commands) > 0 else entry.commands
	if affine, ok := v.Commands_Affine(basis, commands); ok {
		entry.morph = affine
		vector_path_invalidate_stroke_cache(entry)
		return .None
	}
	if err := v.Validate_Commands(commands); err != .None {
		return vector_path_error(err)
	}
	if len(commands) == len(entry.commands) {
		copy(entry.commands, commands)
	} else {
		owned, allocation_error := make([]Vector_Path_Command, len(commands), entry.command_allocator)
		if allocation_error != nil {
			return .Allocation_Failed
		}
		copy(owned, commands)
		delete(entry.commands, entry.command_allocator)
		entry.commands = owned
	}
	delete(entry.basis_commands, entry.command_allocator)
	entry.basis_commands = nil
	entry.morph = Vector_Identity
	for &cached in entry.cache {
		cached.valid = false
	}
	return .None
}

@(private)
vector_path_evict_cache :: proc(required: u64, protected_path: int = -1, protected_cache: ^int = nil) -> bool {
	vector_owner_assert_no_tess_workers()
	if required > VECTOR_CPU_CACHE_BUDGET {
		return false
	}
	for state.vector.path_cache_bytes > VECTOR_CPU_CACHE_BUDGET - required {
		old_path, old_cache := -1, -1
		old_frame := max(u64)
		for entry, i in state.vector.paths {
			for cached, j in entry.cache {
				if i == protected_path && (protected_cache == nil || j == protected_cache^) { continue }
				if cached.last_used <= old_frame {
					old_frame, old_path, old_cache = cached.last_used, i, j
				}
			}
		}
		if old_path < 0 {
			return false
		}
		entry := &state.vector.paths[old_path]
		state.vector.path_cache_bytes -= vector_path_cache_bytes(entry.cache[old_cache].mesh)
		v.Destroy_Mesh(&entry.cache[old_cache].mesh)
		vector_stroke_release_dash(&entry.cache[old_cache].stroke)
		if old_path == protected_path && protected_cache != nil && protected_cache^ == len(entry.cache) - 1 {
			protected_cache^ = old_cache
		}
		unordered_remove(&entry.cache, old_cache)
		if len(entry.cache) == 0 {
			state.vector.path_cache_bytes -= u64(cap(entry.cache)) * size_of(Vector_Path_Cache)
			delete(entry.cache)
			entry.cache = nil
		}
	}
	return true
}

// Geometry is cached independently of translation and paint. Recorded scenes
// copy the resulting mesh and paint ramps, so later updates/releases cannot
// invalidate the current frame. Cache misses tessellate serially (batch misses
// use Draw_Vector_Paths / Prefetch).
draw_vector_path_paint :: proc(
	handle: Vector_Path_Handle,
	paint: Vector_Paint,
	transform: Vector_Transform = Vector_Identity,
	rule: Vector_Fill_Rule = .Nonzero,
	opacity: f32 = 1,
	instance_morph: Vector_Transform = Vector_Identity,
	op: Vector_Path_Op = .Fill,
	stroke: Vector_Stroke = {},
	current_color: RGBA = {0, 0, 0, 255},
) -> Vector_Error {
	if state == nil || ui_pass() != .Draw {
		return .None
	}

	entry := vector_path_entry(handle)
	if entry == nil {
		return .Invalid_Handle
	}

	for value in transform {
		if math.is_nan(value) || math.is_inf(value) {
			return .Invalid_Value
		}
	}

	if !(opacity >= 0 && opacity <= 1) {
		return .Invalid_Value
	}

	if err := vector_stroke_validate_draw(op, stroke); err != .None {
		return err
	}

	linear := vector_path_draw_linear(transform)
	morph := vector_stroke_draw_morph(entry, instance_morph) if op == .Stroke else Vector_Identity
	cache_index := vector_path_find_cache_index(entry, linear, rule, op, stroke, morph)
	if cache_index < 0 || !entry.cache[cache_index].valid {
		job, need, build_err := vector_path_build_miss_job(handle, entry, linear, rule, op, stroke, morph)
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
			cache_index = vector_path_find_cache_index(entry, linear, rule, op, stroke, morph)
		}
	}

	if cache_index < 0 || !entry.cache[cache_index].valid {
		return .Invalid_Path
	}

	return vector_path_record_cached(
		handle,
		entry,
		cache_index,
		paint,
		transform,
		opacity,
		instance_morph,
		current_color,
	)
}

draw_vector_path_solid :: proc(
	handle: Vector_Path_Handle,
	colour: RGBA,
	transform: Vector_Transform = Vector_Identity,
	rule: Vector_Fill_Rule = .Nonzero,
	opacity: f32 = 1,
	instance_morph: Vector_Transform = Vector_Identity,
	op: Vector_Path_Op = .Fill,
	stroke: Vector_Stroke = {},
	current_color: RGBA = {0, 0, 0, 255},
) -> Vector_Error {
	return draw_vector_path_paint(
		handle,
		Solid_Paint(colour),
		transform,
		rule,
		opacity,
		instance_morph,
		op,
		stroke,
		current_color,
	)
}

Draw_Vector_Path :: proc {
	draw_vector_path_paint,
	draw_vector_path_solid,
}
