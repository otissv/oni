#+test
package oni

import "core:testing"
import sdl "vendor:sdl3"
import img "vendor:sdl3/image"

@(private)
vector_test_rect :: proc(rect: Rect, colour: RGBA) -> Vector_Node {
	points := make([]Vec2, 4, context.temp_allocator)
	points[0] = {rect.x, rect.y}
	points[1] = {rect.x + rect.w, rect.y}
	points[2] = {rect.x + rect.w, rect.y + rect.h}
	points[3] = {rect.x, rect.y + rect.h}
	indices := make([]u32, 6, context.temp_allocator)
	copy(indices, []u32{0, 1, 2, 0, 2, 3})
	return {kind = .Mesh, mesh = {vertices = points, indices = indices}, colour = colour, opacity = 1}
}

@(test)
vector_gpu_group_mask_clip_and_ui_order_readback :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		vector_gpu_composition_case(t, false)
	})
}

@(test)
vector_gpu_late_submission_failure_replays_without_partial_artwork :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		vector_gpu_composition_case(t, true)
	})
}

@(test)
vector_gpu_reuses_completed_slot_upload_storage :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		state.ui.pass = .Draw
		state.dpi = {logical_w = 32, logical_h = 32, drawable_w = 32, drawable_h = 32, scale = 1}
		state.gpu_state.pipeline = gpu_create_ui_layout_pipeline(state.gpu, .R8G8B8A8_UNORM, .UI_Fragment, gpu_blend_state())
		testing.expect(t, state.gpu_state.pipeline != nil)
		if state.gpu_state.pipeline == nil { return }
		gpu_update_projection(state.dpi)
		batch_init()
		slot_transfer: [len(state.vector.gpu.frames)]^sdl.GPUTransferBuffer
		bytes_after_warm := u64(0)
		n_slots := len(state.vector.gpu.frames)
		for frame in 0 ..< n_slots * 2 {
			draw_record_begin(state.dpi)
			nodes := [1]Vector_Node{vector_test_rect({0, 0, 32, 32}, {0, 255, 0, 255})}
			testing.expect_value(t, draw_vector_scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
			draw_record_end()
			cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {})
			testing.expect(t, cmd != nil)
			if cmd == nil { return }
			submitted := vector_gpu_frame()
			submitted.fence = sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
			testing.expect(t, submitted.fence != nil)
			if submitted.fence == nil { return }
			slot := frame % n_slots
			if frame < n_slots {
				slot_transfer[slot] = submitted.transfer
				testing.expect(t, submitted.transfer != nil)
				if frame == n_slots - 1 {
					bytes_after_warm = state.vector.gpu.bytes
				}
			} else {
				testing.expect_value(t, submitted.transfer, slot_transfer[slot])
				testing.expect_value(t, state.vector.gpu.bytes, bytes_after_warm)
			}
			vector_gpu_advance_frame()
			batch_reset()
		}
	})
}

@(private)
vector_gpu_composition_case :: proc(t: ^testing.T, fail_mask: bool) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		state.ui.pass = .Draw
		state.dpi = {logical_w = 32, logical_h = 32, drawable_w = 32, drawable_h = 32, scale = 1}
		state.gpu_state.pipeline = gpu_create_ui_layout_pipeline(state.gpu, .R8G8B8A8_UNORM, .UI_Fragment, gpu_blend_state())
		state.gpu_state.sampler = gpu_create_sampler(state.gpu)
		state.gpu_state.white_texture = gpu_create_white_texture(state.gpu)
		testing.expect(t, state.gpu_state.pipeline != nil && state.gpu_state.sampler != nil && state.gpu_state.white_texture != nil)
		if state.gpu_state.pipeline == nil || state.gpu_state.sampler == nil || state.gpu_state.white_texture == nil {
			return
		}
		gpu_update_projection(state.dpi)
		batch_init()
		draw_record_begin(state.dpi)
		draw_rect({0, 0, 32, 32}, {0, 0, 255, 255})

		red := [2]Vector_Node{
			vector_test_rect({0, 0, 24, 24}, {255, 0, 0, 255}),
			vector_test_rect({8, 0, 24, 24}, {255, 0, 0, 255}),
		}
		group := [1]Vector_Node{{kind = .Group, opacity = 0.5, children = red[:]}}
		testing.expect_value(t, draw_vector_scene({nodes = group[:], opacity = 1}), Vector_Error.None)

		green := [1]Vector_Node{vector_test_rect({0, 0, 32, 32}, {0, 255, 0, 255})}
		mask := [1]Vector_Node{vector_test_rect({0, 0, 16, 32}, {255, 255, 255, 255})}
		masked := [1]Vector_Node{{kind = .Mask, opacity = 1, children = green[:], mask = mask[:]}}
		clipped := [1]Vector_Node{{kind = .Clip, opacity = 1, clip = {0, 16, 32, 16}, children = masked[:]}}
		testing.expect_value(t, draw_vector_scene({nodes = clipped[:], opacity = 1}), Vector_Error.None)
		draw_rect({28, 28, 4, 4}, {255, 255, 255, 255})
		draw_record_end()

		if fail_mask {
			test_hook_vector_fail_pass_after = 2
		}
		cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {})
		testing.expect(t, cmd != nil)
		if cmd == nil {
			return
		}
		fence := sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
		testing.expect(t, fence != nil)
		if fence == nil {
			return
		}
		defer sdl.ReleaseGPUFence(state.gpu, fence)
		testing.expect(t, sdl.WaitForGPUFences(state.gpu, true, &fence, 1))
		pixels, ok := gpu_test_download_vector_framebuffer(t, 32, 32)
		if !ok {
			return
		}
		defer delete(pixels)
		surface := sdl.CreateSurfaceFrom(32, 32, .RGBA8888, raw_data(pixels), 32 * 4)
		testing.expect(t, surface != nil)
		if surface != nil {
			path: cstring = "build/test/vector-composition.png"
			if fail_mask {
				path = "build/test/vector-replay.png"
			}
			testing.expect(t, bool(img.SavePNG(surface, path)))
			sdl.DestroySurface(surface)
		}

		points := [7][2]int{{4, 4}, {12, 4}, {4, 20}, {20, 20}, {4, 28}, {20, 28}, {30, 30}}
		colours := [7][4]u8{
			{128, 0, 128, 255}, {128, 0, 128, 255}, {0, 255, 0, 255}, {128, 0, 128, 255},
			{0, 255, 0, 255}, {0, 0, 255, 255}, {255, 255, 255, 255},
		}
		if fail_mask {
			colours[2] = {128, 0, 128, 255}
			colours[4] = {0, 0, 255, 255}
			testing.expect(t, vector_frame().draws[1].failed)
			testing.expect_value(t, Vector_Last_Error(), Vector_Error.GPU_Failed)
		}
		for point, i in points {
			for channel in 0 ..< 4 {
				gpu_test_expect_u8_near(t, pixels[(point[1] * 32 + point[0]) * 4 + channel], colours[i][channel], "vector composition")
			}
		}
}
