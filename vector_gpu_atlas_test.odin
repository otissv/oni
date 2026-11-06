#+test
package oni

import "core:testing"

@(test)
vector_atlas_packing_separates_tiles_and_render_dependencies :: proc(t: ^testing.T) {
	jobs := [5]Vector_Atlas_Job{
		{depth = 1, bounds = {0, 0, 100, 30}}, {depth = 1, bounds = {0, 0, 100, 40}},
		{depth = 1, bounds = {0, 0, 100, 50}}, {depth = 2, bounds = {0, 0, 10, 10}},
		{depth = 2, bounds = {0, 0, 300, 10}},
	}
	count, bounds := vector_atlas_pack(jobs[:])
	testing.expect_value(t, count, 3)
	testing.expect_value(t, bounds, Rect{0, 0, 204, 94})
	testing.expect_value(t, jobs[0].origin, Vec2{1, 1})
	testing.expect_value(t, jobs[1].origin, Vec2{103, 1})
	testing.expect_value(t, jobs[2].origin, Vec2{1, 43})
	count, _ = vector_atlas_pack(jobs[4:])
	testing.expect_value(t, count, 0)
}

@(test)
vector_gpu_atlas_masks_keep_tiles_opacity_and_frame_reuse :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		defer test_hook_vector_fail_pass_after = 0
		if !vector_composition_gpu_setup(t, 384, 48) { return }
		for frame in 0 ..< 3 {
			draw_record_begin(state.dpi)
			draw_rect({0, 0, 384, 48}, {0, 0, 255, 255})
			for i in 0 ..< 32 {
				x, y := f32(i % 16 * 24), f32(i / 16 * 24)
				content := [2]Vector_Node{vector_test_rect({x, y, 12, 16}, {255, 0, 0, 255}), vector_test_rect({x + 8, y, 12, 16}, {0, 255, 0, 255})}
				inner := [1]Vector_Node{{kind = .Group, opacity = .5, children = content[:]}}
				mask := [1]Vector_Node{vector_test_rect({x, y, 16, 16}, {255, 255, 255, 255})}
				masked := [1]Vector_Node{{kind = .Mask, opacity = .5, children = inner[:], mask = mask[:]}}
				outer := [1]Vector_Node{{kind = .Group, opacity = .5, children = masked[:]}}
				testing.expect_value(t, Draw_Vector_Scene({nodes = outer[:], opacity = 1}), Vector_Error.None)
			}
			draw_record_end()
			if frame == 1 { test_hook_vector_fail_pass_after = 1 }
			if !vector_composition_gpu_submit(t) { return }
			testing.expect_value(t, Vector_Last_Error(), Vector_Error.None)
			testing.expect_value(t, state.vector.gpu.atlas_disabled, frame == 1)
			pixels, ok := gpu_test_download_vector_framebuffer(t, 384, 48)
			if !ok { return }
			for i in 0 ..< 32 {
				x, y := i % 16 * 24, i / 16 * 24
				vector_composition_expect_rgba(t, pixels, 384, x + 4, y + 8, {32, 0, 223, 255}, "atlas red tile")
				vector_composition_expect_rgba(t, pixels, 384, x + 10, y + 8, {0, 32, 223, 255}, "atlas isolated overlap")
				vector_composition_expect_rgba(t, pixels, 384, x + 18, y + 8, {0, 0, 255, 255}, "atlas mask boundary")
			}
			delete(pixels)
			batch_reset()
			vector_gpu_advance_frame()
			batch_flip()
		}
	})
}
