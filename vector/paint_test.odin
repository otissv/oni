#+test
package oni_vector

import "core:testing"
import col "libs:colors"

@(test)
paint_solid_none_and_current_color :: proc(t: ^testing.T) {
	testing.expect_value(t, Validate_Paint(Solid_Paint({255, 0, 0, 255})), Error.None)
	testing.expect_value(t, Validate_Paint(None_Paint()), Error.None)
	testing.expect_value(t, Validate_Paint(Current_Color_Paint()), Error.None)

	color, painted := Paint_Color_At(None_Paint(), {0, 0}, {})
	testing.expect(t, !painted)
	testing.expect_value(t, color, Color{0, 0, 0, 0})

	color, painted = Paint_Color_At(Current_Color_Paint(), {0, 0}, {}, {10, 20, 30, 255})
	testing.expect(t, painted)
	testing.expect_value(t, color, Color{10, 20, 30, 255})
}

@(test)
paint_collapsed_linear_uses_last_stop_for_every_spread :: proc(t: ^testing.T) {
	stops := [2]Gradient_Stop{{0, {255, 0, 0, 255}}, {1, {0, 0, 255, 255}}}
	for spread in Gradient_Spread {
		paint := Linear_Paint({x1 = 0, y1 = 0, x2 = 0, y2 = 0, stops = stops[:], spread = spread})
		color, painted := Paint_Color_At(paint, {10, 10}, {})
		testing.expect(t, painted)
		testing.expect_value(t, color, Color{0, 0, 255, 255})
	}
}

@(test)
paint_radial_handles_tiny_radii_without_absolute_epsilon :: proc(t: ^testing.T) {
	stops := [2]Gradient_Stop{{0, {255, 0, 0, 255}}, {1, {0, 0, 255, 255}}}
	paint := Radial_Paint({cx = .5, cy = .5, fx = .5, fy = .5, r = 1e-15, stops = stops[:]})
	color, painted := Paint_Color_At(paint, {1, 1}, {min = {0, 0}, max = {1, 1}})
	testing.expect(t, painted)
	testing.expect_value(t, color, Color{0, 0, 255, 255})
}

@(test)
paint_gradient_validation_and_clone_owns_stops :: proc(t: ^testing.T) {
	stops := [2]Gradient_Stop{{0, {255, 0, 0, 255}}, {1, {0, 0, 255, 255}}}
	paint := Linear_Paint({
		x1 = 0, y1 = 0, x2 = 10, y2 = 0,
		stops = stops[:],
	})
	testing.expect_value(t, Validate_Paint(paint), Error.None)

	owned, err := Clone_Paint(paint)
	testing.expect_value(t, err, Error.None)
	defer Destroy_Paint(&owned)

	stops[0].color = {0, 255, 0, 255}
	color, painted := Paint_Color_At(owned, {0, 0}, {min = {0, 0}, max = {10, 10}})
	testing.expect(t, painted)
	testing.expect_value(t, color, Color{255, 0, 0, 255})

	bad := Linear_Paint({x1 = 0, y1 = 0, x2 = 1, y2 = 0, stops = {}})
	testing.expect_value(t, Validate_Paint(bad), Error.Invalid_Value)

	unsorted := [2]Gradient_Stop{{0.8, {0, 0, 0, 255}}, {0.2, {255, 255, 255, 255}}}
	testing.expect_value(
		t,
		Validate_Paint(Linear_Paint({x1 = 0, y1 = 0, x2 = 1, y2 = 0, stops = unsorted[:]})),
		Error.Invalid_Value,
	)
}

@(test)
paint_spread_modes :: proc(t: ^testing.T) {
	testing.expect_value(t, Spread_Parameter(-0.25, .Pad), 0)
	testing.expect_value(t, Spread_Parameter(1.25, .Pad), 1)
	testing.expect_value(t, Spread_Parameter(1.25, .Repeat), 0.25)
	testing.expect_value(t, Spread_Parameter(-0.25, .Repeat), 0.75)
	testing.expect_value(t, Spread_Parameter(1.25, .Reflect), 0.75)
	testing.expect_value(t, Spread_Parameter(2.25, .Reflect), 0.25)
}

@(test)
paint_linear_user_space_and_object_bbox :: proc(t: ^testing.T) {
	stops := [2]Gradient_Stop{{0, {255, 0, 0, 255}}, {1, {0, 0, 255, 255}}}
	user := Linear_Paint({
		x1 = 0, y1 = 0, x2 = 100, y2 = 0,
		units = .User_Space,
		stops = stops[:],
	})
	mid, painted := Paint_Color_At(user, {50, 10}, {min = {0, 0}, max = {100, 100}})
	testing.expect(t, painted)
	testing.expect_value(t, mid, Color{128, 0, 128, 255})

	bbox := Linear_Paint({
		x1 = 0, y1 = 0, x2 = 1, y2 = 0,
		units = .Object_Bounding_Box,
		stops = stops[:],
	})
	bbox_color, ok := Paint_Color_At(bbox, {25, 0}, {min = {0, 0}, max = {100, 50}})
	testing.expect(t, ok)
	testing.expect_value(t, bbox_color, Color{191, 0, 64, 255})
}

@(test)
paint_linear_transform_inverts_for_sampling :: proc(t: ^testing.T) {
	stops := [2]Gradient_Stop{{0, {255, 255, 255, 255}}, {1, {0, 0, 0, 255}}}
	// gradientTransform maps gradient +X onto +Y (SVG: gradient→target).
	rotated := Linear_Paint({
		x1 = 0, y1 = 0, x2 = 10, y2 = 0,
		transform = {0, 1, -1, 0, 0, 0},
		stops = stops[:],
	})
	color, painted := Paint_Color_At(rotated, {0, 10}, {})
	testing.expect(t, painted)
	testing.expect_value(t, color, Color{0, 0, 0, 255})

	start, start_ok := Paint_Color_At(rotated, {0, 0}, {})
	testing.expect(t, start_ok)
	testing.expect_value(t, start, Color{255, 255, 255, 255})
}

@(test)
paint_radial_parameter_centred_and_off_centre :: proc(t: ^testing.T) {
	stops := [2]Gradient_Stop{{0, {255, 255, 255, 255}}, {1, {0, 0, 0, 255}}}
	centred := Radial_Gradient{cx = 0, cy = 0, r = 10, fx = 0, fy = 0, fr = 0, stops = stops[:]}
	testing.expect(t, abs(Radial_Parameter(centred, {0, 0}, {}) - 0) < 1e-9)
	testing.expect(t, abs(Radial_Parameter(centred, {5, 0}, {}) - 0.5) < 1e-9)
	testing.expect(t, abs(Radial_Parameter(centred, {10, 0}, {}) - 1) < 1e-9)

	off := Radial_Gradient{cx = 5, cy = 0, r = 10, fx = 0, fy = 0, fr = 0, stops = stops[:]}
	testing.expect(t, abs(Radial_Parameter(off, {0, 0}, {}) - 0) < 1e-9)
	testing.expect(t, abs(Radial_Parameter(off, {5, 0}, {}) - (1.0 / 3.0)) < 1e-9)
	testing.expect(t, abs(Radial_Parameter(off, {15, 0}, {}) - 1) < 1e-9)

	radial := Radial_Paint(centred)
	center, center_ok := Paint_Color_At(radial, {0, 0}, {})
	testing.expect(t, center_ok)
	testing.expect_value(t, center, Color{255, 255, 255, 255})
	mid, mid_ok := Paint_Color_At(radial, {5, 0}, {})
	testing.expect(t, mid_ok)
	testing.expect_value(t, mid, Color{128, 128, 128, 255})
	edge, edge_ok := Paint_Color_At(radial, {10, 0}, {})
	testing.expect(t, edge_ok)
	testing.expect_value(t, edge, Color{0, 0, 0, 255})
}

@(test)
paint_stop_ramp_matches_sample :: proc(t: ^testing.T) {
	stops := [3]Gradient_Stop{
		{0, {255, 0, 0, 255}},
		{0.5, {0, 255, 0, 128}},
		{1, {0, 0, 255, 0}},
	}
	ramp: [256]Color
	Build_Stop_Ramp(stops[:], .sRGB, ramp[:])
	testing.expect_value(t, ramp[0], Color{255, 0, 0, 255})
	testing.expect_value(t, ramp[255], Color{0, 0, 255, 0})
	param := f64(128) / f64(255)
	mid := Sample_Stops(stops[:], param, .sRGB)
	testing.expect_value(t, ramp[128], mid)
}

@(test)
paint_linear_rgb_interpolation_differs_from_srgb :: proc(t: ^testing.T) {
	stops := [2]Gradient_Stop{{0, {0, 0, 0, 255}}, {1, {255, 255, 255, 255}}}
	srgb := Sample_Stops(stops[:], 0.5, .sRGB)
	linear := Sample_Stops(stops[:], 0.5, .Linear_RGB)
	testing.expect(t, srgb != linear)
	testing.expect_value(t, srgb, col.rgba_lerp(stops[0].color, stops[1].color, 0.5, .sRGB))
}
