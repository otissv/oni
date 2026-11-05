package oni

import "core:path/filepath"
import "core:sync"
import "core:thread"
import "core:strings"
import "core:mem"
import sdl "vendor:sdl3"

ASSET_IO_MAX_WORKERS :: 4
ASSET_IO_MAX_REQUESTS :: 256
ASSET_IO_DRAIN_PER_FRAME :: 16
ASSET_IO_MAX_IMAGE_EDGE :: 8192
ASSET_IO_MAX_ENCODED_BYTES :: u64(32 * 1024 * 1024)
ASSET_IO_MAX_DECODED_BYTES :: u64(64 * 1024 * 1024)
ASSET_IO_MAX_INFLIGHT_DECODED :: u64(128 * 1024 * 1024)
ASSET_IO_UPLOAD_BYTES_PER_FRAME :: u64(16 * 1024 * 1024)
// One reserved completion slot per active worker so join cannot deadlock.
ASSET_IO_RESULT_SLOTS :: ASSET_IO_MAX_WORKERS

/*
One completed (or failed) decode waiting for owner commit.
*/
Asset_IO_Result :: struct {
	id:                Asset_Id,
	generation:        u32,
	request_token:     u64,
	device_generation:  u64,
	path:              string,
	path_allocator:    mem.Allocator,
	surface:           ^sdl.Surface,
	ok:                bool,
	diagnostic:        string,
	decoded_bytes:     u64,
}

@(private)
Asset_IO_Job :: struct {
	id:              Asset_Id,
	generation:      u32,
	request_token:   u64,
	device_generation: u64,
	path:            string,
	path_allocator:  mem.Allocator,
}

@(private)
Asset_IO_Pool_Slot :: struct {
	pool:      ^Asset_IO_Pool,
	thread:    ^thread.Thread,
	work_sema: sync.Sema,
}

/*
Bounded pool for disk+decode; owner drains `results` only.
*/
Asset_IO_Pool :: struct {
	slots:              [ASSET_IO_MAX_WORKERS]Asset_IO_Pool_Slot,
	done_sema:          sync.Sema,
	queue_mutex:        sync.Mutex,
	queue:              [dynamic]Asset_IO_Job,
	results_mutex:      sync.Mutex,
	results:            [dynamic]Asset_IO_Result,
	quit:               bool,
	started_count:      int,
	inflight:           int,
	decoded_bytes:     u64,
	device_generation: u64,
}

@(private)
assets_io_device_generation: u64

assets_io_bump_device_generation :: proc() {
	assets_io_device_generation += 1
	if state != nil && state.assets.io_pool != nil {
		state.assets.io_pool.device_generation = assets_io_device_generation
	}
}

@(private)
assets_io_pool_ensure :: proc() -> bool {
	if state == nil {
		return false
	}

	if state.assets.io_pool != nil && state.assets.io_pool.started_count == ASSET_IO_MAX_WORKERS {
		return true
	}

	if state.assets.io_pool != nil {
		assets_io_shutdown()
	}

	pool := new(Asset_IO_Pool)
	if pool == nil {
		return false
	}

	pool.quit = false
	pool.queue = make([dynamic]Asset_IO_Job)
	pool.results = make([dynamic]Asset_IO_Result)
	pool.device_generation = assets_io_device_generation
	state.assets.io_pool = pool

	for i in 0 ..< ASSET_IO_MAX_WORKERS {
		slot := &pool.slots[i]
		slot.pool = pool
		slot.thread = thread.create_and_start_with_poly_data(slot, assets_io_worker)
		if slot.thread == nil {
			assets_io_shutdown()

			return false
		}

		pool.started_count += 1
	}

	return true
}

/*
Joins workers, destroys undrained surfaces, and frees the pool.
*/
assets_io_shutdown :: proc() {
	if state == nil || state.assets.io_pool == nil {
		return
	}

	pool := state.assets.io_pool
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

		slot.pool = nil
	}

	sync.mutex_lock(&pool.queue_mutex)
	for job in pool.queue {
		delete(job.path, job.path_allocator)
	}
	clear(&pool.queue)
	delete(pool.queue)
	sync.mutex_unlock(&pool.queue_mutex)

	sync.mutex_lock(&pool.results_mutex)
	for result in pool.results {
		if result.surface != nil {
			sdl.DestroySurface(result.surface)
		}

		delete(result.path, result.path_allocator)
		delete(result.diagnostic)
	}
	clear(&pool.results)
	delete(pool.results)
	sync.mutex_unlock(&pool.results_mutex)

	free(pool)
	state.assets.io_pool = nil
}

@(private)
assets_io_release_decoded_credit :: proc(bytes: u64) {
	if state == nil || state.assets.io_pool == nil || bytes == 0 {
		return
	}

	pool := state.assets.io_pool
	sync.mutex_lock(&pool.results_mutex)
	if pool.decoded_bytes >= bytes {
		pool.decoded_bytes -= bytes
	} else {
		pool.decoded_bytes = 0
	}
	sync.mutex_unlock(&pool.results_mutex)
}

@(private)
assets_io_free_result :: proc(result: ^Asset_IO_Result) {
	if result == nil {
		return
	}

	if result.decoded_bytes > 0 {
		assets_io_release_decoded_credit(result.decoded_bytes)
		result.decoded_bytes = 0
	}

	if result.surface != nil {
		sdl.DestroySurface(result.surface)
		result.surface = nil
	}

	if len(result.path) > 0 {
		delete(result.path, result.path_allocator)
		result.path = ""
	}

	if len(result.diagnostic) > 0 {
		delete(result.diagnostic)
		result.diagnostic = ""
	}
}

@(private)
assets_io_take_job :: proc(pool: ^Asset_IO_Pool) -> (Asset_IO_Job, bool) {
	sync.mutex_lock(&pool.queue_mutex)
	defer sync.mutex_unlock(&pool.queue_mutex)

	if len(pool.queue) == 0 {
		return {}, false
	}

	job := pool.queue[0]
	ordered_remove(&pool.queue, 0)

	return job, true
}

@(private)
assets_io_signal_completion :: proc(pool: ^Asset_IO_Pool) {
	sync.sema_post(&pool.done_sema)

	// Host-safe wake: user event reaches the idle wait without touching engine state.
	ev: sdl.Event
	ev.type = .USER
	_ = sdl.PushEvent(&ev)
}

@(private)
assets_io_worker :: proc(slot: ^Asset_IO_Pool_Slot) {
	if slot == nil || slot.pool == nil {
		return
	}

	pool := slot.pool
	for {
		sync.sema_wait(&slot.work_sema)
		if pool.quit {
			return
		}

		for {
			if pool.quit {
				return
			}

			job, ok := assets_io_take_job(pool)
			if !ok {
				break
			}

			// Decode only — do not heap-allocate diagnostics on the worker
			// (worker allocator ≠ owner tracking allocator).
			surface, loaded := assets_load_surface(job.path)
			decoded: u64
			if loaded && surface != nil {
				decoded = u64(surface.w) * u64(surface.h) * 4
			}

			result := Asset_IO_Result {
				id                = job.id,
				generation        = job.generation,
				request_token     = job.request_token,
				device_generation  = job.device_generation,
				path              = job.path,
				path_allocator    = job.path_allocator,
				surface           = surface,
				ok                = loaded,
				decoded_bytes     = decoded,
			}

			for {
				sync.mutex_lock(&pool.results_mutex)
				if pool.quit {
					pool.inflight = max(0, pool.inflight - 1)
					sync.mutex_unlock(&pool.results_mutex)

					if result.surface != nil {
						sdl.DestroySurface(result.surface)
						result.surface = nil
					}

					delete(result.path, result.path_allocator)
					delete(result.diagnostic)

					return
				}

				credit_ok :=
					decoded == 0 ||
					pool.decoded_bytes + decoded <= ASSET_IO_MAX_INFLIGHT_DECODED
				if len(pool.results) < ASSET_IO_RESULT_SLOTS && credit_ok {
					pool.decoded_bytes += decoded
					append(&pool.results, result)
					pool.inflight = max(0, pool.inflight - 1)
					sync.mutex_unlock(&pool.results_mutex)
					assets_io_signal_completion(pool)

					break
				}

				sync.mutex_unlock(&pool.results_mutex)
				sync.sema_wait(&pool.done_sema)
			}
		}
	}
}

/*
Queues a Pending asset id for background decode. `path` is cloned for the worker.
*/
assets_io_enqueue :: proc(id: Asset_Id, path: string, generation: u32, request_token: u64) -> bool {
	if state == nil || len(path) == 0 {
		return false
	}

	if !assets_io_pool_ensure() {
		return false
	}

	pool := state.assets.io_pool
	sync.mutex_lock(&pool.queue_mutex)
	defer sync.mutex_unlock(&pool.queue_mutex)

	if len(pool.queue) + pool.inflight >= ASSET_IO_MAX_REQUESTS {
		return false
	}

	// Capture an absolute request path so later CWD changes cannot retarget jobs.
	job_path: string
	if abs_path, abs_err := filepath.abs(path); abs_err == nil && len(abs_path) > 0 {
		job_path = abs_path
	} else {
		job_path = strings.clone(path)
	}

	job := Asset_IO_Job {
		id               = id,
		generation       = generation,
		request_token    = request_token,
		device_generation = pool.device_generation,
		path             = job_path,
		path_allocator   = context.allocator,
	}
	append(&pool.queue, job)
	pool.inflight += 1

	sync.sema_post(&pool.slots[0].work_sema)

	return true
}

/*
True when decode results are waiting for the owner.
*/
assets_io_has_completions :: proc() -> bool {
	if state == nil || state.assets.io_pool == nil {
		return false
	}

	pool := state.assets.io_pool
	sync.mutex_lock(&pool.results_mutex)
	has := len(pool.results) > 0
	sync.mutex_unlock(&pool.results_mutex)

	return has
}

/*
Owner-only: applies up to ASSET_IO_DRAIN_PER_FRAME completions.

Decode success keeps status Pending and queues deferred upload; Ready is published
only after `texture_uploads_flush` submits upload commands.
*/
assets_io_drain :: proc() {
	if state == nil || state.assets.io_pool == nil {
		return
	}

	pool := state.assets.io_pool

	sync.mutex_lock(&pool.results_mutex)
	if len(pool.results) == 0 {
		sync.mutex_unlock(&pool.results_mutex)

		return
	}

	n := min(len(pool.results), ASSET_IO_DRAIN_PER_FRAME)
	local: [dynamic]Asset_IO_Result
	append(&local, ..pool.results[:n])
	copy(pool.results[:], pool.results[n:])
	resize(&pool.results, len(pool.results) - n)
	remaining := len(pool.results) > 0
	sync.mutex_unlock(&pool.results_mutex)
	defer delete(local)

	changed := false
	for &result in local {
		index := int(result.id)
		if index <= 0 || index >= len(state.textures.records) {
			assets_io_free_result(&result)
			continue
		}

		entry := &state.textures.records[index]
		if entry.generation != result.generation ||
		   entry.request_token != result.request_token ||
		   result.device_generation != assets_io_device_generation {
			assets_io_free_result(&result)
			continue
		}

		if entry.status != .Pending {
			assets_io_free_result(&result)
			continue
		}

		if !result.ok || result.surface == nil {
			entry.status = .Failed
			entry.w = 0
			entry.h = 0
			entry.awaiting_upload = false
			assets_free_string(&entry.diagnostic)
			if len(result.diagnostic) > 0 {
				entry.diagnostic = strings.clone(result.diagnostic)
			} else {
				entry.diagnostic = strings.clone("decode failed")
			}

			assets_io_free_result(&result)
			changed = true
			continue
		}

		if entry.surface != nil {
			sdl.DestroySurface(entry.surface)
			entry.surface = nil
		}

		entry.surface = result.surface
		result.surface = nil
		entry.decoded_credit = result.decoded_bytes
		result.decoded_bytes = 0
		entry.w = entry.surface.w
		entry.h = entry.surface.h

		if state.gpu == nil || !texture_upload_record(entry, true, result.id) {
			sdl.DestroySurface(entry.surface)
			entry.surface = nil
			entry.w = 0
			entry.h = 0
			entry.status = .Failed
			entry.awaiting_upload = false
			assets_io_release_decoded_credit(entry.decoded_credit)
			entry.decoded_credit = 0
			assets_free_string(&entry.diagnostic)
			entry.diagnostic = strings.clone("GPU texture allocation failed")
			assets_io_free_result(&result)
			changed = true
			continue
		}

		// Stay Pending until upload flush publishes Ready.
		assets_io_free_result(&result)
		changed = true
	}

	// Wake workers blocked on full result slots / decoded-byte credit.
	for _ in 0 ..< n {
		sync.sema_post(&pool.done_sema)
	}

	if remaining {
		request_frame()
	}

	if changed {
		request_frame()
	}
}

/*
Blocks until the IO queue and inflight jobs are idle, drains, flushes uploads,
and publishes Ready. Used by tests and shutdown paths that need deterministic status.
*/
assets_io_wait_idle :: proc() {
	if state == nil {
		return
	}

	for state.assets.io_pool != nil {
		pool := state.assets.io_pool
		sync.mutex_lock(&pool.queue_mutex)
		sync.mutex_lock(&pool.results_mutex)
		idle := len(pool.queue) == 0 && pool.inflight == 0 && len(pool.results) == 0
		has_results := len(pool.results) > 0
		sync.mutex_unlock(&pool.results_mutex)
		sync.mutex_unlock(&pool.queue_mutex)

		if has_results {
			assets_io_drain()
			continue
		}

		if idle {
			break
		}

		sync.sema_wait(&pool.done_sema)
		assets_io_drain()
	}

	assets_io_drain()
	if state.gpu != nil {
		_ = texture_uploads_flush(state.gpu)
	}
}
