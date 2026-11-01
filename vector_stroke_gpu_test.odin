#+test
package oni

import "core:testing"
import v "./vector"
import sdl "vendor:sdl3"

@(test)
vector_stroke_overlap_keeps_single_translucent_coverage :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		state.ui.pass = .Draw
		state.dpi = {logical_w = 64, logical_h = 32, drawable_w = 64, drawable_h = 32, scale = 1}
		state.gpu_state.pipeline = gpu_create_ui_layout_pipeline(state.gpu, .R8G8B8A8_UNORM, frag_shader_code, gpu_blend_state())
		testing.expect(t, state.gpu_state.pipeline != nil)
		if state.gpu_state.pipeline == nil {
			return
		}

		gpu_update_projection(state.dpi)
		batch_init()
		path: v.Path
		defer v.Destroy_Path(&path)
		// Retrace the middle third so stroke geometry overlaps itself.
		_ = v.Move_To(&path, {8, 16})
		_ = v.Line_To(&path, {56, 16})
		_ = v.Line_To(&path, {32, 16})
		handle, err := Vector_Create_Path(path.commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		draw_record_begin(state.dpi)
		stroke := Vector_Stroke{width = 8, cap = .Butt, join = .Bevel, miter_limit = 4}
		testing.expect_value(
			t,
			Draw_Vector_Path(handle, {255, 0, 0, 255}, opacity = 0.5, op = .Stroke, stroke = stroke),
			Vector_Error.None,
		)
		testing.expect_value(t, Vector_Destroy_Path(handle), Vector_Error.None)
		draw_record_end()
		cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {})
		testing.expect(t, cmd != nil)
		if cmd == nil {
			return
		}

		submitted := vector_gpu_frame()
		submitted.fence = sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
		fence := submitted.fence
		testing.expect(t, fence != nil)
		if fence == nil {
			return
		}

		testing.expect(t, sdl.WaitForGPUFences(state.gpu, true, &fence, 1))
		pixels, ok := gpu_test_download_vector_framebuffer(t, 64, 32)
		if !ok {
			return
		}

		defer delete(pixels)
		// Overlap centre and a single-pass region must share the same translucent red.
		for sample in ([2]int{20, 40}) {
			base := (16 * 64 + sample) * 4
			gpu_test_expect_u8_near(t, pixels[base + 0], 128, "stroke overlap red")
			gpu_test_expect_u8_near(t, pixels[base + 1], 0, "stroke overlap green")
			gpu_test_expect_u8_near(t, pixels[base + 2], 0, "stroke overlap blue")
			gpu_test_expect_u8_near(t, pixels[base + 3], 128, "stroke overlap alpha")
		}
	})
}

@(test)
vector_stroke_non_scaling_and_reflection_render :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		state.ui.pass = .Draw
		state.dpi = {logical_w = 96, logical_h = 32, drawable_w = 96, drawable_h = 32, scale = 1}
		state.gpu_state.pipeline = gpu_create_ui_layout_pipeline(state.gpu, .R8G8B8A8_UNORM, frag_shader_code, gpu_blend_state())
		testing.expect(t, state.gpu_state.pipeline != nil)
		if state.gpu_state.pipeline == nil {
			return
		}

		gpu_update_projection(state.dpi)
		batch_init()
		path: v.Path
		defer v.Destroy_Path(&path)
		_ = v.Move_To(&path, {0, 0})
		_ = v.Line_To(&path, {40, 0})
		handle, err := Vector_Create_Path(path.commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		draw_record_begin(state.dpi)
		scaled := Vector_Transform{2, 0, 0, 2, 8, 16}
		stroke := Vector_Stroke{width = 4, cap = .Butt, join = .Miter, miter_limit = 4, non_scaling = true}
		testing.expect_value(
			t,
			Draw_Vector_Path(handle, {0, 255, 0, 255}, scaled, op = .Stroke, stroke = stroke),
			Vector_Error.None,
		)
		reflected := Vector_Transform{-1, 0, 0, 1, 88, 16}
		plain := Vector_Stroke{width = 4, cap = .Square, join = .Miter, miter_limit = 4}
		testing.expect_value(
			t,
			Draw_Vector_Path(handle, {0, 0, 255, 255}, reflected, op = .Stroke, stroke = plain),
			Vector_Error.None,
		)
		testing.expect_value(t, Vector_Destroy_Path(handle), Vector_Error.None)
		draw_record_end()
		cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {})
		testing.expect(t, cmd != nil)
		if cmd == nil {
			return
		}

		submitted := vector_gpu_frame()
		submitted.fence = sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
		fence := submitted.fence
		testing.expect(t, fence != nil)
		if fence == nil {
			return
		}

		testing.expect(t, sdl.WaitForGPUFences(state.gpu, true, &fence, 1))
		pixels, ok := gpu_test_download_vector_framebuffer(t, 96, 32)
		if !ok {
			return
		}

		defer delete(pixels)
		// Non-scaling width stays ~4px despite 2× transform.
		green := (16 * 96 + 40) * 4
		testing.expect(t, pixels[green + 1] > 200)
		testing.expect(t, pixels[((16 + 4) * 96 + 40) * 4 + 1] < 40)
		blue := (16 * 96 + 68) * 4
		testing.expect(t, pixels[blue + 2] > 200)
	})
}
