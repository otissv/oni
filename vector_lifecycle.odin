package oni

/*
Snapshot of retained vector CPU/GPU bookkeeping for diagnostics and the M8 stress gallery.
*/
Vector_Stats :: struct {
	live_paths:         int,
	path_cache_bytes:   u64,
	gpu_bytes:          u64,
	gpu_pool_bytes:     u64,
	geometry_epoch:     u64,
	tess_workers:       int,
	encode_fence_ms:    f64,
	encode_upload_ms:   f64,
	encode_record_ms:   f64,
	sample_work:        u64,
	command_visits:     u64,
	svg_path_bytes: u64,
	pair_tests, exact_ops: int,
	encode_attempts: int,
	gpu_peak_bytes: u64,
	gpu_current, gpu_peak: [Vector_Resource_Category]u64,
}

Vector_Resource_Category :: enum { Scene_Targets, Intermediate_Targets, Buffers, Gradient_Ramps, Other_Textures }

@(private)
vector_gpu_current_bytes :: proc() -> (bytes: [Vector_Resource_Category]u64) {
	for frame in state.vector.gpu.frames {
		bytes[.Scene_Targets] += frame.root.bytes
		for target in frame.pool { bytes[.Intermediate_Targets] += target.bytes }
		bytes[.Buffers] += frame.buffer_bytes
		bytes[.Gradient_Ramps] += frame.ramp_bytes
	}
	if state.vector.gpu.white != nil { bytes[.Other_Textures] = 4 }
	return
}

@(private)
vector_gpu_note_peak :: proc(extra: u64, category: Vector_Resource_Category) {
	g := &state.vector.gpu
	current := vector_gpu_current_bytes()
	current[category] += extra
	for kind in Vector_Resource_Category { g.peak[kind] = max(g.peak[kind], current[kind]) }
	g.peak_bytes = max(g.peak_bytes, g.bytes + extra)
}

vector_stats :: proc() -> Vector_Stats {
	if state == nil {
		return {}
	}

	live := 0
	for entry in state.vector.paths {
		if entry.live {
			live += 1
		}
	}

	g := state.vector.gpu

	return {
		live_paths       = live,
		path_cache_bytes   = state.vector.path_cache_bytes,
		gpu_bytes          = g.bytes,
		gpu_pool_bytes     = g.pool_bytes,
		geometry_epoch     = g.geometry_epoch,
		tess_workers       = state.vector.tess_workers,
		encode_fence_ms    = g.encode_fence_ms,
		encode_upload_ms   = g.encode_upload_ms,
		encode_record_ms   = g.encode_record_ms,
		sample_work        = g.sample_work,
		command_visits     = g.command_visits,
		svg_path_bytes = state.vector.svg_path_bytes,
		pair_tests = vector_frame().pair_tests,
		exact_ops = vector_frame().exact_ops,
		encode_attempts = g.encode_attempts,
		gpu_peak_bytes = g.peak_bytes,
		gpu_current = vector_gpu_current_bytes(),
		gpu_peak = g.peak,
	}
}

// Tracks device recreation while retaining CPU path caches.
vector_after_gpu_recreate :: proc() {
	if state == nil {
		return
	}

	state.vector.gpu.geometry_epoch += 1
	for &frame in state.vector.gpu.frames { frame.index_snapshot_valid = false }
}
