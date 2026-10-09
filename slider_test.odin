package oni

import "core:testing"

@(test)
slider_snap_clamps_and_steps :: proc(t: ^testing.T) {
	testing.expect(t, abs(slider_snap(37, 0, 100, 10) - 40) < 1e-4)
	testing.expect(t, abs(slider_snap(-5, 0, 100, 1) - 0) < 1e-4)
	testing.expect(t, abs(slider_snap(150, 0, 100, 1) - 100) < 1e-4)
	testing.expect(t, abs(slider_snap(33.3, 0, 100, 0) - 33.3) < 1e-4)
}

@(test)
slider_normalize_bounds_swaps_inverted_range :: proc(t: ^testing.T) {
	lo, hi := slider_normalize_bounds(80, 20)
	testing.expect(t, abs(lo - 20) < 1e-4)
	testing.expect(t, abs(hi - 80) < 1e-4)
}

@(test)
slider_t_value_round_trip :: proc(t: ^testing.T) {
	t0 := slider_t_from_value(25, 0, 100, false)
	v0 := slider_value_from_t(t0, 0, 100, false)
	testing.expect(t, abs(v0 - 25) < 1e-4)

	t1 := slider_t_from_value(25, 0, 100, true)
	v1 := slider_value_from_t(t1, 0, 100, true)
	testing.expect(t, abs(v1 - 25) < 1e-4)
	testing.expect(t, abs(t1 - 0.75) < 1e-4)
}

@(test)
slider_pointer_maps_to_track_t :: proc(t: ^testing.T) {
	tt := slider_t_from_pointer(50, 0, 100, 20, 10)
	testing.expect(t, abs(tt - 0.5) < 1e-4)
}

@(test)
slider_set_thumb_respects_min_gap :: proc(t: ^testing.T) {
	values := [SLIDER_MAX_THUMBS]f32{20, 80}
	changed := slider_set_thumb_value(&values, 2, 0, 70, 0, 100, 1, 10)
	testing.expect(t, changed)
	testing.expect(t, values[0] <= values[1] - 10)
	testing.expect(t, abs(values[0] - 70) < 1e-4 || values[0] <= 70)
}

@(test)
slider_normalize_values_sorts_range :: proc(t: ^testing.T) {
	values := [SLIDER_MAX_THUMBS]f32{80, 20}
	n := slider_normalize_values(&values, 2, 0, 100, 1, 0)
	testing.expect_value(t, n, 2)
	testing.expect(t, values[0] <= values[1])
	testing.expect(t, abs(values[0] - 20) < 1e-4)
	testing.expect(t, abs(values[1] - 80) < 1e-4)
}

@(test)
slider_nearest_thumb_picks_closest :: proc(t: ^testing.T) {
	values := [SLIDER_MAX_THUMBS]f32{10, 90}
	idx := slider_nearest_thumb(values, 2, 0.8, 0, 100, false)
	testing.expect_value(t, idx, 1)
}

@(test)
slider_drag_entry_clears_on_shutdown :: proc(t: ^testing.T) {
	test_state: State
	saved := state
	defer state = saved
	state = &test_state

	id := UI_Id(42)
	drag := slider_drag_entry(id)
	testing.expect(t, drag != nil)
	drag.active = true
	drag.thumb_index = 1

	testing.expect(t, state.ui.slider_drags != nil)
	slider_drag_end(id)
	testing.expect(t, !state.ui.slider_drags[id].active)
	testing.expect_value(t, state.ui.slider_drags[id].thumb_index, 1)

	slider_drag_clear(id)
	_, ok := state.ui.slider_drags[id]
	testing.expect(t, !ok)

	slider_shutdown()
	testing.expect(t, state.ui.slider_drags == nil)
	slider_shutdown()
}
