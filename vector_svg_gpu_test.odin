#+test
package oni

import "core:fmt"
import "core:testing"
import "core:sync"
import sdl "vendor:sdl3"
import img "vendor:sdl3/image"

@(test)
vector_svg_fills_match_reference :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		state.gpu_state.pipeline = gpu_create_ui_layout_pipeline(state.gpu, .R8G8B8A8_UNORM, .UI_Fragment, gpu_blend_state())
		testing.expect(t, state.gpu_state.pipeline != nil)
		if state.gpu_state.pipeline == nil {
			return
		}

		batch_init()
		for scale in 1 ..= 2 {
			for opacity in ([2]f32{1, 0.5}) {
				vector_svg_fills_reference_case(t, scale, opacity)
				batch_reset()
			}
		}
	})
}

@(private)
vector_svg_fills_reference_case :: proc(t: ^testing.T, scale: int, opacity: f32) {
	defer vector_scene_shutdown()
	defer vector_gpu_shutdown()
	w, h := 128 * scale, 64 * scale
	state.ui.pass = .Draw
	state.dpi = {logical_w = 128, logical_h = 64, drawable_w = i32(w), drawable_h = i32(h), scale = f32(scale)}
	gpu_update_projection(state.dpi)
	draw_record_begin(state.dpi)
	asset, result := Load_Svg_File("fixtures/vector/fills.svg")
	defer Destroy_Svg_Load_Result(&result)
	defer Destroy_Svg_Asset(asset)
	testing.expect(t, asset != nil && result.ok)
	if asset == nil {
		return
	}

	testing.expect_value(t, Draw_Svg_Asset(asset, opacity = opacity), Vector_Error.None)
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
	variant := opacity == 1 ? "opaque" : "translucent"
	name := fmt.ctprintf("fixtures/vector/fills-%s-%dx.png", variant, scale)
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
					got := pixels[index + channel]
					want := ref[y * int(reference.pitch) + x * 4 + channel]
					if channel < 3 { want = u8((u32(want) * u32(r) + 127) / 255) }
					testing.expectf(t, abs(int(got) - int(want)) <= 2, "interior channel at %v,%v DPI %v", x, y, scale)
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
			suffix := i == 0 ? "svg-actual" : "svg-difference"
			testing.expect(t, bool(img.SavePNG(surface, fmt.ctprintf("build/test/vector-fills-%s-%dx-%s.png", variant, scale, suffix))))
			sdl.DestroySurface(surface)
		}
	}

	testing.expect_value(t, Vector_Last_Error(), Vector_Error.None)
}

@(test)
svg_imported_profile_matches_independent_references :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	available := test_gpu_device_available_unlocked()
	sync.mutex_unlock(&test_global_state_guard)
	if !available && #config(ONI_REQUIRE_VECTOR_GPU_TESTS, false) {
		testing.expect(t, false, "M6 image acceptance requires a real GPU and cannot be skipped")
		return
	}
	with_gpu_device_env(t, proc(t: ^testing.T) {
		if !vector_composition_gpu_setup(t, 128, 64) { return }
		for name in ([]string{"css-classes", "nested-viewports", "mask-stroke", "clip-union", "gradient-inheritance", "geometry-paths", "physical-lengths", "namespace-scope", "use-sizing", "opacity-paint-order", "namespace-prefixed", "symbol-instances", "stroke-properties"}) {
			for scale in 1 ..= 2 {
				svg_profile_reference_case(t, name, scale)
				batch_reset()
			}
		}
	})
}

@(test)
svg_imported_degenerate_gradients_have_defined_colours :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 32, 16) { return }
		asset, result := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg" width="32" height="16"><defs><linearGradient id="l" x1="0" y1="0" x2="0" y2="0" spreadMethod="repeat"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient><radialGradient id="r" r="1e-15"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></radialGradient></defs><rect width="16" height="16" fill="url(#l)"/><rect x="16" width="16" height="16" fill="url(#r)"/></svg>`)
		defer Destroy_Svg_Asset(asset)
		defer Destroy_Svg_Load_Result(&result)
		testing.expect(t, asset != nil && result.ok)
		if asset == nil { return }
		draw_record_begin(state.dpi)
		testing.expect_value(t, Draw_Svg_Asset(asset), Vector_Error.None)
		draw_record_end()
		if !vector_composition_gpu_submit(t) { return }
		pixels, ok := gpu_test_download_vector_framebuffer(t, 32, 16)
		if !ok { return }
		defer delete(pixels)
		vector_composition_expect_rgba(t, pixels, 32, 8, 8, {0, 0, 255, 255}, "collapsed repeating linear gradient")
		vector_composition_expect_rgba(t, pixels, 32, 24, 8, {0, 0, 255, 255}, "tiny radial gradient")
	})
}

@(private)
svg_profile_reference_case :: proc(t: ^testing.T, name: string, scale: int) {
	defer vector_scene_shutdown()
	defer vector_gpu_shutdown()
	asset, result := Load_Svg_File(fmt.tprintf("fixtures/vector/m6/%s.svg", name))
	defer Destroy_Svg_Load_Result(&result)
	testing.expectf(t, asset != nil && result.ok, "%s: %v", name, result.diagnostics[:])
	if asset == nil { return }
	width, height := Svg_Intrinsic_Size(asset)
	w, h := int(width) * scale, int(height) * scale
	state.dpi = {logical_w = i32(width), logical_h = i32(height), drawable_w = i32(w), drawable_h = i32(h), scale = f32(scale)}
	gpu_update_projection(state.dpi)
	draw_record_begin(state.dpi)
	err := Draw_Svg_Asset(asset)
	Destroy_Svg_Asset(asset)
	testing.expect_value(t, err, Vector_Error.None)
	draw_record_end()
	if !vector_composition_gpu_submit(t) { return }
	pixels, ok := gpu_test_download_vector_framebuffer(t, u32(w), u32(h))
	if !ok { return }
	defer delete(pixels)
	loaded := img.Load(fmt.ctprintf("fixtures/vector/m6/%s-%dx.png", name, scale))
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
			reference_index := y * int(reference.pitch) + x * 4
			a, r := pixels[index + 3], ref[reference_index + 3]
			region := y / (32 * scale) * 4 + x / (32 * scale)
			actual_area[region] += f64(a) / 255
			reference_area[region] += f64(r) / 255
			interior, near_actual, near_reference := true, false, false
			for dy in -1 ..= 1 {
				for dx in -1 ..= 1 {
					px, py := clamp(x + dx, 0, w - 1), clamp(y + dy, 0, h - 1)
					near_actual ||= pixels[(py * w + px) * 4 + 3] > 0
					neighbor := ref[py * int(reference.pitch) + px * 4 + 3]
					near_reference ||= neighbor > 0
					interior &&= neighbor == r
					for channel in 0 ..< 3 {
						interior &&= abs(int(ref[py * int(reference.pitch) + px * 4 + channel]) - int(ref[reference_index + channel])) <= 32
					}
				}
			}
			testing.expectf(t, a == 0 || near_reference, "%s DPI %d: extra silhouette at %d,%d", name, scale, x, y)
			testing.expectf(t, r == 0 || near_actual, "%s DPI %d: missing silhouette at %d,%d", name, scale, x, y)
			for channel in 0 ..< 4 {
				want := ref[reference_index + channel]
				if channel < 3 { want = u8((u32(want) * u32(r) + 127) / 255) }
				difference[index + channel] = u8(abs(int(pixels[index + channel]) - int(want)))
				if interior { testing.expectf(t, abs(int(pixels[index + channel]) - int(want)) <= 2, "%s DPI %d: interior at %d,%d channel %d", name, scale, x, y, channel) }
			}
			difference[index + 3] = 255
		}
	}
	for actual, index in actual_area {
		testing.expectf(t, abs(actual - reference_area[index]) <= max(f64(1), reference_area[index] * .05), "%s DPI %d: coverage region %d got %v expected %v", name, scale, index, actual, reference_area[index])
	}
	for data, index in ([2][]u8{pixels, difference}) {
		surface := sdl.CreateSurfaceFrom(i32(w), i32(h), .ABGR8888, raw_data(data), i32(w * 4))
		testing.expect(t, surface != nil)
		if surface != nil {
			suffix := index == 0 ? "actual" : "difference"
			testing.expect(t, bool(img.SavePNG(surface, fmt.ctprintf("build/test/svg-%s-%dx-%s.png", name, scale, suffix))))
			sdl.DestroySurface(surface)
		}
	}
	testing.expect_value(t, Vector_Last_Error(), Vector_Error.None)
}
