package oni

import "core:math"
import v "./vector"

VECTOR_RAMP_WIDTH :: 256

Vector_Paint :: v.Paint
Vector_Paint_Kind :: v.Paint_Kind
Vector_Gradient_Stop :: v.Gradient_Stop
Vector_Gradient_Spread :: v.Gradient_Spread
Vector_Gradient_Units :: v.Gradient_Units
Vector_Color_Interpolation :: v.Color_Interpolation
Vector_Linear_Gradient :: v.Linear_Gradient
Vector_Radial_Gradient :: v.Radial_Gradient

Solid_Paint :: v.Solid_Paint
None_Paint :: v.None_Paint
Current_Color_Paint :: v.Current_Color_Paint
Linear_Paint :: v.Linear_Paint
Radial_Paint :: v.Radial_Paint

@(private)
Vector_Paint_GPU :: struct {
	mode:     f32, // 0 solid, 1 linear, 2 radial
	spread:   f32,
	ramp_row: f32,
	focal:    [2]f32, // radial focal point in gradient definition space
	grad0:    [4]f32, // linear x1,y1,x2,y2 or radial cx,cy,r,fr
	combined: Vector_Transform, // mesh position -> gradient definition space
	colour:   [4]f32, // solid rgba*opacity, or {1,1,1,opacity} for gradients
}

@(private)
vector_paint_error :: proc(err: v.Error) -> Vector_Error {
	switch err {
	case .None:
		return .None
	case .Invalid_Path, .Invalid_Value:
		return .Invalid_Value
	case .Limit_Exceeded, .Mesh_Memory_Limit:
		return .Limit_Exceeded
	case .Allocation_Failed:
		return .Allocation_Failed
	}

	return .Invalid_Value
}

@(private)
vector_paint_bounds_to_rect :: proc(bounds: v.Bounds) -> Rect {
	if bounds.empty || bounds.max.x <= bounds.min.x || bounds.max.y <= bounds.min.y {
		return {}
	}

	return {
		f32(bounds.min.x),
		f32(bounds.min.y),
		f32(bounds.max.x - bounds.min.x),
		f32(bounds.max.y - bounds.min.y),
	}
}

@(private)
vector_frame_alloc_ramp_row :: proc(stops: []v.Gradient_Stop, space: v.Color_Interpolation) -> (row: int, err: Vector_Error) {
	f := vector_frame()
	row = f.ramp_rows
	needed := (row + 1) * VECTOR_RAMP_WIDTH * 4
	if !vector_reserve(&f.ramp_pixels, needed, VECTOR_MAX_FRAME_NODES * VECTOR_RAMP_WIDTH * 4) {
		return 0, .Allocation_Failed
	}

	if resize(&f.ramp_pixels, needed) != nil {
		return 0, .Allocation_Failed
	}

	ramp: [VECTOR_RAMP_WIDTH]v.Color
	v.Build_Stop_Ramp(stops, space, ramp[:])
	base := row * VECTOR_RAMP_WIDTH * 4
	for color, i in ramp {
		f.ramp_pixels[base + i * 4 + 0] = color.r
		f.ramp_pixels[base + i * 4 + 1] = color.g
		f.ramp_pixels[base + i * 4 + 2] = color.b
		f.ramp_pixels[base + i * 4 + 3] = color.a
	}

	f.ramp_rows = row + 1
	return row, .None
}

@(private)
vector_paint_mesh_to_user :: proc(linear: [4]f64) -> (v.Affine, bool) {
	L := v.Affine{linear[0], linear[1], linear[2], linear[3], 0, 0}
	if L == v.IDENTITY {
		return v.IDENTITY, true
	}

	return v.Affine_Invert(L)
}

@(private)
vector_paint_bbox_to_unit :: proc(bounds: Rect) -> v.Affine {
	if bounds.w <= 0 || bounds.h <= 0 {
		return v.IDENTITY
	}

	return {
		1 / f64(bounds.w),
		0,
		0,
		1 / f64(bounds.h),
		-f64(bounds.x) / f64(bounds.w),
		-f64(bounds.y) / f64(bounds.h),
	}
}

/*
Builds mesh→gradient-definition mapping.

gradientTransform maps gradient space onto the SVG target space, so sampling
inverts it. objectBoundingBox uses path-local AABB axes (not the transformed
mesh AABB), so rotation/shear keep gradient alignment with the path.
*/
@(private)
vector_paint_combined_transform :: proc(
	units: v.Gradient_Units,
	gradient_transform: v.Affine,
	linear: [4]f64,
	local_bounds: Rect,
) -> (v.Affine, bool) {
	mesh_to_user, ok := vector_paint_mesh_to_user(linear)
	if !ok {
		return {}, false
	}

	mapping := mesh_to_user
	if units == .Object_Bounding_Box {
		mapping = v.Affine_Compose(vector_paint_bbox_to_unit(local_bounds), mesh_to_user)
	}

	xform := gradient_transform if gradient_transform != {} else v.IDENTITY
	if xform == v.IDENTITY {
		return mapping, true
	}

	inv, inv_ok := v.Affine_Invert(xform)
	if !inv_ok {
		return {}, false
	}

	return v.Affine_Compose(inv, mapping), true
}

@(private)
vector_paint_resolve :: proc(
	paint: Vector_Paint,
	opacity: f32,
	linear: [4]f64,
	local_bounds: Rect,
	current_color: RGBA,
) -> (
	gpu: Vector_Paint_GPU,
	skip: bool,
	err: Vector_Error,
) {
	if !(opacity >= 0 && opacity <= 1) {
		return {}, true, .Invalid_Value
	}

	draw_opacity := opacity * draw_effective_opacity()

	switch paint.kind {
	case .None:
		return {}, true, .None
	case .Solid:
		if paint.solid.a == 0 || draw_opacity == 0 {
			return {}, true, .None
		}

		colour := rgba_to_f32(paint.solid)
		colour[3] *= draw_opacity
		return {colour = colour}, false, .None
	case .Current_Color:
		if current_color.a == 0 || draw_opacity == 0 {
			return {}, true, .None
		}

		colour := rgba_to_f32(current_color)
		colour[3] *= draw_opacity
		return {colour = colour}, false, .None
	case .Linear_Gradient:
		if err_v := v.Validate_Paint(paint); err_v != .None {
			return {}, true, vector_paint_error(err_v)
		}
		if draw_opacity == 0 {
			return {}, true, .None
		}

		row, ramp_err := vector_frame_alloc_ramp_row(paint.linear.stops, paint.linear.color_interpolation)
		if ramp_err != .None {
			return {}, true, ramp_err
		}

		combined, ok := vector_paint_combined_transform(
			paint.linear.units,
			paint.linear.transform,
			linear,
			local_bounds,
		)
		if !ok {
			return {}, true, .Invalid_Value
		}

		return vector_paint_gpu_checked(Vector_Paint_GPU{
				mode = 1,
				spread = f32(paint.linear.spread),
				ramp_row = f32(row),
				grad0 = {
					f32(paint.linear.x1),
					f32(paint.linear.y1),
					f32(paint.linear.x2),
					f32(paint.linear.y2),
				},
				combined = combined,
				colour = {1, 1, 1, draw_opacity},
			})
	case .Radial_Gradient:
		if err_v := v.Validate_Paint(paint); err_v != .None {
			return {}, true, vector_paint_error(err_v)
		}
		if draw_opacity == 0 {
			return {}, true, .None
		}

		row, ramp_err := vector_frame_alloc_ramp_row(paint.radial.stops, paint.radial.color_interpolation)
		if ramp_err != .None {
			return {}, true, ramp_err
		}

		combined, ok := vector_paint_combined_transform(
			paint.radial.units,
			paint.radial.transform,
			linear,
			local_bounds,
		)
		if !ok {
			return {}, true, .Invalid_Value
		}

		fx := paint.radial.fx
		fy := paint.radial.fy
		if math.is_nan(fx) || math.is_inf(fx) || math.is_nan(fy) || math.is_inf(fy) {
			fx, fy = paint.radial.cx, paint.radial.cy
		}

		return vector_paint_gpu_checked(Vector_Paint_GPU{
				mode = 2,
				spread = f32(paint.radial.spread),
				ramp_row = f32(row),
				focal = {f32(fx), f32(fy)},
				grad0 = {
					f32(paint.radial.cx),
					f32(paint.radial.cy),
					f32(paint.radial.r),
					f32(paint.radial.fr),
				},
				combined = combined,
				colour = {1, 1, 1, draw_opacity},
			})
	}

	return {}, true, .Invalid_Value
}

@(private)
vector_paint_gpu_checked :: proc(gpu: Vector_Paint_GPU) -> (Vector_Paint_GPU, bool, Vector_Error) {
	for value in gpu.grad0 {
		if math.is_nan(value) || math.is_inf(value) { return {}, true, .Invalid_Value }
	}
	for value in gpu.focal {
		if math.is_nan(value) || math.is_inf(value) { return {}, true, .Invalid_Value }
	}
	// Bound shader matrix products for the renderer's physical coordinate range.
	max_coefficient := f64(max(f32)) / (4 * f64(VECTOR_MAX_COORDINATE))
	for value in gpu.combined {
		if math.is_nan(value) || math.is_inf(value) || abs(value) > max_coefficient { return {}, true, .Invalid_Value }
	}
	return gpu, false, .None
}
