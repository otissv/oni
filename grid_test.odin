package oni

import "core:testing"

@(test)
grid_parse_template_tracks_fr_and_minmax :: proc(t: ^testing.T) {
	tracks, ok := grid_parse_template_tracks("1fr 100px minmax(0, 1fr)")
	testing.expect(t, ok)
	testing.expect_value(t, tracks.count, 3)
	fr, is_fr := grid_track_size_is_fr(tracks.tracks[0])
	testing.expect(t, is_fr)
	testing.expect_value(t, fr, 1)
	testing.expect_value(t, tracks.tracks[1].kind, Grid_Track_Size_Kind.PX)
	testing.expect_value(t, tracks.tracks[1].px, 100)
	testing.expect_value(t, tracks.tracks[2].kind, Grid_Track_Size_Kind.MINMAX)
}

@(test)
grid_template_columns_count_matches_tailwind :: proc(t: ^testing.T) {
	tracks := grid_template_columns_count(3)
	testing.expect_value(t, tracks.count, 3)
	for i in 0 ..< 3 {
		testing.expect_value(t, tracks.tracks[i].kind, Grid_Track_Size_Kind.MINMAX)
	}
}

@(test)
grid_parse_line_shorthand_span_and_slash :: proc(t: ^testing.T) {
	start, end, ok := grid_parse_line_shorthand("1 / 3")
	testing.expect(t, ok)
	testing.expect_value(t, start.line, 1)
	testing.expect_value(t, end.line, 3)

	only_span, _, span_ok := grid_parse_line_shorthand("span 2")
	testing.expect(t, span_ok)
	testing.expect_value(t, only_span.span, 2)
}

@(test)
grid_distribute_tracks_splits_fr :: proc(t: ^testing.T) {
	tracks := []Grid_Track_Size {
		grid_track_size_px(50),
		grid_track_size_fr(1),
		grid_track_size_fr(1),
	}
	mins := []f32{50, 0, 0}
	out := make([]f32, 3, context.temp_allocator)
	grid_distribute_tracks(tracks, 0, 250, mins, out)
	testing.expect_value(t, out[0], 50)
	testing.expectf(t, abs(out[1] - 100) < 1e-3, "got=%v want=100", out[1])
	testing.expectf(t, abs(out[2] - 100) < 1e-3, "got=%v want=100", out[2])
}

@(test)
grid_resolve_template_columns_int_and_string :: proc(t: ^testing.T) {
	from_n := grid_resolve_template_columns(Grid_Template_Columns(2))
	testing.expect_value(t, from_n.count, 2)
	from_s := grid_resolve_template_columns(Grid_Template_Columns("100px 1fr"))
	testing.expect_value(t, from_s.count, 2)
}
