package oni

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import sdl "vendor:sdl3"
import img "vendor:sdl3/image"

/*
Minimal 1x1 opaque red PNG (RGB). Used to exercise disk load paths.
*/
ASSETS_TEST_PNG_1X1_RED :: []u8 {
	0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
	0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
	0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, 0x78, 0xDA, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
	0x00, 0x03, 0x01, 0x01, 0x00, 0xF7, 0x03, 0x41, 0x43, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
	0x44, 0xAE, 0x42, 0x60, 0x82,
}

/*
Minimal 2x2 JPEG. SDL_LoadSurface rejects JPEG; img.Load succeeds — covers fallback.
*/
ASSETS_TEST_JPEG_2X2_RED :: []u8 {
	0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
	0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
	0x00, 0x02, 0x01, 0x01, 0x01, 0x01, 0x01, 0x02, 0x01, 0x01, 0x01, 0x02,
	0x02, 0x02, 0x02, 0x02, 0x04, 0x03, 0x02, 0x02, 0x02, 0x02, 0x05, 0x04,
	0x04, 0x03, 0x04, 0x06, 0x05, 0x06, 0x06, 0x06, 0x05, 0x06, 0x06, 0x06,
	0x07, 0x09, 0x08, 0x06, 0x07, 0x09, 0x07, 0x06, 0x06, 0x08, 0x0B, 0x08,
	0x09, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x06, 0x08, 0x0B, 0x0C, 0x0B, 0x0A,
	0x0C, 0x09, 0x0A, 0x0A, 0x0A, 0xFF, 0xDB, 0x00, 0x43, 0x01, 0x02, 0x02,
	0x02, 0x02, 0x02, 0x02, 0x05, 0x03, 0x03, 0x05, 0x0A, 0x07, 0x06, 0x07,
	0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A,
	0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A,
	0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A,
	0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A,
	0x0A, 0x0A, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x02, 0x00, 0x02, 0x03,
	0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01, 0xFF, 0xC4, 0x00,
	0x1F, 0x00, 0x00, 0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05,
	0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00,
	0x02, 0x01, 0x03, 0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00,
	0x00, 0x01, 0x7D, 0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21,
	0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81,
	0x91, 0xA1, 0x08, 0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24,
	0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25,
	0x26, 0x27, 0x28, 0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A,
	0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56,
	0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A,
	0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86,
	0x87, 0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99,
	0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3,
	0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6,
	0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9,
	0xDA, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF1,
	0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xC4, 0x00,
	0x1F, 0x01, 0x00, 0x03, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
	0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05,
	0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x11, 0x00,
	0x02, 0x01, 0x02, 0x04, 0x04, 0x03, 0x04, 0x07, 0x05, 0x04, 0x04, 0x00,
	0x01, 0x02, 0x77, 0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31,
	0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13, 0x22, 0x32, 0x81, 0x08,
	0x14, 0x42, 0x91, 0xA1, 0xB1, 0xC1, 0x09, 0x23, 0x33, 0x52, 0xF0, 0x15,
	0x62, 0x72, 0xD1, 0x0A, 0x16, 0x24, 0x34, 0xE1, 0x25, 0xF1, 0x17, 0x18,
	0x19, 0x1A, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x35, 0x36, 0x37, 0x38, 0x39,
	0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55,
	0x56, 0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
	0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x82, 0x83, 0x84,
	0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97,
	0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA,
	0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4,
	0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7,
	0xD8, 0xD9, 0xDA, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA,
	0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xDA, 0x00,
	0x0C, 0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3F, 0x00, 0xF8,
	0xBE, 0x8A, 0x28, 0xAF, 0xE5, 0x33, 0xFD, 0xFC, 0x3F, 0xFF, 0xD9,
}


@(private)
assets_test_fixture_dir :: proc() -> string {
	return "oni_assets_test_fixtures"
}

@(private)
assets_test_ensure_dir :: proc(t: ^testing.T) -> bool {
	dir := assets_test_fixture_dir()
	if os.exists(dir) do return true
	if err := os.make_directory(dir); err != nil {
		testing.expectf(t, false, "make_directory(%q) failed: %v", dir, err)
		return false
	}
	return true
}

@(private)
assets_test_write_bytes :: proc(t: ^testing.T, path: string, data: []u8) -> bool {
	if !assets_test_ensure_dir(t) do return false
	if err := os.write_entire_file(path, data); err != nil {
		testing.expectf(t, false, "write_entire_file(%q) failed: %v", path, err)
		return false
	}
	return true
}

/*
Writes a 24-bit uncompressed BMP (BGR, bottom-up) for SDL_LoadSurface coverage.
*/
@(private)
assets_test_write_bmp :: proc(t: ^testing.T, path: string, w, h: i32, bgr: [3]u8) -> bool {
	if w <= 0 || h <= 0 {
		testing.expect(t, false, "bmp dimensions must be positive")
		return false
	}
	row_stride := ((int(w) * 3) + 3) / 4 * 4
	pixel_bytes := row_stride * int(h)
	file_size := 14 + 40 + pixel_bytes
	buf, buf_err := make([]u8, file_size)
	testing.expect(t, buf_err == nil)
	if buf_err != nil do return false
	defer delete(buf)

	// BITMAPFILEHEADER
	buf[0] = 'B'
	buf[1] = 'M'
	buf[2] = u8(file_size)
	buf[3] = u8(file_size >> 8)
	buf[4] = u8(file_size >> 16)
	buf[5] = u8(file_size >> 24)
	buf[10] = 54 // pixel offset

	// BITMAPINFOHEADER
	buf[14] = 40
	buf[18] = u8(w)
	buf[19] = u8(w >> 8)
	buf[20] = u8(w >> 16)
	buf[21] = u8(w >> 24)
	buf[22] = u8(h)
	buf[23] = u8(h >> 8)
	buf[24] = u8(h >> 16)
	buf[25] = u8(h >> 24)
	buf[26] = 1 // planes
	buf[28] = 24 // bpp

	pixels := buf[54:]
	for row in 0 ..< int(h) {
		row_off := row * row_stride
		for col in 0 ..< int(w) {
			off := row_off + col * 3
			pixels[off + 0] = bgr[0]
			pixels[off + 1] = bgr[1]
			pixels[off + 2] = bgr[2]
		}
	}
	return assets_test_write_bytes(t, path, buf)
}

@(private)
assets_test_cleanup_fixtures :: proc() {
	_ = os.remove_all(assets_test_fixture_dir())
}

@(private)
with_assets_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	if !sdl.Init({.VIDEO}) {
		testing.expectf(t, false, "SDL_Init failed: %s", sdl.GetError())
		return
	}
	defer sdl.Quit()

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
	assets_init(nil)
	defer assets_shutdown()

	body(t)
}

@(private)
with_assets_gpu_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	if !sdl.Init({.VIDEO}) {
		testing.expectf(t, false, "SDL_Init failed: %s", sdl.GetError())
		return
	}
	defer sdl.Quit()

	gpu := sdl.CreateGPUDevice({.SPIRV}, true, nil)
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
	state.gpu = gpu
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

	assets_init(gpu)
	defer assets_shutdown()

	body(t)
}

// ---------------------------------------------------------------------------
// Lifecycle: init / shutdown / reload
// ---------------------------------------------------------------------------

@(test)
assets_init_creates_cache_and_reserves_white_texture_slot :: proc(t: ^testing.T) {
	with_assets_env(
		t,
		proc(t: ^testing.T) {
			// Empty maps compare equal to nil in this Odin version; prove the cache is
			// usable and texture_init ran via assets_init.
			testing.expect_value(t, len(state.assets.paths), 0)
			state.assets.paths[strings.clone("probe")] = Asset_Id(1)
			testing.expect(t, state.assets.paths != nil)
			testing.expect_value(t, len(state.assets.paths), 1)
			testing.expect_value(t, len(state.textures.records), 1)
			testing.expect_value(t, state.textures.atlas.texture_id, INVALID_ASSET_ID)
		},
	)
}

@(test)
assets_init_is_idempotent_and_preserves_existing_cache_entries :: proc(t: ^testing.T) {
	with_assets_env(
		t,
		proc(t: ^testing.T) {
			key := strings.clone("kept.png")
			state.assets.paths[key] = Asset_Id(42)

			assets_init(nil)
			testing.expect(t, state.assets.paths != nil)
			testing.expect_value(t, len(state.assets.paths), 1)
			got, ok := state.assets.paths["kept.png"]
			testing.expect(t, ok)
			testing.expect_value(t, got, Asset_Id(42))
			testing.expect_value(t, len(state.textures.records), 1)
		},
	)
}

@(test)
assets_shutdown_frees_cloned_paths_and_texture_state :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	if !sdl.Init({.VIDEO}) {
		testing.expectf(t, false, "SDL_Init failed: %s", sdl.GetError())
		return
	}
	defer sdl.Quit()

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
	assets_init(nil)

	state.assets.paths[strings.clone("a.png")] = Asset_Id(1)
	state.assets.paths[strings.clone("b.png")] = Asset_Id(2)
	surface := texture_test_make_surface(2, 2)
	testing.expect(t, surface != nil)
	append(
		&state.textures.records,
		Texture_Record{surface = surface, w = 2, h = 2, path = strings.clone("a.png")},
	)

	assets_shutdown()
	testing.expect(t, state.assets.paths == nil)
	testing.expect(t, state.textures.records == nil)
}

@(test)
assets_shutdown_then_reinit_restores_empty_cache :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	if !sdl.Init({.VIDEO}) {
		testing.expectf(t, false, "SDL_Init failed: %s", sdl.GetError())
		return
	}
	defer sdl.Quit()

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
	assets_init(nil)
	state.assets.paths[strings.clone("gone.png")] = Asset_Id(7)
	assets_shutdown()
	testing.expect(t, state.assets.paths == nil)

	assets_init(nil)
	defer assets_shutdown()
	testing.expect_value(t, len(state.assets.paths), 0)
	testing.expect_value(t, len(state.textures.records), 1)
	state.assets.paths[strings.clone("fresh")] = Asset_Id(3)
	testing.expect(t, state.assets.paths != nil)
}

@(test)
assets_reload_gpu_without_gpu_is_safe_noop :: proc(t: ^testing.T) {
	with_assets_env(
		t,
		proc(t: ^testing.T) {
			surface := texture_test_make_surface(2, 2)
			testing.expect(t, surface != nil)
			append(&state.textures.records, Texture_Record{surface = surface, w = 2, h = 2})

			assets_reload_gpu(nil)
			testing.expect(t, state.textures.records[1].gpu == nil)
			testing.expect(t, state.textures.records[1].surface != nil)
		},
	)
}

// ---------------------------------------------------------------------------
// assets_load_surface
// ---------------------------------------------------------------------------

@(test)
assets_load_surface_loads_bmp_and_png_fixtures :: proc(t: ^testing.T) {
	with_assets_env(
		t,
		proc(t: ^testing.T) {
			defer assets_test_cleanup_fixtures()

			bmp_path := fmt.tprintf("%s/red.bmp", assets_test_fixture_dir())
			png_path := fmt.tprintf("%s/red.png", assets_test_fixture_dir())
			testing.expect(t, assets_test_write_bmp(t, bmp_path, 3, 2, {0, 0, 255}))
			testing.expect(t, assets_test_write_bytes(t, png_path, ASSETS_TEST_PNG_1X1_RED))

			bmp, bmp_ok := assets_load_surface(bmp_path)
			testing.expect(t, bmp_ok)
			testing.expect(t, bmp != nil)
			testing.expect(t, bmp.w == 3)
			testing.expect(t, bmp.h == 2)
			sdl.DestroySurface(bmp)

			png, png_ok := assets_load_surface(png_path)
			testing.expect(t, png_ok)
			testing.expect(t, png != nil)
			testing.expect(t, png.w == 1)
			testing.expect(t, png.h == 1)
			sdl.DestroySurface(png)
		},
	)
}

@(test)
assets_load_surface_falls_back_to_img_load_for_jpeg :: proc(t: ^testing.T) {
	with_assets_env(
		t,
		proc(t: ^testing.T) {
			defer assets_test_cleanup_fixtures()

			path := fmt.tprintf("%s/fallback.jpg", assets_test_fixture_dir())
			testing.expect(t, assets_test_write_bytes(t, path, ASSETS_TEST_JPEG_2X2_RED))

			cpath := strings.clone_to_cstring(path, context.temp_allocator)
			sdl.ClearError()
			direct := sdl.LoadSurface(cpath)
			testing.expect(t, direct == nil) // forces assets_load_surface into img.Load
			img_surface := img.Load(cpath)
			testing.expect(t, img_surface != nil)
			if img_surface != nil do sdl.DestroySurface(img_surface)

			surface, ok := assets_load_surface(path)
			testing.expect(t, ok)
			testing.expect(t, surface != nil)
			testing.expect_value(t, surface.w, i32(2))
			testing.expect_value(t, surface.h, i32(2))
			sdl.DestroySurface(surface)
		},
	)
}

@(test)
assets_load_surface_fails_for_missing_empty_and_garbage_paths :: proc(t: ^testing.T) {
	with_assets_env(
		t,
		proc(t: ^testing.T) {
			defer assets_test_cleanup_fixtures()

			// Expected failures log ERROR; capture so the suite stays quiet.
			out := with_captured_stderr(
				t,
				proc(t: ^testing.T) {
					_, ok := assets_load_surface("oni_assets_test_fixtures/does-not-exist-xyz.png")
					testing.expect(t, !ok)

					_, ok = assets_load_surface("")
					testing.expect(t, !ok)

					garbage := fmt.tprintf("%s/not-an-image.bin", assets_test_fixture_dir())
					testing.expect(t, assets_test_write_bytes(t, garbage, {0x00, 0x01, 0x02, 0xFF}))
					_, ok = assets_load_surface(garbage)
					testing.expect(t, !ok)
				},
			)
			defer delete(out)
		},
	)
}

@(private)
assets_test_logged_missing_path: string

@(test)
assets_load_surface_failure_logs_path_and_sdl_error :: proc(t: ^testing.T) {
	with_assets_env(
		t,
		proc(t: ^testing.T) {
			assets_test_logged_missing_path = "oni_assets_test_fixtures/logged-missing.png"
			out := with_captured_stderr(
				t,
				proc(t: ^testing.T) {
					_, ok := assets_load_surface(assets_test_logged_missing_path)
					testing.expect(t, !ok)
				},
			)
			defer delete(out)
			testing.expect(t, strings.contains(out, "Failed to load image"))
			testing.expect(t, strings.contains(out, assets_test_logged_missing_path))
		},
	)
}

// ---------------------------------------------------------------------------
// assets_get_texture
// ---------------------------------------------------------------------------

@(test)
assets_get_texture_delegates_white_invalid_and_registered :: proc(t: ^testing.T) {
	with_assets_env(
		t,
		proc(t: ^testing.T) {
			sentinel: sdl.GPUTexture
			state.gpu_state.white_texture = &sentinel

			white := assets_get_texture(TEXTURE_WHITE_ID)
			testing.expect_value(t, white.id, TEXTURE_WHITE_ID)
			expect_close(t, white.w, 1)
			expect_close(t, white.h, 1)

			missing := assets_get_texture(Asset_Id(99))
			testing.expect_value(t, missing.id, Asset_Id(0))
			expect_close(t, missing.w, 0)
			expect_close(t, missing.h, 0)

			invalid := assets_get_texture(INVALID_ASSET_ID)
			testing.expect_value(t, invalid.id, Asset_Id(0))
			expect_close(t, invalid.w, 0)
			expect_close(t, invalid.h, 0)

			negative := assets_get_texture(Asset_Id(-5))
			testing.expect_value(t, negative.id, Asset_Id(0))

			append(&state.textures.records, Texture_Record{w = 16, h = 24})
			handle := assets_get_texture(Asset_Id(1))
			testing.expect_value(t, handle.id, Asset_Id(1))
			expect_close(t, handle.w, 16)
			expect_close(t, handle.h, 24)

			state.gpu_state.white_texture = nil
		},
	)
}

// ---------------------------------------------------------------------------
// assets_load_texture — failure / cache / ownership (CPU)
// ---------------------------------------------------------------------------

@(test)
assets_load_texture_fails_for_missing_file_without_caching :: proc(t: ^testing.T) {
	with_assets_env(
		t,
		proc(t: ^testing.T) {
			before_records := len(state.textures.records)
			out := with_captured_stderr(
				t,
				proc(t: ^testing.T) {
					handle, ok := assets_load_texture("oni_assets_test_fixtures/missing-nope.png")
					testing.expect(t, !ok)
					testing.expect_value(t, handle.id, Asset_Id(0))
				},
			)
			defer delete(out)
			testing.expect_value(t, len(state.assets.paths), 0)
			testing.expect_value(t, len(state.textures.records), before_records)
		},
	)
}

@(test)
assets_load_texture_register_failure_destroys_surface_and_does_not_cache :: proc(t: ^testing.T) {
	with_assets_env(
		t,
		proc(t: ^testing.T) {
			defer assets_test_cleanup_fixtures()

			path := fmt.tprintf("%s/orphan.bmp", assets_test_fixture_dir())
			testing.expect(t, assets_test_write_bmp(t, path, 2, 2, {10, 20, 30}))

			before_records := len(state.textures.records)
			// No GPU device → texture_register_surface fails and assets destroys the surface.
			handle, ok := assets_load_texture(path)
			testing.expect(t, !ok)
			testing.expect_value(t, handle.id, Asset_Id(0))
			testing.expect_value(t, len(state.assets.paths), 0)
			testing.expect_value(t, len(state.textures.records), before_records)
		},
	)
}

@(test)
assets_load_texture_cache_hit_returns_prior_handle_without_reload :: proc(t: ^testing.T) {
	with_assets_env(
		t,
		proc(t: ^testing.T) {
			append(&state.textures.records, Texture_Record{w = 8, h = 4})
			id := Asset_Id(1)
			state.assets.paths[strings.clone("cached/tex.png")] = id

			handle, ok := assets_load_texture("cached/tex.png")
			testing.expect(t, ok)
			testing.expect_value(t, handle.id, id)
			expect_close(t, handle.w, 8)
			expect_close(t, handle.h, 4)
			testing.expect_value(t, len(state.assets.paths), 1)
			testing.expect_value(t, len(state.textures.records), 2)
		},
	)
}

@(test)
assets_load_texture_cache_key_is_owned_clone_independent_of_caller :: proc(t: ^testing.T) {
	with_assets_env(
		t,
		proc(t: ^testing.T) {
			append(&state.textures.records, Texture_Record{w = 5, h = 5})
			path := strings.clone("owned/key.png")
			state.assets.paths[strings.clone(path)] = Asset_Id(1)

			// Corrupt caller's buffer; cached key must remain usable.
			raw := raw_data(path)
			for i in 0 ..< len(path) {
				raw[i] = 'x'
			}
			delete(path)

			handle, ok := assets_load_texture("owned/key.png")
			testing.expect(t, ok)
			testing.expect_value(t, handle.id, Asset_Id(1))
			expect_close(t, handle.w, 5)
			expect_close(t, handle.h, 5)
		},
	)
}

// ---------------------------------------------------------------------------
// GPU integration
// ---------------------------------------------------------------------------

@(test)
assets_gpu_load_texture_caches_and_returns_stable_handle :: proc(t: ^testing.T) {
	with_assets_gpu_env(
		t,
		proc(t: ^testing.T) {
			defer assets_test_cleanup_fixtures()

			path := fmt.tprintf("%s/gpu-red.bmp", assets_test_fixture_dir())
			testing.expect(t, assets_test_write_bmp(t, path, 4, 6, {0, 0, 255}))

			handle1, ok1 := assets_load_texture(path)
			testing.expect(t, ok1)
			testing.expect(t, handle1.id > TEXTURE_WHITE_ID)
			expect_close(t, handle1.w, 4)
			expect_close(t, handle1.h, 6)
			testing.expect_value(t, len(state.assets.paths), 1)
			testing.expect(t, texture_get_gpu(handle1.id) != nil)

			id, cached := state.assets.paths[path]
			testing.expect(t, cached)
			testing.expect_value(t, id, handle1.id)
			testing.expect_value(t, state.textures.records[int(id)].path, path)

			handle2, ok2 := assets_load_texture(path)
			testing.expect(t, ok2)
			testing.expect_value(t, handle2.id, handle1.id)
			expect_close(t, handle2.w, handle1.w)
			expect_close(t, handle2.h, handle1.h)
			testing.expect_value(t, len(state.assets.paths), 1)
			testing.expect_value(t, len(state.textures.records), int(handle1.id) + 1)

			via_get := assets_get_texture(handle1.id)
			testing.expect_value(t, via_get.id, handle1.id)
			expect_close(t, via_get.w, 4)
			expect_close(t, via_get.h, 6)
		},
	)
}

@(test)
assets_gpu_load_distinct_paths_get_distinct_ids :: proc(t: ^testing.T) {
	with_assets_gpu_env(
		t,
		proc(t: ^testing.T) {
			defer assets_test_cleanup_fixtures()

			a := fmt.tprintf("%s/a.bmp", assets_test_fixture_dir())
			b := fmt.tprintf("%s/b.bmp", assets_test_fixture_dir())
			testing.expect(t, assets_test_write_bmp(t, a, 2, 2, {1, 2, 3}))
			testing.expect(t, assets_test_write_bmp(t, b, 3, 3, {4, 5, 6}))

			ha, oka := assets_load_texture(a)
			hb, okb := assets_load_texture(b)
			testing.expect(t, oka && okb)
			testing.expect(t, ha.id != hb.id)
			testing.expect_value(t, len(state.assets.paths), 2)
			expect_close(t, ha.w, 2)
			expect_close(t, hb.w, 3)
		},
	)
}

@(test)
assets_gpu_load_png_fixture_and_empty_path_string_content_lookup :: proc(t: ^testing.T) {
	with_assets_gpu_env(
		t,
		proc(t: ^testing.T) {
			defer assets_test_cleanup_fixtures()

			path := fmt.tprintf("%s/gpu-red.png", assets_test_fixture_dir())
			testing.expect(t, assets_test_write_bytes(t, path, ASSETS_TEST_PNG_1X1_RED))

			handle, ok := assets_load_texture(path)
			testing.expect(t, ok)
			testing.expect(t, handle.id > TEXTURE_WHITE_ID)
			expect_close(t, handle.w, 1)
			expect_close(t, handle.h, 1)

			// Same bytes, different string allocation — map lookup is by content.
			path_copy := strings.clone(path)
			defer delete(path_copy)
			again, ok2 := assets_load_texture(path_copy)
			testing.expect(t, ok2)
			testing.expect_value(t, again.id, handle.id)
			testing.expect_value(t, len(state.assets.paths), 1)
		},
	)
}

@(test)
assets_gpu_reload_keeps_cache_and_restores_gpu_textures :: proc(t: ^testing.T) {
	with_assets_gpu_env(
		t,
		proc(t: ^testing.T) {
			defer assets_test_cleanup_fixtures()

			path := fmt.tprintf("%s/reload.bmp", assets_test_fixture_dir())
			testing.expect(t, assets_test_write_bmp(t, path, 5, 5, {9, 8, 7}))

			handle, ok := assets_load_texture(path)
			testing.expect(t, ok)
			id := handle.id
			testing.expect(t, texture_get_gpu(id) != nil)

			assets_reload_gpu(state.gpu)
			testing.expect(t, texture_get_gpu(id) != nil)

			cached, found := state.assets.paths[path]
			testing.expect(t, found)
			testing.expect_value(t, cached, id)

			again, ok2 := assets_load_texture(path)
			testing.expect(t, ok2)
			testing.expect_value(t, again.id, id)
			expect_close(t, again.w, 5)
			expect_close(t, again.h, 5)
		},
	)
}

@(test)
assets_gpu_failed_load_does_not_poison_later_success :: proc(t: ^testing.T) {
	with_assets_gpu_env(
		t,
		proc(t: ^testing.T) {
			defer assets_test_cleanup_fixtures()

			out := with_captured_stderr(
				t,
				proc(t: ^testing.T) {
					_, bad := assets_load_texture("oni_assets_test_fixtures/nope-again.png")
					testing.expect(t, !bad)
				},
			)
			defer delete(out)
			testing.expect_value(t, len(state.assets.paths), 0)

			path := fmt.tprintf("%s/after-fail.bmp", assets_test_fixture_dir())
			testing.expect(t, assets_test_write_bmp(t, path, 2, 2, {11, 22, 33}))
			handle, ok := assets_load_texture(path)
			testing.expect(t, ok)
			testing.expect(t, handle.id > TEXTURE_WHITE_ID)
			testing.expect_value(t, len(state.assets.paths), 1)
		},
	)
}

@(test)
assets_load_texture_fails_for_empty_path_without_caching :: proc(t: ^testing.T) {
	with_assets_env(
		t,
		proc(t: ^testing.T) {
			before := len(state.textures.records)
			out := with_captured_stderr(
				t,
				proc(t: ^testing.T) {
					handle, ok := assets_load_texture("")
					testing.expect(t, !ok)
					testing.expect_value(t, handle.id, Asset_Id(0))
				},
			)
			defer delete(out)
			testing.expect_value(t, len(state.assets.paths), 0)
			testing.expect_value(t, len(state.textures.records), before)
		},
	)
}

@(test)
assets_gpu_load_unicode_path_roundtrip :: proc(t: ^testing.T) {
	with_assets_gpu_env(
		t,
		proc(t: ^testing.T) {
			defer assets_test_cleanup_fixtures()

			path := fmt.tprintf("%s/テクスチャ.bmp", assets_test_fixture_dir())
			testing.expect(t, assets_test_write_bmp(t, path, 2, 2, {40, 50, 60}))

			handle, ok := assets_load_texture(path)
			testing.expect(t, ok)
			testing.expect(t, handle.id > TEXTURE_WHITE_ID)

			again, ok2 := assets_load_texture(path)
			testing.expect(t, ok2)
			testing.expect_value(t, again.id, handle.id)
			id, found := state.assets.paths[path]
			testing.expect(t, found)
			testing.expect_value(t, id, handle.id)
		},
	)
}

@(test)
assets_init_accepts_gpu_pointer_reserved_for_future_use :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	if !sdl.Init({.VIDEO}) {
		testing.expectf(t, false, "SDL_Init failed: %s", sdl.GetError())
		return
	}
	defer sdl.Quit()

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
	sentinel: sdl.GPUDevice
	assets_init(&sentinel)
	defer assets_shutdown()
	testing.expect_value(t, len(state.textures.records), 1)
	testing.expect_value(t, state.textures.atlas.texture_id, INVALID_ASSET_ID)
	// gpu arg is currently unused; cache must still be usable.
	state.assets.paths[strings.clone("via-gpu-arg")] = Asset_Id(9)
	got, ok := state.assets.paths["via-gpu-arg"]
	testing.expect(t, ok)
	testing.expect_value(t, got, Asset_Id(9))
}

@(test)
assets_shutdown_on_empty_cache_is_safe :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	if !sdl.Init({.VIDEO}) {
		testing.expectf(t, false, "SDL_Init failed: %s", sdl.GetError())
		return
	}
	defer sdl.Quit()

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
	assets_init(nil)
	testing.expect_value(t, len(state.assets.paths), 0)
	assets_shutdown()
	testing.expect(t, state.assets.paths == nil)
	testing.expect(t, state.textures.records == nil)
}

@(test)
assets_gpu_cache_hit_survives_deleted_source_file :: proc(t: ^testing.T) {
	with_assets_gpu_env(
		t,
		proc(t: ^testing.T) {
			defer assets_test_cleanup_fixtures()

			path := fmt.tprintf("%s/ephemeral.bmp", assets_test_fixture_dir())
			testing.expect(t, assets_test_write_bmp(t, path, 3, 3, {7, 8, 9}))

			first, ok1 := assets_load_texture(path)
			testing.expect(t, ok1)
			testing.expect(t, first.id > TEXTURE_WHITE_ID)

			testing.expect(t, os.remove(path) == nil)
			testing.expect(t, !os.exists(path))

			second, ok2 := assets_load_texture(path)
			testing.expect(t, ok2)
			testing.expect_value(t, second.id, first.id)
			expect_close(t, second.w, 3)
			expect_close(t, second.h, 3)
			testing.expect_value(t, len(state.assets.paths), 1)
		},
	)
}

@(test)
assets_gpu_load_path_with_spaces_and_reload_twice :: proc(t: ^testing.T) {
	with_assets_gpu_env(
		t,
		proc(t: ^testing.T) {
			defer assets_test_cleanup_fixtures()

			path := fmt.tprintf("%s/my texture file.bmp", assets_test_fixture_dir())
			testing.expect(t, assets_test_write_bmp(t, path, 2, 4, {1, 2, 3}))

			handle, ok := assets_load_texture(path)
			testing.expect(t, ok)
			id := handle.id

			assets_reload_gpu(state.gpu)
			assets_reload_gpu(nil) // gpu arg ignored; still uses state.gpu
			testing.expect(t, texture_get_gpu(id) != nil)

			again, ok2 := assets_load_texture(path)
			testing.expect(t, ok2)
			testing.expect_value(t, again.id, id)
			expect_close(t, again.h, 4)
		},
	)
}

@(test)
assets_gpu_load_jpeg_via_img_fallback_registers_texture :: proc(t: ^testing.T) {
	with_assets_gpu_env(
		t,
		proc(t: ^testing.T) {
			defer assets_test_cleanup_fixtures()

			path := fmt.tprintf("%s/gpu-fallback.jpg", assets_test_fixture_dir())
			testing.expect(t, assets_test_write_bytes(t, path, ASSETS_TEST_JPEG_2X2_RED))

			handle, ok := assets_load_texture(path)
			testing.expect(t, ok)
			testing.expect(t, handle.id > TEXTURE_WHITE_ID)
			expect_close(t, handle.w, 2)
			expect_close(t, handle.h, 2)
			testing.expect(t, texture_get_gpu(handle.id) != nil)
		},
	)
}

@(test)
assets_distinct_path_strings_are_distinct_cache_keys :: proc(t: ^testing.T) {
	with_assets_gpu_env(
		t,
		proc(t: ^testing.T) {
			defer assets_test_cleanup_fixtures()

			dir := assets_test_fixture_dir()
			testing.expect(t, assets_test_ensure_dir(t))
			a := fmt.tprintf("%s/same.bmp", dir)
			testing.expect(t, assets_test_write_bmp(t, a, 2, 2, {9, 9, 9}))

			// Cache keys are literal path strings, not canonicalized filesystem paths.
			dot_a := fmt.tprintf("./%s/same.bmp", dir)
			ha, oka := assets_load_texture(a)
			hb, okb := assets_load_texture(dot_a)
			testing.expect(t, oka && okb)
			testing.expect(t, ha.id != hb.id)
			testing.expect_value(t, len(state.assets.paths), 2)
		},
	)
}
