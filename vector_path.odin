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
Vector_Path_Cache :: struct #align(64) {
	linear: [4]f64,
	policy_revision: u64,
	rule: Vector_Fill_Rule,
	op: Vector_Path_Op,
	valid: bool,
	pending: bool,
	geometry_id: u64,
	bounds: Rect, // tessellated mesh AABB (draw space)
	local_bounds: Rect, // path-local AABB for objectBoundingBox paints
	mesh: v.Mesh,
	last_used: u64,
	geometry_vertex_count: int,
	geometry_index_count: int,
	recorded_geometry: Vector_Recorded_Geometry,
	morph: Vector_Transform,
	stroke: Vector_Stroke,
	stroke_allocator: mem.Allocator,
}

#assert(offset_of(Vector_Path_Cache, pending) < 64)

@(private)
Vector_Path_Cache_Key :: struct {
	linear:          [4]f64,
	rule:            Vector_Fill_Rule,
	op:              Vector_Path_Op,
	policy_revision: u64,
	stroke_fp:       [2]u64,
	morph:           Vector_Transform,
}

@(private)
Vector_Path_Entry :: struct #align(64) {
	generation: u32,
	live: bool,
	cache: [dynamic]Vector_Path_Cache,
	morph: Vector_Transform,
	commands: []Vector_Path_Command,
	basis_commands: []Vector_Path_Command,
	command_allocator: mem.Allocator,
	cache_lookup: map[Vector_Path_Cache_Key]int,
	command_revision: u64,
	memo_local_bounds: Rect,
	memo_local_bounds_revision: u64,
	// False after a non-affine Update_Path; skips repeated Commands_Affine until structure resets.
	affine_solvable: bool,
	// False after uniform stable remesh fails for this path (self-intersecting /
	// non-convex rings); subsequent morph remeshes stay adaptive.
	morph_uniform_ok: bool,
	svg_retained: bool,
	// Mesh-only SVG entries borrow commands only during synchronous recording.
	svg_mesh_only: bool,
	svg_key: [2]u64,
	svg_command_hash: [2]u64,
	svg_structure: [2]u64,
	svg_lru_prev, svg_lru_next: Vector_Path_Handle,
	last_used: u64,
}

@(private)
VECTOR_CPU_CACHE_BUDGET :: u64(64 * 1024 * 1024)

// Bump when flatten / quantization / stroke approximation policy changes.
@(private)
VECTOR_GEOMETRY_POLICY_REVISION :: u64(5)

// Fill meshes tessellate under dpi×zoom isotropic basis only; draw rotation/scale
// and path morph run as GPU morph (MSAA + basis flatten at DPI for edge AA).
@(private)
vector_path_basis_scale :: proc() -> f64 {
	return f64(state.dpi.scale * view_artboard_zoom())
}

@(private)
vector_path_fill_tess_linear :: proc() -> [4]f64 {
	scale := vector_path_basis_scale()

	return {scale, 0, 0, scale}
}

@(private)
vector_path_tess_linear :: proc(op: Vector_Path_Op, #by_ptr transform: Vector_Transform) -> [4]f64 {
	if op == .Fill {

		return vector_path_fill_tess_linear()
	}

	return vector_path_draw_linear(transform)
}

@(private)
vector_path_cache_key :: proc(
	linear: [4]f64,
	rule: Vector_Fill_Rule,
	op: Vector_Path_Op,
	stroke: Vector_Stroke,
	morph: Vector_Transform,
) -> Vector_Path_Cache_Key {
	cache_rule := vector_path_cache_rule(op, rule)
	stroke_morph := morph if op == .Stroke else Vector_Identity

	return {
		linear = linear,
		rule = cache_rule,
		op = op,
		policy_revision = VECTOR_GEOMETRY_POLICY_REVISION,
		stroke_fp = vector_stroke_fingerprint(op, stroke, stroke_morph),
		morph = stroke_morph,
	}
}

@(private)
vector_path_cache_key_from_cached :: proc(cached: ^Vector_Path_Cache) -> Vector_Path_Cache_Key {
	stroke_morph := cached.morph if cached.op == .Stroke else Vector_Identity

	return {
		linear = cached.linear,
		rule = cached.rule,
		op = cached.op,
		policy_revision = cached.policy_revision,
		stroke_fp = vector_stroke_fingerprint(cached.op, cached.stroke, stroke_morph),
		morph = stroke_morph,
	}
}

@(private)
vector_path_cache_unmap_slot :: proc(entry: ^Vector_Path_Entry, index: int) {
	if entry == nil || index < 0 || index >= len(entry.cache) {

		return
	}

	delete_key(&entry.cache_lookup, vector_path_cache_key_from_cached(&entry.cache[index]))
}

@(private)
vector_path_cache_map_slot :: proc(entry: ^Vector_Path_Entry, index: int) -> bool {
	if entry == nil || index < 0 || index >= len(entry.cache) {

		return false
	}
	if len(entry.cache) == 1 { return true }
	if reserve(&entry.cache_lookup, len(entry.cache)) != nil { return false }
	if len(entry.cache_lookup) == 0 {
		for &cached, i in entry.cache {
			entry.cache_lookup[vector_path_cache_key_from_cached(&cached)] = i
		}
		return true
	}

	entry.cache_lookup[vector_path_cache_key_from_cached(&entry.cache[index])] = index
	return true
}

@(private)
vector_path_bump_command_revision :: proc(entry: ^Vector_Path_Entry) {
	if entry == nil {

		return
	}

	if entry.command_revision < max(u64) {
		entry.command_revision += 1
	}
}

@(private)
vector_path_rebase_morph :: proc(basis: v.Affine, morph: Vector_Transform) -> Vector_Transform {
	if morph == Vector_Identity {

		return Vector_Identity
	}

	if basis == v.IDENTITY {

		return morph
	}

	if inverse, ok := v.Affine_Invert(basis); ok {

		return v.Affine_Compose(basis, v.Affine_Compose(morph, inverse))
	}

	return Vector_Identity
}

@(private)
vector_path_fill_gpu_morph :: proc(
	entry: ^Vector_Path_Entry,
	instance_morph: Vector_Transform,
	draw_linear: [4]f64,
	basis_linear: [4]f64,
) -> Vector_Transform {
	path_morph := v.Affine_Compose(entry.morph, vector_path_normalize_morph(instance_morph))
	scale := basis_linear[0]
	if scale == 0 { return Vector_Identity }
	draw_aff := v.Affine{draw_linear[0] / scale, draw_linear[1] / scale, draw_linear[2] / scale, draw_linear[3] / scale, 0, 0}
	// Isotropic dpi×zoom basis cancels under rebase, so Identity path morphs
	// upload the draw linear directly.
	if path_morph == Vector_Identity {
		return draw_aff
	}
	combined := v.Affine_Compose(draw_aff, path_morph)
	basis := v.Affine{basis_linear[0], basis_linear[1], basis_linear[2], basis_linear[3], 0, 0}

	return vector_path_rebase_morph(basis, combined)
}

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
	tess_linear := linear
	if op == .Fill {
		tess_linear = vector_path_fill_tess_linear()
	}

	return [10]u64 {
		u64(handle.index),
		u64(handle.generation),
		transmute(u64)tess_linear[0],
		transmute(u64)tess_linear[1],
		transmute(u64)tess_linear[2],
		transmute(u64)tess_linear[3],
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
vector_path_entry :: #force_inline proc(handle: Vector_Path_Handle) -> ^Vector_Path_Entry {
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
		state.vector.path_cache_bytes -= u64(len(cached.stroke.dash)) * size_of(f64)
		v.Destroy_Mesh(&cached.mesh)
		vector_stroke_release_dash(&cached.stroke, cached.stroke_allocator)
	}
	delete(entry.cache)
	entry.cache = nil
	delete(entry.cache_lookup)
	entry.cache_lookup = nil
}

@(private)
vector_paths_shutdown :: proc() {
	vector_svg_layout_cache_shutdown()
	vector_tess_pool_shutdown()
	delete(state.vector.tess_jobs)
	state.vector.tess_jobs = nil
	state.vector.tess_jobs_in_use = false
	for &entry in state.vector.paths {
		vector_path_clear_cache(&entry)
		if !entry.svg_mesh_only { delete(entry.commands, entry.command_allocator) }
		delete(entry.basis_commands, entry.command_allocator)
	}
	delete(state.vector.paths)
	delete(state.vector.svg_paths)
	delete(state.vector.path_free)
	state.vector.svg_paths = nil
	state.vector.path_free = nil
	state.vector.svg_path_bytes = 0
	state.vector.svg_lru_first = {}
	state.vector.svg_lru_last = {}
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
// Locates the cache slot for `key`. When `require_valid` is false, returns the
// slot even if geometry was invalidated (morph remesh keeps the mesh for
// Tessellate_Into reposition). Prefetch may include pending slots to deduplicate.
vector_path_find_cache_index :: #force_inline proc(
	entry: ^Vector_Path_Entry,
	linear: [4]f64,
	rule: Vector_Fill_Rule,
	op: Vector_Path_Op = .Fill,
	#by_ptr stroke: Vector_Stroke = {},
	morph: Vector_Transform = Vector_Identity,
	require_valid := true,
	allow_pending := false,
) -> int {
	if len(entry.cache) == 1 {
		cached := &entry.cache[0]
		if (!allow_pending && cached.pending) || (require_valid && !cached.valid) ||
		   cached.policy_revision != VECTOR_GEOMETRY_POLICY_REVISION ||
		   cached.linear != linear || cached.rule != vector_path_cache_rule(op, rule) || cached.op != op {
			return -1
		}
		if op == .Stroke && (!vector_stroke_same(cached.stroke, stroke) || cached.morph != morph) { return -1 }
		return 0
	}
	key := vector_path_cache_key(linear, rule, op, stroke, morph)
	index, ok := entry.cache_lookup[key]
	if !ok || index < 0 || index >= len(entry.cache) {

		return -1
	}

	cached := &entry.cache[index]
	if (!allow_pending && cached.pending) ||
	   cached.policy_revision != VECTOR_GEOMETRY_POLICY_REVISION ||
	   cached.linear != key.linear ||
	   cached.rule != key.rule ||
	   cached.op != key.op {

		return -1
	}

	if require_valid && !cached.valid {
		return -1
	}

	if op == .Stroke && (!vector_stroke_same(cached.stroke, stroke) || cached.morph != morph) {

		return -1
	}

	return index
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
	if entry.svg_mesh_only { return .None }
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
	// Include invalidated same-key slots so morph remesh can reposition.
	cache_index = vector_path_find_cache_index(entry, linear, rule, op, stroke, morph, require_valid = false)
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

	// Same-key remesh: keep mesh capacity for Tessellate_Into reuse.
	if cache_index >= 0 {
		if op == .Stroke {
			state.vector.path_cache_bytes -= u64(len(entry.cache[cache_index].stroke.dash)) * size_of(f64)
			vector_stroke_release_dash(&entry.cache[cache_index].stroke, entry.cache[cache_index].stroke_allocator)
			entry.cache[cache_index].stroke = owned_stroke
			entry.cache[cache_index].stroke_allocator = context.allocator
			state.vector.path_cache_bytes += u64(len(owned_stroke.dash)) * size_of(f64)
			entry.cache[cache_index].morph = morph
		} else {
			vector_stroke_release_dash(&owned_stroke)
			entry.cache[cache_index].morph = Vector_Identity
		}
		entry.cache[cache_index].valid = false
		entry.cache[cache_index].pending = false
		entry.cache[cache_index].policy_revision = VECTOR_GEOMETRY_POLICY_REVISION

		return cache_index, .None
	}

	if cache_index < 0 {
		for cached, i in entry.cache {
			if !cached.valid && !cached.pending {
				cache_index = i

				break
			}
		}
	}
	if cache_index >= 0 && !entry.cache[cache_index].valid && !entry.cache[cache_index].pending {
		vector_path_cache_unmap_slot(entry, cache_index)
	}
	if cache_index < 0 {
		metadata_bytes := u64(max(1, cap(entry.cache) * 2) - cap(entry.cache)) * size_of(Vector_Path_Cache)
		if len(entry.cache) == cap(entry.cache) {
			if !vector_path_evict_cache(metadata_bytes + u64(len(owned_stroke.dash)) * size_of(f64), int(handle.index - 1)) {
				vector_stroke_release_dash(&owned_stroke)

				return -1, .Limit_Exceeded
			}

			if reserve(&entry.cache, max(1, cap(entry.cache) * 2)) != nil {
				vector_stroke_release_dash(&owned_stroke)

				return -1, .Allocation_Failed
			}

			state.vector.path_cache_bytes += metadata_bytes
		}

		cache_index = len(entry.cache)
		append(&entry.cache, Vector_Path_Cache{linear = linear, rule = vector_path_cache_rule(op, rule), op = op})
	}

	state.vector.path_cache_bytes -= u64(len(entry.cache[cache_index].stroke.dash)) * size_of(f64)
	vector_stroke_release_dash(&entry.cache[cache_index].stroke, entry.cache[cache_index].stroke_allocator)
	state.vector.path_cache_bytes -= vector_path_cache_bytes(entry.cache[cache_index].mesh)
	v.Destroy_Mesh(&entry.cache[cache_index].mesh)
	entry.cache[cache_index].mesh = {}
	entry.cache[cache_index].valid = false
	entry.cache[cache_index].pending = false
	entry.cache[cache_index].linear = linear
	entry.cache[cache_index].rule = vector_path_cache_rule(op, rule)
	entry.cache[cache_index].op = op
	entry.cache[cache_index].stroke = owned_stroke
	entry.cache[cache_index].stroke_allocator = context.allocator
	entry.cache[cache_index].policy_revision = VECTOR_GEOMETRY_POLICY_REVISION
	entry.cache[cache_index].geometry_id = 0
	entry.cache[cache_index].geometry_vertex_count = 0
	entry.cache[cache_index].geometry_index_count = 0
	state.vector.path_cache_bytes += u64(len(owned_stroke.dash)) * size_of(f64)
	entry.cache[cache_index].morph = morph if op == .Stroke else Vector_Identity
	if !vector_path_cache_map_slot(entry, cache_index) { return -1, .Allocation_Failed }

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
	limits.max_pair_tests = min(limits.max_pair_tests, max(0, VECTOR_MAX_FRAME_PAIR_TESTS - vector_frame().pair_tests))
	limits.max_exact_ops = min(limits.max_exact_ops, max(0, VECTOR_MAX_FRAME_EXACT_OPS - vector_frame().exact_ops))

	return limits, .None
}

@(private)
vector_path_charge_tess_work :: #force_inline proc(#by_ptr usage: v.Build_Usage, #by_ptr limits: v.Limits, failed: bool) {
	f := vector_frame()
	f.new_segments += usage.flattened_segments
	f.new_triangles += usage.triangles
	f.pair_tests += usage.pair_tests
	f.exact_ops += usage.exact_ops
	if failed {
		state.vector.last_build_usage = usage
		state.vector.last_build_limits = limits
	}
}

@(private)
vector_path_install_tess_job :: proc(job: ^Vector_Tess_Job) -> Vector_Error {
	vector_owner_assert_no_tess_workers()
	vector_path_charge_tess_work(job.usage, job.limits, job.err != .None)
	entry := vector_path_entry(job.handle)
	if entry == nil || entry.generation != job.generation {
		v.Destroy_Mesh(&job.mesh)
		vector_path_release_job_commands(job)
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
		vector_path_release_job_commands(job)
		vector_stroke_release_dash(&job.stroke)

		return .Invalid_Handle
	}

	entry.cache[slot].pending = false

	// Keep morph_uniform_ok even when stable remesh misses (e.g. figure-8
	// sweeps the forced endpoint flatten). Clearing it forced adaptive
	// re-flatten on every subsequent morph frame.

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
		limits.max_pair_tests = min(v.DEFAULT_LIMITS.max_pair_tests, max(0, VECTOR_MAX_FRAME_PAIR_TESTS - vector_frame().pair_tests))
		limits.max_exact_ops = min(v.DEFAULT_LIMITS.max_exact_ops, max(0, VECTOR_MAX_FRAME_EXACT_OPS - vector_frame().exact_ops))
		if limits.max_flattened_segments > 0 && limits.max_triangles > 0 {
			usage: v.Build_Usage
			if job.op == .Stroke {
				stroke_transform := vector_stroke_tess_transform(job.linear, job.morph)
				err = v.Tessellate_Stroke_Into(&job.mesh, job.commands, stroke_transform, job.stroke, limits, context.temp_allocator, &usage)
			} else {
				linear := v.Affine{job.linear[0], job.linear[1], job.linear[2], job.linear[3], 0, 0}
				err = v.Tessellate_Into(&job.mesh, job.commands, linear, job.rule, limits, context.temp_allocator, &usage)
			}
			vector_path_charge_tess_work(usage, limits, err != .None)
			job.bounds = vector_path_mesh_bounds(job.mesh)
		}
	}

	defer {
		vector_path_release_job_commands(job)
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

	// Prefer mesh AABB mapped through the isotropic fill basis over re-running
	// Geometry_Bounds on every morph remesh (solids ignore local_bounds anyway).
	mesh_bounds := job.bounds
	local_bounds: Rect
	if job.op == .Fill && job.linear[0] == job.linear[3] && job.linear[1] == 0 && job.linear[2] == 0 && job.linear[0] != 0 {
		scale := job.linear[0]
		local_bounds = {mesh_bounds.x / f32(scale), mesh_bounds.y / f32(scale), mesh_bounds.w / f32(scale), mesh_bounds.h / f32(scale)}
	} else {
		local_err: v.Error
		local_bounds, local_err = vector_path_entry_local_bounds(entry, job.commands)
		if local_err != .None {
			v.Destroy_Mesh(&job.mesh)

			return vector_path_error(local_err)
		}
	}

	reuse_id := entry.cache[cache_index].geometry_id != 0 &&
		len(job.mesh.vertices) == entry.cache[cache_index].geometry_vertex_count &&
		len(job.mesh.indices) == entry.cache[cache_index].geometry_index_count
	if !reuse_id {
		state.vector.next_geometry_id += 1
		state.vector.gpu.geometry_epoch += 1
		entry.cache[cache_index].geometry_id = state.vector.next_geometry_id
	}
	entry.cache[cache_index].linear = job.linear
	entry.cache[cache_index].rule = vector_path_cache_rule(job.op, job.rule)
	entry.cache[cache_index].op = job.op
	entry.cache[cache_index].morph = job.morph if job.op == .Stroke else Vector_Identity
	entry.cache[cache_index].mesh = job.mesh
	entry.cache[cache_index].valid = true
	entry.cache[cache_index].bounds = mesh_bounds
	entry.cache[cache_index].local_bounds = local_bounds
	entry.cache[cache_index].geometry_vertex_count = len(job.mesh.vertices)
	entry.cache[cache_index].geometry_index_count = len(job.mesh.indices)
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
vector_path_entry_local_bounds :: proc(entry: ^Vector_Path_Entry, commands: []Vector_Path_Command) -> (Rect, v.Error) {
	if entry.memo_local_bounds_revision == entry.command_revision {

		return entry.memo_local_bounds, .None
	}

	bounds, err := vector_path_local_bounds(commands)
	if err != .None {

		return {}, err
	}

	entry.memo_local_bounds = bounds
	entry.memo_local_bounds_revision = entry.command_revision

	return bounds, .None
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
vector_path_release_job_commands :: proc(job: ^Vector_Tess_Job) {
	if job.commands_owned {
		delete(job.commands)
	}
	job.commands = nil
	job.commands_owned = false
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
	// Endpoint-only curve flatten keeps a fixed vertex count for morph remesh
	// reposition (≈1 sample/cubic, matching dense-icon adaptive density).
	if op == .Fill && !entry.affine_solvable && entry.morph_uniform_ok {
		limits.uniform_subdivision = -1
	}

	// Borrow live commands: workers only read them, and Update_Path is forbidden
	// while tess_workers > 0.
	job_stroke: Vector_Stroke
	if op == .Stroke {
		job_stroke, err = vector_stroke_copy_dash(stroke, context.allocator)
		if err != .None {
			return {}, false, err
		}
	}

	job = Vector_Tess_Job {
		commands        = entry.commands,
		commands_owned  = false,
		linear          = linear,
		rule            = rule,
		op              = op,
		stroke          = job_stroke,
		morph           = stroke_morph,
		limits          = limits,
		handle          = handle,
		generation      = entry.generation,
		cache_index     = cache_index,
	}
	job.mesh = entry.cache[cache_index].mesh
	if _, recorded := vector_frame().geometry[entry.cache[cache_index].geometry_id]; recorded {
		entry.cache[cache_index].geometry_id = 0
	}
	entry.cache[cache_index].mesh = {}
	state.vector.path_cache_bytes -= vector_path_cache_bytes(job.mesh)
	entry.cache[cache_index].pending = true

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
@(private)
vector_path_begin_jobs :: proc() -> ([dynamic]Vector_Tess_Job, Vector_Error) {
	if state.vector.tess_jobs_in_use { return nil, .Invalid_Value }
	state.vector.tess_jobs_in_use = true
	jobs := state.vector.tess_jobs
	state.vector.tess_jobs = nil
	return jobs, .None
}

@(private)
vector_path_end_jobs :: proc(jobs: ^[dynamic]Vector_Tess_Job) {
	for &job in jobs^ { vector_path_cancel_job(&job) }
	clear(jobs)
	state.vector.tess_jobs = jobs^
	jobs^ = nil
	state.vector.tess_jobs_in_use = false
}

@(private)
vector_path_flush_prefetch_burst :: proc(jobs: ^[dynamic]Vector_Tess_Job) -> Vector_Error {
	if len(jobs^) == 0 {
		return .None
	}

	vector_tess_assign_exclusive_quotas(jobs^[:])
	vector_tessellate_jobs(jobs^[:])
	first_err := Vector_Error.None
	for &job in jobs^ {
		install_err := vector_path_install_tess_job(&job)
		if first_err == .None && install_err != .None {
			first_err = install_err
		}

		if job.commands != nil {
			vector_path_release_job_commands(&job)
		}

		vector_stroke_release_dash(&job.stroke)
		v.Destroy_Mesh(&job.mesh)
	}

	clear(jobs)

	return first_err
}

Vector_Prefetch_Paths :: proc(specs: []Vector_Path_Tess_Spec) -> Vector_Error {
	if state == nil {
		return .Invalid_Handle
	}

	if len(specs) == 0 {
		return .None
	}

	jobs, buffer_error := vector_path_begin_jobs()
	if buffer_error != .None { return buffer_error }
	defer vector_path_end_jobs(&jobs)
	if reserve(&jobs, min(len(specs), VECTOR_TESS_MAX_JOBS_PER_BURST)) != nil { return .Allocation_Failed }

	burst_bytes := u64(VECTOR_TESS_MAX_WORKERS) * u64(VECTOR_TESS_WORKER_SCRATCH)
	first_err := Vector_Error.None

	for &spec in specs {
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

		linear := vector_path_tess_linear(spec.op, spec.transform)
		morph := vector_stroke_draw_morph(entry, Vector_Identity) if spec.op == .Stroke else Vector_Identity
		cached := vector_path_find_cache_index(entry, linear, spec.rule, spec.op, spec.stroke, morph, require_valid = false, allow_pending = true)
		if cached >= 0 && (entry.cache[cached].valid || entry.cache[cached].pending) {
			continue
		}

		job, need, err := vector_path_build_miss_job(spec.handle, entry, linear, spec.rule, spec.op, spec.stroke, morph)
		if err != .None {
			return err
		}

		if !need {
			continue
		}

		cost := vector_path_job_burst_bytes(job)
		if len(jobs) >= VECTOR_TESS_MAX_JOBS_PER_BURST || burst_bytes + cost > VECTOR_TESS_BURST_MEMORY {
			if flush_err := vector_path_flush_prefetch_burst(&jobs); flush_err != .None && first_err == .None {
				first_err = flush_err
			}

			burst_bytes = u64(VECTOR_TESS_MAX_WORKERS) * u64(VECTOR_TESS_WORKER_SCRATCH)
			if len(jobs) >= VECTOR_TESS_MAX_JOBS_PER_BURST || burst_bytes + cost > VECTOR_TESS_BURST_MEMORY {
				vector_path_release_job_commands(&job)
				vector_stroke_release_dash(&job.stroke)
				if first_err == .None {
					first_err = .Limit_Exceeded
				}

				continue
			}
		}

		burst_bytes += cost
		append(&jobs, job)
	}

	if flush_err := vector_path_flush_prefetch_burst(&jobs); flush_err != .None && first_err == .None {
		first_err = flush_err
	}

	return first_err
}

@(private)
vector_path_record_cached :: proc(
	handle: Vector_Path_Handle,
	entry: ^Vector_Path_Entry,
	cache_index: int,
	#by_ptr paint: Vector_Paint,
	transform: Vector_Transform,
	opacity: f32,
	instance_morph: Vector_Transform,
	current_color: RGBA = {0, 0, 0, 255},
) -> Vector_Error {
	_ = handle
	return vector_path_record_cached_fast(
		entry,
		cache_index,
		paint,
		transform,
		opacity,
		instance_morph,
		current_color,
		f64(state.dpi.scale * view_artboard_zoom()),
		draw_effective_opacity(),
	)
}

// Hit-record fast path for Draw_Vector_Paths: hoisted dpi/zoom/opacity, solid-paint
// and identity-morph shortcuts, caller-warmed instance/command/record capacity.
@(private)
vector_path_record_cached_fast :: #force_inline proc(
	entry: ^Vector_Path_Entry,
	cache_index: int,
	#by_ptr paint: Vector_Paint,
	transform: Vector_Transform,
	opacity: f32,
	instance_morph: Vector_Transform,
	current_color: RGBA,
	dpi_zoom: f64,
	draw_opacity_scale: f32,
	recording: ^Vector_Path_Record_Context = nil,
) -> Vector_Error {
	if !(opacity >= 0 && opacity <= 1) {
		return .Invalid_Value
	}

	entry.cache[cache_index].last_used = state.ui.frame
	cached := &entry.cache[cache_index]
	origin := view_transform_point({f32(transform[4]), f32(transform[5])}) * state.dpi.scale
	morph: Vector_Transform
	if cached.op == .Stroke {
		path_morph := v.Affine_Compose(entry.morph, vector_path_normalize_morph(instance_morph))
		basis := v.Affine{cached.linear[0], cached.linear[1], cached.linear[2], cached.linear[3], 0, 0}
		morph = vector_path_rebase_morph(basis, path_morph)
	} else if entry.morph == Vector_Identity && (instance_morph == {} || instance_morph == Vector_Identity) {
		scale := dpi_zoom / cached.linear[0]
		morph = {transform[0] * scale, transform[1] * scale, transform[2] * scale, transform[3] * scale, 0, 0}
	} else {
		draw_linear := [4]f64{transform[0] * dpi_zoom, transform[1] * dpi_zoom, transform[2] * dpi_zoom, transform[3] * dpi_zoom}
		morph = vector_path_fill_gpu_morph(entry, instance_morph, draw_linear, cached.linear)
	}

	gpu_paint: Vector_Paint_GPU
	switch paint.kind {
	case .None:
		return .None
	case .Solid:
		draw_opacity := opacity * draw_opacity_scale
		if paint.solid.a == 0 || draw_opacity == 0 {
			return .None
		}
		colour := rgba_to_f32(paint.solid)
		colour[3] *= draw_opacity
		gpu_paint = {colour = colour}
	case .Current_Color, .Linear_Gradient, .Radial_Gradient:
		if paint.kind == .Linear_Gradient || paint.kind == .Radial_Gradient {
			bounds, err := vector_path_entry_local_bounds(entry, entry.commands)
			if err != .None { return vector_path_error(err) }
			cached.local_bounds = bounds
		}
		resolved, skip, paint_err := vector_paint_resolve(paint, opacity, cached.linear, cached.local_bounds, current_color)
		if paint_err != .None {
			return paint_err
		}
		if skip {
			return .None
		}
		gpu_paint = resolved
	}

	return vector_record_cached_mesh(
		cached.mesh.vertices[:],
		cached.mesh.indices[:],
		cached.bounds,
		origin,
		gpu_paint,
		cached.geometry_id,
		morph,
		&cached.recorded_geometry,
		recording,
	)
}

// A retained endpoint mesh can be refreshed on the owner without constructing
// and installing a one-job burst. Failed work stays charged to the frame.
@(private)
vector_path_refresh_cached_fill :: proc(entry: ^Vector_Path_Entry, linear: [4]f64, rule: Vector_Fill_Rule) -> (index: int, handled: bool, err: Vector_Error) {
	index = vector_path_find_cache_index(entry, linear, rule, require_valid = false)
	if index < 0 || entry.affine_solvable || !entry.morph_uniform_ok || linear[0] <= 0 { return index, false, .None }
	cached := &entry.cache[index]
	if !cached.mesh.contour_slots || !entry.svg_mesh_only && len(entry.basis_commands) == 0 { return index, false, .None }
	if state.vector.next_geometry_id == max(u64) { return index, true, .Limit_Exceeded }
	limits, limit_error := vector_path_frame_tess_limits()
	if limit_error != .None { return index, true, limit_error }
	before := vector_path_cache_bytes(cached.mesh)
	limits.max_mesh_bytes += int(before)
	limits.uniform_subdivision = -1
	usage: v.Build_Usage
	handled_refresh, tess_error := v.Try_Refresh_Endpoint_Mesh(&cached.mesh, entry.commands,
		{linear[0], linear[1], linear[2], linear[3], 0, 0}, rule, limits, &usage)
	if !handled_refresh { return index, false, .None }
	vector_path_charge_tess_work(usage, limits, tess_error != .None)
	state.vector.path_cache_bytes = state.vector.path_cache_bytes - before + vector_path_cache_bytes(cached.mesh)
	if tess_error == .Mesh_Memory_Limit { return index, false, .None }
	if tess_error != .None { return index, true, vector_path_error(tess_error) }
	_, recorded := vector_frame().geometry[cached.geometry_id]
	if recorded || len(cached.mesh.vertices) != cached.geometry_vertex_count || len(cached.mesh.indices) != cached.geometry_index_count {
		state.vector.next_geometry_id += 1
		state.vector.gpu.geometry_epoch += 1
		cached.geometry_id = state.vector.next_geometry_id
	}
	cached.bounds = vector_path_mesh_bounds(cached.mesh)
	scale := f32(linear[0])
	cached.local_bounds = {cached.bounds.x / scale, cached.bounds.y / scale, cached.bounds.w / scale, cached.bounds.h / scale}
	cached.geometry_vertex_count = len(cached.mesh.vertices)
	cached.geometry_index_count = len(cached.mesh.indices)
	cached.last_used = state.ui.frame
	cached.valid = true
	return index, true, .None
}

/*
Draws many paths; unique cache misses tessellate in a parallel burst then record.
On any item failure after recording has begun, rolls the frame back so no partial
batch (including half an SVG) remains visible to later submissions.
*/
@(private)
vector_path_record_cache_hits :: proc(items: []Vector_Path_Draw, recording: ^Vector_Path_Record_Context) -> (complete: bool, err: Vector_Error) {
	f := vector_frame()
	if !vector_reserve(&f.instances, len(f.instances) + len(items), VECTOR_MAX_FRAME_NODES) ||
	   !vector_reserve(&f.commands, len(f.commands) + len(items), VECTOR_MAX_FRAME_NODES) {
		return true, .Allocation_Failed
	}
	recording.capacity_reserved = true
	linear := vector_path_fill_tess_linear()
	dpi_zoom := f64(state.dpi.scale * view_artboard_zoom())
	opacity_scale := draw_effective_opacity()
	for &item in items {
		for value in item.transform {
			if math.is_nan(value) || math.is_inf(value) { return true, .Invalid_Value }
		}
		if !(item.opacity >= 0 && item.opacity <= 1) { return true, .Invalid_Value }
		entry := vector_path_entry(item.handle)
		if entry == nil { return true, .Invalid_Handle }
		if item.op != .Fill { return false, .None }
		cache_index := vector_path_find_cache_index(entry, linear, item.rule)
		if cache_index < 0 {
			if len(items) >= VECTOR_TESS_PARALLEL_THRESHOLD { return false, .None }
			refreshed, handled, refresh_error := vector_path_refresh_cached_fill(entry, linear, item.rule)
			if refresh_error != .None { return true, refresh_error }
			if handled {
				cache_index = refreshed
			} else {
				// Small batches cannot use the worker pool. Resolve each miss in place
				// instead of allocating a job list, dedup map and index array.
				job, need, build_error := vector_path_build_miss_job(item.handle, entry, linear, item.rule)
				if build_error != .None { return true, build_error }
				if need {
					jobs := [1]Vector_Tess_Job{job}
					vector_tessellate_jobs_serial(jobs[:])
					if install_error := vector_path_install_tess_job(&jobs[0]); install_error != .None { return true, install_error }
					cache_index = jobs[0].cache_index
				} else {
					cache_index = vector_path_find_cache_index(entry, linear, item.rule)
				}
				if cache_index < 0 { return true, .Invalid_Path }
			}
		}
		if record_err := vector_path_record_cached_fast(entry, cache_index, item.paint, item.transform,
			item.opacity, item.instance_morph, item.current_color, dpi_zoom, opacity_scale, recording); record_err != .None {
			return true, record_err
		}
	}
	return true, .None
}

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

	f := vector_frame()
	saved_vertices := f.atlas_vertex_count if f.atlas_vertex_count > 0 else len(f.vertices)
	saved_indices := f.atlas_index_count if f.atlas_index_count > 0 else len(f.indices)
	saved_instances := len(f.instances)
	saved_commands := len(f.commands)
	saved_records := len(f.records)
	saved_draws := len(f.draws)
	saved_last_draw: Vector_Submission
	saved_last_record: Vector_Record
	if saved_draws > 0 {
		saved_last_draw = f.draws[saved_draws - 1]
		if saved_last_draw.first >= 0 && saved_last_draw.first < saved_records { saved_last_record = f.records[saved_last_draw.first] }
	}
	saved_ramps := len(f.ramp_pixels)
	saved_ramp_rows := f.ramp_rows
	saved_revision := f.vertex_revision
	saved_segments := len(batch_current().segments)
	recording := Vector_Path_Record_Context{clip = batch_current_clip(), draw_space = draw_current_space(), stack_index = batch_current().current_stack}
	complete, hit_error := vector_path_record_cache_hits(items, &recording)
	if complete && hit_error == .None { return .None }
	vector_scene_rollback_recording(saved_vertices, saved_indices, saved_instances, saved_commands,
		saved_records, saved_draws, saved_ramps, saved_ramp_rows, saved_revision, saved_segments)
	if saved_draws > 0 {
		f.draws[saved_draws - 1] = saved_last_draw
		if saved_last_draw.first >= 0 && saved_last_draw.first < saved_records { f.records[saved_last_draw.first] = saved_last_record }
	}
	if complete { return hit_error }
	recording.coalesce = false

	jobs, buffer_error := vector_path_begin_jobs()
	if buffer_error != .None { return buffer_error }
	defer vector_path_end_jobs(&jobs)

	// Deduplicate miss keys (handle index + linear + rule) within this batch.
	seen: map[[10]u64]bool
	collecting := false
	burst_bytes := u64(VECTOR_TESS_MAX_WORKERS) * u64(VECTOR_TESS_WORKER_SCRATCH)
	first_err := Vector_Error.None
	resolved := make([]int, len(items), context.temp_allocator)
	for i in 0 ..< len(resolved) {
		resolved[i] = -1
	}

	for &item, i in items {
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

		linear := vector_path_tess_linear(item.op, item.transform)
		morph := vector_stroke_draw_morph(entry, item.instance_morph) if item.op == .Stroke else Vector_Identity
		cache_index := vector_path_find_cache_index(entry, linear, item.rule, item.op, item.stroke, morph)
		if cache_index >= 0 && entry.cache[cache_index].valid {
			resolved[i] = cache_index

			continue
		}

		if !collecting {
			if reserve(&jobs, min(len(items), VECTOR_TESS_MAX_JOBS_PER_BURST)) != nil { return .Allocation_Failed }
			seen = make(map[[10]u64]bool, context.temp_allocator)
			collecting = true
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
				vector_path_release_job_commands(&job)
				vector_stroke_release_dash(&job.stroke)
				if first_err == .None {
					first_err = .Limit_Exceeded
				}

				continue
			}

			cost := vector_path_job_burst_bytes(job)
			if burst_bytes + cost > VECTOR_TESS_BURST_MEMORY {
				vector_path_release_job_commands(&job)
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

	// Warm capacity once for the hit-record loop (transform-only is all hits).
	if !vector_reserve(&f.instances, len(f.instances) + len(items), VECTOR_MAX_FRAME_NODES) ||
	   !vector_reserve(&f.commands, len(f.commands) + len(items), VECTOR_MAX_FRAME_NODES) ||
	   !vector_reserve(&f.records, len(f.records) + 1, VECTOR_MAX_FRAME_NODES) {
		return .Allocation_Failed
	}

	dpi_zoom := f64(state.dpi.scale * view_artboard_zoom())
	draw_opacity_scale := draw_effective_opacity()

	for &item, i in items {
		entry := vector_path_entry(item.handle)
		if entry == nil {
			if first_err == .None {
				first_err = .Invalid_Handle
			}

			continue
		}

		cache_index := resolved[i]
		if cache_index < 0 {
			linear := vector_path_tess_linear(item.op, item.transform)
			morph := vector_stroke_draw_morph(entry, item.instance_morph) if item.op == .Stroke else Vector_Identity
			cache_index = vector_path_find_cache_index(entry, linear, item.rule, item.op, item.stroke, morph)
		}
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

		if err := vector_path_record_cached_fast(
			entry,
			cache_index,
			item.paint,
			item.transform,
			item.opacity,
			item.instance_morph,
			item.current_color,
			dpi_zoom,
			draw_opacity_scale,
			&recording,
		); err != .None && first_err == .None {
			first_err = err
		}
	}

	if first_err != .None {
		vector_scene_rollback_recording(
			saved_vertices,
			saved_indices,
			saved_instances,
			saved_commands,
			saved_records,
			saved_draws,
			saved_ramps,
			saved_ramp_rows,
			saved_revision,
			saved_segments,
		)
		if saved_draws > 0 {
			f.draws[saved_draws - 1] = saved_last_draw
			if saved_last_draw.first >= 0 && saved_last_draw.first < saved_records { f.records[saved_last_draw.first] = saved_last_record }
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
	return vector_register_path(owned, context.allocator, false)
}

@(private)
vector_register_path :: proc(commands: []Vector_Path_Command, allocator: mem.Allocator, mesh_only: bool) -> (Vector_Path_Handle, Vector_Error) {
	for len(state.vector.path_free) > 0 {
		i := state.vector.path_free[len(state.vector.path_free) - 1]
		resize(&state.vector.path_free, len(state.vector.path_free) - 1)
		entry := &state.vector.paths[i]
		entry.commands = commands
		entry.basis_commands = nil
		entry.morph = Vector_Identity
		entry.command_allocator = allocator
		entry.live = true
		entry.affine_solvable = true
		entry.morph_uniform_ok = true
		entry.svg_retained = false
		entry.svg_mesh_only = mesh_only
		entry.svg_key = {}
		entry.svg_command_hash = {}
		entry.svg_structure = {}
		entry.svg_lru_prev = {}
		entry.svg_lru_next = {}
		if entry.cache_lookup != nil {
			delete(entry.cache_lookup)
			entry.cache_lookup = nil
		}
		entry.memo_local_bounds = {}
		entry.memo_local_bounds_revision = 0
		vector_path_bump_command_revision(entry)

		return {index = u32(i + 1), generation = entry.generation}, .None
	}
	if _, append_error := append(&state.vector.paths, Vector_Path_Entry{commands = commands, morph = Vector_Identity, command_allocator = allocator, generation = 1, live = true, affine_solvable = true, morph_uniform_ok = true, command_revision = 1, svg_mesh_only = mesh_only}); append_error != nil {
		if !mesh_only { delete(commands, allocator) }
		return {}, .Allocation_Failed
	}
	return {index = u32(len(state.vector.paths)), generation = 1}, .None
}

// Sets an affine morph relative to the path's retained basis commands.
// Fill caches stay shared; Draw applies the morph on the GPU. Stroke geometry is
// baked with morph, so stroke cache slots are invalidated here.
Vector_Set_Path_Morph :: proc(handle: Vector_Path_Handle, morph: Vector_Transform) -> Vector_Error {
	entry := vector_path_entry(handle)
	if entry == nil || entry.svg_mesh_only {
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
	if entry.svg_retained {
		vector_svg_lru_unlink(handle)
		delete_key(&state.vector.svg_paths, entry.svg_key)
		if !entry.svg_mesh_only { state.vector.svg_path_bytes -= u64(len(entry.commands)) * size_of(Vector_Path_Command) }
		entry.svg_retained = false
		entry.svg_key = {}
		entry.svg_command_hash = {}
		entry.svg_structure = {}
	}
	if !entry.svg_mesh_only { delete(entry.commands, entry.command_allocator) }
	delete(entry.basis_commands, entry.command_allocator)
	entry.commands = nil
	entry.basis_commands = nil
	entry.command_allocator = {}
	entry.live = false
	if entry.generation < max(u32) {
		entry.generation += 1
	}
	_ = append(&state.vector.path_free, handle.index - 1)

	return .None
}

// Borrows the live command slice for in-place point edits. Caller must keep the
// same length/kinds and finish with Vector_Path_Geometry_Changed (or
// Vector_Update_Path) before the next Prefetch / Draw tessellation.
Vector_Borrow_Path_Commands :: proc(handle: Vector_Path_Handle) -> ([]Vector_Path_Command, Vector_Error) {
	entry := vector_path_entry(handle)
	if entry == nil || entry.svg_mesh_only {
		return nil, .Invalid_Handle
	}
	if state.vector.tess_workers != 0 {
		return nil, .Invalid_Value
	}
	return entry.commands, .None
}

// Marks geometry dirty after an in-place edit of Vector_Borrow_Path_Commands.
// Same-structure control-point morphs keep command_revision stable.
Vector_Path_Geometry_Changed :: proc(handle: Vector_Path_Handle) -> Vector_Error {
	entry := vector_path_entry(handle)
	if entry == nil {
		return .Invalid_Handle
	}
	if state.vector.tess_workers != 0 {
		return .Invalid_Value
	}
	entry.affine_solvable = false
	entry.morph = Vector_Identity
	for &cached in entry.cache {
		cached.valid = false
	}
	entry.memo_local_bounds_revision = 0
	return .None
}

// Batch form of Vector_Path_Geometry_Changed for dense morph updates.
Vector_Path_Geometry_Changed_Many :: proc(handles: []Vector_Path_Handle) -> Vector_Error {
	if state.vector.tess_workers != 0 {
		return .Invalid_Value
	}
	for handle in handles {
		entry := vector_path_entry(handle)
		if entry == nil {
			return .Invalid_Handle
		}
		entry.affine_solvable = false
		entry.morph = Vector_Identity
		for &cached in entry.cache {
			cached.valid = false
		}
		entry.memo_local_bounds_revision = 0
	}
	return .None
}

// Validates and allocates the replacement before invalidating old geometry.
// Compatible control-point edits that are a single affine update `morph` so
// fill basis meshes stay shared (GPU morph). Stroke slots are invalidated because
// stroke meshes bake morph into tessellated outlines.
Vector_Update_Path :: proc(handle: Vector_Path_Handle, commands: []Vector_Path_Command) -> Vector_Error {
	entry := vector_path_entry(handle)
	if entry == nil || entry.svg_mesh_only {
		return .Invalid_Handle
	}

	if state.vector.tess_workers != 0 {
		return .Invalid_Value
	}

	if len(commands) > (64 * 1024 * 1024) / size_of(Vector_Path_Command) || len(commands) > v.DEFAULT_LIMITS.max_commands {
		return .Limit_Exceeded
	}
	basis := entry.basis_commands if len(entry.basis_commands) > 0 else entry.commands
	if entry.affine_solvable {
		if affine, ok := v.Commands_Affine(basis, commands); ok {
			entry.morph = affine
			vector_path_invalidate_stroke_cache(entry)
			return .None
		}
		if v.Commands_Same_Structure(basis, commands) {
			entry.affine_solvable = false
		}
	}
	same_structure := len(commands) == len(entry.commands) &&
		(entry.affine_solvable == false || v.Commands_Same_Structure(entry.commands, commands))
	if !same_structure {
		if err := v.Validate_Commands(commands); err != .None {
			return vector_path_error(err)
		}
		same_structure = len(commands) == len(entry.commands) && v.Commands_Same_Structure(entry.commands, commands)
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
		entry.affine_solvable = true
		entry.morph_uniform_ok = true
		delete(entry.basis_commands, entry.command_allocator)
		entry.basis_commands = nil
	}
	entry.morph = Vector_Identity
	for &cached in entry.cache {
		cached.valid = false
	}
	if !same_structure {
		vector_path_bump_command_revision(entry)
	} else {
		entry.memo_local_bounds_revision = 0
	}

	return .None
}

@(private)
vector_path_cancel_job :: proc(job: ^Vector_Tess_Job) {
	entry := vector_path_entry(job.handle)
	if entry != nil &&
	   job.cache_index >= 0 &&
	   job.cache_index < len(entry.cache) &&
	   entry.cache[job.cache_index].linear == job.linear {
		entry.cache[job.cache_index].pending = false
	}
	vector_path_release_job_commands(job)
	vector_stroke_release_dash(&job.stroke)
	v.Destroy_Mesh(&job.mesh)
}

@(private)
vector_path_evict_cache :: proc(required: u64, protected_path: int = -1, protected_cache: ^int = nil) -> bool {
	vector_owner_assert_no_tess_workers()
	if required > VECTOR_CPU_CACHE_BUDGET {

		return false
	}
	if state.vector.path_cache_bytes <= VECTOR_CPU_CACHE_BUDGET - required {

		return true
	}
	headroom := max(required, VECTOR_CPU_CACHE_BUDGET / 8)
	frame := state.ui.frame
	thresholds := [3]u64{frame > 0 ? frame - 1 : 0, frame, max(u64)}
	for threshold in thresholds {
		for &entry, i in state.vector.paths {
			for &cached, j in entry.cache {
				if cached.pending || cached.last_used >= threshold {

					continue
				}
				if i == protected_path && (protected_cache == nil || j == protected_cache^) {

					continue
				}
				vector_path_cache_unmap_slot(&entry, j)
				state.vector.path_cache_bytes -= vector_path_cache_bytes(cached.mesh) + u64(len(cached.stroke.dash)) * size_of(f64)
				v.Destroy_Mesh(&cached.mesh)
				vector_stroke_release_dash(&cached.stroke, cached.stroke_allocator)
				cached = {}
				if state.vector.path_cache_bytes <= VECTOR_CPU_CACHE_BUDGET - headroom {

					break
				}
			}
			if i != protected_path && len(entry.cache) > 0 {
				empty := true
				for cached in entry.cache {
					if cached.pending || cached.valid || cap(cached.mesh.vertices) != 0 || cap(cached.mesh.indices) != 0 || len(cached.stroke.dash) != 0 {
						empty = false

						break
					}
				}
				if empty {
					state.vector.path_cache_bytes -= u64(cap(entry.cache)) * size_of(Vector_Path_Cache)
					delete(entry.cache)
					entry.cache = nil
					delete(entry.cache_lookup)
					entry.cache_lookup = nil
				}
			}
			if state.vector.path_cache_bytes <= VECTOR_CPU_CACHE_BUDGET - headroom {

				return true
			}
		}
	}

	return state.vector.path_cache_bytes <= VECTOR_CPU_CACHE_BUDGET - required
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

	linear := vector_path_tess_linear(op, transform)
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
