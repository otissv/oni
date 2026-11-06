#+test
package oni

import "core:testing"
import v "./vector"

@(test)
vector_svg_clip_reuses_linear_geometry_across_translations :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		commands := vector_tess_test_triangle()
		items := [1]v.Svg_Path_Item{{commands = commands[:], transform = Vector_Identity}}
		first, err := draw_svg_clip_mesh(items[:], Vector_Identity)
		testing.expect_value(t, err, Vector_Error.None)
		work := vector_frame().new_segments
		testing.expect(t, work > 0)
		second, shifted_err := draw_svg_clip_mesh(items[:], {1, 0, 0, 1, 13, 27})
		testing.expect_value(t, shifted_err, Vector_Error.None)
		testing.expect_value(t, vector_frame().new_segments, work)
		testing.expect_value(t, len(first.vertices), len(second.vertices))
		for point, i in first.vertices { testing.expect_value(t, second.vertices[i], point + Vec2{13, 27}) }
		_, scaled_err := draw_svg_clip_mesh(items[:], {2, 0, 0, 2, 0, 0})
		testing.expect_value(t, scaled_err, Vector_Error.None)
		testing.expect(t, vector_frame().new_segments > work)
	})
}

@(test)
vector_svg_pixel_aligned_rect_clips_use_scissors :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		path: v.Path
		defer v.Destroy_Path(&path)
		testing.expect_value(t, v.Rectangle(&path, {2, 3}, {20, 10}), v.Error.None)
		node := v.Svg_Draw_Node{kind = .Clip, clip_items = []v.Svg_Path_Item{{commands = path.commands[:], transform = Vector_Identity}}}
		rect, ok := draw_svg_rect_clip(node, {1, 0, 0, 1, 10, 20})
		testing.expect(t, ok)
		testing.expect_value(t, rect, Rect{12, 23, 20, 10})
		_, fractional := draw_svg_rect_clip(node, {1, 0, 0, 1, .5, 0})
		testing.expect(t, !fractional)
		_, rotated := draw_svg_rect_clip(node, {1, .5, 0, 1, 0, 0})
		testing.expect(t, !rotated)
	})
}
