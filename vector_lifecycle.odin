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
	}
}

// Invalidates GPU upload reuse after device recreation while retaining CPU path caches.
vector_after_gpu_recreate :: proc() {
	if state == nil {
		return
	}

	state.vector.gpu.geometry_epoch += 1
	for &frame in state.vector.gpu.frames {
		frame.uploaded_geometry_epoch = 0
		frame.uploaded_vertex_revision = 0
		frame.uploaded_vertex_bytes = 0
		frame.uploaded_index_bytes = 0
	}
}
