package oni

import "core:testing"

@(test)
color_picker_apply_field_h_mode :: proc(t: ^testing.T) {
	hsva := HSVA{h = 120, s = 0.5, v = 0.5, a = 1}
	rgba := hsva_to_rgba(hsva)
	out_h, out_r := color_picker_apply_field(hsva, rgba, .H, 1, 0)
	testing.expect_value(t, out_h.s, f32(1))
	testing.expect_value(t, out_h.v, f32(1))
	testing.expect_value(t, out_r.g, u8(255))
}

@(test)
color_picker_channel_unit_and_apply :: proc(t: ^testing.T) {
	hsva := HSVA{h = 180, s = 1, v = 1, a = 1}
	rgba := hsva_to_rgba(hsva)
	testing.expect_value(t, color_picker_channel_unit(hsva, rgba, .H), f32(0.5))

	out_h, out_r := color_picker_apply_channel_unit(hsva, rgba, .H, 0)
	testing.expect_value(t, out_h.h, f32(0))
	testing.expect_value(t, out_r.r, u8(255))
}

@(test)
color_picker_hsva_preserves_hue_when_gray :: proc(t: ^testing.T) {
	prior := HSVA{h = 40, s = 1, v = 1, a = 1}
	got := color_picker_hsva_from_rgba({128, 128, 128, 255}, prior)
	testing.expect_value(t, got.h, f32(40))
	testing.expect(t, got.s <= 1e-5)
}

@(test)
color_picker_alpha_and_nudge :: proc(t: ^testing.T) {
	hsva := HSVA{h = 0, s = 1, v = 1, a = 1}
	rgba := hsva_to_rgba(hsva)
	out_h, out_r := color_picker_apply_alpha(hsva, rgba, 0.5)
	testing.expect_value(t, out_r.a, u8(128))
	testing.expect_value(t, out_h.a, f32(0.5))

	n_h, n_r, ok := color_picker_nudge(out_h, out_r, .H, .ALPHA, .RIGHT, 0.25)
	testing.expect(t, ok)
	testing.expect(t, n_r.a > out_r.a)
	_ = n_h
}

@(test)
color_picker_parse_component_ranges :: proc(t: ^testing.T) {
	h, h_ok := color_picker_parse_component("180", .H)
	testing.expect(t, h_ok)
	testing.expect_value(t, h, f32(180))

	s, s_ok := color_picker_parse_component("50", .S)
	testing.expect(t, s_ok)
	testing.expect_value(t, s, f32(0.5))

	r, r_ok := color_picker_parse_component("128", .R)
	testing.expect(t, r_ok)
	testing.expect_value(t, r, f32(128) / 255)

	_, bad := color_picker_parse_component("x", .G)
	testing.expect(t, !bad)
}

@(test)
color_picker_drag_entry_clears_on_shutdown :: proc(t: ^testing.T) {
	test_state: State
	saved := state
	state = &test_state
	defer {
		color_picker_shutdown()
		state = saved
	}

	id := UI_Id(42)
	drag := color_picker_drag_entry(id)
	testing.expect(t, drag != nil)
	drag.active = true
	drag.region = .FIELD

	testing.expect(t, state.ui.color_picker_drags != nil)
	color_picker_drag_end(id)
	testing.expect(t, !state.ui.color_picker_drags[id].active)

	color_picker_drag_clear(id)
	_, ok := state.ui.color_picker_drags[id]
	testing.expect(t, !ok)

	color_picker_shutdown()
	testing.expect(t, state.ui.color_picker_drags == nil)
	color_picker_shutdown()
}
