#+test
package oni

import "core:strings"
import "core:testing"
import sdl "vendor:sdl3"

@(test)
debug_memory_linux_status_parses_bytes_and_ignores_unrelated_fields :: proc(t: ^testing.T) {
	s := debug_memory_parse_linux_status("Name:\toni-app\nVmSize: 999999 kB\nVmRSS:\t 275456 kB\nVmHWM: 300000 kB\nRssAnon: 200000 kB\nRssFile: 70000 kB\nRssShmem: 5456 kB\nThreads: 18\n")
	testing.expect(t, s.available && s.breakdown_available)
	testing.expect_value(t, s.resident_bytes, u64(275456 * 1024))
	testing.expect_value(t, s.peak_resident_bytes, u64(300000 * 1024))
	testing.expect_value(t, s.anonymous_bytes + s.file_bytes + s.shared_bytes, s.resident_bytes)
	partial := debug_memory_parse_linux_status("VmRSS: 123 kB\nVmHWM: 456 kB\n")
	testing.expect(t, partial.available && !partial.breakdown_available)
}

@(test)
debug_memory_linux_status_rejects_missing_malformed_and_overflow_values :: proc(t: ^testing.T) {
	for text in ([]string{"", "VmSize: 100 kB\n", "VmRSS: 12 MB\nVmHWM: 12 kB\n", "VmRSS: -1 kB\nVmHWM: 12 kB\n", "VmRSS: 12x kB\nVmHWM: 12 kB\n", "VmRSS: 18446744073709551615 kB\nVmHWM: 12 kB\n"}) {
		testing.expect(t, !debug_memory_parse_linux_status(text).available, text)
	}
}

@(test)
debug_memory_process_sampling_reads_self_without_retaining_allocations :: proc(t: ^testing.T) {
	for _ in 0 ..< 4 {
		s := debug_memory_process()
		when ODIN_OS == .Linux {
			testing.expect(t, s.available, "/proc/self/status must be readable on the Linux test host")
			testing.expect(t, s.resident_bytes > 0)
			testing.expect(t, s.peak_resident_bytes >= s.resident_bytes)
		} else {
			testing.expect(t, !s.available)
		}
	}
}

@(test)
debug_memory_snapshot_counts_retained_capacity_and_live_resources :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		layout := &state.ui.layout.frame_arena
		scratch := &state.ui.render_scratch
		defer layout_frame_arena_chain_free_blocks(layout)
		defer layout_frame_arena_chain_free_blocks(scratch)
		layout_frame_arena_push_block(layout, 0)
		layout_frame_arena_push_block(scratch, 0)
		_, err := layout_frame_arena_take(&layout.blocks[0], 1024, 8)
		testing.expect_value(t, err, nil)
		_, err = layout_frame_arena_take(&scratch.blocks[0], 2048, 8)
		testing.expect_value(t, err, nil)
		for &b in state.gpu_state.batches {
			reserve(&b.vertices, 8)
			reserve(&b.indices, 12)
			// Capacity without live GPU handles must not count as GPU memory.
			b.vertex_capacity = 65536
			b.index_capacity = 393216
			b.transfer_capacity = 1024
		}
		surface := sdl.CreateSurface(16, 8, .RGBA8888)
		testing.expect(t, surface != nil)
		if surface == nil {

			return
		}
		defer sdl.DestroySurface(surface)
		append(&state.textures.records, Texture_Record{surface = surface, w = 16, h = 8})
		defer delete(state.textures.records)
		state.vector.gpu.bytes = 4096
		state.vector.gpu.pool_bytes = 1024
		state.vector.path_cache_bytes = 2048
		state.vector.svg_path_bytes = 1024
		s := debug_memory_snapshot()
		testing.expect_value(t, s.layout_used_bytes, u64(1024))
		testing.expect_value(t, s.scratch_used_bytes, u64(2048))
		testing.expect_value(t, s.layout_capacity_bytes, u64(layout_frame_arena_chain_total_capacity(layout)))
		testing.expect_value(t, s.scratch_capacity_bytes, u64(layout_frame_arena_chain_total_capacity(scratch)))
		testing.expect_value(t, s.texture_cpu_bytes, u64(surface.pitch * surface.h))
		testing.expect_value(t, s.texture_gpu_bytes, u64(0))
		testing.expect_value(t, s.texture_count, 1)
		expected_cpu := u64(0)
		for &b in state.gpu_state.batches {
			expected_cpu += u64(cap(b.vertices) * size_of(UI_Vertex) + cap(b.indices) * size_of(u16))
		}
		testing.expect_value(t, s.batch_cpu_bytes, expected_cpu)
		testing.expect_value(t, s.batch_gpu_bytes, u64(0))
		testing.expect_value(t, s.batch_upload_bytes, u64(0))
		testing.expect_value(t, s.vector_gpu_bytes, u64(4096))
		testing.expect_value(t, s.vector_pool_bytes, u64(1024))
		testing.expect_value(t, s.vector_cache_bytes, u64(3072))
	})
}

@(test)
debug_memory_gpu_snapshot_counts_both_slots_and_texture_copies :: proc(t: ^testing.T) {
	with_present_env(t, proc(t: ^testing.T) {
		testing.expect(t, texture_atlas_init())
		s := debug_memory_snapshot()
		testing.expect_value(t, s.texture_cpu_bytes, u64(512 * 512 * 4))
		testing.expect_value(t, s.texture_gpu_bytes, u64(512 * 512 * 4))
		testing.expect(t, s.batch_gpu_bytes <= 1024 * 1024, "empty UI batch slots must reserve at most 1 MiB combined")
		testing.expect_value(t, s.batch_gpu_bytes, u64(2 * BATCH_INITIAL_VERT_CAPACITY * (size_of(UI_Vertex) + 6 * size_of(u16))))
		present_frame(present_test_quad_draw)
		s = debug_memory_snapshot()
		testing.expect(t, s.batch_cpu_bytes > 0)
		testing.expect(t, s.batch_upload_bytes >= 4 * size_of(UI_Vertex) + 6 * size_of(u16))
		batch_destroy()
		s = debug_memory_snapshot()
		testing.expect_value(t, s.batch_cpu_bytes, u64(0))
		testing.expect_value(t, s.batch_gpu_bytes, u64(0))
		testing.expect_value(t, s.batch_upload_bytes, u64(0))
	})
}

@(test)
debug_memory_sampling_is_throttled_and_stops_when_hidden :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		state.vector.gpu.bytes = 123
		debug_overlay_begin_present()
		debug_overlay_end_present(1_000_000_000)
		testing.expect_value(t, render_stats().memory.vector_gpu_bytes, u64(0))
		debug_overlay_set_visible(true)
		debug_overlay_begin_present()
		debug_overlay_end_present(1_010_000_000)
		testing.expect_value(t, render_stats().memory.vector_gpu_bytes, u64(123))
		state.vector.gpu.bytes = 456
		debug_overlay_begin_present()
		debug_overlay_end_present(1_020_000_000)
		testing.expect_value(t, render_stats().memory.vector_gpu_bytes, u64(123))
		debug_overlay_begin_present()
		debug_overlay_end_present(1_260_000_000)
		testing.expect_value(t, render_stats().memory.vector_gpu_bytes, u64(456))
		debug_overlay_set_visible(false)
		state.vector.gpu.bytes = 789
		debug_overlay_begin_present()
		debug_overlay_end_present(2_000_000_000)
		testing.expect_value(t, render_stats().memory.vector_gpu_bytes, u64(456))
		debug_overlay_set_visible(true)
		debug_overlay_begin_present()
		debug_overlay_end_present(2_010_000_000)
		testing.expect_value(t, render_stats().memory.vector_gpu_bytes, u64(789))
		state.debug_overlay.minimized = true
		state.vector.gpu.bytes = 987
		debug_overlay_begin_present()
		debug_overlay_end_present(3_000_000_000)
		testing.expect_value(t, render_stats().memory.vector_gpu_bytes, u64(789))
		state.debug_overlay.minimized = false
		debug_overlay_begin_present()
		debug_overlay_end_present(3_010_000_000)
		testing.expect_value(t, render_stats().memory.vector_gpu_bytes, u64(987))
		state.vector.gpu.bytes = 654
		debug_overlay_begin_present()
		debug_overlay_end_present(1_000_000_000)
		testing.expect_value(t, render_stats().memory.vector_gpu_bytes, u64(654))
	})
}

@(test)
debug_memory_overlay_labels_measured_ram_and_estimated_gpu_separately :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		state.debug_overlay.stats.memory.process = {available = true, breakdown_available = true,
			resident_bytes = 269 * 1024 * 1024, peak_resident_bytes = 300 * 1024 * 1024}
		debug_overlay_format()
		text := string(state.debug_overlay.text[:state.debug_overlay.text_length])
		for label in ([]string{"RAM: 269.0 MiB", "Peak: 300.0", "Anon/file/shared", "Layout used/cap", "Scratch used/cap", "Textures CPU/GPU", "Batch CPU/GPU", "Uploads", "Vector GPU/pool", "GPU = estimates"}) {
			testing.expect(t, strings.contains(text, label), label)
		}
		testing.expect(t, state.debug_overlay.text_length < len(state.debug_overlay.text) - 1, "diagnostics must fit without truncation")
		state.debug_overlay.stats.memory.process = {}
		debug_overlay_format()
		text = string(state.debug_overlay.text[:state.debug_overlay.text_length])
		testing.expect(t, strings.contains(text, "RAM: unavailable"))
	})
}
