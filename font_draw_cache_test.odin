#+test
package oni

import "core:testing"

@(test)
font_draw_cached_and_missing_glyphs_preserve_run_tints :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)
		shaped := font_shape(face, "AB", .LTR)
		defer delete(shaped)
		if len(shaped) != 2 { testing.expect(t, false); return }
		paints := [2]Layout_Glyph_Paint{}
		for &paint, i in paints { paint = {face_id = handle.id, glyph_id = shaped[i].glyph_id, dst = {f32(i * 10), 0, 8, 10}, run_index = u16(i)} }
		laid := Layout_Text{lines = []Shaped_Line{{width = 20}}, glyphs = paints[:], size = {20, 12}}
		tints := [2]RGBA{{255, 0, 0, 255}, {0, 0, 255, 128}}
		for iteration in 0 ..< 3 {
			if iteration == 2 {
				for mode in Font_Glyph_Render_Mode { delete_key(&state.fonts.glyph_cache, Font_Glyph_Key{face_id = handle.id, glyph_id = shaped[1].glyph_id, render_mode = mode}) }
			}
			batch_reset()
			testing.expect_value(t, font_draw_layout_text(&laid, {0, 255, 0, 255}, run_colors = tints[:]), Vec2{20, 12})
			testing.expect_value(t, len(batch_current().vertices), 8)
			if len(batch_current().vertices) != 8 { return }
			testing.expect_value(t, batch_current().vertices[0].color, rgba_to_f32(tints[0]))
			testing.expect_value(t, batch_current().vertices[4].color, rgba_to_f32(tints[1]))
		}
	})
}
