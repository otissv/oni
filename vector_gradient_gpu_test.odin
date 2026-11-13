#+test
package oni

import "core:fmt"
import "core:testing"
import v "./vector"
import sdl "vendor:sdl3"
import img "vendor:sdl3/image"

@(test)
vector_gradients_match_independent_references :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		state.gpu_state.pipeline = gpu_create_ui_layout_pipeline(state.gpu, .R8G8B8A8_UNORM, .UI_Fragment, gpu_blend_state())
		testing.expect(t, state.gpu_state.pipeline != nil)
		if state.gpu_state.pipeline == nil {
			return
		}

		batch_init()
		for scale in 1 ..= 2 {
			vector_gradient_reference_case(t, scale)
			batch_reset()
		}
	})
}

@(test)
vector_gradient_instances_keep_independent_paints_on_shared_mesh :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		state.ui.pass = .Draw
		state.dpi = {logical_w = 64, logical_h = 32, drawable_w = 64, drawable_h = 32, scale = 1}
		state.gpu_state.pipeline = gpu_create_ui_layout_pipeline(state.gpu, .R8G8B8A8_UNORM, .UI_Fragment, gpu_blend_state())
		testing.expect(t, state.gpu_state.pipeline != nil)
		if state.gpu_state.pipeline == nil {
			return
		}

		gpu_update_projection(state.dpi)
		batch_init()
		path: v.Path
		defer v.Destroy_Path(&path)
		testing.expect_value(t, v.Rectangle(&path, {0, 0}, {24, 24}), v.Error.None)
		handle, err := Vector_Create_Path(path.commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		defer Vector_Destroy_Path(handle)

		stops_a := [2]Vector_Gradient_Stop{{0, {255, 0, 0, 255}}, {1, {0, 0, 255, 255}}}
		stops_b := [2]Vector_Gradient_Stop{{0, {0, 255, 0, 255}}, {1, {255, 255, 0, 255}}}
		draw_record_begin(state.dpi)
		testing.expect_value(
			t,
			Draw_Vector_Path(
				handle,
				Linear_Paint({x1 = 0, y1 = 0, x2 = 24, y2 = 0, stops = stops_a[:]}),
				{1, 0, 0, 1, 4, 4},
			),
			Vector_Error.None,
		)
		testing.expect_value(
			t,
			Draw_Vector_Path(
				handle,
				Linear_Paint({x1 = 0, y1 = 0, x2 = 24, y2 = 0, stops = stops_b[:]}),
				{1, 0, 0, 1, 36, 4},
			),
			Vector_Error.None,
		)
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
		left := pixels[(16 * 64 + 8) * 4:]
		right := pixels[(16 * 64 + 40) * 4:]
		testing.expect(t, left[0] > 200 && left[2] < 80, "left instance samples red side of gradient")
		testing.expect(t, right[1] > 180, "right instance samples green/yellow gradient")
		entry := vector_path_entry(handle)
		testing.expect(t, entry != nil && len(entry.cache) == 1)
	})
}

@(test)
vector_gpu_ramp_accounting_retains_allocated_texture_bytes :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		state.ui.pass = .Draw
		state.dpi = {logical_w = 64, logical_h = 32, drawable_w = 64, drawable_h = 32, scale = 1}
		gpu_update_projection(state.dpi)
		batch_init()

		path: v.Path
		defer v.Destroy_Path(&path)
		testing.expect_value(t, v.Rectangle(&path, {0, 0}, {16, 16}), v.Error.None)
		handle, err := Vector_Create_Path(path.commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		defer Vector_Destroy_Path(handle)

		stops := [2]Vector_Gradient_Stop{{0, {255, 0, 0, 255}}, {1, {0, 0, 255, 255}}}
		draw_many :: proc(handle: Vector_Path_Handle, count: int, stops: []Vector_Gradient_Stop) {
			batch_reset()
			draw_record_begin(state.dpi)
			for i in 0 ..< count {
				_ = Draw_Vector_Path(
					handle,
					Linear_Paint({x1 = 0, y1 = 0, x2 = 16, y2 = 0, stops = stops}),
					{1, 0, 0, 1, f64(i) * 2, 0},
				)
			}
			draw_record_end()
		}

		draw_many(handle, 3, stops[:])
		cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
		testing.expect(t, cmd != nil && vector_gpu_upload(cmd))
		testing.expect(t, sdl.CancelGPUCommandBuffer(cmd))
		grown_rows := vector_gpu_frame().ramp_rows
		grown_bytes := vector_gpu_frame().ramp_bytes
		testing.expect(t, grown_rows >= 3)
		testing.expect_value(t, grown_bytes, u64(VECTOR_RAMP_WIDTH) * u64(grown_rows) * 4)
		ramp_after_grow := vector_gpu_frame().ramp

		draw_many(handle, 1, stops[:])
		cmd = sdl.AcquireGPUCommandBuffer(state.gpu)
		testing.expect(t, cmd != nil && vector_gpu_upload(cmd))
		testing.expect(t, sdl.CancelGPUCommandBuffer(cmd))
		testing.expect(t, vector_gpu_frame().ramp == ramp_after_grow)
		testing.expect_value(t, vector_gpu_frame().ramp_rows, grown_rows)
		testing.expect_value(t, vector_gpu_frame().ramp_bytes, grown_bytes)
		testing.expect(t, state.vector.gpu.bytes >= grown_bytes)

		batch_reset()
		draw_record_begin(state.dpi)
		testing.expect_value(t, Draw_Vector_Path(handle, Solid_Paint({255, 0, 0, 255})), Vector_Error.None)
		draw_record_end()
		cmd = sdl.AcquireGPUCommandBuffer(state.gpu)
		testing.expect(t, cmd != nil && vector_gpu_upload(cmd))
		testing.expect(t, sdl.CancelGPUCommandBuffer(cmd))
		testing.expect(t, vector_gpu_frame().ramp == ramp_after_grow)
		testing.expect_value(t, vector_gpu_frame().ramp_rows, grown_rows)
		testing.expect_value(t, vector_gpu_frame().ramp_bytes, grown_bytes)
		testing.expect(t, state.vector.gpu.bytes >= grown_bytes)
	})
}

@(private)
vector_gradient_reference_case :: proc(t: ^testing.T, scale: int) {
	defer vector_scene_shutdown()
	defer vector_gpu_shutdown()
	w, h := 192 * scale, 64 * scale
	state.ui.pass = .Draw
	state.dpi = {logical_w = 192, logical_h = 64, drawable_w = i32(w), drawable_h = i32(h), scale = f32(scale)}
	gpu_update_projection(state.dpi)
	draw_record_begin(state.dpi)

	lin_stops := [2]Vector_Gradient_Stop{{0, {255, 0, 0, 255}}, {1, {0, 0, 255, 255}}}
	rad_stops := [2]Vector_Gradient_Stop{{0, {255, 255, 255, 255}}, {1, {0, 0, 0, 255}}}
	spread_stops := [2]Vector_Gradient_Stop{{0, {0, 255, 0, 255}}, {1, {0, 0, 255, 255}}}

	{
		path: v.Path
		_ = v.Rectangle(&path, {0, 0}, {28, 28})
		handle, err := Vector_Create_Path(path.commands[:])
		v.Destroy_Path(&path)
		testing.expect_value(t, err, Vector_Error.None)
		testing.expect_value(
			t,
			Draw_Vector_Path(
				handle,
				Linear_Paint({
					x1 = 0, y1 = 0, x2 = 1, y2 = 0,
					units = .Object_Bounding_Box,
					stops = lin_stops[:],
				}),
				{1, 0, 0, 1, 2.375, 2.125},
			),
			Vector_Error.None,
		)
		_ = Vector_Destroy_Path(handle)
	}
	{
		path: v.Path
		_ = v.Circle(&path, {12, 12}, 12)
		handle, err := Vector_Create_Path(path.commands[:])
		v.Destroy_Path(&path)
		testing.expect_value(t, err, Vector_Error.None)
		testing.expect_value(
			t,
			Draw_Vector_Path(
				handle,
				Radial_Paint({
					cx = 0.5, cy = 0.5, r = 0.5, fx = 0.5, fy = 0.5, fr = 0,
					units = .Object_Bounding_Box,
					stops = rad_stops[:],
				}),
				{1, 0, 0, 1, 42.375, 4.125},
			),
			Vector_Error.None,
		)
		_ = Vector_Destroy_Path(handle)
	}
	{
		path: v.Path
		_ = v.Rectangle(&path, {74.375, 2.125}, {48, 28})
		handle, err := Vector_Create_Path(path.commands[:])
		v.Destroy_Path(&path)
		testing.expect_value(t, err, Vector_Error.None)
		testing.expect_value(
			t,
			Draw_Vector_Path(
				handle,
				Linear_Paint({
					x1 = 74.375, y1 = 0, x2 = 98.375, y2 = 0,
					units = .User_Space,
					spread = .Pad,
					stops = spread_stops[:],
				}),
			),
			Vector_Error.None,
		)
		_ = Vector_Destroy_Path(handle)
	}
	{
		path: v.Path
		_ = v.Rectangle(&path, {0, 0}, {28, 28})
		handle, err := Vector_Create_Path(path.commands[:])
		v.Destroy_Path(&path)
		testing.expect_value(t, err, Vector_Error.None)
		// rotate(90 0.5 0.5) in objectBoundingBox units
		xf := v.Affine{0, 1, -1, 0, 1, 0}
		testing.expect_value(
			t,
			Draw_Vector_Path(
				handle,
				Linear_Paint({
					x1 = 0, y1 = 0, x2 = 1, y2 = 0,
					units = .Object_Bounding_Box,
					transform = xf,
					stops = lin_stops[:],
				}),
				{1, 0, 0, 1, 134.375, 2.125},
			),
			Vector_Error.None,
		)
		_ = Vector_Destroy_Path(handle)
	}
	{
		path: v.Path
		_ = v.Rectangle(&path, {0, 0}, {28, 28})
		handle, err := Vector_Create_Path(path.commands[:])
		v.Destroy_Path(&path)
		testing.expect_value(t, err, Vector_Error.None)
		testing.expect_value(
			t,
			Draw_Vector_Path(
				handle,
				Linear_Paint({
					x1 = 0, y1 = 0, x2 = 1, y2 = 0,
					units = .Object_Bounding_Box,
					stops = lin_stops[:],
				}),
				{1, 0, 0, 1, 2.375, 34.125},
				opacity = 0.5,
			),
			Vector_Error.None,
		)
		_ = Vector_Destroy_Path(handle)
	}
	{
		path: v.Path
		_ = v.Rectangle(&path, {42.375, 34.125}, {48, 28})
		handle, err := Vector_Create_Path(path.commands[:])
		v.Destroy_Path(&path)
		testing.expect_value(t, err, Vector_Error.None)
		testing.expect_value(
			t,
			Draw_Vector_Path(
				handle,
				Linear_Paint({
					x1 = 42.375, y1 = 0, x2 = 66.375, y2 = 0,
					units = .User_Space,
					spread = .Reflect,
					stops = spread_stops[:],
				}),
			),
			Vector_Error.None,
		)
		_ = Vector_Destroy_Path(handle)
	}
	{
		path: v.Path
		_ = v.Rectangle(&path, {98.375, 34.125}, {48, 28})
		handle, err := Vector_Create_Path(path.commands[:])
		v.Destroy_Path(&path)
		testing.expect_value(t, err, Vector_Error.None)
		testing.expect_value(
			t,
			Draw_Vector_Path(
				handle,
				Linear_Paint({
					x1 = 98.375, y1 = 0, x2 = 122.375, y2 = 0,
					units = .User_Space,
					spread = .Repeat,
					stops = spread_stops[:],
				}),
			),
			Vector_Error.None,
		)
		_ = Vector_Destroy_Path(handle)
	}
	{
		path: v.Path
		_ = v.Circle(&path, {12, 12}, 12)
		handle, err := Vector_Create_Path(path.commands[:])
		v.Destroy_Path(&path)
		testing.expect_value(t, err, Vector_Error.None)
		testing.expect_value(
			t,
			Draw_Vector_Path(
				handle,
				Radial_Paint({
					cx = 0.5, cy = 0.5, r = 0.5, fx = 0.2, fy = 0.5, fr = 0,
					units = .Object_Bounding_Box,
					stops = rad_stops[:],
				}),
				{1, 0, 0, 1, 158.375, 36.125},
			),
			Vector_Error.None,
		)
		_ = Vector_Destroy_Path(handle)
	}

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
	pixels, ok := gpu_test_download_vector_framebuffer(t, u32(w), u32(h))
	if !ok {
		return
	}

	defer delete(pixels)
	name := fmt.ctprintf("fixtures/vector/gradients-%dx.png", scale)
	loaded := img.Load(name)
	testing.expect(t, loaded != nil)
	if loaded == nil {
		return
	}

	defer sdl.DestroySurface(loaded)
	reference := sdl.ConvertSurface(loaded, .ABGR8888)
	testing.expect(t, reference != nil)
	if reference == nil {
		return
	}

	defer sdl.DestroySurface(reference)
	ref := cast([^]u8)reference.pixels
	difference := make([]u8, w * h * 4)
	defer delete(difference)
	cols, rows := 4, 2
	cell_w, cell_h := 48 * scale, 32 * scale
	actual_area, reference_area: [8]f64
	for y in 0 ..< h {
		for x in 0 ..< w {
			index := (y * w + x) * 4
			a := pixels[index + 3]
			r := ref[y * int(reference.pitch) + x * 4 + 3]
			col := clamp(x / cell_w, 0, cols - 1)
			row := clamp(y / cell_h, 0, rows - 1)
			region := row * cols + col
			actual_area[region] += f64(a) / 255
			reference_area[region] += f64(r) / 255
			d := u8(abs(int(a) - int(r)))
			copy(difference[index:index + 4], []u8{d, d, d, 255})
			near_actual, near_reference := false, false
			boundary := false
			high_frequency := false
			center_rgb := [3]int{
				int(ref[y * int(reference.pitch) + x * 4 + 0]),
				int(ref[y * int(reference.pitch) + x * 4 + 1]),
				int(ref[y * int(reference.pitch) + x * 4 + 2]),
			}
			for dy in -2 ..= 2 {
				for dx in -2 ..= 2 {
					px, py := clamp(x + dx, 0, w - 1), clamp(y + dy, 0, h - 1)
					na := pixels[(py * w + px) * 4 + 3]
					nr := ref[py * int(reference.pitch) + px * 4 + 3]
					near_actual ||= na > 0
					near_reference ||= nr > 0
					if (nr == 0) != (r == 0) || abs(int(nr) - int(r)) > 8 {
						boundary = true
					}
					for channel in 0 ..< 3 {
						if abs(int(ref[py * int(reference.pitch) + px * 4 + channel]) - center_rgb[channel]) > 24 {
							high_frequency = true
						}
					}
				}
			}
			testing.expectf(t, a == 0 || near_reference, "silhouette outside reference at %v,%v DPI %v", x, y, scale)
			testing.expectf(t, r == 0 || near_actual, "missing silhouette at %v,%v DPI %v", x, y, scale)
			// Include translucent interiors (alpha≈128); skip only near-zero coverage.
			// ±3/255 covers circle chord tessellation vs librsvg geometry at 2×.
			if !boundary && !high_frequency && r > 24 {
				ra := f32(r) / 255
				want := [4]int{
					int(f32(ref[y * int(reference.pitch) + x * 4 + 0]) * ra + 0.5),
					int(f32(ref[y * int(reference.pitch) + x * 4 + 1]) * ra + 0.5),
					int(f32(ref[y * int(reference.pitch) + x * 4 + 2]) * ra + 0.5),
					int(r),
				}
				for channel in 0 ..< 4 {
					got := int(pixels[index + channel])
					testing.expectf(
						t,
						abs(got - want[channel]) <= 3,
						"interior channel at %v,%v DPI %v",
						x,
						y,
						scale,
					)
				}
			}
		}
	}
	for area, i in actual_area {
		testing.expectf(
			t,
			abs(area - reference_area[i]) <= max(f64(1), reference_area[i] * 0.05),
			"integrated coverage region %v DPI %v: actual %v reference %v",
			i,
			scale,
			area,
			reference_area[i],
		)
	}
	for data, i in ([2][]u8{pixels, difference}) {
		surface := sdl.CreateSurfaceFrom(i32(w), i32(h), .ABGR8888, raw_data(data), i32(w * 4))
		testing.expect(t, surface != nil)
		if surface != nil {
			suffix := i == 0 ? "actual" : "difference"
			testing.expect(t, bool(img.SavePNG(surface, fmt.ctprintf("build/test/vector-gradients-%dx-%s.png", scale, suffix))))
			sdl.DestroySurface(surface)
		}
	}
	testing.expect_value(t, Vector_Last_Error(), Vector_Error.None)
}
