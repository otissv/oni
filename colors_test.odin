package oni

import "core:testing"

@(private)
expect_rgba_eq :: proc(t: ^testing.T, got, want: RGBA, loc := #caller_location) {
	testing.expectf(t, got == want, "got=%v want=%v", got, want, loc = loc)
}

@(private)
expect_f32x4_close :: proc(
	t: ^testing.T,
	got, want: [4]f32,
	epsilon: f32 = 1e-5,
	loc := #caller_location,
) {
	ok :=
		abs(got[0] - want[0]) <= epsilon &&
		abs(got[1] - want[1]) <= epsilon &&
		abs(got[2] - want[2]) <= epsilon &&
		abs(got[3] - want[3]) <= epsilon
	testing.expectf(
		t,
		ok,
		"got=%v want=%v epsilon=%v",
		got,
		want,
		epsilon,
		loc = loc,
	)
}

@(private)
colors_test_push_parent_color :: proc(color: Colors) {
	ctx := ui_style_current()^
	ctx.color = color
	ui_push_style(ctx)
}

@(private)
colors_test_static_callback :: proc(
	frame_state: Widget_Frame_State,
	event: Widget_Event(Widget_Frame_State),
) -> Colors {
	_ = frame_state
	_ = event
	return RGBA{10, 20, 30, 40}
}

@(private)
colors_test_named_callback :: proc(
	frame_state: Widget_Frame_State,
	event: Widget_Event(Widget_Frame_State),
) -> Colors {
	_ = frame_state
	_ = event
	return Color.PRIMARY
}

@(private)
colors_test_invalid_callback :: proc(
	frame_state: Widget_Frame_State,
	event: Widget_Event(Widget_Frame_State),
) -> Colors {
	_ = frame_state
	_ = event
	return Color.INVALID
}

@(private)
colors_test_inherit_callback :: proc(
	frame_state: Widget_Frame_State,
	event: Widget_Event(Widget_Frame_State),
) -> Colors {
	_ = frame_state
	_ = event
	return Color.INHERIT
}

@(private)
colors_test_nested_callback :: proc(
	frame_state: Widget_Frame_State,
	event: Widget_Event(Widget_Frame_State),
) -> Colors {
	_ = frame_state
	_ = event
	return colors_test_static_callback
}

@(private)
colors_test_hex_callback :: proc(
	frame_state: Widget_Frame_State,
	event: Widget_Event(Widget_Frame_State),
) -> Colors {
	_ = frame_state
	_ = event
	return Hex(0xAABBCCDD)
}

@(private)
colors_test_seen_hovered: bool
@(private)
colors_test_seen_pressed: bool
@(private)
colors_test_seen_focused: bool
@(private)
colors_test_callback_calls: int
@(private)
colors_test_event_hovered: bool

@(private)
colors_test_frame_aware_callback :: proc(
	frame_state: Widget_Frame_State,
	event: Widget_Event(Widget_Frame_State),
) -> Colors {
	colors_test_seen_hovered = frame_state.is_hovered
	colors_test_seen_pressed = frame_state.is_Pressed
	colors_test_seen_focused = frame_state.is_focused
	colors_test_event_hovered = event.frame_state.is_hovered
	colors_test_callback_calls += 1
	if frame_state.is_hovered {
		return RGBA{255, 0, 0, 255}
	}
	return RGBA{0, 0, 255, 255}
}

@(private)
colors_test_hsla_callback :: proc(
	frame_state: Widget_Frame_State,
	event: Widget_Event(Widget_Frame_State),
) -> Colors {
	_ = frame_state
	_ = event
	return HSLA{0, 1, 0.5, 1}
}

@(private)
colors_test_hwba_callback :: proc(
	frame_state: Widget_Frame_State,
	event: Widget_Event(Widget_Frame_State),
) -> Colors {
	_ = frame_state
	_ = event
	return HWBA{120, 0, 0, 1}
}

@(private)
colors_test_lcha_callback :: proc(
	frame_state: Widget_Frame_State,
	event: Widget_Event(Widget_Frame_State),
) -> Colors {
	_ = frame_state
	_ = event
	return LCHA{50, 40, 30, 1}
}

@(private)
colors_test_oklcha_callback :: proc(
	frame_state: Widget_Frame_State,
	event: Widget_Event(Widget_Frame_State),
) -> Colors {
	_ = frame_state
	_ = event
	return OKLCHA{0.628, 0.258, 29.23, 1}
}

@(private)
colors_test_nested_inherit_callback :: proc(
	frame_state: Widget_Frame_State,
	event: Widget_Event(Widget_Frame_State),
) -> Colors {
	_ = frame_state
	_ = event
	return colors_test_inherit_callback
}

// ---------------------------------------------------------------------------
// Re-exports / aliases
// ---------------------------------------------------------------------------

@(test)
colors_reexports_match_colors_package_palette_and_helpers :: proc(t: ^testing.T) {
	expect_rgba_eq(t, palette[.BLACK], RGBA{0, 0, 0, 255})
	expect_rgba_eq(t, palette[.WHITE], RGBA{255, 255, 255, 255})
	expect_rgba_eq(t, palette[.TRANSPARENT], RGBA{0, 0, 0, 0})
	expect_rgba_eq(t, palette[.PRIMARY], css_color_to_rgba(.PRIMARY))

	expect_rgba_eq(t, css_color_to_rgba(.INVALID), {})
	expect_rgba_eq(t, css_color_to_rgba(.INHERIT), {})
	expect_rgba_eq(t, css_color_to_rgba(.RED_500), palette[.RED_500])

	expect_rgba_eq(t, to_rgba_color(Color.GREEN_500), css_color_to_rgba(.GREEN_500))
	expect_rgba_eq(t, to_rgba_color(RGBA{1, 2, 3, 4}), RGBA{1, 2, 3, 4})
	expect_rgba_eq(t, to_rgba_color(Hex(0x11223344)), RGBA{0x11, 0x22, 0x33, 0x44})
	// Pure red / lime via alternate spaces through the re-exported overload set.
	expect_rgba_eq(t, to_rgba_color(HSLA{0, 1, 0.5, 1}), RGBA{255, 0, 0, 255})
	expect_rgba_eq(t, to_rgba_color(HWBA{120, 0, 0, 1}), RGBA{0, 255, 0, 255})
	got_lch := to_rgba_color(LCHA{50, 40, 30, 1})
	testing.expect(t, got_lch.a == 255)
	testing.expect(t, got_lch.r > 0 || got_lch.g > 0 || got_lch.b > 0)
	got_oklch := to_rgba_color(OKLCHA{0.7, 0.1, 150, 1})
	testing.expect(t, got_oklch.a == 255)
	testing.expect(t, got_oklch.r > 0 || got_oklch.g > 0 || got_oklch.b > 0)

	expect_f32x4_close(t, rgba_to_f32(RGBA{255, 128, 0, 64}), {1, 128.0 / 255, 0, 64.0 / 255})
	expect_f32x4_close(t, rgba_to_f32({}), {0, 0, 0, 0})

	// Palette is a full Color-indexed table.
	testing.expect(t, len(palette) > 100)
	expect_rgba_eq(t, palette[Color.BLUE_500], css_color_to_rgba(.BLUE_500))
}

// ---------------------------------------------------------------------------
// colors_is_proc
// ---------------------------------------------------------------------------

@(test)
colors_is_proc_true_only_for_callback_variant :: proc(t: ^testing.T) {
	testing.expect(t, !colors_is_proc(Color.PRIMARY))
	testing.expect(t, !colors_is_proc(Color.INVALID))
	testing.expect(t, !colors_is_proc(Color.INHERIT))
	testing.expect(t, !colors_is_proc(RGBA{1, 2, 3, 4}))
	testing.expect(t, !colors_is_proc(Hex(0xFF0000FF)))
	testing.expect(t, !colors_is_proc(HSLA{0, 1, 0.5, 1}))
	testing.expect(t, !colors_is_proc(HWBA{120, 0, 0, 1}))
	testing.expect(t, !colors_is_proc(LCHA{50, 40, 30, 1}))
	testing.expect(t, !colors_is_proc(OKLCHA{0.6, 0.1, 40, 1}))

	testing.expect(t, colors_is_proc(colors_test_static_callback))
	testing.expect(t, colors_is_proc(colors_test_named_callback))
	testing.expect(t, colors_is_proc(colors_test_nested_callback))

	proc_val: Colors = colors_test_hex_callback
	testing.expect(t, colors_is_proc(proc_val))
}

// ---------------------------------------------------------------------------
// to_rgba — static variants
// ---------------------------------------------------------------------------

@(test)
to_rgba_resolves_all_static_color_spaces :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			named, named_ok := to_rgba(Color.PRIMARY, &frame, event)
			testing.expect(t, named_ok)
			expect_rgba_eq(t, named, css_color_to_rgba(.PRIMARY))

			direct, direct_ok := to_rgba(RGBA{9, 8, 7, 6}, &frame, event)
			testing.expect(t, direct_ok)
			expect_rgba_eq(t, direct, RGBA{9, 8, 7, 6})

			hex, hex_ok := to_rgba(Hex(0xDEADBEEF), &frame, event)
			testing.expect(t, hex_ok)
			expect_rgba_eq(t, hex, to_rgba_color(Hex(0xDEADBEEF)))

			hsla, hsla_ok := to_rgba(HSLA{0, 1, 0.5, 1}, &frame, event)
			testing.expect(t, hsla_ok)
			expect_rgba_eq(t, hsla, to_rgba_color(HSLA{0, 1, 0.5, 1}))

			hwba, hwba_ok := to_rgba(HWBA{120, 0, 0, 1}, &frame, event)
			testing.expect(t, hwba_ok)
			expect_rgba_eq(t, hwba, to_rgba_color(HWBA{120, 0, 0, 1}))

			lcha, lcha_ok := to_rgba(LCHA{50, 40, 30, 1}, &frame, event)
			testing.expect(t, lcha_ok)
			expect_rgba_eq(t, lcha, to_rgba_color(LCHA{50, 40, 30, 1}))

			oklch, oklch_ok := to_rgba(OKLCHA{0.628, 0.258, 29.23, 1}, &frame, event)
			testing.expect(t, oklch_ok)
			expect_rgba_eq(t, oklch, to_rgba_color(OKLCHA{0.628, 0.258, 29.23, 1}))

			transparent, t_ok := to_rgba(Color.TRANSPARENT, &frame, event)
			testing.expect(t, t_ok)
			expect_rgba_eq(t, transparent, RGBA{0, 0, 0, 0})
		},
	)
}

@(test)
to_rgba_rejects_invalid_named_color :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()
			got, ok := to_rgba(Color.INVALID, &frame, event)
			testing.expect(t, !ok)
			expect_rgba_eq(t, got, {})
		},
	)
}

// ---------------------------------------------------------------------------
// to_rgba — INHERIT against style stack
// ---------------------------------------------------------------------------

@(test)
to_rgba_inherit_from_rgba_parent :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()
			parent := RGBA{11, 22, 33, 44}
			colors_test_push_parent_color(parent)
			defer ui_pop_style()

			got, ok := to_rgba(Color.INHERIT, &frame, event)
			testing.expect(t, ok)
			expect_rgba_eq(t, got, parent)
		},
	)
}

@(test)
to_rgba_inherit_from_named_color_parent :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()
			colors_test_push_parent_color(Color.SUCCESS)
			defer ui_pop_style()

			got, ok := to_rgba(Color.INHERIT, &frame, event)
			testing.expect(t, ok)
			expect_rgba_eq(t, got, css_color_to_rgba(.SUCCESS))
		},
	)
}

@(test)
to_rgba_inherit_from_invalid_named_parent_fails :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()
			colors_test_push_parent_color(Color.INVALID)
			defer ui_pop_style()

			got, ok := to_rgba(Color.INHERIT, &frame, event)
			testing.expect(t, !ok)
			expect_rgba_eq(t, got, {})
		},
	)
}

@(test)
to_rgba_inherit_from_inherit_named_parent_returns_empty_ok :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()
			// Parent Color.INHERIT is not INVALID, so css_color_to_rgba path runs.
			colors_test_push_parent_color(Color.INHERIT)
			defer ui_pop_style()

			got, ok := to_rgba(Color.INHERIT, &frame, event)
			testing.expect(t, ok)
			expect_rgba_eq(t, got, {})
		},
	)
}

@(test)
to_rgba_inherit_from_non_rgba_non_color_parent_fails :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			cases := []Colors {
				Hex(0xFF00FF00),
				HSLA{90, 0.5, 0.5, 1},
				HWBA{10, 0.1, 0.2, 1},
				LCHA{40, 20, 10, 1},
				OKLCHA{0.5, 0.05, 100, 1},
				colors_test_static_callback,
			}
			for parent in cases {
				colors_test_push_parent_color(parent)
				got, ok := to_rgba(Color.INHERIT, &frame, event)
				testing.expect(t, !ok)
				expect_rgba_eq(t, got, {})
				ui_pop_style()
			}
		},
	)
}

@(test)
to_rgba_inherit_uses_top_of_style_stack_not_deeper_ancestors :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()
			colors_test_push_parent_color(RGBA{1, 1, 1, 255})
			defer ui_pop_style()
			colors_test_push_parent_color(RGBA{200, 100, 50, 255})
			defer ui_pop_style()

			got, ok := to_rgba(Color.INHERIT, &frame, event)
			testing.expect(t, ok)
			expect_rgba_eq(t, got, RGBA{200, 100, 50, 255})
		},
	)
}

// ---------------------------------------------------------------------------
// to_rgba — callback procs
// ---------------------------------------------------------------------------

@(test)
to_rgba_resolves_callback_returning_static_and_named_colors :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			rgba, rgba_ok := to_rgba(colors_test_static_callback, &frame, event)
			testing.expect(t, rgba_ok)
			expect_rgba_eq(t, rgba, RGBA{10, 20, 30, 40})

			named, named_ok := to_rgba(colors_test_named_callback, &frame, event)
			testing.expect(t, named_ok)
			expect_rgba_eq(t, named, css_color_to_rgba(.PRIMARY))

			hex, hex_ok := to_rgba(colors_test_hex_callback, &frame, event)
			testing.expect(t, hex_ok)
			expect_rgba_eq(t, hex, RGBA{0xAA, 0xBB, 0xCC, 0xDD})
		},
	)
}

@(test)
to_rgba_resolves_nested_callbacks :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()
			got, ok := to_rgba(colors_test_nested_callback, &frame, event)
			testing.expect(t, ok)
			expect_rgba_eq(t, got, RGBA{10, 20, 30, 40})
		},
	)
}

@(test)
to_rgba_callback_returning_invalid_fails :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()
			got, ok := to_rgba(colors_test_invalid_callback, &frame, event)
			testing.expect(t, !ok)
			expect_rgba_eq(t, got, {})
		},
	)
}

@(test)
to_rgba_callback_returning_inherit_uses_style_parent :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()
			colors_test_push_parent_color(RGBA{77, 88, 99, 255})
			defer ui_pop_style()

			got, ok := to_rgba(colors_test_inherit_callback, &frame, event)
			testing.expect(t, ok)
			expect_rgba_eq(t, got, RGBA{77, 88, 99, 255})
		},
	)
}

@(test)
to_rgba_callback_returning_inherit_fails_without_resolvable_parent :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()
			colors_test_push_parent_color(Hex(0x01020304))
			defer ui_pop_style()

			got, ok := to_rgba(colors_test_inherit_callback, &frame, event)
			testing.expect(t, !ok)
			expect_rgba_eq(t, got, {})
		},
	)
}

// ---------------------------------------------------------------------------
// color_to_f32 — static only (procs unsupported)
// ---------------------------------------------------------------------------

@(test)
color_to_f32_converts_all_static_variants :: proc(t: ^testing.T) {
	expect_f32x4_close(
		t,
		color_to_f32(Color.BLACK),
		rgba_to_f32(css_color_to_rgba(.BLACK)),
	)
	expect_f32x4_close(
		t,
		color_to_f32(Color.PRIMARY),
		rgba_to_f32(css_color_to_rgba(.PRIMARY)),
	)
	expect_f32x4_close(t, color_to_f32(RGBA{255, 0, 128, 64}), rgba_to_f32({255, 0, 128, 64}))
	expect_f32x4_close(
		t,
		color_to_f32(Hex(0x11223344)),
		rgba_to_f32(to_rgba_color(Hex(0x11223344))),
	)
	expect_f32x4_close(
		t,
		color_to_f32(HSLA{0, 1, 0.5, 1}),
		rgba_to_f32(to_rgba_color(HSLA{0, 1, 0.5, 1})),
	)
	expect_f32x4_close(
		t,
		color_to_f32(HWBA{240, 0, 0, 1}),
		rgba_to_f32(to_rgba_color(HWBA{240, 0, 0, 1})),
	)
	expect_f32x4_close(
		t,
		color_to_f32(LCHA{50, 30, 45, 1}),
		rgba_to_f32(to_rgba_color(LCHA{50, 30, 45, 1})),
	)
	expect_f32x4_close(
		t,
		color_to_f32(OKLCHA{0.7, 0.1, 150, 0.5}),
		rgba_to_f32(to_rgba_color(OKLCHA{0.7, 0.1, 150, 0.5})),
	)
	expect_f32x4_close(t, color_to_f32(Color.TRANSPARENT), {0, 0, 0, 0})
}

@(test)
color_to_f32_invalid_and_inherit_and_proc_return_zero :: proc(t: ^testing.T) {
	expect_f32x4_close(t, color_to_f32(Color.INVALID), {})
	// INHERIT is not special-cased; css path yields empty RGBA → zero floats.
	expect_f32x4_close(t, color_to_f32(Color.INHERIT), {})
	expect_f32x4_close(t, color_to_f32(colors_test_static_callback), {})
	expect_f32x4_close(t, color_to_f32(colors_test_nested_callback), {})
}

@(test)
color_to_f32_matches_to_rgba_for_static_values :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()
			samples := []Colors {
				Color.BLUE_500,
				RGBA{12, 34, 56, 78},
				Hex(0xABCDEF12),
				HSLA{180, 0.4, 0.6, 0.8},
				HWBA{45, 0.2, 0.1, 1},
				LCHA{70, 25, 200, 1},
				OKLCHA{0.4, 0.08, 280, 1},
			}
			for sample in samples {
				rgba, ok := to_rgba(sample, &frame, event)
				testing.expect(t, ok)
				expect_f32x4_close(t, color_to_f32(sample), rgba_to_f32(rgba))
			}
		},
	)
}

@(test)
colors_union_zero_value_is_invalid_named_color :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()
			zero: Colors
			testing.expect(t, !colors_is_proc(zero))
			got, ok := to_rgba(zero, &frame, event)
			testing.expect(t, !ok)
			expect_rgba_eq(t, got, {})
			expect_f32x4_close(t, color_to_f32(zero), {})
		},
	)
}

@(test)
to_rgba_and_color_to_f32_agree_on_theme_semantic_tokens :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()
			tokens := []Color {
				.BACKGROUND,
				.FOREGROUND,
				.PRIMARY,
				.SECONDARY,
				.SUCCESS,
				.WARNING,
				.DESTRUCTIVE,
				.MUTED,
				.ACCENT,
				.BORDER,
				.INFO,
			}
			for token in tokens {
				rgba, ok := to_rgba(token, &frame, event)
				testing.expect(t, ok)
				expect_rgba_eq(t, rgba, css_color_to_rgba(token))
				expect_f32x4_close(t, color_to_f32(token), rgba_to_f32(rgba))
			}
		},
	)
}

@(test)
colors_is_proc_false_for_zero_and_true_when_assigned_through_colors_union :: proc(t: ^testing.T) {
	var_zero: Colors
	testing.expect(t, !colors_is_proc(var_zero))

	var_proc: Colors = colors_test_static_callback
	testing.expect(t, colors_is_proc(var_proc))

	var_proc = Color.PRIMARY
	testing.expect(t, !colors_is_proc(var_proc))
	var_proc = colors_test_nested_callback
	testing.expect(t, colors_is_proc(var_proc))
}

@(test)
to_rgba_forwards_widget_frame_state_into_callback :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			colors_test_callback_calls = 0
			frame := Widget_Frame_State {
				is_hovered = true,
				is_Pressed = true,
				is_focused = true,
			}
			event := Widget_Event(Widget_Frame_State) {
				frame_state = frame,
			}

			got, ok := to_rgba(colors_test_frame_aware_callback, &frame, event)
			testing.expect(t, ok)
			expect_rgba_eq(t, got, RGBA{255, 0, 0, 255})
			testing.expect_value(t, colors_test_callback_calls, 1)
			testing.expect(t, colors_test_seen_hovered)
			testing.expect(t, colors_test_seen_pressed)
			testing.expect(t, colors_test_seen_focused)
			testing.expect(t, colors_test_event_hovered)

			frame.is_hovered = false
			event.frame_state = frame
			got, ok = to_rgba(colors_test_frame_aware_callback, &frame, event)
			testing.expect(t, ok)
			expect_rgba_eq(t, got, RGBA{0, 0, 255, 255})
			testing.expect_value(t, colors_test_callback_calls, 2)
			testing.expect(t, !colors_test_seen_hovered)
		},
	)
}

@(test)
to_rgba_resolves_callbacks_returning_all_color_spaces :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			hsla, hsla_ok := to_rgba(colors_test_hsla_callback, &frame, event)
			testing.expect(t, hsla_ok)
			expect_rgba_eq(t, hsla, to_rgba_color(HSLA{0, 1, 0.5, 1}))

			hwba, hwba_ok := to_rgba(colors_test_hwba_callback, &frame, event)
			testing.expect(t, hwba_ok)
			expect_rgba_eq(t, hwba, to_rgba_color(HWBA{120, 0, 0, 1}))

			lcha, lcha_ok := to_rgba(colors_test_lcha_callback, &frame, event)
			testing.expect(t, lcha_ok)
			expect_rgba_eq(t, lcha, to_rgba_color(LCHA{50, 40, 30, 1}))

			oklch, oklch_ok := to_rgba(colors_test_oklcha_callback, &frame, event)
			testing.expect(t, oklch_ok)
			expect_rgba_eq(t, oklch, to_rgba_color(OKLCHA{0.628, 0.258, 29.23, 1}))
		},
	)
}

@(test)
to_rgba_nested_callback_returning_inherit_uses_parent :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()
			colors_test_push_parent_color(RGBA{12, 34, 56, 78})
			defer ui_pop_style()

			got, ok := to_rgba(colors_test_nested_inherit_callback, &frame, event)
			testing.expect(t, ok)
			expect_rgba_eq(t, got, RGBA{12, 34, 56, 78})
		},
	)
}

@(test)
color_to_f32_does_not_resolve_inherit_against_style_stack :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			colors_test_push_parent_color(RGBA{255, 255, 255, 255})
			defer ui_pop_style()
			// Unlike to_rgba, color_to_f32 never walks the style stack.
			expect_f32x4_close(t, color_to_f32(Color.INHERIT), {})
		},
	)
}
