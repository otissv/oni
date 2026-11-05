#+test
package oni

import "core:testing"
import v "./vector"

@(test)
vector_paint_recording_copies_stops_before_caller_mutation :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		path: v.Path
		defer v.Destroy_Path(&path)
		testing.expect_value(t, v.Rectangle(&path, {0, 0}, {20, 20}), v.Error.None)
		handle, err := Vector_Create_Path(path.commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		defer Vector_Destroy_Path(handle)

		stops := make([]Vector_Gradient_Stop, 2)
		stops[0] = {0, {255, 0, 0, 255}}
		stops[1] = {1, {0, 0, 255, 255}}
		paint := Linear_Paint({x1 = 0, y1 = 0, x2 = 20, y2 = 0, stops = stops})

		testing.expect_value(t, Draw_Vector_Path(handle, paint), Vector_Error.None)
		testing.expect(t, vector_frame().ramp_rows == 1)
		before := vector_frame().ramp_pixels[0]

		stops[0].color = {0, 255, 0, 255}
		delete(stops)
		paint.linear.stops = nil

		testing.expect_value(t, vector_frame().ramp_pixels[0], before)
		testing.expect(t, len(vector_frame().instances) == 1)
		testing.expect_value(t, vector_frame().instances[0].paint[0], f32(1))
	})
}

@(test)
vector_paint_none_and_current_color_record :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		path: v.Path
		defer v.Destroy_Path(&path)
		testing.expect_value(t, v.Rectangle(&path, {0, 0}, {10, 10}), v.Error.None)
		handle, err := Vector_Create_Path(path.commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		defer Vector_Destroy_Path(handle)

		testing.expect_value(t, Draw_Vector_Path(handle, None_Paint()), Vector_Error.None)
		testing.expect_value(t, len(vector_frame().instances), 0)

		testing.expect_value(
			t,
			Draw_Vector_Path(handle, Current_Color_Paint(), current_color = {10, 20, 30, 255}),
			Vector_Error.None,
		)
		testing.expect_value(t, len(vector_frame().instances), 1)
		testing.expect_value(t, vector_frame().instances[0].paint[0], f32(0))
		colour := vector_frame().instances[0].colour
		testing.expect(t, abs(colour[0] - 10.0 / 255.0) < 1e-5)
		testing.expect(t, abs(colour[1] - 20.0 / 255.0) < 1e-5)
		testing.expect(t, abs(colour[2] - 30.0 / 255.0) < 1e-5)
	})
}

@(test)
vector_paint_gradients_share_geometry_across_instances :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		path: v.Path
		defer v.Destroy_Path(&path)
		testing.expect_value(t, v.Rectangle(&path, {0, 0}, {16, 16}), v.Error.None)
		handle, err := Vector_Create_Path(path.commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		defer Vector_Destroy_Path(handle)

		stops_a := [2]Vector_Gradient_Stop{{0, {255, 0, 0, 255}}, {1, {255, 255, 0, 255}}}
		stops_b := [2]Vector_Gradient_Stop{{0, {0, 0, 255, 255}}, {1, {0, 255, 255, 255}}}
		a := Linear_Paint({x1 = 0, y1 = 0, x2 = 16, y2 = 0, stops = stops_a[:]})
		b := Radial_Paint({cx = 8, cy = 8, r = 8, fx = 8, fy = 8, fr = 0, stops = stops_b[:]})

		testing.expect_value(t, Draw_Vector_Path(handle, a), Vector_Error.None)
		testing.expect_value(
			t,
			Draw_Vector_Path(handle, b, {1, 0, 0, 1, 20, 0}),
			Vector_Error.None,
		)
		testing.expect_value(t, Draw_Vector_Path(handle, {255, 0, 0, 255}, {1, 0, 0, 1, 40, 0}), Vector_Error.None)

		entry := vector_path_entry(handle)
		testing.expect(t, entry != nil)
		testing.expect_value(t, len(entry.cache), 1)
		testing.expect(t, entry.cache[0].valid)
		testing.expect_value(t, vector_frame().ramp_rows, 2)
		testing.expect_value(t, len(vector_frame().geometry), 1)
	})
}

@(test)
vector_paint_nested_transform_compose :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		path: v.Path
		defer v.Destroy_Path(&path)
		testing.expect_value(t, v.Rectangle(&path, {0, 0}, {10, 10}), v.Error.None)
		handle, err := Vector_Create_Path(path.commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		defer Vector_Destroy_Path(handle)

		parent := Vector_Transform{2, 0, 0, 2, 5, 7}
		child := Vector_Transform{1, 0, 0, 1, 3, 4}
		composed := v.Affine_Compose(parent, child)
		stops := [2]Vector_Gradient_Stop{{0, {255, 0, 0, 255}}, {1, {0, 0, 255, 255}}}
		paint := Linear_Paint({
			x1 = 0, y1 = 0, x2 = 1, y2 = 0,
			units = .Object_Bounding_Box,
			transform = {0, 1, -1, 0, 0, 0},
			stops = stops[:],
		})
		testing.expect_value(t, Draw_Vector_Path(handle, paint, composed), Vector_Error.None)
		testing.expect_value(t, len(vector_frame().instances), 1)
		testing.expect_value(t, vector_frame().instances[0].paint[0], f32(1))
		entry := vector_path_entry(handle)
		testing.expect(t, entry != nil && len(entry.cache) == 1)
		// Fill tessellation uses shared dpi×zoom basis; draw affine is GPU morph, not baked into combined_linear.
		want, ok := vector_paint_combined_transform(
			paint.linear.units,
			paint.linear.transform,
			entry.cache[0].linear,
			entry.cache[0].local_bounds,
		)
		testing.expect(t, ok)
		got := vector_frame().instances[0]
		testing.expect(t, abs(f64(got.combined_linear[0]) - want[0]) < 1e-5)
		testing.expect(t, abs(f64(got.combined_linear[1]) - want[1]) < 1e-5)
		testing.expect(t, abs(f64(got.combined_linear[2]) - want[2]) < 1e-5)
		testing.expect(t, abs(f64(got.combined_linear[3]) - want[3]) < 1e-5)
		testing.expect(t, got.morph_linear != [4]f32{1, 0, 0, 1})
	})
}

@(test)
vector_paint_object_bbox_uses_path_local_bounds_under_rotation :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		path: v.Path
		defer v.Destroy_Path(&path)
		testing.expect_value(t, v.Rectangle(&path, {0, 0}, {20, 10}), v.Error.None)
		handle, err := Vector_Create_Path(path.commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		defer Vector_Destroy_Path(handle)

		stops := [2]Vector_Gradient_Stop{{0, {255, 0, 0, 255}}, {1, {0, 0, 255, 255}}}
		paint := Linear_Paint({
			x1 = 0, y1 = 0, x2 = 1, y2 = 0,
			units = .Object_Bounding_Box,
			stops = stops[:],
		})
		// 90° draw rotation is GPU morph; OBB gradients still use path-local 20×10 bounds.
		testing.expect_value(
			t,
			Draw_Vector_Path(handle, paint, {0, 1, -1, 0, 0, 0}),
			Vector_Error.None,
		)
		entry := vector_path_entry(handle)
		testing.expect(t, entry != nil && len(entry.cache) == 1)
		testing.expect(t, abs(entry.cache[0].local_bounds.w - 20) < 0.5)
		testing.expect(t, abs(entry.cache[0].local_bounds.h - 10) < 0.5)
		// Basis fill mesh stays path-local 20×10; rotation is applied via GPU morph.
		testing.expect(t, abs(entry.cache[0].bounds.w - 20) < 1.5)
		testing.expect(t, abs(entry.cache[0].bounds.h - 10) < 1.5)
		want, ok := vector_paint_combined_transform(
			paint.linear.units,
			paint.linear.transform,
			entry.cache[0].linear,
			entry.cache[0].local_bounds,
		)
		testing.expect(t, ok)
		got := vector_frame().instances[0]
		testing.expect(t, abs(f64(got.combined_linear[0]) - want[0]) < 1e-4)
		testing.expect(t, abs(f64(got.combined_linear[1]) - want[1]) < 1e-4)
		testing.expect(t, abs(f64(got.combined_linear[2]) - want[2]) < 1e-4)
		testing.expect(t, abs(f64(got.combined_linear[3]) - want[3]) < 1e-4)
		testing.expect(t, got.morph_linear != [4]f32{1, 0, 0, 1})
	})
}
