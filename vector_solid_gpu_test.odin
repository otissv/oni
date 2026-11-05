#+test
package oni

import "core:testing"
import sdl "vendor:sdl3"

@(test)
vector_gpu_instance_formats_transition_atomically_in_both_slots :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 32, 32) { return }
		commands := [5]Vector_Path_Command{
			{kind = .Move}, {kind = .Line, points = {{24, 0}, {}, {}}},
			{kind = .Line, points = {{24, 24}, {}, {}}}, {kind = .Line, points = {{0, 24}, {}, {}}}, {kind = .Close},
		}
		handle, err := Vector_Create_Path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		for frame in 0 ..< 6 {
			draw_record_begin(state.dpi)
			draw_rect({0, 0, 32, 32}, {0, 0, 255, 255})
			want := [4]u8{255, 0, 0, 255}
			if frame == 2 {
				stops := [2]Vector_Gradient_Stop{{0, {0, 255, 0, 255}}, {1, {0, 255, 0, 255}}}
				testing.expect_value(t, Draw_Vector_Path(handle, Linear_Paint({x2 = 24, stops = stops[:]})), Vector_Error.None)
				want = {0, 255, 0, 255}
			} else if frame == 3 {
				fill := [1]Vector_Node{vector_test_rect({0, 0, 24, 24}, {255, 0, 0, 255})}
				nodes := [1]Vector_Node{{kind = .Group, opacity = .5, children = fill[:]}}
				testing.expect_value(t, Draw_Vector_Scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
				want = {128, 0, 127, 255}
			} else {
				fill := [1]Vector_Node{vector_test_rect({0, 0, 32, 32}, {255, 0, 0, 255})}
				clip := vector_test_rect({0, 0, 24, 24}, {255, 255, 255, 255})
				nodes := [1]Vector_Node{{kind = .Clip, opacity = 1, mesh = clip.mesh, children = fill[:]}}
				testing.expect_value(t, Draw_Vector_Scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
			}
			draw_record_end()
			if frame == 2 || frame == 3 {
				cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
				testing.expect(t, cmd != nil)
				if cmd == nil { return }
				testing.expect(t, vector_gpu_frame().solid_instances)
				test_hook_vector_fail_map = true
				testing.expect(t, !vector_gpu_upload(cmd))
				test_hook_vector_fail_map = false
				testing.expect(t, vector_gpu_frame().solid_instances)
				testing.expect(t, sdl.CancelGPUCommandBuffer(cmd))
			}
			if !vector_composition_gpu_submit(t) { return }
			testing.expect_value(t, vector_gpu_frame().solid_instances, frame != 2 && frame != 3)
			pixels, ok := gpu_test_download_vector_framebuffer(t, 32, 32)
			if !ok { return }
			vector_composition_expect_rgba(t, pixels, 32, 12, 12, want, "instance layout keeps centre colour")
			vector_composition_expect_rgba(t, pixels, 32, 28, 28, {0, 0, 255, 255}, "clip and quad preserve outside UI")
			delete(pixels)
			vector_gpu_advance_frame()
			batch_reset()
			batch_flip()
		}
	})
}

@(test)
vector_gpu_solid_pipeline_partial_initialization_is_recoverable :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_gpu_shutdown()
		for failure in 0 ..= 10 {
			test_hook_vector_fail_solid_shader = failure == 0
			test_hook_vector_fail_solid_pipeline_after = failure
			testing.expect(t, !vector_gpu_init(.R8G8B8A8_UNORM))
			for &family in state.vector.gpu.solid_pipelines { for pipeline in family { testing.expect(t, pipeline == nil) } }
			testing.expect(t, state.vector.gpu.pipeline == nil)
			testing.expect_value(t, state.vector.gpu.bytes, u64(0))
			test_hook_vector_fail_solid_shader = false
			test_hook_vector_fail_solid_pipeline_after = 0
			testing.expect(t, vector_gpu_init(.R8G8B8A8_UNORM))
			vector_gpu_shutdown()
		}
	})
}
