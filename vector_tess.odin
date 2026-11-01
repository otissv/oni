package oni

import v "./vector"
import "core:mem"
import "core:sync"
import "core:thread"

VECTOR_TESS_PARALLEL_THRESHOLD :: 4
VECTOR_TESS_MAX_WORKERS :: 4
VECTOR_TESS_MAX_JOBS_PER_BURST :: 4096
VECTOR_TESS_BURST_MEMORY :: u64(128 * 1024 * 1024)
// Private per-worker scratch for Tessellate_Into (never the frame temp_allocator).
VECTOR_TESS_WORKER_SCRATCH :: 1 * 1024 * 1024

/*
One tessellation job: owner copies commands; workers fill mesh/usage/err only.
*/
Vector_Tess_Job :: struct {
	commands:    []Vector_Path_Command,
	linear:      [4]f64,
	rule:        Vector_Fill_Rule,
	op:          Vector_Path_Op,
	stroke:      Vector_Stroke,
	morph:       Vector_Transform,
	limits:      v.Limits,
	mesh:        v.Mesh,
	usage:       v.Build_Usage,
	err:         v.Error,
	handle:      Vector_Path_Handle,
	generation:  u32,
	cache_index: int,
}

/*
Per-worker chunk of tess jobs plus a private scratch arena.
*/
Vector_Tess_Worker_Chunk :: struct {
	jobs:            []Vector_Tess_Job,
	scratch:         mem.Arena,
	scratch_backing: []u8,
}

/*
One persistent vector tessellation worker slot.
*/
Vector_Tess_Pool_Slot :: struct {
	pool:      ^Vector_Tess_Pool,
	thread:    ^thread.Thread,
	chunk:     Vector_Tess_Worker_Chunk,
	work_sema: sync.Sema,
}

/*
Bounded tessellation worker pool reused across Prefetch / Draw_Paths bursts.
*/
Vector_Tess_Pool :: struct {
	slots:         [VECTOR_TESS_MAX_WORKERS]Vector_Tess_Pool_Slot,
	done_sema:     sync.Sema,
	quit:          bool,
	started_count: int,
}

@(private)
vector_owner_assert_no_tess_workers :: proc() {
	when ODIN_DEBUG {
		if state != nil && state.vector.tess_workers != 0 {
			panic("vector cache mutation while tess workers active")
		}
	}
}

@(private)
vector_owner_begin_tess_workers :: proc(count: int) {
	if state == nil {
		return
	}

	vector_owner_assert_no_tess_workers()
	state.vector.tess_workers = count
}

@(private)
vector_owner_end_tess_workers :: proc() {
	if state == nil {
		return
	}

	state.vector.tess_workers = 0
}

/*
Ensures the bounded tessellation pool is running.

Returns false if threads or scratch cannot be allocated (caller falls back to serial).
*/
vector_tess_pool_ensure :: proc() -> bool {
	if state == nil {
		return false
	}

	if state.vector.tess_pool != nil && state.vector.tess_pool.started_count == VECTOR_TESS_MAX_WORKERS {
		return true
	}

	if state.vector.tess_pool != nil {
		vector_tess_pool_shutdown()
	}

	pool := new(Vector_Tess_Pool)
	if pool == nil {
		return false
	}

	pool.quit = false
	state.vector.tess_pool = pool

	for i in 0 ..< VECTOR_TESS_MAX_WORKERS {
		slot := &pool.slots[i]
		slot.pool = pool
		backing := make([]u8, VECTOR_TESS_WORKER_SCRATCH)
		if len(backing) != VECTOR_TESS_WORKER_SCRATCH {
			vector_tess_pool_shutdown()

			return false
		}

		mem.arena_init(&slot.chunk.scratch, backing)
		slot.chunk.scratch_backing = backing
		slot.thread = thread.create_and_start_with_poly_data(slot, vector_tess_pool_worker)
		if slot.thread == nil {
			delete(slot.chunk.scratch_backing)
			slot.chunk.scratch_backing = nil
			slot.chunk.scratch = {}
			slot.pool = nil
			vector_tess_pool_shutdown()

			return false
		}

		pool.started_count += 1
	}

	return true
}

/*
Signals quit, joins workers, and frees pool scratch + heap.
*/
vector_tess_pool_shutdown :: proc() {
	if state == nil || state.vector.tess_pool == nil {
		return
	}

	pool := state.vector.tess_pool
	pool.quit = true

	for i in 0 ..< pool.started_count {
		sync.sema_post(&pool.slots[i].work_sema)
	}

	for i in 0 ..< pool.started_count {
		slot := &pool.slots[i]
		if slot.thread != nil {
			thread.join(slot.thread)
			thread.destroy(slot.thread)
			slot.thread = nil
		}

		if slot.chunk.scratch_backing != nil {
			delete(slot.chunk.scratch_backing)
			slot.chunk.scratch_backing = nil
			slot.chunk.scratch = {}
		}

		slot.chunk.jobs = nil
		slot.pool = nil
	}

	free(pool)
	state.vector.tess_pool = nil
	state.vector.tess_workers = 0
}

@(private)
vector_tess_pool_worker :: proc(slot: ^Vector_Tess_Pool_Slot) {
	if slot == nil || slot.pool == nil {
		return
	}

	for {
		sync.sema_wait(&slot.work_sema)
		if slot.pool.quit {
			return
		}

		vector_tess_worker_chunk(&slot.chunk)
		sync.sema_post(&slot.pool.done_sema)
	}
}

/*
Worker entry: tessellates each job with private scratch; never mutates path cache.
*/
@(private)
vector_tess_worker_chunk :: proc(args: ^Vector_Tess_Worker_Chunk) {
	if args == nil || len(args.jobs) == 0 {
		return
	}

	scratch_alloc := mem.arena_allocator(&args.scratch)

	for &job in args.jobs {
		mem.arena_free_all(&args.scratch)
		job.usage = {}
		if job.op == .Stroke {
			stroke_transform := vector_stroke_tess_transform(job.linear, job.morph)
			job.err = v.Tessellate_Stroke_Into(
				&job.mesh,
				job.commands,
				stroke_transform,
				job.stroke,
				job.limits,
				scratch_alloc,
				&job.usage,
			)
		} else {
			linear := v.Affine{job.linear[0], job.linear[1], job.linear[2], job.linear[3], 0, 0}
			job.err = v.Tessellate_Into(
				&job.mesh,
				job.commands,
				linear,
				job.rule,
				job.limits,
				scratch_alloc,
				&job.usage,
			)
		}
	}
}

@(private)
vector_tessellate_jobs_serial :: proc(jobs: []Vector_Tess_Job) {
	vector_owner_assert_no_tess_workers()

	for &job in jobs {
		job.usage = {}
		if job.op == .Stroke {
			stroke_transform := vector_stroke_tess_transform(job.linear, job.morph)
			job.err = v.Tessellate_Stroke_Into(
				&job.mesh,
				job.commands,
				stroke_transform,
				job.stroke,
				job.limits,
				context.temp_allocator,
				&job.usage,
			)
		} else {
			linear := v.Affine{job.linear[0], job.linear[1], job.linear[2], job.linear[3], 0, 0}
			job.err = v.Tessellate_Into(
				&job.mesh,
				job.commands,
				linear,
				job.rule,
				job.limits,
				context.temp_allocator,
				&job.usage,
			)
		}
	}
}

/*
Parallel tessellation via the bounded worker pool.

Falls back to serial below the threshold or when the pool cannot start.
*/
vector_tessellate_jobs :: proc(jobs: []Vector_Tess_Job) {
	vector_owner_assert_no_tess_workers()

	if len(jobs) == 0 {
		return
	}

	if len(jobs) < VECTOR_TESS_PARALLEL_THRESHOLD {
		vector_tessellate_jobs_serial(jobs)

		return
	}

	if !vector_tess_pool_ensure() {
		vector_tessellate_jobs_serial(jobs)

		return
	}

	pool := state.vector.tess_pool
	n_workers := min(VECTOR_TESS_MAX_WORKERS, len(jobs))

	base := 0
	for w in 0 ..< n_workers {
		remaining := len(jobs) - base
		chunks_left := n_workers - w
		count := remaining / chunks_left
		slot := &pool.slots[w]
		mem.arena_free_all(&slot.chunk.scratch)
		slot.chunk.jobs = jobs[base:][:count]
		base += count
	}

	vector_owner_begin_tess_workers(n_workers)
	defer vector_owner_end_tess_workers()

	for w in 0 ..< n_workers {
		sync.sema_post(&pool.slots[w].work_sema)
	}

	for w in 0 ..< n_workers {
		_ = w
		sync.sema_wait(&pool.done_sema)
	}
}

/*
Splits remaining frame segment/triangle budgets into exclusive per-job quotas.

Sum of quotas equals the remaining frame budget; later jobs receive leftover
remainders so serial and parallel runners share one deterministic algorithm.
*/
vector_tess_assign_exclusive_quotas :: proc(jobs: []Vector_Tess_Job) {
	if len(jobs) == 0 {
		return
	}

	seg_remain := VECTOR_MAX_NEW_SEGMENTS - vector_frame().new_segments
	tri_remain := VECTOR_MAX_NEW_TRIANGLES - vector_frame().new_triangles
	if seg_remain < 0 {
		seg_remain = 0
	}

	if tri_remain < 0 {
		tri_remain = 0
	}

	for i in 0 ..< len(jobs) {
		left := len(jobs) - i
		seg_share := seg_remain / left
		tri_share := tri_remain / left
		limits := v.DEFAULT_LIMITS
		limits.max_flattened_segments = min(limits.max_flattened_segments, seg_share)
		limits.max_triangles = min(limits.max_triangles, tri_share)
		limits.max_mesh_bytes = int(VECTOR_CPU_CACHE_BUDGET - state.vector.path_cache_bytes)
		jobs[i].limits = limits
		seg_remain -= seg_share
		tri_remain -= tri_share
	}
}
