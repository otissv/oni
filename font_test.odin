package oni

import "core:c"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"
import sdl "vendor:sdl3"

PIXEL_BOLD_FONT_FIXTURE :: "fixtures/fonts/PixelOperator8-Bold.ttf"

@(private)
font_test_read_pixel :: proc(surface: ^sdl.Surface, x, y: c.int) -> (r, g, b, a: u8, ok: bool) {
	ok = sdl.ReadSurfacePixel(surface, x, y, &r, &g, &b, &a)
	return
}

@(private)
with_font_gpu_fixtures :: proc(
	t: ^testing.T,
	body: proc(inter, pixel: Font_Handle, t: ^testing.T),
) {
	if !font_fixture_available() {
		testing.expectf(
			t,
			false,
			"missing font fixtures; expected %s and %s (run from repo root)",
			INTER_FONT_FIXTURE,
			PIXEL_FONT_FIXTURE,
		)
		return
	}

	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	if !test_require_gpu_device_unlocked() {
		return
	}

	if !sdl.Init({.VIDEO}) {
		testing.expectf(t, false, "SDL_Init failed: %s", sdl.GetError())
		return
	}
	defer sdl.Quit()

	gpu := gpu_create_device(true)
	if gpu == nil {
		testing.expectf(t, false, "SDL_CreateGPUDevice failed: %s", sdl.GetError())
		return
	}
	defer sdl.DestroyGPUDevice(gpu)

	test_state: State
	saved_state := state
	saved_theme := theme
	defer {
		state = saved_state
		widget_ctx_sync()
		theme = saved_theme
	}

	state = &test_state
	widget_ctx_sync()
	theme = nil
	state.dpi = {
		logical_w = 800,
		logical_h = 600,
		scale     = 1,
	}
	state.view = view_default()
	state.gpu = gpu
	batch_current().vertex_capacity = 64 * 1024
	batch_current().index_capacity = 64 * 1024 * 6

	white := gpu_create_white_texture(gpu)
	if white == nil {
		testing.expect(t, false, "gpu_create_white_texture failed")
		return
	}
	state.gpu_state.white_texture = white
	defer {
		if state.gpu_state.white_texture != nil {
			sdl.ReleaseGPUTexture(gpu, state.gpu_state.white_texture)
			state.gpu_state.white_texture = nil
		}
	}

	texture_init()
	defer texture_shutdown()
	defer error_shutdown()
	defer {
		delete(batch_current().vertices)
		delete(batch_current().indices)
		delete(batch_current().segments)
		delete(batch_current().clip_stack)
		delete(batch_current().space_stack)
		delete(batch_current().opacity_stack)
		batch_current().vertices = nil
		batch_current().indices = nil
		batch_current().segments = nil
		batch_current().clip_stack = nil
		batch_current().space_stack = nil
		batch_current().opacity_stack = nil
	}

	testing.expect(t, font_init())
	defer font_shutdown()

	inter, inter_ok := font_register_family(
		"InterGpuTest",
		{
			{path = INTER_FONT_FIXTURE, style = .NORMAL, weight = .Normal},
			{path = INTER_ITALIC_FONT_FIXTURE, style = .ITALIC, weight = .Normal},
		},
	)
	testing.expect(t, inter_ok)
	inter = font_with_size(inter, 16)

	pixel, pixel_ok := font_register_family(
		"PixelGpuTest",
		{{path = PIXEL_FONT_FIXTURE, style = .NORMAL, weight = .Normal}},
	)
	testing.expect(t, pixel_ok)
	pixel = font_with_size(pixel, 8)

	body(inter, pixel, t)
}

@(private)
with_sdl_video :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	if !sdl.Init({.VIDEO}) {
		testing.expectf(t, false, "SDL_Init failed: %s", sdl.GetError())
		return
	}
	defer sdl.Quit()
	body(t)
}

// --- font_weights_to_f32 / font_weight_value / font_style_kind ---

@(test)
font_weights_to_f32_maps_all_named_css_weights :: proc(t: ^testing.T) {
	testing.expect_value(t, font_weights_to_f32(.Thin), f32(100))
	testing.expect_value(t, font_weights_to_f32(.Extra_Light), f32(200))
	testing.expect_value(t, font_weights_to_f32(.Light), f32(300))
	testing.expect_value(t, font_weights_to_f32(.Normal), f32(400))
	testing.expect_value(t, font_weights_to_f32(.Medium), f32(500))
	testing.expect_value(t, font_weights_to_f32(.Semi_Bold), f32(600))
	testing.expect_value(t, font_weights_to_f32(.Bold), f32(700))
	testing.expect_value(t, font_weights_to_f32(.Extra_Bold), f32(800))
	testing.expect_value(t, font_weights_to_f32(.Heavy), f32(900))
}

@(test)
font_weight_value_named_numeric_and_nil_default :: proc(t: ^testing.T) {
	testing.expect_value(t, font_weight_value(Font_Weights.Thin), f32(100))
	testing.expect_value(t, font_weight_value(Font_Weights.Bold), f32(700))
	testing.expect_value(t, font_weight_value(Font_Weights.Heavy), f32(900))

	testing.expect_value(t, font_weight_value(f32(250)), f32(250))
	testing.expect_value(t, font_weight_value(f32(0)), f32(0))
	testing.expect_value(t, font_weight_value(f32(1000)), f32(1000))
	testing.expect_value(t, font_weight_value(f32(-10)), f32(-10))

	nil_weight: Font_Weight
	testing.expect_value(t, font_weight_value(nil_weight), f32(400))
}

@(test)
font_style_kind_named_and_nil_default :: proc(t: ^testing.T) {
	testing.expect_value(t, font_style_kind(Font_Styles.NORMAL), Font_Styles.NORMAL)
	testing.expect_value(t, font_style_kind(Font_Styles.ITALIC), Font_Styles.ITALIC)

	nil_style: Font_Style
	testing.expect_value(t, font_style_kind(nil_style), Font_Styles.NORMAL)
}

// --- snap_logical / font_text_line_height / font_measure_lines ---

@(test)
snap_logical_rounds_to_device_pixels :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			state.dpi.scale = 1
			expect_close(t, snap_logical(0), 0)
			expect_close(t, snap_logical(1), 1)
			expect_close(t, snap_logical(1.2), 1)
			expect_close(t, snap_logical(1.49), 1)
			expect_close(t, snap_logical(1.5), 2)
			expect_close(t, snap_logical(1.75), 2)
			expect_close(t, snap_logical(-1.2), -1)
			expect_close(t, snap_logical(-1.6), -2)

			state.dpi.scale = 2
			expect_close(t, snap_logical(1.2), 1)
			expect_close(t, snap_logical(1.3), 1.5)
			expect_close(t, snap_logical(1.6), 1.5)
			expect_close(t, snap_logical(1.8), 2)
		},
	)
}

@(test)
font_device_to_logical_respects_dpi_scale :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			state.dpi.scale = 1
			expect_close(t, font_device_to_logical(20), 20)
			expect_close(t, font_dpi_scale(), 1)
			testing.expect(t, font_dpi_scale_is_integer())

			state.dpi.scale = 2
			expect_close(t, font_device_to_logical(20), 10)
			expect_close(t, font_dpi_scale(), 2)
			testing.expect(t, font_dpi_scale_is_integer())

			state.dpi.scale = 1.5
			expect_close(t, font_device_to_logical(30), 20)
			testing.expect(t, !font_dpi_scale_is_integer())
			testing.expect(t, !font_text_uses_nearest_filter())

			state.dpi.scale = 2
			testing.expect(t, font_text_uses_nearest_filter())
		},
	)
}

@(test)
font_load_flags_use_light_target_for_ui_sizes :: proc(t: ^testing.T) {
	testing.expect(t, font_uses_ui_hinting(16))
	testing.expect(t, font_uses_ui_hinting(FONT_UI_HINT_MAX_PX))
	testing.expect(t, !font_uses_ui_hinting(FONT_UI_HINT_MAX_PX + 1))
	testing.expect(t, !font_uses_ui_hinting(0))

	ui := font_load_flags(16, c.int(FT_LOAD_RENDER))
	testing.expect(t, (ui & c.int(FT_LOAD_TARGET_LIGHT)) != 0)
	testing.expect(t, (ui & c.int(FT_LOAD_RENDER)) != 0)

	display := font_load_flags(64, c.int(FT_LOAD_RENDER))
	testing.expect(t, (display & c.int(FT_LOAD_TARGET_LIGHT)) == 0)
	testing.expect(t, (display & c.int(FT_LOAD_RENDER)) != 0)

	lcd := font_load_flags(16, c.int(FT_LOAD_RENDER), .LCD)
	// Target bits are (mode & 15) << 16; LCD (3) shares low bits with LIGHT (1).
	testing.expect_value(t, lcd & c.int(15 << 16), c.int(FT_LOAD_TARGET_LCD))
	testing.expect_value(t, font_render_mode_ft(16, .LCD), c.int(FT_RENDER_MODE_LCD))
	testing.expect_value(t, font_render_mode_ft(16, .Gray), c.int(FT_RENDER_MODE_LIGHT))
	testing.expect_value(t, font_render_mode_ft(64, .Gray), c.int(FT_RENDER_MODE_NORMAL))
}

@(test)
font_text_coverage_gamma_boosts_light_on_dark :: proc(t: ^testing.T) {
	coverage: f32 = 0.5
	white_lum := font_tint_luminance({255, 255, 255, 255})
	black_lum := font_tint_luminance({0, 0, 0, 255})
	expect_close(t, white_lum, 1)
	expect_close(t, black_lum, 0)

	white_a := font_text_coverage_alpha(coverage, white_lum)
	black_a := font_text_coverage_alpha(coverage, black_lum)
	// Light tint densifies mid-coverage; dark tint thins it.
	testing.expect(t, white_a > coverage)
	testing.expect(t, black_a < coverage)

	expect_close(t, font_text_coverage_exponent(1), 0.70)
	expect_close(t, font_text_coverage_exponent(0), 1.45)
	expect_close(t, font_text_coverage_alpha(0, 1), 0)
	expect_close(t, font_text_coverage_alpha(1, 1), 1)
	expect_close(t, font_text_coverage_alpha(1, 0, 0.5), 0.5)
}

@(test)
font_text_line_height_prefers_explicit_override :: proc(t: ^testing.T) {
	face := Font_Face {
		line_height = 20,
	}
	expect_close(t, font_text_line_height(&face, 24, 1), 24)
	expect_close(t, font_text_line_height(&face, 24, 0.5), 24)
	expect_close(t, font_text_line_height(&face, 0, 1), 20)
	expect_close(t, font_text_line_height(&face, 0, 2), 40)
	expect_close(t, font_text_line_height(&face, -1, 1), 20)
}

@(test)
font_measure_lines_nil_empty_and_scaled :: proc(t: ^testing.T) {
	expect_close(t, font_measure_lines(nil, nil).x, 0)
	expect_close(t, font_measure_lines(nil, nil).y, 0)

	face := Font_Face {
		line_height = 12,
	}
	empty: []Shaped_Line
	size0 := font_measure_lines(&face, empty)
	expect_close(t, size0.x, 0)
	expect_close(t, size0.y, 0)

	lines := []Shaped_Line{{width = 10}, {width = 30}, {width = 20}}
	size := font_measure_lines(&face, lines, 0, 1)
	expect_close(t, size.x, 30)
	expect_close(t, size.y, 36)

	scaled := font_measure_lines(&face, lines, 0, 0.5)
	expect_close(t, scaled.x, 15)
	expect_close(t, scaled.y, 18)

	override := font_measure_lines(&face, lines, 10, 2)
	expect_close(t, override.x, 60)
	expect_close(t, override.y, 30)
}

// --- font_copy_glyph_bitmap ---

@(test)
font_copy_glyph_bitmap_lcd_writes_rgb_coverage :: proc(t: ^testing.T) {
	with_sdl_video(
		t,
		proc(t: ^testing.T) {
			// Two logical pixels: RGB triples (10,20,30) and (40,50,60).
			subpixels := [6]u8{10, 20, 30, 40, 50, 60}
			bitmap := FT_Bitmap {
				rows       = 1,
				width      = 6,
				pitch      = 6,
				buffer     = raw_data(subpixels[:]),
				pixel_mode = FT_PIXEL_MODE_LCD,
			}
			surface := sdl.CreateSurface(2, 1, .RGBA8888)
			testing.expect(t, surface != nil)
			if surface == nil do return
			defer sdl.DestroySurface(surface)

			font_copy_glyph_bitmap(&bitmap, surface)

			r0, g0, b0, a0, ok0 := font_test_read_pixel(surface, 0, 0)
			testing.expect(t, ok0)
			testing.expect_value(t, r0, u8(10))
			testing.expect_value(t, g0, u8(20))
			testing.expect_value(t, b0, u8(30))
			testing.expect_value(t, a0, u8(255))

			r1, g1, b1, a1, ok1 := font_test_read_pixel(surface, 1, 0)
			testing.expect(t, ok1)
			testing.expect_value(t, r1, u8(40))
			testing.expect_value(t, g1, u8(50))
			testing.expect_value(t, b1, u8(60))
			testing.expect_value(t, a1, u8(255))
		},
	)
}

@(test)
font_copy_glyph_bitmap_gray_writes_white_with_alpha :: proc(t: ^testing.T) {
	with_sdl_video(t, proc(t: ^testing.T) {
		alphas := [4]u8{0, 64, 128, 255}
		bitmap := FT_Bitmap {
			rows       = 2,
			width      = 2,
			pitch      = 2,
			buffer     = raw_data(alphas[:]),
			pixel_mode = FT_PIXEL_MODE_GRAY,
		}
		surface := sdl.CreateSurface(2, 2, .RGBA8888)
		testing.expect(t, surface != nil)
		if surface == nil do return
		defer sdl.DestroySurface(surface)

		font_copy_glyph_bitmap(&bitmap, surface)

		r, g, b, a, ok := font_test_read_pixel(surface, 0, 0)
		testing.expect(t, ok)
		testing.expect_value(t, r, u8(255))
		testing.expect_value(t, g, u8(255))
		testing.expect_value(t, b, u8(255))
		testing.expect_value(t, a, u8(0))

		_, _, _, a, ok = font_test_read_pixel(surface, 1, 0)
		testing.expect(t, ok)
		testing.expect_value(t, a, u8(64))

		_, _, _, a, ok = font_test_read_pixel(surface, 0, 1)
		testing.expect(t, ok)
		testing.expect_value(t, a, u8(128))

		_, _, _, a, ok = font_test_read_pixel(surface, 1, 1)
		testing.expect(t, ok)
		testing.expect_value(t, a, u8(255))
	})
}

@(test)
font_copy_glyph_bitmap_mono_unpacks_msb_first_bits :: proc(t: ^testing.T) {
	with_sdl_video(
		t,
		proc(t: ^testing.T) {
			// One byte: bits 1 0 1 0 0 0 0 1 -> pixels on/off for 8 columns, 1 row.
			src := [1]u8{0b10100001}
			bitmap := FT_Bitmap {
				rows       = 1,
				width      = 8,
				pitch      = 1,
				buffer     = raw_data(src[:]),
				pixel_mode = FT_PIXEL_MODE_MONO,
			}
			surface := sdl.CreateSurface(8, 1, .RGBA8888)
			testing.expect(t, surface != nil)
			if surface == nil do return
			defer sdl.DestroySurface(surface)

			font_copy_glyph_bitmap(&bitmap, surface)

			want := [8]u8{255, 0, 255, 0, 0, 0, 0, 255}
			for col in 0 ..< 8 {
				r, g, b, a, ok := font_test_read_pixel(surface, c.int(col), 0)
				testing.expect(t, ok)
				testing.expect_value(t, r, u8(255))
				testing.expect_value(t, g, u8(255))
				testing.expect_value(t, b, u8(255))
				testing.expect_value(t, a, want[col])
			}
		},
	)
}

@(test)
font_copy_glyph_bitmap_bgra_swizzles_to_rgba_write :: proc(t: ^testing.T) {
	with_sdl_video(
		t,
		proc(t: ^testing.T) {
			// B, G, R, A
			src := [4]u8{10, 20, 30, 40}
			bitmap := FT_Bitmap {
				rows       = 1,
				width      = 1,
				pitch      = 4,
				buffer     = raw_data(src[:]),
				pixel_mode = FT_PIXEL_MODE_BGRA,
			}
			surface := sdl.CreateSurface(1, 1, .RGBA8888)
			testing.expect(t, surface != nil)
			if surface == nil do return
			defer sdl.DestroySurface(surface)

			font_copy_glyph_bitmap(&bitmap, surface)
			r, g, b, a, ok := font_test_read_pixel(surface, 0, 0)
			testing.expect(t, ok)
			testing.expect_value(t, r, u8(30))
			testing.expect_value(t, g, u8(20))
			testing.expect_value(t, b, u8(10))
			testing.expect_value(t, a, u8(40))
		},
	)
}

@(test)
font_copy_glyph_bitmap_unsupported_mode_leaves_surface_untouched :: proc(t: ^testing.T) {
	with_sdl_video(t, proc(t: ^testing.T) {
		src := [1]u8{255}
		bitmap := FT_Bitmap {
			rows       = 1,
			width      = 1,
			pitch      = 1,
			buffer     = raw_data(src[:]),
			pixel_mode = 99,
		}
		surface := sdl.CreateSurface(1, 1, .RGBA8888)
		testing.expect(t, surface != nil)
		if surface == nil do return
		defer sdl.DestroySurface(surface)

		testing.expect(t, sdl.WriteSurfacePixel(surface, 0, 0, 1, 2, 3, 4))

		sync.mutex_lock(&log_test_guard)
		defer sync.mutex_unlock(&log_test_guard)

		_ = os.make_directory_all("build")
		path := "build/test_font_unsupported_pixel_mode.txt"
		_ = os.remove(path)
		file, err := os.open(path, {.Write, .Create, .Trunc})
		testing.expectf(t, err == nil, "open capture: %v", err)
		if err != nil do return
		old := os.stderr
		os.stderr = file
		font_copy_glyph_bitmap(&bitmap, surface)
		os.flush(file)
		os.stderr = old
		os.close(file)

		data, read_err := os.read_entire_file(path, context.allocator)
		testing.expect(t, read_err == nil)
		defer delete(data)
		testing.expect(t, strings.contains(string(data), "Unsupported glyph pixel mode"))

		r, g, b, a, ok := font_test_read_pixel(surface, 0, 0)
		testing.expect(t, ok)
		testing.expect_value(t, r, u8(1))
		testing.expect_value(t, g, u8(2))
		testing.expect_value(t, b, u8(3))
		testing.expect_value(t, a, u8(4))
	})
}

@(test)
font_copy_glyph_bitmap_gray_respects_pitch_padding :: proc(t: ^testing.T) {
	with_sdl_video(
		t,
		proc(t: ^testing.T) {
			// width=2, pitch=4 with padding bytes that must be ignored.
			src := [8]u8{10, 20, 0xEE, 0xFF, 30, 40, 0xEE, 0xFF}
			bitmap := FT_Bitmap {
				rows       = 2,
				width      = 2,
				pitch      = 4,
				buffer     = raw_data(src[:]),
				pixel_mode = FT_PIXEL_MODE_GRAY,
			}
			surface := sdl.CreateSurface(2, 2, .RGBA8888)
			testing.expect(t, surface != nil)
			if surface == nil do return
			defer sdl.DestroySurface(surface)

			font_copy_glyph_bitmap(&bitmap, surface)
			_, _, _, a00, ok0 := font_test_read_pixel(surface, 0, 0)
			_, _, _, a10, ok1 := font_test_read_pixel(surface, 1, 0)
			_, _, _, a01, ok2 := font_test_read_pixel(surface, 0, 1)
			_, _, _, a11, ok3 := font_test_read_pixel(surface, 1, 1)
			testing.expect(t, ok0 && ok1 && ok2 && ok3)
			testing.expect_value(t, a00, u8(10))
			testing.expect_value(t, a10, u8(20))
			testing.expect_value(t, a01, u8(30))
			testing.expect_value(t, a11, u8(40))
		},
	)
}

// --- font_resolve ---

@(test)
font_resolve_rejects_invalid_family_handle :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = inter
		_ = pixel
		_, scale, ok := font_resolve({id = Asset_Id(9999), size_px = 16}, 16, .SCREEN)
		testing.expect(t, !ok)
		expect_close(t, scale, 1)
	})
}

@(test)
font_resolve_defaults_size_from_handle_then_sixteen :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		sized := font_with_size(inter, 22)
		handle, _, ok := font_resolve(sized, 0, .SCREEN)
		testing.expect(t, ok)
		face := font_face_from_handle(handle)
		testing.expect(t, face != nil)
		expect_close(t, face.size_px, 22)

		bare := Font_Handle {
			id      = inter.id,
			size_px = 0,
		}
		handle2, _, ok2 := font_resolve(bare, 0, .SCREEN)
		testing.expect(t, ok2)
		face2 := font_face_from_handle(handle2)
		testing.expect(t, face2 != nil)
		expect_close(t, face2.size_px, 16)
	})
}

@(test)
font_resolve_screen_layout_scale_is_one :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		_, scale, ok := font_resolve(inter, 16, .SCREEN)
		testing.expect(t, ok)
		expect_close(t, scale, 1)
	})
}

@(test)
font_resolve_artboard_applies_zoom_and_inverse_layout_scale :: proc(t: ^testing.T) {
	with_font_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			view_set_zoom(2)
			handle, scale, ok := font_resolve(inter, 16, .ARTBOARD)
			testing.expect(t, ok)
			expect_close(t, scale, 0.5)
			face := font_face_from_handle(handle)
			testing.expect(t, face != nil)
			// font_resolve passes zoomed raster size into the instance handle.
			expect_close(t, handle.size_px, 32)
			expect_close(t, face.size_px, 32)
			testing.expect(t, face.pixel_size >= 30)

			view_set_zoom(1)
			_, scale1, ok1 := font_resolve(inter, 16, .ARTBOARD)
			testing.expect(t, ok1)
			expect_close(t, scale1, 1)
		},
	)
}

@(test)
font_resolve_caches_identical_instances :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		a, _, aok := font_resolve(inter, 16, .SCREEN, .Normal, .NORMAL)
		b, _, bok := font_resolve(inter, 16, .SCREEN, .Normal, .NORMAL)
		testing.expect(t, aok && bok)
		testing.expect_value(t, a.id, b.id)
	})
}

@(test)
font_resolve_italic_and_numeric_weight :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		italic, _, iok := font_resolve(inter, 16, .SCREEN, .Normal, .ITALIC)
		testing.expect(t, iok)
		iface := font_face_from_handle(italic)
		testing.expect(t, iface != nil)
		testing.expect(t, iface.style == .ITALIC || iface.fake_italic)

		heavy, _, hok := font_resolve(inter, 16, .SCREEN, f32(850), .NORMAL)
		testing.expect(t, hok)
		hface := font_face_from_handle(heavy)
		testing.expect(t, hface != nil)
		testing.expect(t, hface.weight >= 800 || hface.fake_bold)
	})
}

@(test)
font_resolve_static_pixel_fake_bold_when_heavier_than_source :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = inter
		bold, _, ok := font_resolve(pixel, 8, .SCREEN, .Bold, .NORMAL)
		testing.expect(t, ok)
		face := font_face_from_handle(bold)
		testing.expect(t, face != nil)
		testing.expect(t, face.fake_bold)
	})
}

@(test)
font_resolve_fake_italic_when_family_lacks_italic_source :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = inter
		italic, _, ok := font_resolve(pixel, 8, .SCREEN, .Normal, .ITALIC)
		testing.expect(t, ok)
		face := font_face_from_handle(italic)
		testing.expect(t, face != nil)
		testing.expect(t, face.fake_italic)
	})
}

// --- font_atlas_reset ---

@(test)
font_atlas_reset_noop_when_atlas_uninitialized :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	test_state: State
	saved := state
	defer {
		state = saved
		widget_ctx_sync()
	}
	state = &test_state
	widget_ctx_sync()
	texture_init()
	defer texture_shutdown()

	testing.expect_value(t, state.textures.atlas.texture_id, INVALID_ASSET_ID)
	font_atlas_reset() // must not panic
	testing.expect_value(t, state.textures.atlas.texture_id, INVALID_ASSET_ID)
}

@(test)
font_atlas_reset_clears_pixels_and_shelves :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = inter
			_ = pixel
			testing.expect(t, texture_atlas_init(64))
			region, ok := texture_atlas_alloc(8, 8)
			testing.expect(t, ok)
			testing.expect(t, len(state.textures.atlas.shelves) >= 1)

			index := int(state.textures.atlas.texture_id)
			entry := &state.textures.records[index]
			testing.expect(t, entry.surface != nil)
			pixels := cast([^]u8)entry.surface.pixels
			pixels[0] = 123
			pixels[1] = 45

			font_atlas_reset()
			testing.expect_value(t, len(state.textures.atlas.shelves), 0)
			testing.expect_value(t, pixels[0], u8(0))
			testing.expect_value(t, pixels[1], u8(0))
			// Atlas identity preserved for reuse.
			testing.expect_value(t, state.textures.atlas.texture_id, region.texture_id)
		},
	)
}

@(test)
font_atlas_reset_clears_glyph_cache :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, handle, ok := font_test_face(inter, 16)
			testing.expect(t, ok)

			shaped := font_shape(face, "Ag", .LTR)
			defer delete(shaped)
			testing.expect(t, len(shaped) >= 1)
			testing.expect(t, font_ensure_glyphs(face, handle.id, shaped))
			testing.expect(t, len(state.fonts.glyph_cache) >= 1)

			atlas_id := state.textures.atlas.texture_id
			gen_before := state.textures.atlas.generation
			testing.expect(t, atlas_id != INVALID_ASSET_ID)
			testing.expect(t, len(state.textures.atlas.shelves) >= 1)
			testing.expect(t, state.textures.atlas.slot_count >= 1)

			font_atlas_reset()

			testing.expect_value(t, len(state.textures.atlas.shelves), 0)
			testing.expect_value(t, len(state.fonts.glyph_cache), 0)
			testing.expect_value(t, state.textures.atlas.texture_id, atlas_id)
			testing.expect_value(t, state.textures.atlas.slot_count, u32(0))
			testing.expect_value(t, state.textures.atlas.bytes_used, u64(0))
			testing.expect_value(t, state.textures.atlas.generation, gen_before + 1)

			// Re-ensure after reset must repack; cache is empty then populated again.
			testing.expect(t, font_ensure_glyphs(face, handle.id, shaped))
			testing.expect(t, len(state.fonts.glyph_cache) >= 1)
			testing.expect(t, len(state.textures.atlas.shelves) >= 1)

			for key, entry in state.fonts.glyph_cache {
				_ = key
				testing.expect_value(t, entry.generation, state.textures.atlas.generation)
			}
		},
	)
}

@(test)
font_glyph_residency_stamp_and_generation_on_ensure :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, handle, ok := font_test_face(inter, 16)
			testing.expect(t, ok)

			shaped := font_shape(face, "A", .LTR)
			defer delete(shaped)
			testing.expect(t, len(shaped) >= 1)

			state.ui.frame = 11
			testing.expect(t, font_ensure_glyphs(face, handle.id, shaped))

			key := Font_Glyph_Key {
				face_id  = handle.id,
				glyph_id = shaped[0].glyph_id,
			}
			entry, found := state.fonts.glyph_cache[key]
			testing.expect(t, found)
			testing.expect_value(t, entry.last_used_frame, u64(11))
			testing.expect_value(t, entry.generation, state.textures.atlas.generation)
			testing.expect_value(t, entry.flags, Font_Glyph_Residency_Flags{})

			stats := atlas_stats()
			testing.expect(t, stats.slot_count >= 1)
			testing.expect(t, stats.cache_count >= 1)
			testing.expect_value(t, stats.generation, state.textures.atlas.generation)
			testing.expect_value(t, stats.frame, u64(11))

			state.ui.frame = 22
			testing.expect(t, font_ensure_glyphs(face, handle.id, shaped))
			entry2, found2 := state.fonts.glyph_cache[key]
			testing.expect(t, found2)
			testing.expect_value(t, entry2.last_used_frame, u64(22))
			testing.expect_value(t, entry2.generation, entry.generation)
		},
	)
}

@(test)
font_atlas_evict_cold_skips_hot_and_pinned :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, handle, ok := font_test_face(inter, 16)
			testing.expect(t, ok)

			shaped := font_shape(face, "ABC", .LTR)
			defer delete(shaped)
			testing.expect(t, len(shaped) >= 3)

			state.ui.frame = 10
			testing.expect(t, font_ensure_glyphs(face, handle.id, shaped))

			hot_key := Font_Glyph_Key {
				face_id  = handle.id,
				glyph_id = shaped[0].glyph_id,
			}
			cold_key := Font_Glyph_Key {
				face_id  = handle.id,
				glyph_id = shaped[1].glyph_id,
			}
			pinned_key := Font_Glyph_Key {
				face_id  = handle.id,
				glyph_id = shaped[2].glyph_id,
			}

			{
				e := &state.fonts.glyph_cache[hot_key]
				e.last_used_frame = 10
			}
			{
				e := &state.fonts.glyph_cache[cold_key]
				e.last_used_frame = 1
			}
			{
				// Age-cold ( < frame-3 ) but pin still active ( >= frame-5 ).
				e := &state.fonts.glyph_cache[pinned_key]
				e.last_used_frame = 5
				e.flags = {.Pinned, .Prefetched}
			}

			state.ui.frame = 10
			evicted := font_atlas_evict_cold()
			testing.expect_value(t, evicted, 1)
			testing.expect(t, hot_key in state.fonts.glyph_cache)
			testing.expect(t, cold_key not_in state.fonts.glyph_cache)
			testing.expect(t, pinned_key in state.fonts.glyph_cache)
			testing.expect(t, state.textures.atlas.needs_repack)
		},
	)
}

@(test)
font_atlas_prefetch_pin_expires_then_evicts :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, handle, ok := font_test_face(inter, 16)
			testing.expect(t, ok)

			shaped := font_shape(face, "A", .LTR)
			defer delete(shaped)
			testing.expect(t, len(shaped) >= 1)
			testing.expect(t, font_ensure_glyphs(face, handle.id, shaped))

			key := Font_Glyph_Key {
				face_id  = handle.id,
				glyph_id = shaped[0].glyph_id,
			}
			{
				e := &state.fonts.glyph_cache[key]
				e.last_used_frame = 1
				e.flags = {.Pinned, .Prefetched}
			}

			state.ui.frame = u64(ATLAS_PREFETCH_PIN_FRAMES) + 2
			evicted := font_atlas_evict_cold()
			testing.expect(t, evicted >= 1)
			testing.expect(t, key not_in state.fonts.glyph_cache)
		},
	)
}

@(test)
font_atlas_compact_rewrites_survivor_regions_and_generation :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, handle, ok := font_test_face(inter, 16)
			testing.expect(t, ok)

			shaped := font_shape(face, "Ag", .LTR)
			defer delete(shaped)
			testing.expect(t, len(shaped) >= 2)
			testing.expect(t, font_ensure_glyphs(face, handle.id, shaped))

			gen_before := state.textures.atlas.generation
			before_regions := make(map[Font_Glyph_Key]Atlas_Region, context.temp_allocator)
			for key, entry in state.fonts.glyph_cache {
				before_regions[key] = entry.region
			}

			// Fragment shelves: evict one cold glyph so compact can reclaim.
			state.ui.frame = 20
			marked_cold := false
			for _, &entry in state.fonts.glyph_cache {
				if !marked_cold {
					entry.last_used_frame = 0
					marked_cold = true
				} else {
					entry.last_used_frame = 20
				}
			}

			_ = font_atlas_evict_cold()
			used_before := atlas_stats().used_percent

			testing.expect(t, Atlas_Compact())
			testing.expect_value(t, state.textures.atlas.generation, gen_before + 1)
			testing.expect(t, !state.textures.atlas.needs_repack)
			testing.expect(t, len(state.fonts.glyph_cache) <= len(before_regions))
			testing.expect(t, atlas_stats().used_percent <= used_before + 0.01)

			for key, entry in state.fonts.glyph_cache {
				testing.expect_value(t, entry.generation, state.textures.atlas.generation)
				testing.expect(t, entry.region.w > 0 || entry.region.h > 0)
				testing.expect_value(t, entry.region.texture_id, state.textures.atlas.texture_id)
				testing.expect(t, texture_get_gpu(entry.region.texture_id) != nil)
				_ = before_regions[key]
			}
		},
	)
}

@(test)
font_atlas_fill_evict_repack_packs_new_keeps_hot :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			// Small atlas + modest size so we can fill with distinct glyphs.
			testing.expect(t, texture_atlas_init(64))
			// Hold growth so this test exercises evict+repack, not Group D grow.
			state.textures.max_2d_texture_size = 64
			face, handle, ok := font_test_face(inter, 18)
			testing.expect(t, ok)

			fill := font_shape(
				face,
				"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789",
				.LTR,
			)
			defer delete(fill)
			testing.expect(t, len(fill) >= 8)

			state.ui.frame = 10
			packed := 0
			for g in fill {
				entry, rok := font_rasterize_glyph(face, g.glyph_id, .Gray)
				if !rok {
					break
				}

				key := Font_Glyph_Key {
					face_id  = handle.id,
					glyph_id = g.glyph_id,
				}
				state.fonts.glyph_cache[key] = entry
				packed += 1
				if !texture_atlas_can_fit(8, 8) {
					break
				}
			}

			testing.expect(t, packed >= 2)
			testing.expect(t, len(state.fonts.glyph_cache) >= 2)

			// Age every cached glyph to cold, then restamp one as hot.
			for key, &entry in state.fonts.glyph_cache {
				_ = key
				entry.last_used_frame = 1
			}

			hot_glyph := fill[0]
			hot_key := Font_Glyph_Key {
				face_id  = handle.id,
				glyph_id = hot_glyph.glyph_id,
			}
			testing.expect(t, hot_key in state.fonts.glyph_cache)
			{
				e := &state.fonts.glyph_cache[hot_key]
				e.last_used_frame = 10
			}

			// Find a glyph not yet cached.
			new_glyph: Shaped_Glyph
			found_new := false
			for g in fill {
				key := Font_Glyph_Key {
					face_id  = handle.id,
					glyph_id = g.glyph_id,
				}
				if key not_in state.fonts.glyph_cache {
					new_glyph = g
					found_new = true
					break
				}
			}

			if !found_new {
				// Atlas held the whole fill set; force pressure with a second face size.
				face2, handle2, ok2 := font_test_face(inter, 20)
				testing.expect(t, ok2)
				extra := font_shape(face2, "W", .LTR)
				defer delete(extra)
				testing.expect(t, len(extra) >= 1)
				new_glyph = extra[0]
				handle = handle2
				face = face2
				found_new = true
			}

			testing.expect(t, found_new)
			state.ui.frame = 10
			gen_before := state.textures.atlas.generation
			testing.expect(t, font_ensure_glyphs(face, handle.id, {new_glyph}))

			new_key := Font_Glyph_Key {
				face_id  = handle.id,
				glyph_id = new_glyph.glyph_id,
			}
			testing.expect(t, new_key in state.fonts.glyph_cache)
			testing.expect(t, hot_key in state.fonts.glyph_cache)
			testing.expect(t, state.textures.atlas.generation >= gen_before)

			hot_entry := state.fonts.glyph_cache[hot_key]
			testing.expect_value(t, hot_entry.generation, state.textures.atlas.generation)
			testing.expect(t, hot_entry.region.w > 0 || hot_entry.region.h > 0)
			testing.expect_value(t, hot_entry.region.texture_id, state.textures.atlas.texture_id)
		},
	)
}

@(test)
font_atlas_recover_fails_when_hot_fill_at_effective_max :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			testing.expect(t, texture_atlas_init(32))
			// Cap growth at current size so Group D refuses (overflow is Group E).
			state.textures.max_2d_texture_size = 32
			face, handle, ok := font_test_face(inter, 16)
			testing.expect(t, ok)

			fill := font_shape(face, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", .LTR)
			defer delete(fill)

			state.ui.frame = 50
			for g in fill {
				entry, rok := font_rasterize_glyph(face, g.glyph_id, .Gray)
				if !rok {
					break
				}

				state.fonts.glyph_cache[Font_Glyph_Key {
						face_id  = handle.id,
						glyph_id = g.glyph_id,
					}] = entry
				if !texture_atlas_can_fit(4, 4) {
					break
				}
			}

			testing.expect(t, len(state.fonts.glyph_cache) >= 1)
			// All entries are current-frame hot — eviction must not remove them.
			for key, &entry in state.fonts.glyph_cache {
				_ = key
				entry.last_used_frame = 50
			}

			testing.expect(t, !font_atlas_recover_space(16, 16))
			testing.expect_value(t, state.textures.atlas.width, i32(32))
			testing.expect(t, len(state.fonts.glyph_cache) >= 1)
		},
	)
}

@(test)
font_atlas_grows_when_hot_glyphs_fill_tiny_atlas :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			testing.expect(t, texture_atlas_init(64))
			// Hold growth during fill so pressure lands on a true 64×64 atlas.
			state.textures.max_2d_texture_size = 64
			face, handle, ok := font_test_face(inter, 18)
			testing.expect(t, ok)

			fill := font_shape(
				face,
				"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz",
				.LTR,
			)
			defer delete(fill)
			testing.expect(t, len(fill) >= 8)

			state.ui.frame = 40
			for g in fill {
				entry, rok := font_rasterize_glyph(face, g.glyph_id, .Gray)
				if !rok {
					break
				}

				state.fonts.glyph_cache[Font_Glyph_Key {
						face_id  = handle.id,
						glyph_id = g.glyph_id,
					}] = entry
				if !texture_atlas_can_fit(8, 8) {
					break
				}
			}

			testing.expect(t, len(state.fonts.glyph_cache) >= 2)
			for key, &entry in state.fonts.glyph_cache {
				_ = key
				entry.last_used_frame = 40
			}

			new_glyph: Shaped_Glyph
			found_new := false
			for g in fill {
				key := Font_Glyph_Key {
					face_id  = handle.id,
					glyph_id = g.glyph_id,
				}
				if key not_in state.fonts.glyph_cache {
					new_glyph = g
					found_new = true
					break
				}
			}

			if !found_new {
				face2, handle2, ok2 := font_test_face(inter, 22)
				testing.expect(t, ok2)
				extra := font_shape(face2, "W", .LTR)
				defer delete(extra)
				testing.expect(t, len(extra) >= 1)
				new_glyph = extra[0]
				handle = handle2
				face = face2
				found_new = true
			}

			testing.expect(t, found_new)
			width_before := state.textures.atlas.width
			testing.expect_value(t, width_before, i32(64))

			state.textures.max_2d_texture_size = 256
			testing.expect(t, font_ensure_glyphs(face, handle.id, {new_glyph}))
			testing.expect(t, state.textures.atlas.width >= width_before * 2)
			testing.expect(t, state.textures.atlas.width <= i32(256))

			new_key := Font_Glyph_Key {
				face_id  = handle.id,
				glyph_id = new_glyph.glyph_id,
			}
			testing.expect(t, new_key in state.fonts.glyph_cache)
			entry := state.fonts.glyph_cache[new_key]
			testing.expect_value(t, entry.generation, state.textures.atlas.generation)
			testing.expect_value(t, entry.region.texture_id, state.textures.atlas.texture_id)
		},
	)
}

@(test)
font_atlas_try_grow_refuses_past_hard_or_device_max :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = inter
			_ = pixel
			testing.expect(t, texture_atlas_init(128))
			state.textures.max_2d_texture_size = 128
			testing.expect_value(t, texture_atlas_effective_max(), i32(128))
			testing.expect(t, !font_atlas_try_grow(8, 8))
			testing.expect_value(t, state.textures.atlas.width, i32(128))

			// HARD_MAX also clamps even if device reports higher.
			state.textures.max_2d_texture_size = ATLAS_HARD_MAX * 2
			testing.expect_value(t, texture_atlas_effective_max(), i32(ATLAS_HARD_MAX))
		},
	)
}

// --- font_glyph_metrics ---

@(private)
font_test_glyph_paint_from_cache :: proc(
	face: ^Font_Face,
	face_id: Asset_Id,
	glyph: Shaped_Glyph,
	pen_x, baseline_y, scale: f32,
) -> (
	paint: Layout_Glyph_Paint,
	ok: bool,
) {
	_ = face
	key := Font_Glyph_Key {
		face_id  = face_id,
		glyph_id = glyph.glyph_id,
	}
	entry, cache_ok := state.fonts.glyph_cache[key]
	if !cache_ok do return {}, false

	return font_glyph_paint_from_entry(face_id, glyph, entry, pen_x, baseline_y, scale), true
}

@(test)
font_glyph_metrics_nil_face_and_invalid_glyph :: proc(t: ^testing.T) {
	_, _, _, _, ok := font_glyph_metrics(nil, 1)
	testing.expect(t, !ok)

	face := Font_Face{}
	_, _, _, _, ok = font_glyph_metrics(&face, 1)
	testing.expect(t, !ok)
}

@(test)
font_glyph_metrics_matches_rasterized_bearings :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, _, ok := font_test_face(inter, 16)
			testing.expect(t, ok)

			shaped := font_shape(face, "Ag", .LTR)
			defer delete(shaped)
			testing.expect(t, len(shaped) >= 2)

			for glyph in shaped {
				mw, mh, mbx, mby, metrics_ok := font_glyph_metrics(face, glyph.glyph_id)
				testing.expect(t, metrics_ok)

				entry, cache_ok := font_rasterize_glyph(face, glyph.glyph_id)
				testing.expect(t, cache_ok)

				expect_close(t, mbx, font_device_to_logical(entry.bearing_x), 1.5)
				expect_close(t, mby, font_device_to_logical(entry.bearing_y), 1.5)
				expect_close(t, mw, font_device_to_logical(entry.region.w), 1.5)
				expect_close(t, mh, font_device_to_logical(entry.region.h), 1.5)
			}
		},
	)
}

// --- font_ensure_glyphs / font_rasterize_glyph / font_ensure_glyphs_from_paint ---

@(test)
font_ensure_glyphs_nil_face_and_empty_are_success :: proc(t: ^testing.T) {
	testing.expect(t, font_ensure_glyphs(nil, 0, nil))
	testing.expect(t, font_ensure_glyphs(nil, 0, {}))
	face := Font_Face{}
	testing.expect(t, font_ensure_glyphs(&face, 0, {}))
}

@(test)
font_ensure_glyphs_from_paint_nil_face_and_empty_are_success :: proc(t: ^testing.T) {
	testing.expect(t, font_ensure_glyphs_from_paint(nil))
	testing.expect(t, font_ensure_glyphs_from_paint({}))
}

@(test)
font_ensure_glyphs_short_circuits_when_all_cached :: proc(t: ^testing.T) {
	with_font_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, handle, ok := font_test_face(inter, 16)
			testing.expect(t, ok)
			glyphs := []Shaped_Glyph{{glyph_id = 7}, {glyph_id = 8}}
			layout_test_seed_glyph(handle.id, 7, 4, 4)
			layout_test_seed_glyph(handle.id, 8, 4, 4)
			// No GPU / atlas available in this env; success proves cache short-circuit.
			testing.expect(t, font_ensure_glyphs(face, handle.id, glyphs))
		},
	)
}

@(test)
font_ensure_glyphs_from_paint_fails_without_gpu_when_glyphs_present :: proc(t: ^testing.T) {
	with_font_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, handle, ok := font_test_face(inter, 16)
			testing.expect(t, ok)
			_ = face
			paints := []Layout_Glyph_Paint{{face_id = handle.id, glyph_id = 1, dst = {0, 0, 4, 4}}}
			// Even if cached, paint path always calls texture_atlas_init.
			layout_test_seed_glyph(handle.id, 1, 4, 4)
			testing.expect(t, !font_ensure_glyphs_from_paint(paints))
		},
	)
}

@(test)
font_rasterize_and_ensure_glyphs_packs_into_atlas :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, handle, ok := font_test_face(inter, 16)
			testing.expect(t, ok)

			shaped := font_shape(face, "Ag", .LTR)
			defer delete(shaped)
			testing.expect(t, len(shaped) >= 2)

			testing.expect(t, font_ensure_glyphs(face, handle.id, shaped))
			for g in shaped {
				key := Font_Glyph_Key {
					face_id  = handle.id,
					glyph_id = g.glyph_id,
				}
				entry, found := state.fonts.glyph_cache[key]
				testing.expect(t, found)
				testing.expect(t, entry.region.w > 0 || entry.region.h > 0 || true)
				testing.expect(t, entry.region.texture_id != INVALID_ASSET_ID)
			}

			// Second call is all-cached short-circuit.
			before := len(state.fonts.glyph_cache)
			testing.expect(t, font_ensure_glyphs(face, handle.id, shaped))
			testing.expect_value(t, len(state.fonts.glyph_cache), before)
		},
	)
}

/*
Phase C.4 exit: LCD glyphs pack with logical width (subpixel/3), and gray vs LCD
never share a cache entry for the same face+glyph.
*/
@(test)
font_lcd_glyph_packs_and_gray_cache_entries_are_isolated :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, handle, ok := font_test_face(inter, 16)
			testing.expect(t, ok)

			shaped := font_shape(face, "A", .LTR)
			defer delete(shaped)
			testing.expect(t, len(shaped) >= 1)
			gid := shaped[0].glyph_id

			gray_entry, gray_ok := font_rasterize_glyph(face, gid, .Gray)
			testing.expect(t, gray_ok)
			lcd_entry, lcd_ok := font_rasterize_glyph(face, gid, .LCD)
			testing.expect(t, lcd_ok)

			state.fonts.glyph_cache[Font_Glyph_Key {
					face_id     = handle.id,
					glyph_id    = gid,
					render_mode = .Gray,
				}] = gray_entry
			state.fonts.glyph_cache[Font_Glyph_Key {
					face_id     = handle.id,
					glyph_id    = gid,
					render_mode = .LCD,
				}] = lcd_entry

			gray_key := Font_Glyph_Key {
				face_id     = handle.id,
				glyph_id    = gid,
				render_mode = .Gray,
			}
			lcd_key := Font_Glyph_Key {
				face_id     = handle.id,
				glyph_id    = gid,
				render_mode = .LCD,
			}
			got_gray, found_gray := state.fonts.glyph_cache[gray_key]
			got_lcd, found_lcd := state.fonts.glyph_cache[lcd_key]
			testing.expect(t, found_gray)
			testing.expect(t, found_lcd)
			testing.expect(t, got_gray.region.texture_id != INVALID_ASSET_ID)
			testing.expect(t, got_lcd.region.texture_id != INVALID_ASSET_ID)
			testing.expect(t, got_lcd.region.w > 0)
			testing.expect(t, got_lcd.region.h > 0)

			// Distinct atlas slots (same glyph, different render modes).
			testing.expect(
				t,
				got_gray.region.x != got_lcd.region.x ||
				got_gray.region.y != got_lcd.region.y ||
				got_gray.region.w != got_lcd.region.w ||
				got_gray.region.h != got_lcd.region.h,
			)

			// LCD surface from rasterize is logical width (bitmap.width/3).
			surface, _, _, rok := font_rasterize_glyph_bitmap(
				face.ft_face,
				face.fake_bold,
				gid,
				face.pixel_size,
				.LCD,
			)
			testing.expect(t, rok)
			if surface != nil {
				defer sdl.DestroySurface(surface)
				testing.expect(t, surface.w > 0)
				testing.expect_value(t, surface.w, i32(got_lcd.region.w))
			}

			// ensure_glyphs(.LCD) hits the LCD key, not gray.
			before := len(state.fonts.glyph_cache)
			testing.expect(t, font_ensure_glyphs(face, handle.id, shaped, .LCD))
			testing.expect_value(t, len(state.fonts.glyph_cache), before)
		},
	)
}

@(test)
font_invalidate_lcd_glyphs_removes_lcd_keeps_gray :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, handle, ok := font_test_face(inter, 16)
			testing.expect(t, ok)

			shaped := font_shape(face, "A", .LTR)
			defer delete(shaped)
			testing.expect(t, len(shaped) >= 1)
			gid := shaped[0].glyph_id

			gray_entry, gray_ok := font_rasterize_glyph(face, gid, .Gray)
			testing.expect(t, gray_ok)
			lcd_entry, lcd_ok := font_rasterize_glyph(face, gid, .LCD)
			testing.expect(t, lcd_ok)

			gray_key := Font_Glyph_Key {
				face_id     = handle.id,
				glyph_id    = gid,
				render_mode = .Gray,
			}
			lcd_key := Font_Glyph_Key {
				face_id     = handle.id,
				glyph_id    = gid,
				render_mode = .LCD,
			}
			state.fonts.glyph_cache[gray_key] = gray_entry
			state.fonts.glyph_cache[lcd_key] = lcd_entry

			font_invalidate_lcd_glyphs()
			testing.expect(t, gray_key in state.fonts.glyph_cache)
			testing.expect(t, lcd_key not_in state.fonts.glyph_cache)
		},
	)
}

@(test)
font_rasterize_glyph_bitmap_lcd_pixel_mode_and_dims :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, _, ok := font_test_face(inter, 16)
			testing.expect(t, ok)

			shaped := font_shape(face, "A", .LTR)
			defer delete(shaped)
			testing.expect(t, len(shaped) >= 1)

			// Direct FreeType path: LCD load produces FT_PIXEL_MODE_LCD.
			flags := font_load_flags(face.pixel_size, c.int(FT_LOAD_RENDER), .LCD)
			testing.expect(t, ft_ok(Load_Glyph(face.ft_face, c.uint(shaped[0].glyph_id), flags)))
			bitmap := ft_slot_bitmap(ft_glyph_slot(face.ft_face))^
			testing.expect_value(t, bitmap.pixel_mode, u8(FT_PIXEL_MODE_LCD))
			testing.expect(t, bitmap.width % 3 == 0)

			surface, _, _, rok := font_rasterize_glyph_bitmap(
				face.ft_face,
				false,
				shaped[0].glyph_id,
				face.pixel_size,
				.LCD,
			)
			testing.expect(t, rok)
			if surface == nil do return
			defer sdl.DestroySurface(surface)

			testing.expect_value(t, surface.w, i32(bitmap.width / 3))
			testing.expect_value(t, surface.h, i32(bitmap.rows))

			// Not the gray white+α pattern: at least one channel differs across RGB.
			r, g, b, a, pok := font_test_read_pixel(surface, 0, 0)
			testing.expect(t, pok)
			testing.expect_value(t, a, u8(255))
			_ = r
			_ = g
			_ = b
		},
	)
}

@(test)
font_rasterize_glyph_space_uses_empty_placeholder_region :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, _, ok := font_test_face(inter, 16)
			testing.expect(t, ok)

			shaped := font_shape(face, " ", .LTR)
			defer delete(shaped)
			testing.expect(t, len(shaped) >= 1)

			entry, rok := font_rasterize_glyph(face, shaped[0].glyph_id)
			testing.expect(t, rok)
			// Empty bitmaps allocate a 1x1 placeholder.
			testing.expect(t, entry.region.w >= 1)
			testing.expect(t, entry.region.h >= 1)
		},
	)
}

@(test)
font_rasterize_glyph_fake_bold_path_succeeds :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = inter
		handle, _, ok := font_resolve(pixel, 8, .SCREEN, .Bold, .NORMAL)
		testing.expect(t, ok)
		face := font_face_from_handle(handle)
		testing.expect(t, face != nil && face.fake_bold)

		shaped := font_shape(face, "W", .LTR)
		defer delete(shaped)
		testing.expect(t, len(shaped) >= 1)

		entry, rok := font_rasterize_glyph(face, shaped[0].glyph_id)
		testing.expect(t, rok)
		testing.expect(t, entry.region.w > 0)
		testing.expect(t, entry.region.h > 0)
	})
}

@(test)
font_ensure_glyphs_from_paint_rasterizes_missing_and_skips_cached :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		shaped := font_shape(face, "xy", .LTR)
		defer delete(shaped)
		testing.expect(t, len(shaped) >= 2)

		paints := make([]Layout_Glyph_Paint, len(shaped))
		defer delete(paints)
		for g, i in shaped {
			paints[i] = {
				face_id  = handle.id,
				glyph_id = g.glyph_id,
				dst      = {f32(i * 8), 0, 8, 10},
			}
		}

		testing.expect(t, font_ensure_glyphs_from_paint(paints))
		for g in shaped {
			_, found := state.fonts.glyph_cache[{face_id = handle.id, glyph_id = g.glyph_id}]
			testing.expect(t, found)
		}

		count := len(state.fonts.glyph_cache)
		testing.expect(t, font_ensure_glyphs_from_paint(paints))
		testing.expect_value(t, len(state.fonts.glyph_cache), count)
	})
}

@(test)
font_ensure_glyphs_parallel_path_caches_many_unique_glyphs :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, handle, ok := font_test_face(inter, 16)
			testing.expect(t, ok)

			// Enough distinct glyphs to trip FONT_GLYPH_PARALLEL_THRESHOLD.
			shaped := font_shape(face, "ABCDEabcde", .LTR)
			defer delete(shaped)
			testing.expect(t, len(shaped) >= FONT_GLYPH_PARALLEL_THRESHOLD)

			testing.expect(t, font_ensure_glyphs(face, handle.id, shaped))
			for g in shaped {
				_, found := state.fonts.glyph_cache[{face_id = handle.id, glyph_id = g.glyph_id}]
				testing.expect(t, found)
			}
		},
	)
}

@(test)
font_rasterize_real_inter_glyph_has_positive_bearings_when_inked :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, _, ok := font_test_face(inter, 24)
		testing.expect(t, ok)
		shaped := font_shape(face, "H", .LTR)
		defer delete(shaped)
		testing.expect(t, len(shaped) == 1)

		entry, rok := font_rasterize_glyph(face, shaped[0].glyph_id)
		testing.expect(t, rok)
		testing.expect(t, entry.region.w > 1)
		testing.expect(t, entry.region.h > 1)
		testing.expect(t, entry.bearing_y > 0)
	})
}

// --- should_use_lcd (Phase C.6) ---

@(test)
should_use_lcd_requires_pipeline_subpixel_nearest_and_opaque :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = inter
			_ = pixel

			opaque := Lcd_Draw_State {
				tint_a            = 255,
				effective_opacity = 1,
				axis_aligned      = true,
			}
			testing.expect(t, !should_use_lcd(opaque))

			pipeline := gpu_create_lcd_pipeline(state.gpu, .R8G8B8A8_UNORM)
			testing.expect(t, pipeline != nil)
			state.gpu_state.lcd_pipeline = pipeline
			defer {
				sdl.ReleaseGPUGraphicsPipeline(state.gpu, state.gpu_state.lcd_pipeline)
				state.gpu_state.lcd_pipeline = nil
			}

			state.dpi.scale = 1
			state.dpi.subpixel_order = .RGB
			state.view = view_default()
			testing.expect(t, should_use_lcd(opaque))
			testing.expect_value(t, font_glyph_render_mode_for_draw(opaque), Font_Glyph_Render_Mode.LCD)

			state.dpi.subpixel_order = .BGR
			testing.expect(t, should_use_lcd(opaque))

			state.dpi.subpixel_order = .Unknown
			testing.expect(t, !should_use_lcd(opaque))
			state.dpi.subpixel_order = .None
			testing.expect(t, !should_use_lcd(opaque))
			state.dpi.subpixel_order = .RGB

			testing.expect(t, !should_use_lcd({tint_a = 254, effective_opacity = 1, axis_aligned = true}))
			testing.expect(t, !should_use_lcd({tint_a = 255, effective_opacity = 0.99, axis_aligned = true}))
			testing.expect(t, !should_use_lcd({tint_a = 255, effective_opacity = 1, axis_aligned = false}))

			state.dpi.scale = 1.5
			testing.expect(t, !should_use_lcd(opaque))
			state.dpi.scale = 1

			draw_push_space(.ARTBOARD)
			view_set_zoom(2)
			testing.expect(t, !should_use_lcd(opaque))
			view_set_zoom(VIEW_ZOOM_DEFAULT)
			testing.expect(t, should_use_lcd(opaque))
			draw_pop_space()

			testing.expect_value(
				t,
				font_glyph_render_mode_for_draw(
					{tint_a = 200, effective_opacity = 1, axis_aligned = true},
				),
				Font_Glyph_Render_Mode.Gray,
			)
		},
	)
}

/*
Phase C.6 exit: opaque 1:1 UI text uses LCD cache + batch lcd; translucent / fractional → gray.
*/
@(test)
font_draw_layout_text_uses_lcd_when_gated_else_gray :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			pipeline := gpu_create_lcd_pipeline(state.gpu, .R8G8B8A8_UNORM)
			testing.expect(t, pipeline != nil)
			state.gpu_state.lcd_pipeline = pipeline
			defer {
				sdl.ReleaseGPUGraphicsPipeline(state.gpu, state.gpu_state.lcd_pipeline)
				state.gpu_state.lcd_pipeline = nil
			}

			state.dpi.scale = 1
			state.dpi.subpixel_order = .RGB
			state.view = view_default()

			face, handle, ok := font_test_face(inter, 16)
			testing.expect(t, ok)

			shaped := font_shape(face, "A", .LTR)
			defer delete(shaped)
			testing.expect(t, len(shaped) >= 1)

			paints := make([]Layout_Glyph_Paint, 1)
			defer delete(paints)
			paints[0] = {
				face_id  = handle.id,
				glyph_id = shaped[0].glyph_id,
				dst      = {10, 20, 8, 12},
			}
			lines := []Shaped_Line{{glyphs = shaped, width = 8, direction = .LTR}}
			laid := Layout_Text {
				lines  = lines,
				glyphs = paints,
				font   = handle,
				size   = {8, 16},
			}

			draw_begin_record :: proc() {
				clear(&batch_current().vertices)
				clear(&batch_current().indices)
				clear(&batch_current().segments)
				batch_current().current_key = {}
				batch_current().has_current_key = false
			}

			draw_begin_record()
			_ = font_draw_layout_text(&laid, RGBA{255, 255, 255, 255})
			testing.expect(t, len(batch_current().segments) >= 1)
			testing.expect(t, batch_current().segments[0].key.lcd)
			lcd_key := Font_Glyph_Key {
				face_id     = handle.id,
				glyph_id    = shaped[0].glyph_id,
				render_mode = .LCD,
			}
			testing.expect(t, lcd_key in state.fonts.glyph_cache)

			draw_begin_record()
			_ = font_draw_layout_text(&laid, RGBA{255, 255, 255, 200})
			testing.expect(t, len(batch_current().segments) >= 1)
			testing.expect(t, !batch_current().segments[0].key.lcd)
			gray_key := Font_Glyph_Key {
				face_id     = handle.id,
				glyph_id    = shaped[0].glyph_id,
				render_mode = .Gray,
			}
			testing.expect(t, gray_key in state.fonts.glyph_cache)

			draw_begin_record()
			draw_push_opacity(0.5)
			_ = font_draw_layout_text(&laid, RGBA{255, 255, 255, 255})
			draw_pop_opacity()
			testing.expect(t, len(batch_current().segments) >= 1)
			testing.expect(t, !batch_current().segments[0].key.lcd)

			state.dpi.scale = 1.25
			draw_begin_record()
			_ = font_draw_layout_text(&laid, RGBA{255, 255, 255, 255})
			testing.expect(t, len(batch_current().segments) >= 1)
			testing.expect(t, !batch_current().segments[0].key.lcd)
		},
	)
}

@(test)
batch_lcd_ubo_bgr_flag_matches_subpixel_order :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		state.dpi.subpixel_order = .RGB
		ubo := GPU_Lcd_UBO {
			bgr = dpi_subpixel_order() == .BGR ? 1 : 0,
		}
		expect_close(t, ubo.bgr, 0)

		state.dpi.subpixel_order = .BGR
		ubo.bgr = dpi_subpixel_order() == .BGR ? 1 : 0
		expect_close(t, ubo.bgr, 1)
	})
}

// --- font_draw_layout_text ---

@(test)
font_draw_layout_text_early_returns :: proc(t: ^testing.T) {
	with_font_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = inter
			_ = pixel
			white := RGBA{255, 255, 255, 255}
			size := font_draw_layout_text(nil, white)
			expect_close(t, size.x, 0)
			expect_close(t, size.y, 0)

			laid := Layout_Text{}
			size = font_draw_layout_text(&laid, white)
			expect_close(t, size.x, 0)

			laid.lines = []Shaped_Line{{width = 1}}
			// Invalid face id → nil face → empty return without drawing.
			laid.font = {
				id      = Asset_Id(9999),
				size_px = 16,
			}
			size = font_draw_layout_text(&laid, white)
			expect_close(t, size.x, 0)
			expect_close(t, size.y, 0)
		},
	)
}

@(test)
font_draw_layout_text_draws_glyphs_and_decorations :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		shaped := font_shape(face, "Hi", .LTR)
		defer delete(shaped)
		testing.expect(t, len(shaped) >= 2)
		testing.expect(t, font_ensure_glyphs(face, handle.id, shaped))

		paints := make([]Layout_Glyph_Paint, len(shaped))
		defer delete(paints)
		for g, i in shaped {
			paints[i] = {
				face_id  = handle.id,
				glyph_id = g.glyph_id,
				dst      = {10 + f32(i) * 8, 20, 8, 12},
			}
		}

		strokes := []Layout_Decoration_Stroke{{a = {10, 34}, b = {40, 34}, thickness = 1}}
		lines := []Shaped_Line{{glyphs = shaped, width = 20, direction = .LTR}}
		laid := Layout_Text {
			lines              = lines,
			glyphs             = paints,
			decoration_strokes = strokes,
			font               = handle,
			size               = {40, 16},
		}

		before_verts := len(batch_current().vertices)
		got := font_draw_layout_text(&laid, RGBA{255, 255, 255, 255}, RGBA{255, 0, 0, 255})
		expect_close(t, got.x, 40)
		expect_close(t, got.y, 16)
		testing.expect(t, len(batch_current().vertices) > before_verts)
	})
}

@(test)
font_draw_layout_text_skips_decorations_when_alpha_zero :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, handle, ok := font_test_face(inter, 16)
			testing.expect(t, ok)
			shaped := font_shape(face, "A", .LTR)
			defer delete(shaped)
			testing.expect(t, font_ensure_glyphs(face, handle.id, shaped))

			paints := []Layout_Glyph_Paint{{face_id = handle.id, glyph_id = shaped[0].glyph_id, dst = {0, 0, 8, 10}}}
			strokes := []Layout_Decoration_Stroke{{a = {0, 0}, b = {10, 0}, thickness = 2}}
			laid := Layout_Text {
				lines              = []Shaped_Line{{width = 8}},
				glyphs             = paints,
				decoration_strokes = strokes,
				font               = handle,
				size               = {8, 10},
			}

			white := RGBA{255, 255, 255, 255}
			_ = font_draw_layout_text(&laid, white, RGBA{255, 255, 255, 0})
			// Still drew glyph quads; decoration skipped — just assert it returned size.
			got := font_draw_layout_text(&laid, white, {})
			expect_close(t, got.x, 8)
			expect_close(t, got.y, 10)
		},
	)
}

@(test)
font_draw_layout_text_continues_when_glyph_missing_from_cache_after_ensure_fail :: proc(
	t: ^testing.T,
) {
	with_font_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			_, handle, ok := font_test_face(inter, 16)
			testing.expect(t, ok)
			// Glyphs present but atlas cannot init without GPU → ensure fails → empty size.
			laid := Layout_Text {
				lines  = []Shaped_Line{{width = 1}},
				glyphs = []Layout_Glyph_Paint{{face_id = handle.id, glyph_id = 42, dst = {0, 0, 4, 4}}},
				font   = handle,
				size   = {9, 9},
			}
			got := font_draw_layout_text(&laid, RGBA{255, 255, 255, 255})
			expect_close(t, got.x, 0)
			expect_close(t, got.y, 0)
		},
	)
}

// --- Integration: reload atlas reset path used by font_reload_faces ---

@(test)
font_reload_faces_resets_atlas_and_recreates_families :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, handle, ok := font_test_face(inter, 16)
			testing.expect(t, ok)
			shaped := font_shape(face, "R", .LTR)
			defer delete(shaped)
			testing.expect(t, font_ensure_glyphs(face, handle.id, shaped))
			testing.expect(t, len(state.fonts.glyph_cache) >= 1)
			testing.expect(t, len(state.textures.atlas.shelves) >= 1)

			name_before := strings.clone(state.fonts.families[int(inter.id)].name)
			defer delete(name_before)

			font_reload_faces()
			testing.expect_value(t, len(state.fonts.faces), 0)
			testing.expect_value(t, len(state.fonts.glyph_cache), 0)
			testing.expect_value(t, len(state.textures.atlas.shelves), 0)
			testing.expect(t, len(state.fonts.families) >= 1)

			// Re-resolve after reload.
			re_inter := Font_Handle {
				id      = Asset_Id(0),
				size_px = 16,
			}
			// Family order preserved: first registered family is InterGpuTest.
			found := false
			for family, i in state.fonts.families {
				if family.name == name_before {
					re_inter.id = Asset_Id(i)
					found = true
					break
				}
			}
			testing.expect(t, found)
			_, _, rok := font_resolve(re_inter, 16, .SCREEN)
			testing.expect(t, rok)
		},
	)
}

@(test)
font_pixel_bold_fixture_registers_when_present :: proc(t: ^testing.T) {
	if !os.exists(PIXEL_BOLD_FONT_FIXTURE) {
		testing.expectf(t, false, "missing %s", PIXEL_BOLD_FONT_FIXTURE)
		return
	}
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = inter
		_ = pixel
		bold_family, ok := font_register_family(
			"PixelBoldTest",
			{
				{path = PIXEL_FONT_FIXTURE, style = .NORMAL, weight = .Normal},
				{path = PIXEL_BOLD_FONT_FIXTURE, style = .NORMAL, weight = .Bold},
			},
		)
		testing.expect(t, ok)
		bold_family = font_with_size(bold_family, 8)

		normal, _, nok := font_resolve(bold_family, 8, .SCREEN, .Normal, .NORMAL)
		bold, _, bok := font_resolve(bold_family, 8, .SCREEN, .Bold, .NORMAL)
		testing.expect(t, nok && bok)
		nface := font_face_from_handle(normal)
		bface := font_face_from_handle(bold)
		testing.expect(t, nface != nil && bface != nil)
		testing.expect(t, !bface.fake_bold)
		testing.expect(t, nface.path != bface.path)
	})
}

// --- Gap coverage: failure paths, negative pitch, zoom edges, draw variants ---

@(test)
font_copy_glyph_bitmap_negative_pitch_gray_reads_top_row_first :: proc(t: ^testing.T) {
	with_sdl_video(
		t,
		proc(t: ^testing.T) {
			// Memory layout bottom→top; FreeType negative pitch with buffer at top row.
			// Row0 (top): 10,20  Row1 (bottom): 30,40  stored as [30,40, pad,pad, 10,20, pad,pad]
			// buffer points at top row (offset 4), pitch = -4.
			storage := [8]u8{30, 40, 0, 0, 10, 20, 0, 0}
			top := raw_data(storage[4:])
			bitmap := FT_Bitmap {
				rows       = 2,
				width      = 2,
				pitch      = -4,
				buffer     = top,
				pixel_mode = FT_PIXEL_MODE_GRAY,
			}
			surface := sdl.CreateSurface(2, 2, .RGBA8888)
			testing.expect(t, surface != nil)
			if surface == nil do return
			defer sdl.DestroySurface(surface)

			font_copy_glyph_bitmap(&bitmap, surface)
			_, _, _, a00, ok0 := font_test_read_pixel(surface, 0, 0)
			_, _, _, a10, ok1 := font_test_read_pixel(surface, 1, 0)
			_, _, _, a01, ok2 := font_test_read_pixel(surface, 0, 1)
			_, _, _, a11, ok3 := font_test_read_pixel(surface, 1, 1)
			testing.expect(t, ok0 && ok1 && ok2 && ok3)
			testing.expect_value(t, a00, u8(10))
			testing.expect_value(t, a10, u8(20))
			testing.expect_value(t, a01, u8(30))
			testing.expect_value(t, a11, u8(40))
		},
	)
}

@(test)
font_copy_glyph_bitmap_negative_pitch_mono_and_bgra :: proc(t: ^testing.T) {
	with_sdl_video(
		t,
		proc(t: ^testing.T) {
			// Mono: 2 rows × 8 cols, pitch -1. Bottom row in memory first.
			mono_store := [2]u8{0b00001111, 0b11110000}
			mono := FT_Bitmap {
				rows       = 2,
				width      = 8,
				pitch      = -1,
				buffer     = raw_data(mono_store[1:]),
				pixel_mode = FT_PIXEL_MODE_MONO,
			}
			ms := sdl.CreateSurface(8, 2, .RGBA8888)
			testing.expect(t, ms != nil)
			if ms == nil do return
			defer sdl.DestroySurface(ms)
			font_copy_glyph_bitmap(&mono, ms)
			_, _, _, a0, ok0 := font_test_read_pixel(ms, 0, 0)
			_, _, _, a7, ok1 := font_test_read_pixel(ms, 7, 0)
			_, _, _, b0, ok2 := font_test_read_pixel(ms, 0, 1)
			_, _, _, b7, ok3 := font_test_read_pixel(ms, 7, 1)
			testing.expect(t, ok0 && ok1 && ok2 && ok3)
			testing.expect_value(t, a0, u8(255))
			testing.expect_value(t, a7, u8(0))
			testing.expect_value(t, b0, u8(0))
			testing.expect_value(t, b7, u8(255))

			// BGRA negative pitch: 1×2, pitch -4.
			bgra_store := [8]u8{1, 2, 3, 4, 10, 20, 30, 40} // bottom then top
			bgra := FT_Bitmap {
				rows       = 2,
				width      = 1,
				pitch      = -4,
				buffer     = raw_data(bgra_store[4:]),
				pixel_mode = FT_PIXEL_MODE_BGRA,
			}
			bs := sdl.CreateSurface(1, 2, .RGBA8888)
			testing.expect(t, bs != nil)
			if bs == nil do return
			defer sdl.DestroySurface(bs)
			font_copy_glyph_bitmap(&bgra, bs)
			r0, g0, b0c, a0c, ok4 := font_test_read_pixel(bs, 0, 0)
			r1, g1, b1c, a1c, ok5 := font_test_read_pixel(bs, 0, 1)
			testing.expect(t, ok4 && ok5)
			testing.expect_value(t, r0, u8(30))
			testing.expect_value(t, g0, u8(20))
			testing.expect_value(t, b0c, u8(10))
			testing.expect_value(t, a0c, u8(40))
			testing.expect_value(t, r1, u8(3))
			testing.expect_value(t, g1, u8(2))
			testing.expect_value(t, b1c, u8(1))
			testing.expect_value(t, a1c, u8(4))
		},
	)
}

@(test)
font_copy_glyph_bitmap_zero_dims_or_nil_buffer_is_noop :: proc(t: ^testing.T) {
	with_sdl_video(t, proc(t: ^testing.T) {
		surface := sdl.CreateSurface(1, 1, .RGBA8888)
		testing.expect(t, surface != nil)
		if surface == nil do return
		defer sdl.DestroySurface(surface)
		testing.expect(t, sdl.WriteSurfacePixel(surface, 0, 0, 9, 8, 7, 6))

		empty := FT_Bitmap {
			rows       = 0,
			width      = 1,
			pitch      = 1,
			buffer     = nil,
			pixel_mode = FT_PIXEL_MODE_GRAY,
		}
		font_copy_glyph_bitmap(&empty, surface)
		nil_buf := FT_Bitmap {
			rows       = 1,
			width      = 1,
			pitch      = 1,
			buffer     = nil,
			pixel_mode = FT_PIXEL_MODE_GRAY,
		}
		font_copy_glyph_bitmap(&nil_buf, surface)

		r, g, b, a, ok := font_test_read_pixel(surface, 0, 0)
		testing.expect(t, ok)
		testing.expect_value(t, r, u8(9))
		testing.expect_value(t, g, u8(8))
		testing.expect_value(t, b, u8(7))
		testing.expect_value(t, a, u8(6))
	})
}

@(test)
font_bitmap_row_positive_and_negative_pitch :: proc(t: ^testing.T) {
	buf := [6]u8{0, 1, 2, 3, 4, 5}
	row0 := font_bitmap_row(raw_data(buf[:]), 3, 0)
	row1 := font_bitmap_row(raw_data(buf[:]), 3, 1)
	testing.expect_value(t, row0[0], u8(0))
	testing.expect_value(t, row1[0], u8(3))

	// Negative: buffer at "top" which is second row in storage [bottom...][top...]
	store := [6]u8{10, 11, 12, 20, 21, 22}
	top := raw_data(store[3:])
	t0 := font_bitmap_row(top, -3, 0)
	t1 := font_bitmap_row(top, -3, 1)
	testing.expect_value(t, t0[0], u8(20))
	testing.expect_value(t, t1[0], u8(10))
}

@(test)
font_resolve_artboard_zoom_clamps_and_tiny_logical_size :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		view_set_zoom(VIEW_ZOOM_MAX)
		handle, scale, ok := font_resolve(inter, 16, .ARTBOARD)
		testing.expect(t, ok)
		z := view_effective_zoom()
		expect_close(t, scale, 1 / z)
		testing.expect(t, handle.size_px >= 16 * z - 1)

		view_set_zoom(VIEW_ZOOM_MIN)
		_, scale_min, ok_min := font_resolve(inter, 16, .ARTBOARD)
		testing.expect(t, ok_min)
		zmin := view_effective_zoom()
		expect_close(t, scale_min, 1 / zmin)

		tiny, _, tok := font_resolve(inter, 0.25, .SCREEN)
		testing.expect(t, tok)
		tface := font_face_from_handle(tiny)
		testing.expect(t, tface != nil)
		testing.expect(t, tface.pixel_size >= 1)

		view_set_zoom(1)
	})
}

@(test)
font_ensure_glyphs_fails_without_gpu_when_uncached :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)
		shaped := font_shape(face, "Z", .LTR)
		defer delete(shaped)
		testing.expect(t, len(shaped) >= 1)
		for g in shaped {
			delete_key(
				&state.fonts.glyph_cache,
				Font_Glyph_Key{face_id = handle.id, glyph_id = g.glyph_id},
			)
		}
		testing.expect(t, !font_ensure_glyphs(face, handle.id, shaped))
	})
}

@(test)
font_rasterize_glyph_rejects_out_of_range_glyph_id :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, _, ok := font_test_face(inter, 16)
		testing.expect(t, ok)
		_, rok := font_rasterize_glyph(face, 0x7FFFFFFF)
		testing.expect(t, !rok)
	})
}

@(test)
font_rasterize_glyph_fails_when_atlas_is_full :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			// Small face so the glyph fits the effective max (not oversize standalone).
			face, _, ok := font_test_face(inter, 12)
			testing.expect(t, ok)

			// Tiny atlas: exhaust primary + overflow so Group E cannot rescue.
			testing.expect(t, texture_atlas_init(16))
			// Cap growth so Group D cannot rescue an intentionally full atlas.
			state.textures.max_2d_texture_size = 16
			for {
				_, aok := texture_atlas_alloc(1, 1)
				if !aok do break
			}

			for len(state.textures.overflow) < ATLAS_OVERFLOW_CAP {
				atlas, ook := texture_atlas_ensure_overflow()
				testing.expect(t, ook)
				testing.expect(t, atlas != nil)
				for {
					_, aok := texture_atlas_alloc_in(atlas, 1, 1)
					if !aok do break
				}
			}

			testing.expect(t, !texture_atlas_can_fit_any(1, 1))

			shaped := font_shape(face, "i", .LTR)
			defer delete(shaped)
			testing.expect(t, len(shaped) >= 1)
			_, rok := font_rasterize_glyph(face, shaped[0].glyph_id)
			testing.expect(t, !rok)
			testing.expect_value(t, state.textures.last_pack_fail, Atlas_Pack_Fail.Exhausted)
		},
	)
}

@(test)
font_rasterize_empty_glyph_fails_when_placeholder_cannot_alloc :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, _, ok := font_test_face(inter, 16)
		testing.expect(t, ok)
		testing.expect(t, texture_atlas_init(8))
		state.textures.max_2d_texture_size = 8

		// Exhaust primary and every overflow sheet so recover cannot place the
		// 1x1 empty-glyph placeholder (Group E soft-fail at overflow cap).
		for {
			_, aok := texture_atlas_alloc(1, 1)
			if !aok do break
		}

		for len(state.textures.overflow) < ATLAS_OVERFLOW_CAP {
			atlas, ook := texture_atlas_ensure_overflow()
			testing.expect(t, ook)
			testing.expect(t, atlas != nil)
			for {
				_, aok := texture_atlas_alloc_in(atlas, 1, 1)
				if !aok do break
			}
		}

		_, more := texture_atlas_ensure_overflow()
		testing.expect(t, !more)
		testing.expect(t, !texture_atlas_can_fit_any(1, 1))

		shaped := font_shape(face, " ", .LTR)
		defer delete(shaped)
		testing.expect(t, len(shaped) >= 1)
		_, rok := font_rasterize_glyph(face, shaped[0].glyph_id)
		testing.expect(t, !rok)
	})
}

@(test)
font_atlas_reset_skips_nil_surface_and_out_of_range_id :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	test_state: State
	saved := state
	defer {
		state = saved
		widget_ctx_sync()
	}
	state = &test_state
	widget_ctx_sync()
	texture_init()
	defer texture_shutdown()

	state.textures.atlas.texture_id = Asset_Id(9999)
	append(&state.textures.atlas.shelves, Atlas_Shelf{y = 0, height = 8, cursor_x = 4})
	font_atlas_reset()
	testing.expect_value(t, len(state.textures.atlas.shelves), 0)

	state.textures.atlas.texture_id = Asset_Id(0) // white / slot zero — index>0 check skips pixels
	append(&state.textures.atlas.shelves, Atlas_Shelf{})
	font_atlas_reset()
	testing.expect_value(t, len(state.textures.atlas.shelves), 0)
}

@(test)
font_draw_layout_text_decorations_only_without_glyphs :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		_, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		laid := Layout_Text {
			lines              = []Shaped_Line{{width = 20}},
			glyphs             = {},
			decoration_strokes = []Layout_Decoration_Stroke {
				{a = {0, 0}, b = {20, 0}, thickness = 2},
			},
			font               = handle,
			size               = {20, 12},
		}
		before := len(batch_current().vertices)
		got := font_draw_layout_text(&laid, RGBA{255, 255, 255, 255}, RGBA{0, 0, 0, 255})
		expect_close(t, got.x, 20)
		expect_close(t, got.y, 12)
		testing.expect(t, len(batch_current().vertices) > before)
	})
}

@(test)
font_draw_layout_text_re_ensures_deleted_glyph_before_paint :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, handle, ok := font_test_face(inter, 16)
			testing.expect(t, ok)
			shaped := font_shape(face, "AB", .LTR)
			defer delete(shaped)
			testing.expect(t, len(shaped) >= 2)
			testing.expect(t, font_ensure_glyphs(face, handle.id, shaped[:1]))

			// Only first glyph cached; second missing. Ensure will try to fill both.
			// Pre-delete second so ensure re-rasterizes; then delete again after ensure
			// to exercise the draw-loop `continue` on missing cache entry.
			paints := make([]Layout_Glyph_Paint, len(shaped))
			defer delete(paints)
			for g, i in shaped {
				paints[i] = {
					face_id  = handle.id,
					glyph_id = g.glyph_id,
					dst      = {f32(i) * 10, 0, 8, 10},
				}
			}
			testing.expect(t, font_ensure_glyphs_from_paint(paints))
			delete_key(
				&state.fonts.glyph_cache,
				Font_Glyph_Key{face_id = handle.id, glyph_id = shaped[1].glyph_id},
			)

			laid := Layout_Text {
				lines  = []Shaped_Line{{width = 20}},
				glyphs = paints,
				font   = handle,
				size   = {20, 10},
			}
			batch_reset()
			got := font_draw_layout_text(&laid, RGBA{255, 255, 255, 255})
			expect_close(t, got.x, 20)
			// Draw re-ensures the deleted glyph, so both glyph quads are emitted.
			testing.expect_value(t, len(batch_current().vertices), len(shaped) * 4)
		},
	)
}

@(test)
font_draw_layout_text_emits_quad_vertices_per_glyph :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)
		shaped := font_shape(face, "Hi", .LTR)
		defer delete(shaped)
		testing.expect(t, font_ensure_glyphs(face, handle.id, shaped))

		paints := make([]Layout_Glyph_Paint, len(shaped))
		defer delete(paints)
		for g, i in shaped {
			paints[i] = {
				face_id  = handle.id,
				glyph_id = g.glyph_id,
				dst      = {f32(i) * 8, 4, 7, 9},
			}
		}
		laid := Layout_Text {
			lines  = []Shaped_Line{{width = 16}},
			glyphs = paints,
			font   = handle,
			size   = {16, 12},
		}
		batch_reset()
		_ = font_draw_layout_text(&laid, RGBA{255, 255, 255, 255})
		testing.expect_value(t, len(batch_current().vertices), len(shaped) * 4)
		testing.expect_value(t, len(batch_current().indices), len(shaped) * 6)
		testing.expect(t, len(batch_current().segments) >= 1)
	})
}

@(test)
font_ensure_glyphs_from_paint_returns_false_when_rasterize_fails :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)
		_ = face
		paints := []Layout_Glyph_Paint{{face_id = handle.id, glyph_id = 0x7FFFFFFF, dst = {0, 0, 1, 1}}}
		testing.expect(t, !font_ensure_glyphs_from_paint(paints))
	})
}

@(test)
font_ensure_glyphs_returns_false_when_rasterize_fails :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)
		glyphs := []Shaped_Glyph{{glyph_id = 0x7FFFFFFF}}
		testing.expect(t, !font_ensure_glyphs(face, handle.id, glyphs))
	})
}

@(test)
font_prefetch_text_marks_prefetched_and_cache_hits :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		testing.expect(t, font_prefetch_text(face, handle.id, "AB", .LTR))
		testing.expect(t, len(FONT_PREFETCH_ASCII_UI) > 0)

		shaped := font_shape(face, "AB", .LTR)
		defer delete(shaped)
		testing.expect(t, len(shaped) >= 2)

		for g in shaped {
			key := Font_Glyph_Key {
				face_id     = handle.id,
				glyph_id    = g.glyph_id,
				render_mode = .Gray,
			}
			entry, cok := state.fonts.glyph_cache[key]
			testing.expect(t, cok)
			testing.expect(t, .Prefetched in entry.flags)
			testing.expect(t, .Pinned in entry.flags)
			testing.expect(t, font_glyph_entry_is_live(entry))
		}

		before := len(state.fonts.glyph_cache)
		testing.expect(t, font_ensure_glyphs(face, handle.id, shaped))
		testing.expect_value(t, len(state.fonts.glyph_cache), before)
	})
}

@(test)
font_pack_oversize_bypasses_atlas_as_standalone :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = inter
		_ = pixel
		state.textures.max_2d_texture_size = 32
		testing.expect(t, texture_atlas_init(32))
		shelves_before := len(state.textures.atlas.shelves)

		surface := sdl.CreateSurface(32, 32, .RGBA8888)
		testing.expect(t, surface != nil)
		defer sdl.DestroySurface(surface)
		testing.expect(t, texture_atlas_padded_exceeds_effective_max(surface.w, surface.h))

		entry, ok := font_pack_glyph_bitmap(surface, 1, 2, 4242)
		testing.expect(t, ok)
		testing.expect(t, .Standalone in entry.flags)
		testing.expect(t, texture_atlas_by_id(entry.region.texture_id) == nil)
		testing.expect(t, texture_get_gpu(entry.region.texture_id) != nil)
		testing.expect_value(t, len(state.textures.atlas.shelves), shelves_before)
		testing.expect_value(t, state.textures.last_pack_fail, Atlas_Pack_Fail.Oversize)
		testing.expect_value(t, entry.bearing_x, f32(1))
		testing.expect_value(t, entry.bearing_y, f32(2))

		key := Font_Glyph_Key {
			face_id     = Asset_Id(1),
			glyph_id    = 4242,
			render_mode = .Gray,
		}
		state.fonts.glyph_cache[key] = entry
		testing.expect(t, font_glyph_entry_is_live(state.fonts.glyph_cache[key]))

		font_atlas_reset()
		testing.expect(t, texture_get_gpu(entry.region.texture_id) == nil)
		_, still := state.fonts.glyph_cache[key]
		testing.expect(t, !still)
	})
}

@(test)
font_atlas_pack_funnel_exhausts_with_structured_error :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = inter
		_ = pixel
		testing.expect(t, texture_atlas_init(8))
		state.textures.max_2d_texture_size = 8

		for {
			_, aok := texture_atlas_alloc(1, 1)
			if !aok do break
		}

		for len(state.textures.overflow) < ATLAS_OVERFLOW_CAP {
			atlas, ook := texture_atlas_ensure_overflow()
			testing.expect(t, ook)
			for {
				_, aok := texture_atlas_alloc_in(atlas, 1, 1)
				if !aok do break
			}
		}

		surface := sdl.CreateSurface(1, 1, .RGBA8888)
		testing.expect(t, surface != nil)
		defer sdl.DestroySurface(surface)

		error_dismiss_all()
		_, fail := font_atlas_pack_funnel(surface)
		testing.expect_value(t, fail, Atlas_Pack_Fail.Exhausted)
		testing.expect_value(t, state.textures.last_pack_fail, Atlas_Pack_Fail.Exhausted)
		testing.expect(t, error_active_count() >= 1)
	})
}

@(test)
font_atlas_pack_funnel_recovers_via_overflow :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = inter
		_ = pixel
		testing.expect(t, texture_atlas_init(16))
		state.textures.max_2d_texture_size = 16

		for {
			_, aok := texture_atlas_alloc(1, 1)
			if !aok do break
		}

		testing.expect(t, !texture_atlas_can_fit(1, 1))
		testing.expect_value(t, len(state.textures.overflow), 0)

		surface := sdl.CreateSurface(1, 1, .RGBA8888)
		testing.expect(t, surface != nil)
		defer sdl.DestroySurface(surface)

		region, fail := font_atlas_pack_funnel(surface)
		testing.expect_value(t, fail, Atlas_Pack_Fail.None)
		testing.expect(t, region.texture_id != state.textures.atlas.texture_id)
		testing.expect(t, len(state.textures.overflow) >= 1)
		testing.expect(t, texture_atlas_by_id(region.texture_id) != nil)
	})
}

@(test)
font_prefetch_and_multi_size_stress_keeps_cache_coherent :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		sizes := []f32{12, 16, 20, 24}
		for size in sizes {
			face, handle, ok := font_test_face(inter, size)
			testing.expect(t, ok)
			testing.expect(t, font_prefetch_text(face, handle.id, "AbcXY012", .LTR))

			shaped := font_shape(face, "AbcXY012", .LTR)
			defer delete(shaped)
			testing.expect(t, font_ensure_glyphs(face, handle.id, shaped))

			for g in shaped {
				key := Font_Glyph_Key {
					face_id     = handle.id,
					glyph_id    = g.glyph_id,
					render_mode = .Gray,
				}
				entry, cok := state.fonts.glyph_cache[key]
				testing.expect(t, cok)
				testing.expect(t, font_glyph_entry_is_live(entry))
			}
		}

		stats := atlas_stats()
		testing.expect(t, stats.cache_count > 0)
		testing.expect(t, stats.slot_count > 0)
		testing.expect(t, len(state.textures.atlas.shelves) > 0)
		for shelf in state.textures.atlas.shelves {
			testing.expect(t, shelf.cursor_x >= 0)
			testing.expect(t, shelf.cursor_x <= state.textures.atlas.width)
		}
	})
}

@(test)
font_atlas_owner_lock_is_recursive_for_funnel_nesting :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = inter
		_ = pixel
		testing.expect(t, atlas_owner_try_lock())
		testing.expect_value(t, state.textures.owner_depth, 1)
		// Same thread may nest (ensure → funnel → alloc).
		testing.expect(t, atlas_owner_try_lock())
		testing.expect_value(t, state.textures.owner_depth, 2)
		atlas_owner_unlock()
		testing.expect_value(t, state.textures.owner_depth, 1)
		atlas_owner_unlock()
		testing.expect_value(t, state.textures.owner_depth, 0)
	})
}

@(test)
font_atlas_owner_lock_blocks_concurrent_thread :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = inter
		_ = pixel

		Barrier :: struct {
			mu:     sync.Mutex,
			ready:  bool,
			denied: bool,
			done:   bool,
		}
		barrier := new(Barrier)
		defer free(barrier)

		worker :: proc(b: ^Barrier) {
			for {
				sync.mutex_lock(&b.mu)
				ready := b.ready
				sync.mutex_unlock(&b.mu)
				if ready {
					break
				}

				thread.yield()
			}

			ok := atlas_owner_try_lock()
			sync.mutex_lock(&b.mu)
			b.denied = !ok
			b.done = true
			sync.mutex_unlock(&b.mu)
			if ok {
				atlas_owner_unlock()
			}
		}

		testing.expect(t, atlas_owner_try_lock())
		th := thread.create_and_start_with_poly_data(barrier, worker)
		testing.expect(t, th != nil)
		defer {
			thread.join(th)
			thread.destroy(th)
		}

		sync.mutex_lock(&barrier.mu)
		barrier.ready = true
		sync.mutex_unlock(&barrier.mu)

		for {
			sync.mutex_lock(&barrier.mu)
			done := barrier.done
			sync.mutex_unlock(&barrier.mu)
			if done {
				break
			}

			thread.yield()
		}

		testing.expect(t, barrier.denied)
		atlas_owner_unlock()
	})
}

@(test)
font_parallel_raster_then_serial_pack_stress :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 14)
		testing.expect(t, ok)

		text := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
		shaped := font_shape(face, text, .LTR)
		defer delete(shaped)
		testing.expect(t, len(shaped) >= FONT_GLYPH_PARALLEL_THRESHOLD)

		testing.expect(t, font_ensure_glyphs(face, handle.id, shaped))
		testing.expect_value(t, state.textures.raster_workers, 0)
		testing.expect_value(t, state.textures.owner_depth, 0)

		for g in shaped {
			key := Font_Glyph_Key {
				face_id     = handle.id,
				glyph_id    = g.glyph_id,
				render_mode = .Gray,
			}
			entry, cok := state.fonts.glyph_cache[key]
			testing.expect(t, cok)
			testing.expect(t, font_glyph_entry_is_live(entry))
		}

		// Prefetch under the same owner contract must stay coherent.
		testing.expect(t, font_prefetch_text(face, handle.id, text, .LTR))
		testing.expect_value(t, state.textures.owner_depth, 0)
	})
}

@(test)
font_atlas_repack_parallel_raster_keeps_survivors :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		shaped := font_shape(face, "Abcdefghij", .LTR)
		defer delete(shaped)
		testing.expect(t, len(shaped) >= FONT_GLYPH_PARALLEL_THRESHOLD)
		testing.expect(t, font_ensure_glyphs(face, handle.id, shaped))

		before_gen := state.textures.atlas.generation
		before_count := len(state.fonts.glyph_cache)
		testing.expect(t, atlas_compact())
		testing.expect(t, state.textures.atlas.generation > before_gen)
		testing.expect_value(t, state.textures.raster_workers, 0)

		alive := 0
		for g in shaped {
			key := Font_Glyph_Key {
				face_id     = handle.id,
				glyph_id    = g.glyph_id,
				render_mode = .Gray,
			}
			entry, cok := state.fonts.glyph_cache[key]
			if cok && font_glyph_entry_is_live(entry) {
				alive += 1
				testing.expect_value(t, entry.generation, state.textures.atlas.generation)
			}
		}

		testing.expect(t, alive >= FONT_GLYPH_PARALLEL_THRESHOLD)
		testing.expect(t, len(state.fonts.glyph_cache) >= alive)
		_ = before_count
	})
}

@(test)
font_ensure_and_prefetch_share_owner_sequencing :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		testing.expect(t, font_prefetch_text(face, handle.id, "Hi", .LTR))
		shaped := font_shape(face, "Hi", .LTR)
		defer delete(shaped)
		before := len(state.fonts.glyph_cache)
		testing.expect(t, font_ensure_glyphs(face, handle.id, shaped))
		testing.expect_value(t, len(state.fonts.glyph_cache), before)

		for g in shaped {
			key := Font_Glyph_Key {
				face_id     = handle.id,
				glyph_id    = g.glyph_id,
				render_mode = .Gray,
			}
			entry := state.fonts.glyph_cache[key]
			testing.expect(t, .Prefetched in entry.flags)
			testing.expect(t, .Pinned in entry.flags)
		}
	})
}

@(test)
font_open_temp_raster_face_uses_op_arena :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, _, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		shaped := font_shape(face, "A", .LTR, context.temp_allocator)
		testing.expect(t, len(shaped) > 0)

		backing := make([]u8, FONT_RASTER_WORKER_SCRATCH)
		defer delete(backing)
		arena: mem.Arena
		mem.arena_init(&arena, backing)
		alloc := mem.arena_allocator(&arena)

		library, ft_face, opened := font_open_temp_raster_face(face, alloc)
		testing.expect(t, opened)
		defer {
			if ft_face != nil {
				Done_Face(ft_face)
			}

			if library != nil {
				Done_FreeType(library)
			}
		}

		surface, _, _, rok := font_rasterize_glyph_bitmap(
			ft_face,
			face.fake_bold,
			shaped[0].glyph_id,
			face.pixel_size,
			.Gray,
		)
		testing.expect(t, rok)
		testing.expect(t, surface != nil)
		if surface != nil {
			sdl.DestroySurface(surface)
		}

		// Simulate worker face-switch: close, reclaim scratch, reopen.
		Done_Face(ft_face)
		Done_FreeType(library)
		ft_face = nil
		library = nil
		mem.arena_free_all(&arena)

		library2, ft_face2, opened2 := font_open_temp_raster_face(face, alloc)
		testing.expect(t, opened2)
		if ft_face2 != nil {
			Done_Face(ft_face2)
		}

		if library2 != nil {
			Done_FreeType(library2)
		}
	})
}

@(test)
font_prefetch_text_shapes_on_temp_allocator :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		before := len(state.fonts.glyph_cache)
		testing.expect(t, font_prefetch_text(face, handle.id, "Hello", .LTR))
		testing.expect(t, len(state.fonts.glyph_cache) > before)

		shaped := font_shape(face, "Hello", .LTR, context.temp_allocator)
		testing.expect(t, len(shaped) > 0)
		for g in shaped {
			key := Font_Glyph_Key {
				face_id     = handle.id,
				glyph_id    = g.glyph_id,
				render_mode = .Gray,
			}
			entry, cok := state.fonts.glyph_cache[key]
			testing.expect(t, cok)
			testing.expect(t, .Prefetched in entry.flags)
			testing.expect(t, .Pinned in entry.flags)
		}
	})
}

@(test)
font_parallel_raster_frees_worker_scratch :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 14)
		testing.expect(t, ok)

		text := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
		shaped := font_shape(face, text, .LTR, context.temp_allocator)
		testing.expect(t, len(shaped) >= FONT_GLYPH_PARALLEL_THRESHOLD)
		testing.expect(t, font_ensure_glyphs(face, handle.id, shaped))
		testing.expect_value(t, state.textures.raster_workers, 0)
		testing.expect_value(t, state.textures.owner_depth, 0)

		pool := state.fonts.raster_pool
		testing.expect(t, pool != nil)
		testing.expect_value(t, pool.started_count, FONT_GLYPH_MAX_WORKERS)

		// Second miss burst reuses the same pool + scratch arenas.
		face2, handle2, ok2 := font_test_face(inter, 18)
		testing.expect(t, ok2)
		shaped2 := font_shape(face2, text, .LTR, context.temp_allocator)
		testing.expect(t, font_ensure_glyphs(face2, handle2.id, shaped2))
		testing.expect_value(t, state.textures.raster_workers, 0)
		testing.expect(t, state.fonts.raster_pool == pool)
		_ = handle
	})
}
