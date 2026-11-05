#+test
package oni

import "core:testing"

@(test)
vector_index_ranges_cover_changes_and_skip_identical_data :: proc(t: ^testing.T) {
	previous: [4096]u32
	current := previous
	ranges, bytes, ok := vector_gpu_index_upload_ranges(current[:], previous[:], true)
	testing.expect(t, ok)
	testing.expect_value(t, len(ranges), 0)
	testing.expect_value(t, bytes, u64(0))
	current[1], current[4094] = 7, 9
	ranges, bytes, ok = vector_gpu_index_upload_ranges(current[:], previous[:], true)
	testing.expect(t, ok)
	testing.expect_value(t, len(ranges), 2)
	for changed in ([2]int{1, 4094}) {
		covered := false
		for region in ranges { covered ||= u64(changed * size_of(u32)) >= region.offset && u64(changed * size_of(u32)) < region.offset + region.size }
		testing.expect(t, covered)
	}
	testing.expect(t, bytes < u64(size_of(current)))
	ranges, bytes, ok = vector_gpu_index_upload_ranges(current[:], previous[:], false)
	testing.expect(t, ok)
	testing.expect_value(t, len(ranges), 1)
	testing.expect_value(t, bytes, u64(size_of(current)))
}

@(test)
vector_gpu_partial_index_uploads_preserve_changed_triangles :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 16, 16) { return }
		indices := make([]u32, 6144)
		defer delete(indices)
		copy(indices[:3], []u32{0, 1, 2})
		copy(indices[len(indices) - 3:], []u32{0, 1, 2})
		for frame in 0 ..< 4 {
			if frame == 1 { copy(indices[:3], []u32{0, 2, 3}) }
			if frame == 2 { copy(indices[len(indices) - 3:], []u32{0, 2, 3}) }
			draw_record_begin(state.dpi)
			draw_rect({0, 0, 16, 16}, {0, 0, 255, 255})
			nodes := [1]Vector_Node{{kind = .Mesh, opacity = 1, colour = {255, 0, 0, 255}, mesh = {
				vertices = []Vec2{{0, 0}, {16, 0}, {16, 16}, {0, 16}}, indices = indices,
			}}}
			testing.expect_value(t, Draw_Vector_Scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
			draw_record_end()
			if !vector_composition_gpu_submit(t) { return }
			pixels, ok := gpu_test_download_vector_framebuffer(t, 16, 16)
			if !ok { return }
			left := [4]u8{0, 0, 255, 255} if frame == 0 else [4]u8{255, 0, 0, 255}
			right := [4]u8{255, 0, 0, 255} if frame < 2 else [4]u8{0, 0, 255, 255}
			vector_composition_expect_rgba(t, pixels, 16, 4, 12, left, "changed prefix indices")
			vector_composition_expect_rgba(t, pixels, 16, 12, 4, right, "changed suffix indices")
			delete(pixels)
			batch_reset()
		}
	})
}
