#+test
package oni

import "core:testing"
import sdl "vendor:sdl3"

@(test)
vector_gpu_upload_failures_release_partial_replacements :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_gpu_shutdown()
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		for failure in 1 ..= 6 {
			nodes := [1]Vector_Node{vector_test_rect({0, 0, 12, 12}, {255, 0, 0, 255})}
			testing.expect_value(t, draw_vector_scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
			cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
			testing.expect(t, cmd != nil)
			if cmd == nil { return }
			test_hook_vector_fail_buffer_after = failure <= 4 ? failure : 0
			test_hook_vector_fail_transfer = failure == 5
			test_hook_vector_fail_map = failure == 6
			testing.expect(t, !vector_gpu_upload(cmd))
			testing.expect(t, sdl.CancelGPUCommandBuffer(cmd))
			testing.expect_value(t, vector_gpu_frame().buffer_bytes, u64(0))
			testing.expect_value(t, state.vector.gpu.bytes, u64(0))
			for buffer in vector_gpu_frame().buffers { testing.expect(t, buffer == nil) }
			testing.expect(t, vector_gpu_frame().transfer == nil)
			test_hook_vector_fail_buffer_after = 0
			test_hook_vector_fail_transfer = false
			test_hook_vector_fail_map = false
			cmd = sdl.AcquireGPUCommandBuffer(state.gpu)
			testing.expect(t, cmd != nil)
			if cmd == nil { return }
			testing.expect(t, vector_gpu_upload(cmd))
			testing.expect(t, sdl.CancelGPUCommandBuffer(cmd))
			old_buffers, old_transfer, old_bytes := vector_gpu_frame().buffers, vector_gpu_frame().transfer, state.vector.gpu.bytes
			testing.expect_value(t, draw_vector_scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
			cmd = sdl.AcquireGPUCommandBuffer(state.gpu)
			testing.expect(t, cmd != nil)
			if cmd == nil { return }
			test_hook_vector_fail_buffer_after = 2
			testing.expect(t, !vector_gpu_upload(cmd))
			testing.expect(t, sdl.CancelGPUCommandBuffer(cmd))
			testing.expect_value(t, vector_gpu_frame().buffers, old_buffers)
			testing.expect_value(t, vector_gpu_frame().transfer, old_transfer)
			testing.expect_value(t, state.vector.gpu.bytes, old_bytes)
			test_hook_vector_fail_buffer_after = 0
			vector_gpu_shutdown()
			vector_scene_shutdown()
			batch_reset()
			testing.expect_value(t, state.vector.gpu.bytes, u64(0))
		}
	})
}

@(test)
vector_gpu_partial_initialization_releases_owned_resources :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_gpu_shutdown()
		for failure in 0 ..< 4 {
			// Vert/frag hooks fail during MSAA ui_pipeline creation; lcd hook covers
			// lcd_pipeline; sampler fails after pipelines are built.
			test_hook_gpu_fail_vert_shader = failure == 0
			test_hook_gpu_fail_frag_shader = failure == 1
			test_hook_gpu_fail_lcd_pipeline = failure == 2
			test_hook_gpu_fail_sampler = failure == 3
			testing.expect(t, !vector_gpu_init(.R8G8B8A8_UNORM))
			testing.expect(t, state.vector.gpu.pipeline == nil && state.vector.gpu.pipeline_depth == nil)
			testing.expect(t, state.vector.gpu.ui_pipeline == nil && state.vector.gpu.ui_pipeline_depth == nil)
			testing.expect(t, state.vector.gpu.lcd_pipeline == nil && state.vector.gpu.lcd_pipeline_depth == nil)
			testing.expect(t, state.vector.gpu.white == nil && state.vector.gpu.sampler == nil)
			testing.expect_value(t, state.vector.gpu.bytes, u64(0))
			test_hook_gpu_fail_vert_shader = false
			test_hook_gpu_fail_frag_shader = false
			test_hook_gpu_fail_lcd_pipeline = false
			test_hook_gpu_fail_sampler = false
		}
		testing.expect(t, vector_gpu_init(.R8G8B8A8_UNORM))
		testing.expect(t, state.vector.gpu.ui_pipeline != nil && state.vector.gpu.ui_pipeline_depth != nil)
		testing.expect(t, state.vector.gpu.lcd_pipeline != nil && state.vector.gpu.lcd_pipeline_depth != nil)
	})
}

@(test)
vector_gpu_shared_msaa_shutdown_releases_root_and_pipelines :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		state.gpu_state.pipeline = gpu_create_ui_layout_pipeline(state.gpu, .R8G8B8A8_UNORM, .UI_Fragment, gpu_blend_state())
		state.gpu_state.sampler = gpu_create_sampler(state.gpu)
		state.gpu_state.white_texture = gpu_create_white_texture(state.gpu)
		testing.expect(t, state.gpu_state.pipeline != nil && state.gpu_state.sampler != nil && state.gpu_state.white_texture != nil)
		if state.gpu_state.pipeline == nil || state.gpu_state.sampler == nil || state.gpu_state.white_texture == nil {
			return
		}
		batch_init()
		state.ui.pass = .Draw
		state.dpi = {logical_w = 64, logical_h = 64, drawable_w = 64, drawable_h = 64, scale = 1}
		gpu_update_projection(state.dpi)
		for _ in 0 ..< len(state.vector.gpu.frames) {
			draw_record_begin(state.dpi)
			draw_rect({0, 0, 64, 16}, {0, 0, 255, 255})
			nodes := [1]Vector_Node{vector_test_rect({8, 24, 32, 32}, {255, 0, 0, 255})}
			testing.expect_value(t, draw_vector_scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
			draw_record_end()
			cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {})
			testing.expect(t, cmd != nil)
			if cmd == nil {
				return
			}
			submitted := vector_gpu_frame()
			testing.expect(t, submitted.root.colour != nil && submitted.root.resolved != nil)
			testing.expect(t, state.vector.gpu.ui_pipeline != nil && state.vector.gpu.ui_pipeline_depth != nil)
			testing.expect(t, state.vector.gpu.lcd_pipeline != nil && state.vector.gpu.lcd_pipeline_depth != nil)
			testing.expect(t, state.vector.gpu.bytes > 0)
			submitted.fence = sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
			testing.expect(t, submitted.fence != nil)
			if submitted.fence == nil {
				return
			}
			vector_gpu_advance_frame()
			batch_reset()
		}
		vector_gpu_shutdown()
		testing.expect_value(t, state.vector.gpu.bytes, u64(0))
		testing.expect_value(t, state.vector.gpu.pool_bytes, u64(0))
		testing.expect(t, state.vector.gpu.pipeline == nil && state.vector.gpu.pipeline_depth == nil)
		testing.expect(t, state.vector.gpu.ui_pipeline == nil && state.vector.gpu.ui_pipeline_depth == nil)
		testing.expect(t, state.vector.gpu.lcd_pipeline == nil && state.vector.gpu.lcd_pipeline_depth == nil)
		testing.expect(t, state.vector.gpu.white == nil && state.vector.gpu.sampler == nil)
		for frame in state.vector.gpu.frames {
			testing.expect(t, frame.fence == nil && frame.transfer == nil)
			testing.expect(t, frame.root.colour == nil && frame.root.resolved == nil && frame.root.depth == nil)
			testing.expect_value(t, frame.root.bytes, u64(0))
			for buffer in frame.buffers {
				testing.expect(t, buffer == nil)
			}
			testing.expect_value(t, cap(frame.pool), 0)
			testing.expect_value(t, cap(frame.outputs), 0)
		}
	})
}

@(test)
vector_gpu_one_hundred_cycles_retire_both_frame_slots :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		state.gpu_state.pipeline = gpu_create_ui_layout_pipeline(state.gpu, .R8G8B8A8_UNORM, .UI_Fragment, gpu_blend_state())
		testing.expect(t, state.gpu_state.pipeline != nil)
		if state.gpu_state.pipeline == nil { return }
		batch_init()
		state.ui.pass = .Draw
		for cycle in 0 ..< 100 {
			for frame in 0 ..< 4 {
				slot := frame % 2
				state.gpu_state.batch_index = slot
				dimension := i32(24 + 8 * ((cycle + frame) % 3))
				state.dpi = {logical_w = dimension, logical_h = dimension, drawable_w = dimension, drawable_h = dimension, scale = 1}
				gpu_update_projection(state.dpi)
				draw_record_begin(state.dpi)
				box := f32(12 + 4 * ((cycle + frame) % 3))
				content := [1]Vector_Node{vector_test_rect({0, 0, box, box}, {255, 0, 0, 255})}
				mask := [1]Vector_Node{vector_test_rect({0, 0, box * 0.5, box}, {255, 255, 255, 255})}
				nodes := [1]Vector_Node{{kind = .Mask, children = content[:], mask = mask[:], opacity = 0.5}}
				testing.expect_value(t, draw_vector_scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
				draw_record_end()
				cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {})
				testing.expect(t, cmd != nil)
				if cmd == nil { return }
				if cycle == 0 {
					testing.expect(t, sdl.CancelGPUCommandBuffer(cmd))
					cmd = vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {})
					testing.expect(t, cmd != nil)
					if cmd == nil { return }
				}
				submitted := vector_gpu_frame()
				submitted.fence = sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
				testing.expect(t, submitted.fence != nil)
				if submitted.fence == nil { return }
				vector_gpu_advance_frame()
				batch_reset()
			}
			live_fences := 0
			for frame in state.vector.gpu.frames {
				if frame.fence != nil {
					live_fences += 1
				}
			}
			testing.expect(t, live_fences >= 2)
			vector_gpu_shutdown()
			vector_scene_shutdown()
			vector_gpu_shutdown()
			testing.expect_value(t, state.vector.gpu.bytes, u64(0))
			testing.expect_value(t, state.vector.gpu.pool_bytes, u64(0))
			testing.expect(t, state.vector.gpu.ui_pipeline == nil && state.vector.gpu.lcd_pipeline == nil)
			for frame in state.vector.gpu.frames {
				testing.expect(t, frame.fence == nil && frame.transfer == nil && frame.root.colour == nil)
				testing.expect_value(t, frame.root.bytes, u64(0))
				for buffer in frame.buffers { testing.expect(t, buffer == nil) }
				testing.expect_value(t, cap(frame.pool), 0)
				testing.expect_value(t, cap(frame.outputs), 0)
			}
			for frame in state.vector.frames {
				testing.expect_value(t, cap(frame.vertices), 0)
				testing.expect_value(t, cap(frame.instances), 0)
				testing.expect_value(t, cap(frame.commands), 0)
				testing.expect_value(t, len(frame.geometry), 0)
			}
		}
	})
}
