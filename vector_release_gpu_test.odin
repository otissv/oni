#+test
package oni

import "core:testing"

@(test)
vector_gpu_composition_workload_fits_two_slot_target_pool :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 1920, 1080) { return }
		asset, result := Load_Svg_File("fixtures/vector/benchmark/composition.svg")
		defer Destroy_Svg_Asset(asset)
		defer Destroy_Svg_Load_Result(&result)
		testing.expect(t, result.ok)
		if !result.ok { return }
		for _ in 0 ..< 2 {
			draw_record_begin(state.dpi)
			for i in 0 ..< 256 {
				transform := Vector_Transform{1, 0, 0, 1, f64(208 + i % 16 * 96), f64(36 + i / 16 * 64)}
				testing.expect_value(t, Draw_Svg_Asset(asset, transform), Vector_Error.None)
			}
			draw_record_end()
			if !vector_composition_gpu_submit(t) { return }
			testing.expect(t, state.vector.gpu.pool_bytes <= VECTOR_TARGET_POOL_BUDGET)
			testing.expect(t, state.vector.gpu.bytes <= VECTOR_GPU_BUDGET)
			vector_gpu_advance_frame()
			batch_reset()
			batch_flip()
		}
	})
}

@(test)
vector_gpu_submitted_error_frames_are_fenced_before_slot_reuse :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 32, 32) { return }
		for _ in 0 ..< 6 {
			draw_record_begin(state.dpi)
			nodes := [1]Vector_Node{vector_test_rect({0, 0, 16, 16}, {255, 0, 0, 255})}
			testing.expect_value(t, Draw_Vector_Scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
			draw_record_end()
			cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {})
			testing.expect(t, cmd != nil)
			if cmd == nil { return }
			slot := state.vector.gpu.frame_index
			vector_gpu_submit_frame(cmd)
			testing.expect(t, state.vector.gpu.frames[slot].fence != nil)
			testing.expect_value(t, state.vector.gpu.frame_index, (slot + 1) % 2)
			batch_reset()
			batch_flip()
		}
	})
}

@(test)
vector_gpu_upload_failure_keeps_ordered_ordinary_ui_for_fallback :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 32, 32) { return }
		draw_record_begin(state.dpi)
		draw_rect({0, 0, 32, 32}, {0, 0, 255, 255})
		nodes := [1]Vector_Node{vector_test_rect({0, 0, 16, 16}, {255, 0, 0, 255})}
		testing.expect_value(t, Draw_Vector_Scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
		draw_rect({16, 16, 8, 8}, {0, 255, 0, 255})
		draw_record_end()
		ordinary := 0
		for segment in batch_current().segments { if !segment.vector { ordinary += 1 } }
		test_hook_vector_fail_map = true
		cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {})
		test_hook_vector_fail_map = false
		testing.expect(t, cmd == nil)
		vector_discard_frame_submissions()
		testing.expect_value(t, len(batch_current().segments), ordinary)
		testing.expect_value(t, len(vector_frame().draws), 0)
		for segment in batch_current().segments { testing.expect(t, !segment.vector) }
	})
}
