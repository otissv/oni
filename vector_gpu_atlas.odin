package oni

import "core:math"
import "core:slice"
import sdl "vendor:sdl3"

@(private)
Vector_Atlas_Job :: struct {
	record, draw, first, depth: int,
	mask, msaa, stencil: bool,
	bounds, clip: Rect,
	origin: Vec2,
}

@(private)
vector_atlas_collect :: proc(first, draw: int, jobs: ^[dynamic]Vector_Atlas_Job) -> (int, bool) {
	depth := 0
	for index := first; index >= 0; index = vector_frame().records[index].next {
		record := &vector_frame().records[index]
		if record.opacity <= 0 || record.bounds.w <= 0 || record.bounds.h <= 0 { continue }
		child_depth, child_ok := vector_atlas_collect(record.first_child, draw, jobs)
		mask_depth, mask_ok := vector_atlas_collect(record.first_mask, draw, jobs)
		if !child_ok || !mask_ok { return 0, false }
		level := max(child_depth, mask_depth)
		if record.kind == .Group || record.kind == .Mask {
			level += 1
			if _, err := append(jobs, Vector_Atlas_Job{record = index, draw = draw, first = record.first_child, depth = level,
				bounds = record.bounds, msaa = vector_gpu_list_needs_msaa(record.first_child), stencil = vector_gpu_list_needs_stencil(record.first_child)}); err != nil { return 0, false }
			if record.kind == .Mask {
				if _, err := append(jobs, Vector_Atlas_Job{record = index, draw = draw, first = record.first_mask, depth = level,
					bounds = record.bounds, clip = record.clip, mask = true, msaa = true, stencil = vector_gpu_list_needs_stencil(record.first_mask)}); err != nil { return 0, false }
			}
		}
		depth = max(depth, level)
	}
	return depth, true
}

@(private)
vector_atlas_job_before :: proc(a, b: Vector_Atlas_Job) -> bool {
	if a.depth != b.depth { return a.depth < b.depth }
	if a.msaa != b.msaa { return !a.msaa }
	return !a.stencil && b.stencil
}

// Shelf packing includes a transparent pixel around every tile. No tile can
// sample a neighbor through bilinear filtering at a composite boundary.
@(private)
vector_atlas_pack :: proc(jobs: []Vector_Atlas_Job) -> (count: int, bounds: Rect) {
	x, y, row_height, width := 0, 0, 0, 0
	for &job, i in jobs {
		if i > 0 && (job.depth != jobs[0].depth || job.msaa != jobs[0].msaa || job.stencil != jobs[0].stencil) { break }
		w, h := int(math.ceil(job.bounds.w)) + 2, int(math.ceil(job.bounds.h)) + 2
		if w > 256 || h > 512 { break }
		if x + w > 256 { x, y, row_height = 0, y + row_height, 0 }
		if y + h > 512 { break }
		job.origin = {f32(x + 1), f32(y + 1)}
		x += w
		row_height = max(row_height, h)
		width = max(width, x)
		count += 1
	}
	return count, {0, 0, f32(width), f32(y + row_height)}
}

@(private)
vector_gpu_render_atlas_page :: proc(cmd: ^sdl.GPUCommandBuffer, target_index: int, jobs: []Vector_Atlas_Job) -> bool {
	if test_hook_vector_fail_pass_after > 0 {
		test_hook_vector_fail_pass_after -= 1
		if test_hook_vector_fail_pass_after == 0 { return false }
	}
	frame := vector_gpu_frame()
	target := frame.pool[target_index]
	work := u64(target.alloc_w) * u64(target.alloc_h) * (target.msaa ? u64(4) : 1)
	if work > VECTOR_MAX_SAMPLE_WORK - min(state.vector.gpu.sample_work, VECTOR_MAX_SAMPLE_WORK) { return false }
	state.vector.gpu.sample_work += work
	state.vector.gpu.command_visits += 1
	if state.vector.gpu.command_visits > VECTOR_MAX_COMMAND_VISITS { return false }
	colour := sdl.GPUColorTargetInfo{texture = target.colour, load_op = .CLEAR,
		store_op = target.msaa ? .RESOLVE : .STORE, resolve_texture = target.msaa ? target.resolved : nil}
	depth := sdl.GPUDepthStencilTargetInfo{texture = target.depth, load_op = .CLEAR, store_op = .DONT_CARE,
		stencil_load_op = .CLEAR, stencil_store_op = .DONT_CARE}
	pass := sdl.BeginGPURenderPass(cmd, &colour, 1, target.has_depth ? &depth : nil)
	if pass == nil { return false }
	for &job in jobs {
		sdl.SetGPUViewport(pass, {x = job.origin.x, y = job.origin.y, w = job.bounds.w, h = job.bounds.h, min_depth = 0, max_depth = 1})
		clip := job.bounds
		if job.clip.w > 0 && job.clip.h > 0 { clip = rect_intersect(clip, job.clip) }
		vector_gpu_draw_list(cmd, pass, job.first, job.bounds, clip, msaa = target.msaa,
			with_depth = target.has_depth, viewport_origin = job.origin)
		vector_gpu_release_list_outputs(job.first)
	}
	sdl.EndGPURenderPass(pass)
	return true
}

// A bounded group of independent submissions shares intermediate render passes.
// Dependencies run before parents; reference counts keep a shared page live
// until every consumer has finished recording its sampling commands.
@(private)
vector_gpu_prepare_atlas_batch :: proc(cmd: ^sdl.GPUCommandBuffer, begin, end: int, failed: ^int) -> bool {
	jobs := make([dynamic]Vector_Atlas_Job, context.temp_allocator)
	for draw in begin ..< end {
		if !vector_frame().draws[draw].failed {
			if _, ok := vector_atlas_collect(vector_frame().draws[draw].first, draw, &jobs); !ok { failed^ = draw; return false }
		}
	}
	for &job in jobs {
		if job.bounds.w > 254 || job.bounds.h > 510 {
			for draw in begin ..< end {
				if vector_frame().draws[draw].failed { continue }
				if !vector_gpu_prepare_list(cmd, vector_frame().draws[draw].first) { failed^ = draw; return false }
			}
			return true
		}
	}
	slice.sort_by(jobs[:], vector_atlas_job_before)
	for start := 0; start < len(jobs); {
		count, bounds := vector_atlas_pack(jobs[start:])
		if count == 0 { failed^ = jobs[start].draw; return false }
		page_jobs := jobs[start:][:count]
		for &job in page_jobs {
			if job.mask { continue }
			work := u64(job.bounds.w) * u64(job.bounds.h) * 4
			if work > VECTOR_MAX_SAMPLE_WORK - min(state.vector.gpu.sample_work, VECTOR_MAX_SAMPLE_WORK) { failed^ = job.draw; return false }
			state.vector.gpu.sample_work += work
			state.vector.gpu.command_visits += 1
			if state.vector.gpu.command_visits > VECTOR_MAX_COMMAND_VISITS { failed^ = job.draw; return false }
		}
		page, ok := vector_gpu_pool_target(bounds, page_jobs[0].msaa, page_jobs[0].stencil)
		if !ok { failed^ = page_jobs[0].draw; return false }
		frame := vector_gpu_frame()
		frame.pool[page].atlas_refs = count
		for &job in page_jobs {
			uv := Vec2{job.origin.x / frame.pool[page].alloc_w, job.origin.y / frame.pool[page].alloc_h}
			if job.mask {
				frame.outputs[job.record].mask, frame.outputs[job.record].mask_uv = page, uv
			} else {
				frame.outputs[job.record].content, frame.outputs[job.record].content_uv = page, uv
			}
		}
		if !vector_gpu_render_atlas_page(cmd, page, page_jobs) { failed^ = page_jobs[0].draw; return false }
		start += count
	}
	return true
}
