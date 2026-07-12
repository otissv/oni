package oni

import "core:strings"
import "core:sync"
import "core:testing"
import sdl "vendor:sdl3"

TEXTURE_TEST_ATLAS_SIZE :: i32(64)

@(private)
with_texture_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
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
		theme = saved_theme
	}

	state = &test_state
	theme = nil
	texture_init()
	defer texture_shutdown()

	body(t)
}

@(private)
with_texture_gpu_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
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
		theme = saved_theme
	}

	state = &test_state
	theme = nil
	state.gpu = gpu
	// gpu_create_white_texture uploads via state.gpu — must set state first.
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

	body(t)
}

@(private)
texture_test_make_surface :: proc(w, h: i32, fill: [4]u8 = {10, 20, 30, 255}) -> ^sdl.Surface {
	surface := sdl.CreateSurface(w, h, .RGBA8888)
	if surface == nil do return nil

	converted := sdl.ConvertSurface(surface, .RGBA8888)
	if converted == nil {
		sdl.DestroySurface(surface)
		return nil
	}
	if converted != surface {
		sdl.DestroySurface(surface)
		surface = converted
	}

	px := cast([^]u8)surface.pixels
	for row in 0 ..< h {
		row_off := row * surface.pitch
		for col in 0 ..< w {
			off := int(row_off) + int(col) * 4
			px[off + 0] = fill[0]
			px[off + 1] = fill[1]
			px[off + 2] = fill[2]
			px[off + 3] = fill[3]
		}
	}
	return surface
}

@(private)
texture_test_make_surface_format :: proc(
	w, h: i32,
	format: sdl.PixelFormat,
	r: u8 = 40,
	g: u8 = 80,
	b: u8 = 120,
	a: u8 = 255,
) -> ^sdl.Surface {
	surface := sdl.CreateSurface(w, h, format)
	if surface == nil do return nil
	// INDEX8 and similar paletted formats may not support Map/Fill; leave blank.
	if format == .INDEX8 do return surface
	color := sdl.MapSurfaceRGBA(surface, r, g, b, a)
	if !sdl.FillSurfaceRect(surface, nil, color) {
		sdl.DestroySurface(surface)
		return nil
	}
	return surface
}

@(private)
texture_test_seed_atlas :: proc(width: i32 = TEXTURE_TEST_ATLAS_SIZE, height: i32 = TEXTURE_TEST_ATLAS_SIZE) -> Asset_Id {
	surface := texture_test_make_surface(width, height, {0, 0, 0, 0})
	append(
		&state.textures.records,
		Texture_Record{surface = surface, w = width, h = height, gpu = nil},
	)
	id := Asset_Id(len(state.textures.records) - 1)
	state.textures.atlas = Atlas_State {
		texture_id = id,
		width      = width,
		height     = height,
	}
	return id
}

@(private)
expect_atlas_region :: proc(
	t: ^testing.T,
	got: Atlas_Region,
	texture_id: Asset_Id,
	x, y, w, h: f32,
	loc := #caller_location,
) {
	testing.expect_value(t, got.texture_id, texture_id, loc = loc)
	expect_close(t, got.x, x, loc = loc)
	expect_close(t, got.y, y, loc = loc)
	expect_close(t, got.w, w, loc = loc)
	expect_close(t, got.h, h, loc = loc)
}

@(private)
atlas_surface_pixel :: proc(surface: ^sdl.Surface, x, y: i32) -> [4]u8 {
	px := cast([^]u8)surface.pixels
	off := int(y * surface.pitch + x * 4)
	return {px[off + 0], px[off + 1], px[off + 2], px[off + 3]}
}

@(private)
fmt_path :: proc(i: int) -> string {
	switch i {
	case 0:
		return "multi/0.png"
	case 1:
		return "multi/1.png"
	case:
		return "multi/2.png"
	}
}

// ---------------------------------------------------------------------------
// Lifecycle: init / shutdown
// ---------------------------------------------------------------------------

@(test)
texture_init_reserves_slot_zero_and_is_idempotent :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			testing.expect_value(t, len(state.textures.records), 1)
			testing.expect(t, state.textures.records[0].gpu == nil)
			testing.expect(t, state.textures.records[0].surface == nil)
			testing.expect_value(t, state.textures.atlas.texture_id, INVALID_ASSET_ID)

			texture_init()
			testing.expect_value(t, len(state.textures.records), 1)
		},
	)
}

@(test)
texture_init_promotes_zeroed_white_atlas_to_invalid :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	test_state: State
	saved_state := state
	saved_theme := theme
	defer {
		state = saved_state
		theme = saved_theme
	}

	state = &test_state
	theme = nil
	// Zeroed Atlas_State has texture_id == TEXTURE_WHITE_ID (0) and width 0.
	testing.expect_value(t, state.textures.atlas.texture_id, TEXTURE_WHITE_ID)
	testing.expect_value(t, state.textures.atlas.width, i32(0))

	texture_init()
	defer texture_shutdown()

	testing.expect_value(t, state.textures.atlas.texture_id, INVALID_ASSET_ID)
}

@(test)
texture_init_preserves_valid_atlas_and_nonempty_white_width :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			state.textures.atlas = {
				texture_id = Asset_Id(7),
				width      = 128,
				height     = 128,
			}
			texture_init()
			testing.expect_value(t, state.textures.atlas.texture_id, Asset_Id(7))
			testing.expect_value(t, state.textures.atlas.width, i32(128))

			state.textures.atlas = {
				texture_id = TEXTURE_WHITE_ID,
				width      = 1,
				height     = 1,
			}
			texture_init()
			testing.expect_value(t, state.textures.atlas.texture_id, TEXTURE_WHITE_ID)
			testing.expect_value(t, state.textures.atlas.width, i32(1))
		},
	)
}

@(test)
texture_shutdown_frees_paths_surfaces_and_records :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	test_state: State
	saved_state := state
	saved_theme := theme
	defer {
		state = saved_state
		theme = saved_theme
	}

	state = &test_state
	theme = nil
	texture_init()

	surface := texture_test_make_surface(2, 2)
	testing.expect(t, surface != nil)
	append(
		&state.textures.records,
		Texture_Record {
			surface = surface,
			w = 2,
			h = 2,
			path = strings.clone("fixtures/tex.png"),
		},
	)
	append(&state.textures.atlas.shelves, Atlas_Shelf{y = 0, height = 8, cursor_x = 4})

	texture_shutdown()
	testing.expect(t, state.textures.records == nil)
	testing.expect_value(t, len(state.textures.atlas.shelves), 0)
	testing.expect_value(t, state.textures.atlas.texture_id, Asset_Id(0))
}

@(test)
texture_release_and_reload_are_noops_without_gpu :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			surface := texture_test_make_surface(2, 2)
			testing.expect(t, surface != nil)
			append(
				&state.textures.records,
				Texture_Record{surface = surface, w = 2, h = 2},
			)

			texture_release_gpu()
			testing.expect(t, state.textures.records[1].gpu == nil)
			testing.expect(t, state.textures.records[1].surface != nil)

			texture_reload_gpu()
			testing.expect(t, state.textures.records[1].gpu == nil)
		},
	)
}

// ---------------------------------------------------------------------------
// surface_row_to_gpu_rgba
// ---------------------------------------------------------------------------

@(test)
texture_surface_row_to_gpu_rgba_swizzles_little_endian :: proc(t: ^testing.T) {
	// SDL RGBA8888 little-endian memory order is A,B,G,R per the upload path comment.
	src := []u8{0xA1, 0xB2, 0xC3, 0xD4, 0x11, 0x22, 0x33, 0x44}
	dst := make([]u8, 8)
	defer delete(dst)

	surface_row_to_gpu_rgba(dst, src, 2)

	when ODIN_ENDIAN == .Little {
		testing.expect_value(t, dst[0], u8(0xD4))
		testing.expect_value(t, dst[1], u8(0xC3))
		testing.expect_value(t, dst[2], u8(0xB2))
		testing.expect_value(t, dst[3], u8(0xA1))
		testing.expect_value(t, dst[4], u8(0x44))
		testing.expect_value(t, dst[5], u8(0x33))
		testing.expect_value(t, dst[6], u8(0x22))
		testing.expect_value(t, dst[7], u8(0x11))
	} else {
		for i in 0 ..< len(dst) {
			testing.expect_value(t, dst[i], src[i])
		}
	}
}

@(test)
texture_surface_row_to_gpu_rgba_handles_zero_and_single_pixel :: proc(t: ^testing.T) {
	dst := make([]u8, 4)
	defer delete(dst)
	src := []u8{1, 2, 3, 4}

	surface_row_to_gpu_rgba(dst[:0], src[:0], 0)
	testing.expect_value(t, dst[0], u8(0))

	surface_row_to_gpu_rgba(dst, src, 1)
	when ODIN_ENDIAN == .Little {
		testing.expect_value(t, dst[0], u8(4))
		testing.expect_value(t, dst[1], u8(3))
		testing.expect_value(t, dst[2], u8(2))
		testing.expect_value(t, dst[3], u8(1))
	} else {
		for i in 0 ..< len(dst) {
			testing.expect_value(t, dst[i], src[i])
		}
	}
}

// ---------------------------------------------------------------------------
// Lookup helpers: get_gpu / handle / atlas region wrappers
// ---------------------------------------------------------------------------

@(test)
texture_get_gpu_and_handle_for_white_invalid_and_registered :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			sentinel: sdl.GPUTexture
			state.gpu_state.white_texture = &sentinel

			testing.expect(t, texture_get_gpu(TEXTURE_WHITE_ID) == &sentinel)
			white_handle := texture_handle(TEXTURE_WHITE_ID)
			testing.expect_value(t, white_handle.id, TEXTURE_WHITE_ID)
			expect_close(t, white_handle.w, 1)
			expect_close(t, white_handle.h, 1)

			testing.expect(t, texture_get_gpu(INVALID_ASSET_ID) == nil)
			testing.expect(t, texture_get_gpu(Asset_Id(-5)) == nil)
			testing.expect(t, texture_get_gpu(Asset_Id(99)) == nil)
			empty := texture_handle(Asset_Id(99))
			testing.expect_value(t, empty.id, Asset_Id(0))
			expect_close(t, empty.w, 0)
			expect_close(t, empty.h, 0)

			// Slot zero is reserved and is not a normal record lookup.
			testing.expect(t, texture_get_gpu(Asset_Id(0)) == &sentinel) // white id
			testing.expect_value(t, texture_handle(Asset_Id(0)).id, TEXTURE_WHITE_ID)

			fake_gpu: sdl.GPUTexture
			append(
				&state.textures.records,
				Texture_Record{gpu = &fake_gpu, w = 32, h = 48},
			)
			id := Asset_Id(1)
			testing.expect(t, texture_get_gpu(id) == &fake_gpu)
			handle := texture_handle(id)
			testing.expect_value(t, handle.id, id)
			expect_close(t, handle.w, 32)
			expect_close(t, handle.h, 48)

			// Clear fake pointers before shutdown so we do not ReleaseGPUTexture.
			state.textures.records[1].gpu = nil
			state.gpu_state.white_texture = nil
		},
	)
}

@(test)
texture_atlas_region_from_and_handle_roundtrip :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			append(&state.textures.records, Texture_Record{w = 100, h = 50})
			tex := Texture_Handle {
				id = Asset_Id(1),
				w  = 100,
				h  = 50,
			}
			region := atlas_region_from(tex, {10, 20, 30, 40})
			expect_atlas_region(t, region, Asset_Id(1), 10, 20, 30, 40)

			parent := atlas_region_handle(region)
			testing.expect_value(t, parent.id, Asset_Id(1))
			expect_close(t, parent.w, 100)
			expect_close(t, parent.h, 50)

			white_region := atlas_region_from(
				{id = TEXTURE_WHITE_ID, w = 1, h = 1},
				{0, 0, 1, 1},
			)
			white_parent := atlas_region_handle(white_region)
			testing.expect_value(t, white_parent.id, TEXTURE_WHITE_ID)
			expect_close(t, white_parent.w, 1)
			expect_close(t, white_parent.h, 1)
		},
	)
}

// ---------------------------------------------------------------------------
// Atlas shelf allocation (CPU-seeded, no GPU)
// ---------------------------------------------------------------------------

@(test)
texture_atlas_alloc_rejects_non_positive_sizes :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			texture_test_seed_atlas()

			_, ok := texture_atlas_alloc(0, 10)
			testing.expect(t, !ok)
			_, ok = texture_atlas_alloc(10, 0)
			testing.expect(t, !ok)
			_, ok = texture_atlas_alloc(-1, 8)
			testing.expect(t, !ok)
			_, ok = texture_atlas_alloc(8, -3)
			testing.expect(t, !ok)
			testing.expect_value(t, len(state.textures.atlas.shelves), 0)
		},
	)
}

@(test)
texture_atlas_alloc_fails_when_atlas_cannot_init_without_gpu :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, state.gpu == nil)
			testing.expect_value(t, state.textures.atlas.texture_id, INVALID_ASSET_ID)

			_, ok := texture_atlas_alloc(8, 8)
			testing.expect(t, !ok)
		},
	)
}

@(test)
texture_atlas_alloc_packs_first_fit_with_padding_and_new_shelves :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			atlas_id := texture_test_seed_atlas(64, 64)
			pad := i32(ATLAS_PADDING)

			r1, ok1 := texture_atlas_alloc(10, 10)
			testing.expect(t, ok1)
			expect_atlas_region(t, r1, atlas_id, 0, 0, 10, 10)
			testing.expect_value(t, len(state.textures.atlas.shelves), 1)
			testing.expect_value(t, state.textures.atlas.shelves[0].height, 10 + pad)
			testing.expect_value(t, state.textures.atlas.shelves[0].cursor_x, 10 + pad)

			r2, ok2 := texture_atlas_alloc(10, 10)
			testing.expect(t, ok2)
			expect_atlas_region(t, r2, atlas_id, f32(10 + pad), 0, 10, 10)
			testing.expect_value(t, len(state.textures.atlas.shelves), 1)
			testing.expect_value(t, state.textures.atlas.shelves[0].cursor_x, 2 * (10 + pad))

			// Taller than current shelf height → new shelf.
			r3, ok3 := texture_atlas_alloc(20, 20)
			testing.expect(t, ok3)
			expect_atlas_region(t, r3, atlas_id, 0, f32(10 + pad), 20, 20)
			testing.expect_value(t, len(state.textures.atlas.shelves), 2)
			testing.expect_value(t, state.textures.atlas.shelves[1].y, 10 + pad)
			testing.expect_value(t, state.textures.atlas.shelves[1].height, 20 + pad)
			testing.expect_value(t, state.textures.atlas.shelves[1].cursor_x, 20 + pad)

			// 5x5 would still first-fit on shelf 0 (height 11). Use height that only
			// fits the taller second shelf.
			r4, ok4 := texture_atlas_alloc(5, 12)
			testing.expect(t, ok4)
			expect_atlas_region(t, r4, atlas_id, f32(20 + pad), f32(10 + pad), 5, 12)

			// Small region still first-fits onto shelf 0's remaining width.
			r5, ok5 := texture_atlas_alloc(5, 5)
			testing.expect(t, ok5)
			expect_atlas_region(t, r5, atlas_id, f32(2 * (10 + pad)), 0, 5, 5)
		},
	)
}

@(test)
texture_atlas_alloc_skips_full_shelf_and_reports_out_of_space :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			atlas_id := texture_test_seed_atlas(32, 32)
			pad := i32(ATLAS_PADDING)

			// Fill first shelf width exactly with padded width.
			w := 32 - pad
			r1, ok1 := texture_atlas_alloc(w, 8)
			testing.expect(t, ok1)
			expect_atlas_region(t, r1, atlas_id, 0, 0, f32(w), 8)
			testing.expect_value(t, state.textures.atlas.shelves[0].cursor_x, i32(32))

			// Same height cannot fit on full shelf → opens second shelf.
			r2, ok2 := texture_atlas_alloc(4, 4)
			testing.expect(t, ok2)
			expect_atlas_region(t, r2, atlas_id, 0, f32(8 + pad), 4, 4)

			// Exhaust remaining vertical space with a full-width shelf so later
			// first-fit cannot reuse earlier shelves' leftover width.
			used_y := (8 + pad) + (4 + pad)
			remain_h := 32 - used_y
			testing.expect(t, remain_h > pad)
			r3, ok3 := texture_atlas_alloc(32 - pad, remain_h - pad)
			testing.expect(t, ok3)
			testing.expect_value(t, len(state.textures.atlas.shelves), 3)
			testing.expect_value(t, state.textures.atlas.shelves[2].cursor_x, i32(32))

			// Fill shelf 1 remaining width so first-fit has nowhere left.
			shelf1_remain := 32 - state.textures.atlas.shelves[1].cursor_x
			testing.expect(t, shelf1_remain > pad)
			r4, ok4 := texture_atlas_alloc(shelf1_remain - pad, 1)
			testing.expect(t, ok4)
			testing.expect_value(t, state.textures.atlas.shelves[1].cursor_x, i32(32))

			_, ok5 := texture_atlas_alloc(1, 1)
			testing.expect(t, !ok5)
			testing.expect_value(t, len(state.textures.atlas.shelves), 3)
			_ = r1
			_ = r2
			_ = r3
			_ = r4
		},
	)
}

@(test)
texture_atlas_alloc_rejects_region_larger_than_atlas :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			texture_test_seed_atlas(16, 16)
			_, ok := texture_atlas_alloc(16, 16) // needs 16+pad in both axes
			testing.expect(t, !ok)
			_, ok = texture_atlas_alloc(4, 16) // padded height exceeds atlas
			testing.expect(t, !ok)
			testing.expect_value(t, len(state.textures.atlas.shelves), 0)

			// Width-only overflow on a fresh shelf is currently accepted by the
			// packer (it does not clamp new shelves to atlas.width).
			r, wide_ok := texture_atlas_alloc(20, 4)
			testing.expect(t, wide_ok)
			expect_close(t, r.w, 20)
			testing.expect_value(t, state.textures.atlas.shelves[0].cursor_x, 20 + ATLAS_PADDING)
		},
	)
}

@(test)
texture_atlas_shutdown_clears_shelves_but_keeps_records :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			id := texture_test_seed_atlas()
			_, ok := texture_atlas_alloc(8, 8)
			testing.expect(t, ok)
			testing.expect(t, len(state.textures.atlas.shelves) > 0)

			texture_atlas_shutdown()
			testing.expect_value(t, state.textures.atlas.texture_id, Asset_Id(0))
			testing.expect_value(t, state.textures.atlas.width, i32(0))
			testing.expect_value(t, len(state.textures.atlas.shelves), 0)
			testing.expect_value(t, len(state.textures.records), 2)
			testing.expect(t, state.textures.records[int(id)].surface != nil)
			_ = id
		},
	)
}

@(test)
texture_atlas_init_early_returns_when_already_initialized :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			id := texture_test_seed_atlas(48, 48)
			testing.expect(t, texture_atlas_init(128))
			testing.expect_value(t, state.textures.atlas.texture_id, id)
			testing.expect_value(t, state.textures.atlas.width, i32(48))
			testing.expect_value(t, len(state.textures.records), 2)
		},
	)
}

@(test)
texture_atlas_init_fails_without_gpu :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, !texture_atlas_init(32))
			testing.expect_value(t, state.textures.atlas.texture_id, INVALID_ASSET_ID)
		},
	)
}

@(test)
texture_atlas_upload_rejects_invalid_inputs_without_gpu :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			surface := texture_test_make_surface(4, 4, {9, 8, 7, 6})
			testing.expect(t, surface != nil)
			defer sdl.DestroySurface(surface)

			testing.expect(t, !texture_atlas_upload({}, surface))

			atlas_id := texture_test_seed_atlas()
			region := Atlas_Region {
				texture_id = atlas_id,
				x          = 0,
				y          = 0,
				w          = 4,
				h          = 4,
			}
			testing.expect(t, !texture_atlas_upload(region, nil))

			wrong := region
			wrong.texture_id = Asset_Id(99)
			testing.expect(t, !texture_atlas_upload(wrong, surface))

			// Atlas record exists but has no GPU texture.
			testing.expect(t, !texture_atlas_upload(region, surface))
		},
	)
}

@(test)
texture_atlas_pack_rejects_nil_and_rolls_back_new_shelf_on_upload_fail :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			_, ok := texture_atlas_pack(nil)
			testing.expect(t, !ok)

			atlas_id := texture_test_seed_atlas()
			surface := texture_test_make_surface(8, 8)
			testing.expect(t, surface != nil)
			defer sdl.DestroySurface(surface)

			testing.expect_value(t, len(state.textures.atlas.shelves), 0)
			_, ok = texture_atlas_pack(surface)
			testing.expect(t, !ok)
			// New shelf from alloc is rolled back when upload fails (no GPU).
			testing.expect_value(t, len(state.textures.atlas.shelves), 0)

			// Subsequent alloc must behave as if the failed pack never happened.
			r, ok2 := texture_atlas_alloc(8, 8)
			testing.expect(t, ok2)
			expect_atlas_region(t, r, atlas_id, 0, 0, 8, 8)
			testing.expect_value(t, len(state.textures.atlas.shelves), 1)
			testing.expect_value(t, state.textures.atlas.shelves[0].cursor_x, 8 + ATLAS_PADDING)
		},
	)
}

@(test)
texture_atlas_pack_does_not_rewind_existing_shelf_cursor_on_upload_fail :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			atlas_id := texture_test_seed_atlas()
			r1, ok1 := texture_atlas_alloc(8, 8)
			testing.expect(t, ok1)
			cursor_after_first := state.textures.atlas.shelves[0].cursor_x
			testing.expect_value(t, cursor_after_first, 8 + ATLAS_PADDING)

			surface := texture_test_make_surface(8, 8)
			testing.expect(t, surface != nil)
			defer sdl.DestroySurface(surface)

			shelf_count := len(state.textures.atlas.shelves)
			_, ok2 := texture_atlas_pack(surface)
			testing.expect(t, !ok2)
			testing.expect_value(t, len(state.textures.atlas.shelves), shelf_count)
			// Alloc advanced the cursor; pack only resizes shelf count on failure.
			leaked_cursor := state.textures.atlas.shelves[0].cursor_x
			testing.expect_value(t, leaked_cursor, 2 * (8 + ATLAS_PADDING))
			testing.expect(t, leaked_cursor > cursor_after_first)

			// Next successful alloc starts at the leaked cursor, not the pre-fail one.
			r2, ok3 := texture_atlas_alloc(4, 4)
			testing.expect(t, ok3)
			expect_atlas_region(t, r2, atlas_id, f32(leaked_cursor), 0, 4, 4)
			_ = r1
		},
	)
}

@(test)
texture_atlas_pack_cursor_rewind_new_shelf_vs_existing_shelf_contract :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			atlas_id := texture_test_seed_atlas(64, 64)
			pad := i32(ATLAS_PADDING)

			// Occupy first shelf so a taller pack opens a second shelf.
			r1, ok1 := texture_atlas_alloc(10, 10)
			testing.expect(t, ok1)
			testing.expect_value(t, len(state.textures.atlas.shelves), 1)
			shelf0_cursor := state.textures.atlas.shelves[0].cursor_x

			tall := texture_test_make_surface(8, 20)
			testing.expect(t, tall != nil)
			defer sdl.DestroySurface(tall)

			_, ok_fail := texture_atlas_pack(tall)
			testing.expect(t, !ok_fail)
			// Failed pack opened shelf 1 then rolled it back.
			testing.expect_value(t, len(state.textures.atlas.shelves), 1)
			testing.expect_value(t, state.textures.atlas.shelves[0].cursor_x, shelf0_cursor)

			// Retrying the tall alloc succeeds on a fresh second shelf at y = first shelf height.
			r2, ok2 := texture_atlas_alloc(8, 20)
			testing.expect(t, ok2)
			expect_atlas_region(t, r2, atlas_id, 0, f32(10 + pad), 8, 20)
			testing.expect_value(t, len(state.textures.atlas.shelves), 2)

			// Fail a pack that only fits on shelf 1 (taller than shelf 0's height).
			cursor_before := state.textures.atlas.shelves[1].cursor_x
			tall_fail := texture_test_make_surface(6, 12)
			testing.expect(t, tall_fail != nil)
			defer sdl.DestroySurface(tall_fail)
			_, ok_fail2 := texture_atlas_pack(tall_fail)
			testing.expect(t, !ok_fail2)
			testing.expect_value(t, len(state.textures.atlas.shelves), 2)
			testing.expect_value(
				t,
				state.textures.atlas.shelves[1].cursor_x,
				cursor_before + 6 + pad,
			)

			r3, ok3 := texture_atlas_alloc(3, 12)
			testing.expect(t, ok3)
			expect_atlas_region(
				t,
				r3,
				atlas_id,
				f32(cursor_before + 6 + pad),
				f32(10 + pad),
				3,
				12,
			)
			_ = r1
		},
	)
}

@(test)
texture_atlas_rebuild_gpu_noops_for_invalid_or_missing_surface :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			texture_atlas_rebuild_gpu() // invalid id

			state.textures.atlas.texture_id = Asset_Id(99)
			texture_atlas_rebuild_gpu() // out of range

			append(&state.textures.records, Texture_Record{})
			state.textures.atlas.texture_id = Asset_Id(1)
			texture_atlas_rebuild_gpu() // nil surface, no panic
		},
	)
}

@(test)
texture_register_surface_fails_without_gpu_and_rolls_back :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			surface := texture_test_make_surface(3, 3)
			testing.expect(t, surface != nil)
			// Ownership is taken and destroyed on failure — do not defer DestroySurface.

			before := len(state.textures.records)
			id, handle, ok := texture_register_surface(surface, "gone.png")
			testing.expect(t, !ok)
			testing.expect_value(t, id, Asset_Id(0))
			testing.expect_value(t, handle.id, Asset_Id(0))
			testing.expect_value(t, len(state.textures.records), before)
		},
	)
}

@(test)
texture_upload_record_and_surface_reject_invalid_args :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			entry: Texture_Record
			testing.expect(t, !texture_upload_record(&entry))

			surface := texture_test_make_surface(2, 2)
			testing.expect(t, surface != nil)
			defer sdl.DestroySurface(surface)

			entry.surface = surface
			testing.expect(t, !texture_upload_record(&entry)) // gpu nil

			zero := texture_test_make_surface(1, 1)
			testing.expect(t, zero != nil)
			defer sdl.DestroySurface(zero)
			zero.w = 0
			entry.surface = zero
			testing.expect(t, !texture_upload_record(&entry))

			fake_tex: sdl.GPUTexture
			testing.expect(t, !texture_upload_surface(nil, &fake_tex, surface, 0, 0, 2, 2))
			testing.expect(t, !texture_upload_surface(nil, nil, surface, 0, 0, 2, 2))
			testing.expect(t, !texture_upload_surface(nil, &fake_tex, nil, 0, 0, 2, 2))
			testing.expect(t, !texture_upload_surface(nil, &fake_tex, surface, 0, 0, 0, 2))
			testing.expect(t, !texture_upload_surface(nil, &fake_tex, surface, 0, 0, 2, -1))
		},
	)
}

// ---------------------------------------------------------------------------
// GPU integration
// ---------------------------------------------------------------------------

@(test)
texture_gpu_register_upload_handle_and_get :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			surface := texture_test_make_surface(8, 12, {1, 2, 3, 4})
			testing.expect(t, surface != nil)

			id, handle, ok := texture_register_surface(surface, "unit/tex.png")
			testing.expect(t, ok)
			testing.expect(t, id > TEXTURE_WHITE_ID)
			testing.expect_value(t, handle.id, id)
			expect_close(t, handle.w, 8)
			expect_close(t, handle.h, 12)

			entry := state.textures.records[int(id)]
			testing.expect(t, entry.gpu != nil)
			testing.expect(t, entry.surface != nil)
			testing.expect_value(t, entry.path, "unit/tex.png")
			testing.expect(t, texture_get_gpu(id) == entry.gpu)

			looked := texture_handle(id)
			testing.expect_value(t, looked.id, id)
			expect_close(t, looked.w, 8)
			expect_close(t, looked.h, 12)

			testing.expect(t, texture_get_gpu(TEXTURE_WHITE_ID) == state.gpu_state.white_texture)
		},
	)
}

@(test)
texture_gpu_register_empty_path_and_reupload_succeeds :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			surface := texture_test_make_surface(4, 4)
			testing.expect(t, surface != nil)

			id, _, ok := texture_register_surface(surface, "")
			testing.expect(t, ok)
			testing.expect_value(t, state.textures.records[int(id)].path, "")

			entry := &state.textures.records[int(id)]
			testing.expect(t, entry.gpu != nil)

			// Re-upload must succeed and leave a live GPU texture (SDL may recycle
			// the underlying pointer after ReleaseGPUTexture).
			testing.expect(t, texture_upload_record(entry))
			testing.expect(t, entry.gpu != nil)
			testing.expect_value(t, entry.w, i32(4))
			testing.expect_value(t, entry.h, i32(4))
		},
	)
}

@(test)
texture_gpu_release_and_reload_roundtrip :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			s1 := texture_test_make_surface(4, 4, {11, 22, 33, 44})
			s2 := texture_test_make_surface(6, 2, {55, 66, 77, 88})
			testing.expect(t, s1 != nil && s2 != nil)

			id1, _, ok1 := texture_register_surface(s1, "a.png")
			id2, _, ok2 := texture_register_surface(s2, "b.png")
			testing.expect(t, ok1 && ok2)

			testing.expect(t, texture_atlas_init(TEXTURE_TEST_ATLAS_SIZE))
			atlas_id := state.textures.atlas.texture_id
			testing.expect(t, atlas_id != INVALID_ASSET_ID)
			atlas_gpu_before := state.textures.records[int(atlas_id)].gpu
			testing.expect(t, atlas_gpu_before != nil)

			texture_release_gpu()
			for entry, i in state.textures.records {
				if i == 0 do continue
				testing.expect(t, entry.gpu == nil)
				testing.expect(t, entry.surface != nil)
			}

			texture_reload_gpu()
			testing.expect(t, state.textures.records[int(id1)].gpu != nil)
			testing.expect(t, state.textures.records[int(id2)].gpu != nil)
			testing.expect(t, state.textures.records[int(atlas_id)].gpu != nil)
			expect_close(t, texture_handle(id1).w, 4)
			expect_close(t, texture_handle(id2).h, 2)
		},
	)
}

@(test)
texture_gpu_atlas_init_pack_upload_and_cpu_backing_copy :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, texture_atlas_init(TEXTURE_TEST_ATLAS_SIZE))
			testing.expect_value(t, state.textures.atlas.width, TEXTURE_TEST_ATLAS_SIZE)
			testing.expect_value(t, state.textures.atlas.height, TEXTURE_TEST_ATLAS_SIZE)
			atlas_id := state.textures.atlas.texture_id
			testing.expect(t, atlas_id > TEXTURE_WHITE_ID)

			// Idempotent after first init.
			testing.expect(t, texture_atlas_init(128))
			testing.expect_value(t, state.textures.atlas.width, TEXTURE_TEST_ATLAS_SIZE)

			fill := [4]u8{0x10, 0x20, 0x30, 0x40}
			surface := texture_test_make_surface(5, 7, fill)
			testing.expect(t, surface != nil)
			defer sdl.DestroySurface(surface)

			region, ok := texture_atlas_pack(surface)
			testing.expect(t, ok)
			expect_atlas_region(t, region, atlas_id, 0, 0, 5, 7)

			atlas_surface := state.textures.records[int(atlas_id)].surface
			testing.expect(t, atlas_surface != nil)
			for row in i32(0) ..< 7 {
				for col in i32(0) ..< 5 {
					got := atlas_surface_pixel(atlas_surface, i32(region.x) + col, i32(region.y) + row)
					testing.expect_value(t, got[0], fill[0])
					testing.expect_value(t, got[1], fill[1])
					testing.expect_value(t, got[2], fill[2])
					testing.expect_value(t, got[3], fill[3])
				}
			}

			// Second pack sits on the same shelf after padding.
			surface2 := texture_test_make_surface(3, 3, {0xAA, 0xBB, 0xCC, 0xDD})
			testing.expect(t, surface2 != nil)
			defer sdl.DestroySurface(surface2)
			region2, ok2 := texture_atlas_pack(surface2)
			testing.expect(t, ok2)
			expect_close(t, region2.x, f32(5 + ATLAS_PADDING))
			expect_close(t, region2.y, 0)
			got := atlas_surface_pixel(atlas_surface, i32(region2.x), i32(region2.y))
			testing.expect_value(t, got[0], u8(0xAA))
			testing.expect_value(t, got[3], u8(0xDD))
		},
	)
}

@(test)
texture_gpu_atlas_upload_partial_surface_and_wrong_id :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, texture_atlas_init(TEXTURE_TEST_ATLAS_SIZE))
			atlas_id := state.textures.atlas.texture_id

			region, ok := texture_atlas_alloc(8, 8)
			testing.expect(t, ok)

			small := texture_test_make_surface(3, 2, {1, 2, 3, 4})
			testing.expect(t, small != nil)
			defer sdl.DestroySurface(small)

			testing.expect(t, texture_atlas_upload(region, small))
			atlas_surface := state.textures.records[int(atlas_id)].surface
			got := atlas_surface_pixel(atlas_surface, i32(region.x), i32(region.y))
			testing.expect_value(t, got[0], u8(1))
			testing.expect_value(t, got[1], u8(2))

			// Outside the copied sub-rect should remain untouched (zeros from init).
			outside := atlas_surface_pixel(atlas_surface, i32(region.x) + 7, i32(region.y) + 7)
			testing.expect_value(t, outside[0], u8(0))
			testing.expect_value(t, outside[3], u8(0))

			wrong := region
			wrong.texture_id = Asset_Id(int(atlas_id) + 10)
			testing.expect(t, !texture_atlas_upload(wrong, small))
		},
	)
}

@(test)
texture_gpu_atlas_rebuild_after_release :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, texture_atlas_init(TEXTURE_TEST_ATLAS_SIZE))
			atlas_id := state.textures.atlas.texture_id

			surface := texture_test_make_surface(4, 4, {9, 8, 7, 6})
			testing.expect(t, surface != nil)
			defer sdl.DestroySurface(surface)
			_, ok := texture_atlas_pack(surface)
			testing.expect(t, ok)

			texture_release_gpu()
			testing.expect(t, state.textures.records[int(atlas_id)].gpu == nil)

			texture_atlas_rebuild_gpu()
			testing.expect(t, state.textures.records[int(atlas_id)].gpu != nil)
		},
	)
}

@(test)
texture_gpu_upload_surface_subrectangle :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			surface := texture_test_make_surface(4, 4)
			testing.expect(t, surface != nil)
			defer sdl.DestroySurface(surface)

			id, _, ok := texture_register_surface(
				texture_test_make_surface(16, 16, {0, 0, 0, 0}),
				"",
			)
			testing.expect(t, ok)
			entry := state.textures.records[int(id)]
			testing.expect(t, entry.gpu != nil)

			testing.expect(
				t,
				texture_upload_surface(state.gpu, entry.gpu, surface, 4, 6, 4, 4),
			)
			testing.expect(
				t,
				!texture_upload_surface(state.gpu, entry.gpu, surface, 0, 0, 0, 4),
			)
		},
	)
}

@(test)
texture_gpu_reload_skips_nil_surfaces_and_rebuilds_atlas :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			s := texture_test_make_surface(2, 2)
			testing.expect(t, s != nil)
			id, _, ok := texture_register_surface(s, "keep.png")
			testing.expect(t, ok)

			append(&state.textures.records, Texture_Record{w = 1, h = 1}) // nil surface
			nil_surface_index := len(state.textures.records) - 1

			testing.expect(t, texture_atlas_init(TEXTURE_TEST_ATLAS_SIZE))
			atlas_id := state.textures.atlas.texture_id
			testing.expect(t, int(atlas_id) != nil_surface_index)

			texture_release_gpu()
			texture_reload_gpu()

			testing.expect(t, state.textures.records[int(id)].gpu != nil)
			testing.expect(t, state.textures.records[nil_surface_index].surface == nil)
			testing.expect(t, state.textures.records[nil_surface_index].gpu == nil)
			testing.expect(t, state.textures.records[int(atlas_id)].gpu != nil)
		},
	)
}

@(test)
texture_register_clones_path_independently :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			path := strings.clone("temp/owned-path.png")
			surface := texture_test_make_surface(2, 2)
			testing.expect(t, surface != nil)

			id, _, ok := texture_register_surface(surface, path)
			testing.expect(t, ok)
			delete(path)

			entry := state.textures.records[int(id)]
			testing.expect_value(t, entry.path, "temp/owned-path.png")
			testing.expect(t, len(entry.path) > 0)
		},
	)
}

@(test)
texture_upload_record_rejects_zero_height_surface :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			surface := texture_test_make_surface(4, 4)
			testing.expect(t, surface != nil)
			defer sdl.DestroySurface(surface)
			surface.h = 0

			entry := Texture_Record {
				surface = surface,
				w       = 4,
				h       = 0,
			}
			testing.expect(t, !texture_upload_record(&entry))
			testing.expect(t, entry.gpu == nil)
		},
	)
}

@(test)
texture_atlas_alloc_exact_padded_fit_then_full :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			atlas_id := texture_test_seed_atlas(16, 16)
			pad := i32(ATLAS_PADDING)
			r, ok := texture_atlas_alloc(16 - pad, 16 - pad)
			testing.expect(t, ok)
			expect_atlas_region(t, r, atlas_id, 0, 0, f32(16 - pad), f32(16 - pad))
			testing.expect_value(t, state.textures.atlas.shelves[0].cursor_x, i32(16))
			testing.expect_value(t, state.textures.atlas.shelves[0].height, i32(16))

			_, ok = texture_atlas_alloc(1, 1)
			testing.expect(t, !ok)
		},
	)
}

@(test)
texture_atlas_upload_rejects_invalid_atlas_record_index :: proc(t: ^testing.T) {
	with_texture_env(
		t,
		proc(t: ^testing.T) {
			surface := texture_test_make_surface(2, 2)
			testing.expect(t, surface != nil)
			defer sdl.DestroySurface(surface)

			state.textures.atlas = {
				texture_id = Asset_Id(99),
				width      = 32,
				height     = 32,
			}
			region := Atlas_Region {
				texture_id = Asset_Id(99),
				w          = 2,
				h          = 2,
			}
			testing.expect(t, !texture_atlas_upload(region, surface))
		},
	)
}

@(test)
texture_gpu_multiple_registers_and_handles :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			ids: [3]Asset_Id
			for i in 0 ..< 3 {
				s := texture_test_make_surface(i32(2 + i), i32(3 + i), {u8(i + 1), 0, 0, 255})
				testing.expect(t, s != nil)
				id, handle, ok := texture_register_surface(s, fmt_path(i))
				testing.expect(t, ok)
				ids[i] = id
				testing.expect_value(t, handle.id, id)
				expect_close(t, handle.w, f32(2 + i))
				expect_close(t, handle.h, f32(3 + i))
			}

			testing.expect(t, ids[0] != ids[1] && ids[1] != ids[2])
			for id in ids {
				testing.expect(t, texture_get_gpu(id) != nil)
			}
		},
	)
}

@(test)
texture_gpu_atlas_pack_failure_does_not_leave_orphan_gpu_state :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, texture_atlas_init(TEXTURE_TEST_ATLAS_SIZE))
			before_shelves := len(state.textures.atlas.shelves)
			before_records := len(state.textures.records)

			// Force alloc failure by requesting larger than atlas.
			huge := texture_test_make_surface(TEXTURE_TEST_ATLAS_SIZE, TEXTURE_TEST_ATLAS_SIZE)
			testing.expect(t, huge != nil)
			defer sdl.DestroySurface(huge)

			_, ok := texture_atlas_pack(huge)
			testing.expect(t, !ok)
			testing.expect_value(t, len(state.textures.atlas.shelves), before_shelves)
			testing.expect_value(t, len(state.textures.records), before_records)
		},
	)
}

@(test)
texture_reload_gpu_without_atlas_still_reuploads_records :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			s := texture_test_make_surface(3, 3)
			testing.expect(t, s != nil)
			id, _, ok := texture_register_surface(s, "solo.png")
			testing.expect(t, ok)
			testing.expect_value(t, state.textures.atlas.texture_id, INVALID_ASSET_ID)

			texture_release_gpu()
			testing.expect(t, state.textures.records[int(id)].gpu == nil)

			texture_reload_gpu()
			testing.expect(t, state.textures.records[int(id)].gpu != nil)
		},
	)
}

// ---------------------------------------------------------------------------
// SDL failure branches, non-RGBA sources, atlas_init edge cases
// ---------------------------------------------------------------------------

@(test)
texture_atlas_init_fails_on_invalid_create_surface_size :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			before := len(state.textures.records)
			testing.expect(t, !texture_atlas_init(-1))
			testing.expect_value(t, state.textures.atlas.texture_id, INVALID_ASSET_ID)
			testing.expect_value(t, len(state.textures.records), before)
		},
	)
}

@(test)
texture_atlas_init_register_failure_for_zero_size_surface :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			before := len(state.textures.records)
			// CreateSurface(0,0) succeeds with w=h=0; upload_record rejects it.
			testing.expect(t, !texture_atlas_init(0))
			testing.expect_value(t, state.textures.atlas.texture_id, INVALID_ASSET_ID)
			testing.expect_value(t, len(state.textures.records), before)
			// Must not double-free: a later successful init still works.
			testing.expect(t, texture_atlas_init(TEXTURE_TEST_ATLAS_SIZE))
			testing.expect(t, state.textures.atlas.texture_id != INVALID_ASSET_ID)
		},
	)
}

@(test)
texture_atlas_init_success_sets_square_atlas_state :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, texture_atlas_init(48))
			testing.expect_value(t, state.textures.atlas.width, i32(48))
			testing.expect_value(t, state.textures.atlas.height, i32(48))
			testing.expect_value(t, len(state.textures.atlas.shelves), 0)
			id := state.textures.atlas.texture_id
			testing.expect(t, id > TEXTURE_WHITE_ID)
			entry := state.textures.records[int(id)]
			testing.expect(t, entry.gpu != nil)
			testing.expect(t, entry.surface != nil)
			testing.expect_value(t, entry.w, i32(48))
			testing.expect_value(t, entry.h, i32(48))
			testing.expect_value(t, entry.path, "")
		},
	)
}

@(test)
texture_upload_surface_convert_index8_leaves_dest_reusable :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			index8 := texture_test_make_surface_format(4, 4, .INDEX8)
			testing.expect(t, index8 != nil)
			defer sdl.DestroySurface(index8)
			testing.expect(t, sdl.ConvertSurface(index8, .RGBA8888) == nil)

			dst := texture_test_make_surface(4, 4)
			testing.expect(t, dst != nil)
			id, _, ok := texture_register_surface(dst, "dst.png")
			testing.expect(t, ok)
			gpu_tex := state.textures.records[int(id)].gpu

			testing.expect(t, !texture_upload_surface(state.gpu, gpu_tex, index8, 0, 0, 4, 4))

			rgba := texture_test_make_surface(2, 2, {1, 2, 3, 4})
			testing.expect(t, rgba != nil)
			defer sdl.DestroySurface(rgba)
			testing.expect(t, texture_upload_surface(state.gpu, gpu_tex, rgba, 0, 0, 2, 2))
		},
	)
}

@(test)
texture_upload_record_mid_failure_releases_created_gpu_texture :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			index8 := texture_test_make_surface_format(3, 3, .INDEX8)
			testing.expect(t, index8 != nil)
			defer sdl.DestroySurface(index8)

			entry := Texture_Record {
				surface = index8,
				w       = 3,
				h       = 3,
			}
			testing.expect(t, !texture_upload_record(&entry))
			testing.expect(t, entry.gpu == nil)
		},
	)
}

@(test)
texture_register_surface_rolls_back_index8_convert_failure :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			before := len(state.textures.records)
			index8 := texture_test_make_surface_format(5, 5, .INDEX8)
			testing.expect(t, index8 != nil)
			// Ownership destroyed inside register on failure.

			id, handle, ok := texture_register_surface(index8, "bad/index8.png")
			testing.expect(t, !ok)
			testing.expect_value(t, id, Asset_Id(0))
			testing.expect_value(t, handle.id, Asset_Id(0))
			testing.expect_value(t, len(state.textures.records), before)
		},
	)
}

@(test)
texture_upload_surface_fails_when_transfer_buffer_create_fails :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			rgba := texture_test_make_surface(2, 2)
			testing.expect(t, rgba != nil)
			defer sdl.DestroySurface(rgba)

			id, _, ok := texture_register_surface(texture_test_make_surface(4, 4), "")
			testing.expect(t, ok)
			gpu_tex := state.textures.records[int(id)].gpu

			// dst 65536×65536 makes row_bytes*dst_h overflow u32 to 0, so
			// CreateGPUTransferBuffer(size=0) fails without allocating tens of GiB.
			testing.expect(
				t,
				!texture_upload_surface(state.gpu, gpu_tex, rgba, 0, 0, 65536, 65536),
			)
			testing.expect(t, texture_get_gpu(id) == gpu_tex)
		},
	)
}

@(test)
texture_non_rgba_rgb24_and_xrgb_register_and_atlas_pack :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			rgb24 := texture_test_make_surface_format(6, 4, .RGB24, 10, 20, 30)
			testing.expect(t, rgb24 != nil)
			testing.expect(t, rgb24.format != .RGBA8888)

			id, handle, ok := texture_register_surface(rgb24, "rgb24.png")
			testing.expect(t, ok)
			testing.expect_value(t, handle.id, id)
			expect_close(t, handle.w, 6)
			expect_close(t, handle.h, 4)
			testing.expect(t, texture_get_gpu(id) != nil)

			testing.expect(t, texture_atlas_init(TEXTURE_TEST_ATLAS_SIZE))
			atlas_id := state.textures.atlas.texture_id

			xrgb := texture_test_make_surface_format(3, 3, .XRGB8888, 200, 100, 50)
			testing.expect(t, xrgb != nil)
			defer sdl.DestroySurface(xrgb)

			region, pok := texture_atlas_pack(xrgb)
			testing.expect(t, pok)
			expect_atlas_region(t, region, atlas_id, 0, 0, 3, 3)

			// CPU backing stores ConvertSurface(...RGBA8888) bytes (unswizzled).
			converted := sdl.ConvertSurface(xrgb, .RGBA8888)
			testing.expect(t, converted != nil)
			defer if converted != xrgb do sdl.DestroySurface(converted)
			want := atlas_surface_pixel(converted, 0, 0)
			got := atlas_surface_pixel(
				state.textures.records[int(atlas_id)].surface,
				i32(region.x),
				i32(region.y),
			)
			testing.expect_value(t, got[0], want[0])
			testing.expect_value(t, got[1], want[1])
			testing.expect_value(t, got[2], want[2])
			testing.expect_value(t, got[3], want[3])
		},
	)
}

@(test)
texture_non_rgba_bgr24_and_argb8888_upload_paths :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			bgr := texture_test_make_surface_format(4, 2, .BGR24, 1, 2, 3)
			testing.expect(t, bgr != nil)
			id, _, ok := texture_register_surface(bgr, "bgr.png")
			testing.expect(t, ok)
			testing.expect(t, state.textures.records[int(id)].gpu != nil)

			argb := texture_test_make_surface_format(2, 2, .ARGB8888, 9, 8, 7, 6)
			testing.expect(t, argb != nil)
			defer sdl.DestroySurface(argb)

			entry := &state.textures.records[int(id)]
			testing.expect(t, texture_upload_surface(state.gpu, entry.gpu, argb, 0, 0, 2, 2))
			testing.expect(t, texture_upload_record(entry))
		},
	)
}

@(test)
texture_atlas_upload_fails_on_index8_without_cpu_corruption :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, texture_atlas_init(TEXTURE_TEST_ATLAS_SIZE))
			atlas_id := state.textures.atlas.texture_id
			atlas_surface := state.textures.records[int(atlas_id)].surface

			marker := [4]u8{0xDE, 0xAD, 0xBE, 0xEF}
			px := cast([^]u8)atlas_surface.pixels
			px[0], px[1], px[2], px[3] = marker[0], marker[1], marker[2], marker[3]

			region, ok := texture_atlas_alloc(4, 4)
			testing.expect(t, ok)
			index8 := texture_test_make_surface_format(4, 4, .INDEX8)
			testing.expect(t, index8 != nil)
			defer sdl.DestroySurface(index8)

			testing.expect(t, !texture_atlas_upload(region, index8))
			got := atlas_surface_pixel(atlas_surface, 0, 0)
			testing.expect_value(t, got[0], marker[0])
			testing.expect_value(t, got[1], marker[1])
			testing.expect_value(t, got[2], marker[2])
			testing.expect_value(t, got[3], marker[3])
		},
	)
}

@(test)
texture_atlas_pack_index8_rolls_back_new_shelf_with_gpu :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, texture_atlas_init(TEXTURE_TEST_ATLAS_SIZE))
			testing.expect_value(t, len(state.textures.atlas.shelves), 0)

			index8 := texture_test_make_surface_format(8, 8, .INDEX8)
			testing.expect(t, index8 != nil)
			defer sdl.DestroySurface(index8)

			_, ok := texture_atlas_pack(index8)
			testing.expect(t, !ok)
			testing.expect_value(t, len(state.textures.atlas.shelves), 0)

			rgba := texture_test_make_surface(8, 8)
			testing.expect(t, rgba != nil)
			defer sdl.DestroySurface(rgba)
			region, ok2 := texture_atlas_pack(rgba)
			testing.expect(t, ok2)
			expect_close(t, region.x, 0)
			expect_close(t, region.y, 0)
		},
	)
}

@(test)
texture_atlas_pack_index8_leaks_cursor_on_existing_shelf_with_gpu :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, texture_atlas_init(TEXTURE_TEST_ATLAS_SIZE))
			rgba := texture_test_make_surface(8, 8)
			testing.expect(t, rgba != nil)
			defer sdl.DestroySurface(rgba)
			r1, ok1 := texture_atlas_pack(rgba)
			testing.expect(t, ok1)
			cursor := state.textures.atlas.shelves[0].cursor_x
			testing.expect_value(t, cursor, 8 + ATLAS_PADDING)

			index8 := texture_test_make_surface_format(8, 8, .INDEX8)
			testing.expect(t, index8 != nil)
			defer sdl.DestroySurface(index8)
			_, ok2 := texture_atlas_pack(index8)
			testing.expect(t, !ok2)
			testing.expect_value(t, len(state.textures.atlas.shelves), 1)
			testing.expect_value(t, state.textures.atlas.shelves[0].cursor_x, 2 * (8 + ATLAS_PADDING))

			rgba2 := texture_test_make_surface(4, 4)
			testing.expect(t, rgba2 != nil)
			defer sdl.DestroySurface(rgba2)
			r2, ok3 := texture_atlas_pack(rgba2)
			testing.expect(t, ok3)
			expect_close(t, r2.x, f32(2 * (8 + ATLAS_PADDING)))
			expect_close(t, r2.y, 0)
			_ = r1
		},
	)
}

@(test)
texture_atlas_rebuild_logs_and_survives_upload_failure :: proc(t: ^testing.T) {
	with_texture_gpu_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, texture_atlas_init(TEXTURE_TEST_ATLAS_SIZE))
			atlas_id := state.textures.atlas.texture_id
			entry := &state.textures.records[int(atlas_id)]

			// Replace atlas CPU surface with INDEX8 so rebuild's upload_record fails.
			old := entry.surface
			index8 := texture_test_make_surface_format(entry.w, entry.h, .INDEX8)
			testing.expect(t, index8 != nil)
			entry.surface = index8
			if old != nil do sdl.DestroySurface(old)

			texture_release_gpu()
			testing.expect(t, entry.gpu == nil)
			texture_atlas_rebuild_gpu()
			testing.expect(t, entry.gpu == nil)
		},
	)
}

@(test)
texture_constants_and_default_atlas_size :: proc(t: ^testing.T) {
	testing.expect_value(t, ATLAS_PADDING, 1)
	testing.expect_value(t, ATLAS_DEFAULT_SIZE, 2048)
	testing.expect_value(t, TEXTURE_WHITE_ID, Asset_Id(0))
	testing.expect_value(t, INVALID_ASSET_ID, Asset_Id(-1))
}
