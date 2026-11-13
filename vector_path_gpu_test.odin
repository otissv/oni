#+test
package oni

import "core:fmt"
import "core:testing"
import v "./vector"
import sdl "vendor:sdl3"
import img "vendor:sdl3/image"

@(test)
vector_paths_match_independent_fill_references :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		state.gpu_state.pipeline = gpu_create_ui_layout_pipeline(state.gpu, .R8G8B8A8_UNORM, .UI_Fragment, gpu_blend_state())
		testing.expect(t, state.gpu_state.pipeline != nil)
		if state.gpu_state.pipeline == nil { return }
		batch_init()
		for scale in 1 ..= 2 {
			for opacity in ([2]f32{1, 0.5}) {
				vector_path_reference_case(t, scale, opacity)
				batch_reset()
			}
		}
	})
}

@(test)
vector_path_shared_instances_keep_independent_paint_and_source_revisions :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		state.ui.pass = .Draw
		state.dpi = {logical_w = 48, logical_h = 16, drawable_w = 48, drawable_h = 16, scale = 1}
		state.gpu_state.pipeline = gpu_create_ui_layout_pipeline(state.gpu, .R8G8B8A8_UNORM, .UI_Fragment, gpu_blend_state())
		testing.expect(t, state.gpu_state.pipeline != nil)
		if state.gpu_state.pipeline == nil { return }
		gpu_update_projection(state.dpi)
		batch_init()
		path: v.Path
		defer v.Destroy_Path(&path)
		testing.expect_value(t, v.Rectangle(&path, {0, 0}, {12, 12}), v.Error.None)
		handle, err := Vector_Create_Path(path.commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		draw_record_begin(state.dpi)
		transform := Vector_Transform{1, 0, 0, 1, 0.375, 0.125}
		testing.expect_value(t, Draw_Vector_Path(handle, {255, 0, 0, 255}, transform), Vector_Error.None)
		transform[4] += 16
		testing.expect_value(t, Draw_Vector_Path(handle, {0, 255, 0, 255}, transform, opacity = 0.5), Vector_Error.None)
		v.Destroy_Path(&path)
		_ = v.Polyline(&path, []v.Point{{0, 0}, {12, 0}, {0, 12}}, true)
		testing.expect_value(t, Vector_Update_Path(handle, path.commands[:]), Vector_Error.None)
		transform[4] += 16
		testing.expect_value(t, Draw_Vector_Path(handle, {0, 0, 255, 255}, transform), Vector_Error.None)
		testing.expect_value(t, Vector_Destroy_Path(handle), Vector_Error.None)
		draw_record_end()
		cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {})
		testing.expect(t, cmd != nil)
		if cmd == nil { return }
		submitted := vector_gpu_frame()
		submitted.fence = sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
		fence := submitted.fence
		testing.expect(t, fence != nil)
		if fence == nil { return }
		testing.expect(t, sdl.WaitForGPUFences(state.gpu, true, &fence, 1))
		pixels, ok := gpu_test_download_vector_framebuffer(t, 48, 16)
		if !ok { return }
		defer delete(pixels)
		for wanted, i in ([3][4]u8{{255, 0, 0, 255}, {0, 128, 0, 128}, {0, 0, 255, 255}}) {
			for channel in 0 ..< 4 {
				gpu_test_expect_u8_near(t, pixels[(2 * 48 + 2 + 16 * i) * 4 + channel], wanted[channel], "shared path instance")
			}
		}
	})
}

@(private)
vector_path_reference_case :: proc(t: ^testing.T, scale: int, opacity: f32) {
	defer vector_scene_shutdown()
	defer vector_gpu_shutdown()
	w, h := 128 * scale, 64 * scale
	state.ui.pass = .Draw
	state.dpi = {logical_w = 128, logical_h = 64, drawable_w = i32(w), drawable_h = i32(h), scale = f32(scale)}
	gpu_update_projection(state.dpi)
	draw_record_begin(state.dpi)
	for i in 0 ..< 6 {
		path: v.Path
		transform := Vector_Transform{1, 0, 0, 1, 0.375, 0.125}
		rule: Vector_Fill_Rule = .Nonzero
		switch i {
		case 0:
			_ = v.Circle(&path, {16, 16}, 12)
			_ = v.Circle(&path, {16, 16}, 6)
			rule = .Even_Odd
		case 1:
			_ = v.Polyline(&path, []v.Point{{48, 2}, {57, 28}, {34, 12}, {62, 12}, {39, 28}}, true)
			rule = .Even_Odd
		case 2:
			_ = v.Move_To(&path, {66, 28})
			_ = v.Cubic_To(&path, {66, -4}, {94, -4}, {94, 28})
			_ = v.Quadratic_To(&path, {80, 40}, {66, 28})
			_ = v.Close(&path)
		case 3:
			_ = v.Polyline(&path, []v.Point{{2, 36}, {30, 60}, {2, 60}, {30, 36}}, true)
		case 4:
			_ = v.Rectangle(&path, {34, 40}, {28, 0.5})
		case 5:
			_ = v.Rectangle(&path, {4, 36}, {24, 24})
			_ = v.Polyline(&path, []v.Point{{10, 42}, {10, 54}, {22, 54}, {22, 42}}, true)
			transform = {-1, 0, 0.4, 1, 126.375, 0.125}
		}
		handle, err := Vector_Create_Path(path.commands[:])
		v.Destroy_Path(&path)
		testing.expect_value(t, err, Vector_Error.None)
		testing.expect_value(t, Draw_Vector_Path(handle, {255, 255, 255, 255}, transform, rule, opacity), Vector_Error.None)
		// The recording must survive destruction before GPU preparation.
		testing.expect_value(t, Vector_Destroy_Path(handle), Vector_Error.None)
	}
	draw_record_end()
	cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {})
	testing.expect(t, cmd != nil)
	if cmd == nil { return }
	submitted := vector_gpu_frame()
	submitted.fence = sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
	fence := submitted.fence
	testing.expect(t, fence != nil)
	if fence == nil { return }
	testing.expect(t, sdl.WaitForGPUFences(state.gpu, true, &fence, 1))
	pixels, ok := gpu_test_download_vector_framebuffer(t, u32(w), u32(h))
	if !ok { return }
	defer delete(pixels)
	variant := opacity == 1 ? "opaque" : "translucent"
	name := fmt.ctprintf("fixtures/vector/fills-%s-%dx.png", variant, scale)
	loaded := img.Load(name)
	testing.expect(t, loaded != nil)
	if loaded == nil { return }
	defer sdl.DestroySurface(loaded)
	reference := sdl.ConvertSurface(loaded, .ABGR8888)
	testing.expect(t, reference != nil)
	if reference == nil { return }
	defer sdl.DestroySurface(reference)
	ref := cast([^]u8)reference.pixels
	difference := make([]u8, w * h * 4)
	defer delete(difference)
	actual_area, reference_area: [8]f64
	for y in 0 ..< h {
		for x in 0 ..< w {
			index := (y * w + x) * 4
			a := pixels[index + 3]
			r := ref[y * int(reference.pitch) + x * 4 + 3]
			region := (y / (32 * scale)) * 4 + x / (32 * scale)
			actual_area[region] += f64(a) / 255
			reference_area[region] += f64(r) / 255
			d := u8(abs(int(a) - int(r)))
			copy(difference[index:index + 4], []u8{d, d, d, 255})
			interior := true
			near_actual, near_reference := false, false
			for dy in -1 ..= 1 {
				for dx in -1 ..= 1 {
					px, py := clamp(x + dx, 0, w - 1), clamp(y + dy, 0, h - 1)
					na := pixels[(py * w + px) * 4 + 3]
					nr := ref[py * int(reference.pitch) + px * 4 + 3]
					near_actual ||= na > 0
					near_reference ||= nr > 0
					interior &&= nr == r && (r == 0 || abs(int(r) - int(opacity * 255 + 0.5)) <= 1)
				}
			}
			testing.expectf(t, a == 0 || near_reference, "silhouette outside reference at %v,%v DPI %v", x, y, scale)
			testing.expectf(t, r == 0 || near_actual, "missing silhouette at %v,%v DPI %v", x, y, scale)
			if interior {
				for channel in 0 ..< 4 {
					testing.expectf(t, abs(int(pixels[index + channel]) - int(r)) <= 2, "interior channel at %v,%v DPI %v", x, y, scale)
				}
			}
		}
	}
	for area, i in actual_area {
		testing.expectf(t, abs(area - reference_area[i]) <= max(f64(1), reference_area[i] * 0.05), "integrated coverage region %v DPI %v: actual %v reference %v", i, scale, area, reference_area[i])
	}
	for data, i in ([2][]u8{pixels, difference}) {
		surface := sdl.CreateSurfaceFrom(i32(w), i32(h), .ABGR8888, raw_data(data), i32(w * 4))
		testing.expect(t, surface != nil)
		if surface != nil {
			suffix := i == 0 ? "actual" : "difference"
			testing.expect(t, bool(img.SavePNG(surface, fmt.ctprintf("build/test/vector-fills-%s-%dx-%s.png", variant, scale, suffix))))
			sdl.DestroySurface(surface)
		}
	}
	testing.expect_value(t, Vector_Last_Error(), Vector_Error.None)
}
