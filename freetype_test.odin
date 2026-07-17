package oni

import "core:c"
import "core:math"
import "core:os"
import "core:strings"
import "core:testing"

@(private)
ft_test_fixture_path :: proc() -> string {
	return INTER_FONT_FIXTURE
}

@(private)
ft_test_with_face :: proc(t: ^testing.T, body: proc(library: FT_Library, face: FT_Face, t: ^testing.T)) {
	if !os.exists(ft_test_fixture_path()) {
		testing.expectf(t, false, "missing FreeType fixture %s (run from repo root)", ft_test_fixture_path())
		return
	}

	library: FT_Library
	testing.expect(t, ft_ok(Init_FreeType(&library)))
	if library == nil do return
	defer Done_FreeType(library)

	cpath := strings.clone_to_cstring(ft_test_fixture_path(), context.temp_allocator)
	face: FT_Face
	testing.expect(t, ft_ok(New_Face(library, cpath, 0, &face)))
	if face == nil do return
	defer Done_Face(face)

	testing.expect(t, ft_ok(Set_Pixel_Sizes(face, 16, 16)))
	body(library, face, t)
}

@(test)
ft_ok_true_only_for_zero_error :: proc(t: ^testing.T) {
	testing.expect(t, ft_ok(FT_Error(0)))
	testing.expect(t, !ft_ok(FT_Error(1)))
	testing.expect(t, !ft_ok(FT_Error(-1)))
	testing.expect(t, !ft_ok(FT_Error(0x60)))
}

@(test)
ft_fixed_from_f32_round_trip_and_rounding :: proc(t: ^testing.T) {
	expect_close(t, ft_fixed_to_f32(ft_fixed_from_f32(0)), 0)
	expect_close(t, ft_fixed_to_f32(ft_fixed_from_f32(1)), 1)
	expect_close(t, ft_fixed_to_f32(ft_fixed_from_f32(-2.5)), -2.5)
	expect_close(t, ft_fixed_to_f32(ft_fixed_from_f32(400)), 400)
	expect_close(t, ft_fixed_to_f32(ft_fixed_from_f32(14.0)), 14)

	// 16.16 fixed: 1.0 == 65536
	testing.expect_value(t, ft_fixed_from_f32(1), FT_Fixed(65536))
	testing.expect_value(t, ft_fixed_from_f32(0.5), FT_Fixed(32768))
	testing.expect_value(t, ft_fixed_from_f32(-1), FT_Fixed(-65536))

	// Rounding: 1/65536 * 0.6 rounds toward nearest.
	half_up := ft_fixed_from_f32(1.0 / 65536.0 * 0.6)
	testing.expect(t, half_up == 1 || half_up == 0)

	near := ft_fixed_from_f32(400.00001)
	far := ft_fixed_from_f32(400)
	testing.expect_value(t, near, far)

	back := ft_fixed_to_f32(FT_Fixed(65536 + 32768))
	expect_close(t, back, 1.5)
}

@(test)
ft_fixed_to_f32_handles_extremes :: proc(t: ^testing.T) {
	expect_close(t, ft_fixed_to_f32(0), 0)
	expect_close(t, ft_fixed_to_f32(1), 1.0 / 65536.0)
	expect_close(t, ft_fixed_to_f32(-65536), -1)
	large := ft_fixed_to_f32(FT_Fixed(900 * 65536))
	expect_close(t, large, 900)
}

@(test)
ft_tag_and_load_flag_constants_match_freetype :: proc(t: ^testing.T) {
	testing.expect_value(t, FT_TAG_WGHT, u32(0x77676874))
	testing.expect_value(t, FT_TAG_OPSZ, u32(0x6F70737A))
	testing.expect_value(t, FT_LOAD_DEFAULT, 0)
	testing.expect_value(t, FT_LOAD_RENDER, 1 << 2)
	testing.expect_value(t, FT_LOAD_NO_BITMAP, 1 << 3)
	testing.expect_value(t, FT_RENDER_MODE_NORMAL, 0)
	testing.expect_value(t, FT_PIXEL_MODE_MONO, 1)
	testing.expect_value(t, FT_PIXEL_MODE_GRAY, 2)
	testing.expect_value(t, FT_PIXEL_MODE_BGRA, 7)
	testing.expect_value(t, int(FT_Glyph_Format.BITMAP), 1651078259)
}

@(test)
ft_init_new_face_and_done_lifecycle :: proc(t: ^testing.T) {
	if !os.exists(ft_test_fixture_path()) {
		testing.expectf(t, false, "missing FreeType fixture %s", ft_test_fixture_path())
		return
	}

	library: FT_Library
	testing.expect(t, ft_ok(Init_FreeType(&library)))
	testing.expect(t, library != nil)
	defer Done_FreeType(library)

	missing: FT_Face
	testing.expect(t, !ft_ok(New_Face(library, "does/not/exist.ttf", 0, &missing)))
	testing.expect(t, missing == nil)

	cpath := strings.clone_to_cstring(ft_test_fixture_path(), context.temp_allocator)
	face: FT_Face
	testing.expect(t, ft_ok(New_Face(library, cpath, 0, &face)))
	testing.expect(t, face != nil)
	testing.expect(t, ft_ok(Done_Face(face)))
}

@(test)
ft_face_units_per_em_and_underline_metrics_readable :: proc(t: ^testing.T) {
	ft_test_with_face(
		t,
		proc(library: FT_Library, face: FT_Face, t: ^testing.T) {
			_ = library
			upem := ft_face_units_per_em(face)
			testing.expect(t, upem > 0)
			// Inter is typically 2048 or 1000 UPM depending on release; accept common ranges.
			testing.expect(t, upem >= 1000 && upem <= 4096)

			pos := ft_face_underline_position(face)
			thick := ft_face_underline_thickness(face)
			// Metrics exist; thickness is usually positive for Inter.
			testing.expect(t, thick >= 0)
			_ = pos
		},
	)
}

@(test)
ft_face_size_metrics_after_set_pixel_sizes :: proc(t: ^testing.T) {
	ft_test_with_face(
		t,
		proc(library: FT_Library, face: FT_Face, t: ^testing.T) {
			_ = library
			metrics := ft_face_size_metrics(face)
			testing.expect(t, metrics != nil)
			if metrics == nil do return

			testing.expect(t, metrics.x_ppem == 16 || metrics.y_ppem == 16)
			testing.expect(t, metrics.ascender > 0)
			testing.expect(t, metrics.height > 0)
			testing.expect(t, metrics.descender <= 0)

			ascent_px := f32(metrics.ascender) / 64.0
			height_px := f32(metrics.height) / 64.0
			testing.expect(t, ascent_px > 0)
			testing.expect(t, height_px >= ascent_px)
		},
	)
}

@(test)
ft_glyph_slot_accessors_after_load_and_render :: proc(t: ^testing.T) {
	ft_test_with_face(
		t,
		proc(library: FT_Library, face: FT_Face, t: ^testing.T) {
			_ = library
			slot := ft_glyph_slot(face)
			testing.expect(t, slot != nil)
			if slot == nil do return

			// Glyph index 0 is .notdef; still must load without crashing.
			testing.expect(t, ft_ok(Load_Glyph(face, 0, c.int(FT_LOAD_RENDER))))

			format := ft_slot_format(slot)
			testing.expect_value(t, format, FT_Glyph_Format.BITMAP)

			bitmap := ft_slot_bitmap(slot)
			testing.expect(t, bitmap != nil)
			if bitmap == nil do return
			testing.expect(
				t,
				bitmap.pixel_mode == FT_PIXEL_MODE_GRAY ||
				bitmap.pixel_mode == FT_PIXEL_MODE_MONO ||
				bitmap.pixel_mode == FT_PIXEL_MODE_BGRA,
			)

			left := ft_slot_bitmap_left(slot)
			top := ft_slot_bitmap_top(slot)
			// Bearings are finite integers; .notdef may be empty.
			testing.expect(t, math.is_nan(f32(left)) == false)
			testing.expect(t, math.is_nan(f32(top)) == false)
		},
	)
}

@(test)
ft_load_render_latin_glyph_produces_nonzero_bitmap :: proc(t: ^testing.T) {
	ft_test_with_face(
		t,
		proc(library: FT_Library, face: FT_Face, t: ^testing.T) {
			_ = library
			// Inter 'A' is typically glyph index > 0; load via charmap-less index scan is brittle,
			// so load a mid-range glyph that Inter definitely has after shaping 'A' through HB.
			hb := ft_font_create_referenced(face)
			testing.expect(t, hb != nil)
			if hb == nil do return
			defer font_destroy(hb)

			buf := buffer_create()
			testing.expect(t, buf != nil)
			if buf == nil do return
			defer buffer_destroy(buf)

			buffer_add_utf8(buf, "A", 1, 0, 1)
			buffer_guess_segment_properties(buf)
			buffer_set_direction(buf, HB_DIRECTION_LTR)
			testing.expect(t, shape(hb, buf, nil, 0) != 0)

			count := buffer_get_length(buf)
			testing.expect(t, count >= 1)
			info_len: c.uint
			infos := buffer_get_glyph_infos(buf, &info_len)
			testing.expect(t, infos != nil && info_len >= 1)
			gid := infos[0].codepoint

			testing.expect(t, ft_ok(Load_Glyph(face, c.uint(gid), c.int(FT_LOAD_RENDER))))
			slot := ft_glyph_slot(face)
			bitmap := ft_slot_bitmap(slot)^
			testing.expect(t, bitmap.width > 0)
			testing.expect(t, bitmap.rows > 0)
			testing.expect(t, bitmap.buffer != nil)
			testing.expect_value(t, bitmap.pixel_mode, u8(FT_PIXEL_MODE_GRAY))
			testing.expect(t, ft_slot_bitmap_top(slot) > 0)
		},
	)
}

@(test)
ft_load_no_bitmap_then_embolden_and_render :: proc(t: ^testing.T) {
	ft_test_with_face(
		t,
		proc(library: FT_Library, face: FT_Face, t: ^testing.T) {
			_ = library
			hb := ft_font_create_referenced(face)
			testing.expect(t, hb != nil)
			if hb == nil do return
			defer font_destroy(hb)

			buf := buffer_create()
			testing.expect(t, buf != nil)
			if buf == nil do return
			defer buffer_destroy(buf)

			buffer_add_utf8(buf, "B", 1, 0, 1)
			buffer_guess_segment_properties(buf)
			testing.expect(t, shape(hb, buf, nil, 0) != 0)
			info_len: c.uint
			infos := buffer_get_glyph_infos(buf, &info_len)
			testing.expect(t, infos != nil && info_len >= 1)
			gid := infos[0].codepoint

			testing.expect(t, ft_ok(Load_Glyph(face, c.uint(gid), c.int(FT_LOAD_NO_BITMAP))))
			slot := ft_glyph_slot(face)
			testing.expect(t, ft_slot_format(slot) != .BITMAP)

			GlyphSlot_Embolden(slot)
			testing.expect(t, ft_ok(Render_Glyph(slot, FT_RENDER_MODE_NORMAL)))
			testing.expect_value(t, ft_slot_format(slot), FT_Glyph_Format.BITMAP)

			bitmap := ft_slot_bitmap(slot)^
			testing.expect(t, bitmap.width > 0 && bitmap.rows > 0)
		},
	)
}

@(test)
ft_get_mm_var_reports_wght_and_opsz_for_inter :: proc(t: ^testing.T) {
	ft_test_with_face(
		t,
		proc(library: FT_Library, face: FT_Face, t: ^testing.T) {
			mm: ^FT_MM_Var
			testing.expect(t, ft_ok(Get_MM_Var(face, &mm)))
			testing.expect(t, mm != nil)
			if mm == nil do return
			defer Done_MM_Var(library, mm)

			testing.expect(t, mm.num_axis >= 2)
			has_wght, has_opsz: bool
			for i in 0 ..< int(mm.num_axis) {
				axis := mm.axis[i]
				tag := u32(axis.tag)
				min_v := ft_fixed_to_f32(axis.minimum)
				max_v := ft_fixed_to_f32(axis.maximum)
				def_v := ft_fixed_to_f32(axis.def)
				testing.expect(t, min_v <= def_v && def_v <= max_v)
				if tag == FT_TAG_WGHT {
					has_wght = true
					testing.expect(t, min_v <= 100 && max_v >= 900)
				}
				if tag == FT_TAG_OPSZ {
					has_opsz = true
					testing.expect(t, max_v > min_v)
				}
			}
			testing.expect(t, has_wght)
			testing.expect(t, has_opsz)
		},
	)
}

@(test)
ft_set_var_design_coordinates_accepts_weight_axis :: proc(t: ^testing.T) {
	ft_test_with_face(
		t,
		proc(library: FT_Library, face: FT_Face, t: ^testing.T) {
			mm: ^FT_MM_Var
			testing.expect(t, ft_ok(Get_MM_Var(face, &mm)))
			if mm == nil do return
			defer Done_MM_Var(library, mm)

			coords := make([]FT_Fixed, mm.num_axis, context.temp_allocator)
			wght_i := -1
			for i in 0 ..< int(mm.num_axis) {
				coords[i] = mm.axis[i].def
				if u32(mm.axis[i].tag) == FT_TAG_WGHT {
					wght_i = i
					coords[i] = ft_fixed_from_f32(700)
				}
			}
			testing.expect(t, wght_i >= 0)
			testing.expect(
				t,
				ft_ok(Set_Var_Design_Coordinates(face, c.uint(mm.num_axis), raw_data(coords))),
			)

			testing.expect(t, ft_ok(Set_Pixel_Sizes(face, 18, 18)))
			metrics := ft_face_size_metrics(face)
			testing.expect(t, metrics != nil)
			testing.expect(t, metrics.height > 0)
		},
	)
}

@(test)
ft_set_transform_identity_and_shear_do_not_crash :: proc(t: ^testing.T) {
	ft_test_with_face(
		t,
		proc(library: FT_Library, face: FT_Face, t: ^testing.T) {
			_ = library
			Set_Transform(face, nil, nil)

			shear := FT_Matrix {
				xx = 0x10000,
				xy = 13933,
				yx = 0,
				yy = 0x10000,
			}
			Set_Transform(face, &shear, nil)

			testing.expect(t, ft_ok(Load_Glyph(face, 0, c.int(FT_LOAD_RENDER))))
			testing.expect(t, ft_glyph_slot(face) != nil)

			Set_Transform(face, nil, nil)
		},
	)
}

// --- Gap coverage: nil metrics, delta transform, non-VF, crafted offsets ---

@(private)
ft_test_with_pixel_face :: proc(t: ^testing.T, body: proc(library: FT_Library, face: FT_Face, t: ^testing.T)) {
	if !os.exists(PIXEL_FONT_FIXTURE) {
		testing.expectf(t, false, "missing fixture %s", PIXEL_FONT_FIXTURE)
		return
	}
	library: FT_Library
	testing.expect(t, ft_ok(Init_FreeType(&library)))
	if library == nil do return
	defer Done_FreeType(library)

	cpath := strings.clone_to_cstring(PIXEL_FONT_FIXTURE, context.temp_allocator)
	face: FT_Face
	testing.expect(t, ft_ok(New_Face(library, cpath, 0, &face)))
	if face == nil do return
	defer Done_Face(face)
	testing.expect(t, ft_ok(Set_Pixel_Sizes(face, 8, 8)))
	body(library, face, t)
}

@(test)
ft_face_size_metrics_nil_when_size_pointer_absent :: proc(t: ^testing.T) {
	face_bytes := make([]u8, 192)
	defer delete(face_bytes)
	face := cast(FT_Face)raw_data(face_bytes)
	// size pointer at FT_FACE_OFFSET_SIZE left as nil
	testing.expect(t, ft_face_size_metrics(face) == nil)
}

@(test)
ft_face_size_metrics_reads_crafted_size_rec :: proc(t: ^testing.T) {
	face_bytes := make([]u8, 192)
	defer delete(face_bytes)
	face := cast(FT_Face)raw_data(face_bytes)

	size_rec: FT_SizeRec
	size_rec.metrics.ascender = 640 // 10px in 26.6
	size_rec.metrics.descender = -128
	size_rec.metrics.height = 768
	size_rec.metrics.x_ppem = 16
	size_rec.metrics.y_ppem = 16
	(cast(^^FT_SizeRec)(uintptr(face) + FT_FACE_OFFSET_SIZE))^ = &size_rec

	metrics := ft_face_size_metrics(face)
	testing.expect(t, metrics != nil)
	if metrics == nil do return
	testing.expect_value(t, metrics.ascender, FT_Pos(640))
	testing.expect_value(t, metrics.height, FT_Pos(768))
	testing.expect_value(t, metrics.x_ppem, FT_UShort(16))
}

@(test)
ft_crafted_face_and_slot_offset_accessors :: proc(t: ^testing.T) {
	face_bytes := make([]u8, 192)
	defer delete(face_bytes)
	face := cast(FT_Face)raw_data(face_bytes)

	(cast(^FT_UShort)(uintptr(face) + FT_FACE_OFFSET_UNITS_PER_EM))^ = 2048
	(cast(^FT_Short)(uintptr(face) + FT_FACE_OFFSET_UNDERLINE_POSITION))^ = -200
	(cast(^FT_Short)(uintptr(face) + FT_FACE_OFFSET_UNDERLINE_THICKNESS))^ = 100
	testing.expect_value(t, ft_face_units_per_em(face), FT_UShort(2048))
	testing.expect_value(t, ft_face_underline_position(face), FT_Short(-200))
	testing.expect_value(t, ft_face_underline_thickness(face), FT_Short(100))

	slot: FT_GlyphSlotRec
	(cast(^FT_Glyph_Format)(uintptr(&slot) + FT_SLOT_OFFSET_FORMAT))^ = .BITMAP
	(cast(^c.int)(uintptr(&slot) + FT_SLOT_OFFSET_BITMAP_LEFT))^ = -3
	(cast(^c.int)(uintptr(&slot) + FT_SLOT_OFFSET_BITMAP_TOP))^ = 12
	bmp := cast(^FT_Bitmap)(uintptr(&slot) + FT_SLOT_OFFSET_BITMAP)
	bmp.width = 5
	bmp.rows = 7
	bmp.pitch = 5
	bmp.pixel_mode = FT_PIXEL_MODE_GRAY

	(cast(^FT_GlyphSlot)(uintptr(face) + FT_FACE_OFFSET_GLYPH))^ = cast(FT_GlyphSlot)rawptr(&slot)

	got_slot := ft_glyph_slot(face)
	testing.expect(t, got_slot == &slot)
	testing.expect_value(t, ft_slot_format(got_slot), FT_Glyph_Format.BITMAP)
	testing.expect_value(t, ft_slot_bitmap_left(got_slot), c.int(-3))
	testing.expect_value(t, ft_slot_bitmap_top(got_slot), c.int(12))
	got_bmp := ft_slot_bitmap(got_slot)^
	testing.expect_value(t, got_bmp.width, c.uint(5))
	testing.expect_value(t, got_bmp.rows, c.uint(7))
	testing.expect_value(t, got_bmp.pixel_mode, u8(FT_PIXEL_MODE_GRAY))
}

@(test)
ft_set_transform_with_delta_vector :: proc(t: ^testing.T) {
	ft_test_with_face(
		t,
		proc(library: FT_Library, face: FT_Face, t: ^testing.T) {
			_ = library
			delta := FT_Vector {
				x = 64, // 1px in 26.6
				y = -32,
			}
			Set_Transform(face, nil, &delta)
			testing.expect(t, ft_ok(Load_Glyph(face, 0, c.int(FT_LOAD_RENDER))))
			testing.expect(t, ft_glyph_slot(face) != nil)

			xform := FT_Matrix {
				xx = 0x10000,
				xy = 0,
				yx = 0,
				yy = 0x10000,
			}
			Set_Transform(face, &xform, &delta)
			testing.expect(t, ft_ok(Load_Glyph(face, 0, c.int(FT_LOAD_RENDER))))
			Set_Transform(face, nil, nil)
		},
	)
}

@(test)
ft_get_mm_var_fails_on_static_pixel_font :: proc(t: ^testing.T) {
	ft_test_with_pixel_face(
		t,
		proc(library: FT_Library, face: FT_Face, t: ^testing.T) {
			mm: ^FT_MM_Var
			err := Get_MM_Var(face, &mm)
			testing.expect(t, !ft_ok(err))
			if mm != nil {
				Done_MM_Var(library, mm)
			}
		},
	)
}

@(test)
ft_set_var_design_coordinates_fails_on_static_font :: proc(t: ^testing.T) {
	ft_test_with_pixel_face(
		t,
		proc(library: FT_Library, face: FT_Face, t: ^testing.T) {
			_ = library
			coords := [1]FT_Fixed{ft_fixed_from_f32(400)}
			testing.expect(t, !ft_ok(Set_Var_Design_Coordinates(face, 1, raw_data(coords[:]))))
		},
	)
}

@(test)
ft_load_glyph_out_of_range_fails :: proc(t: ^testing.T) {
	ft_test_with_face(
		t,
		proc(library: FT_Library, face: FT_Face, t: ^testing.T) {
			_ = library
			testing.expect(t, !ft_ok(Load_Glyph(face, 0x7FFFFFFF, c.int(FT_LOAD_DEFAULT))))
		},
	)
}

@(test)
ft_render_glyph_on_empty_slot_after_default_load :: proc(t: ^testing.T) {
	ft_test_with_face(
		t,
		proc(library: FT_Library, face: FT_Face, t: ^testing.T) {
			_ = library
			// Load without render so format may be outline; Render_Glyph should succeed.
			testing.expect(t, ft_ok(Load_Glyph(face, 0, c.int(FT_LOAD_NO_BITMAP))))
			slot := ft_glyph_slot(face)
			testing.expect(t, slot != nil)
			if ft_slot_format(slot) != .BITMAP {
				testing.expect(t, ft_ok(Render_Glyph(slot, FT_RENDER_MODE_NORMAL)))
				testing.expect_value(t, ft_slot_format(slot), FT_Glyph_Format.BITMAP)
			} else {
				// Already bitmap — second render should still be ok.
				testing.expect(t, ft_ok(Render_Glyph(slot, FT_RENDER_MODE_NORMAL)))
			}
		},
	)
}
