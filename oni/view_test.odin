package oni

import "core:math"
import "core:sync"
import "core:testing"

@(private)
expect_vec2 :: proc(t: ^testing.T, got, want: Vec2, loc := #caller_location) {
	expect_close(t, got.x, want.x, loc = loc)
	expect_close(t, got.y, want.y, loc = loc)
}

/*
Runs body with a minimal engine state whose view is `view_default()`.

Shares `test_global_state_guard` with other state-backed tests.
*/
@(private)
with_view_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	test_state: State

	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	saved_state := state
	defer {
		delete(test_state.gpu_state.batch.space_stack)
		state = saved_state
	}

	state = &test_state
	state.view = view_default()
	body(t)
}

@(private)
with_nil_state :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	saved_state := state
	state = nil
	defer {
		state = saved_state
	}
	body(t)
}

/*
Snapshots view, clears `state`, runs body, restores `state`, and asserts the view was untouched.
*/
@(private)
expect_view_unchanged_while_nil :: proc(
	t: ^testing.T,
	body: proc(t: ^testing.T),
	loc := #caller_location,
) {
	testing.expect(t, state != nil, loc = loc)
	if state == nil do return

	before := state.view
	saved := state
	state = nil
	body(t)
	state = saved

	expect_close(t, state.view.zoom, before.zoom, loc = loc)
	expect_vec2(t, state.view.pan, before.pan, loc = loc)
	expect_close(t, state.view.zoom_min, before.zoom_min, loc = loc)
	expect_close(t, state.view.zoom_max, before.zoom_max, loc = loc)
}

@(test)
view_default_uses_documented_constants :: proc(t: ^testing.T) {
	v := view_default()
	expect_close(t, v.zoom, VIEW_ZOOM_DEFAULT)
	expect_vec2(t, v.pan, {})
	expect_close(t, v.zoom_min, VIEW_ZOOM_MIN)
	expect_close(t, v.zoom_max, VIEW_ZOOM_MAX)

	expect_close(t, VIEW_ZOOM_QUANTIZE, 0.1)
	expect_close(t, VIEW_ZOOM_MIN, 0.25)
	expect_close(t, VIEW_ZOOM_MAX, 8.0)
	expect_close(t, VIEW_ZOOM_DEFAULT, 1.0)
	expect_close(t, VIEW_ZOOM_STEP, 1.1)
}

@(test)
view_quantize_zoom_snaps_to_step :: proc(t: ^testing.T) {
	expect_close(t, view_quantize_zoom(1.0), 1.0)
	expect_close(t, view_quantize_zoom(1.04), 1.0)
	// 1.05/0.1 is 10.499999 in f32, so this rounds down to 1.0.
	expect_close(t, view_quantize_zoom(1.05), 1.0)
	expect_close(t, view_quantize_zoom(1.06), 1.1)
	expect_close(t, view_quantize_zoom(1.14), 1.1)
	// Exact .5 ratio rounds away from zero: 11.5 → 12 → 1.2.
	expect_close(t, view_quantize_zoom(1.15), 1.2)
	expect_close(t, view_quantize_zoom(0.0), 0.0)
	expect_close(t, view_quantize_zoom(-0.04), 0.0)
	expect_close(t, view_quantize_zoom(-0.05), -0.1)
	expect_close(t, view_quantize_zoom(2.49), 2.5)
	expect_close(t, view_quantize_zoom(2.51), 2.5)
	expect_close(t, view_quantize_zoom(2.55), 2.6)
	// 0.25 is not on the 0.1 grid: 2.5 → 3 → 0.3.
	expect_close(t, view_quantize_zoom(VIEW_ZOOM_MIN), 0.3)
	expect_close(t, view_quantize_zoom(VIEW_ZOOM_MAX), VIEW_ZOOM_MAX)
	expect_close(t, view_quantize_zoom(0.3), 0.3)
}

@(test)
view_quantize_zoom_with_non_positive_step_returns_input :: proc(t: ^testing.T) {
	expect_close(t, view_quantize_zoom_with_step(1.37, 0), 1.37)
	expect_close(t, view_quantize_zoom_with_step(1.37, -0.1), 1.37)
	expect_close(t, view_quantize_zoom_with_step(-2.5, 0), -2.5)
	// Positive step still quantizes.
	expect_close(t, view_quantize_zoom_with_step(1.04, 0.1), 1.0)
	expect_close(t, view_quantize_zoom_with_step(1.5, 0.5), 1.5)
	expect_close(t, view_quantize_zoom_with_step(1.6, 0.5), 1.5)
	expect_close(t, view_quantize_zoom_with_step(1.75, 0.5), 2.0)
}

@(test)
view_quantize_zoom_delegates_to_default_step :: proc(t: ^testing.T) {
	expect_close(t, view_quantize_zoom(1.14), view_quantize_zoom_with_step(1.14, VIEW_ZOOM_QUANTIZE))
	expect_close(t, view_quantize_zoom(2.55), view_quantize_zoom_with_step(2.55, VIEW_ZOOM_QUANTIZE))
}

@(test)
view_effective_zoom_nil_returns_default :: proc(t: ^testing.T) {
	with_nil_state(
		t,
		proc(t: ^testing.T) {
			expect_close(t, view_effective_zoom(), VIEW_ZOOM_DEFAULT)
		},
	)
}

@(test)
view_effective_zoom_quantizes_and_clamps :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			state.view.zoom = 1.04
			expect_close(t, view_effective_zoom(), 1.0)

			state.view.zoom = 1.06
			expect_close(t, view_effective_zoom(), 1.1)

			// Stored below min: quantize to 0 then clamp up to zoom_min.
			state.view.zoom = 0.01
			expect_close(t, view_effective_zoom(), VIEW_ZOOM_MIN)

			// Stored exactly at VIEW_ZOOM_MIN: quantize lifts to 0.3 before clamp.
			state.view.zoom = VIEW_ZOOM_MIN
			expect_close(t, view_effective_zoom(), 0.3)

			state.view.zoom = 100
			expect_close(t, view_effective_zoom(), VIEW_ZOOM_MAX)

			state.view.zoom_min = 0.5
			state.view.zoom_max = 2.0
			state.view.zoom = 0.2
			expect_close(t, view_effective_zoom(), 0.5)
			state.view.zoom = 3.0
			expect_close(t, view_effective_zoom(), 2.0)
			state.view.zoom = 1.24
			expect_close(t, view_effective_zoom(), 1.2)
		},
	)
}

@(test)
view_clamp_zoom_nil_only_quantizes :: proc(t: ^testing.T) {
	with_nil_state(
		t,
		proc(t: ^testing.T) {
			expect_close(t, view_clamp_zoom(1.04), 1.0)
			expect_close(t, view_clamp_zoom(1.06), 1.1)
			// Without state limits, extreme values are only quantized.
			expect_close(t, view_clamp_zoom(0.01), 0.0)
			expect_close(t, view_clamp_zoom(99.94), 99.9)
			// 99.95/0.1 is 999.49994 in f32 → rounds to 999 → 99.9.
			expect_close(t, view_clamp_zoom(99.95), 99.9)
			expect_close(t, view_clamp_zoom(99.96), 100.0)
		},
	)
}

@(test)
view_clamp_zoom_respects_configured_limits :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			expect_close(t, view_clamp_zoom(1.0), 1.0)
			// VIEW_ZOOM_MIN quantizes above itself, then stays (still within max).
			expect_close(t, view_clamp_zoom(VIEW_ZOOM_MIN), 0.3)
			expect_close(t, view_clamp_zoom(VIEW_ZOOM_MAX), VIEW_ZOOM_MAX)
			// Below-min after quantize clamps up to the raw zoom_min (0.25).
			expect_close(t, view_clamp_zoom(0.0), VIEW_ZOOM_MIN)
			expect_close(t, view_clamp_zoom(-5.0), VIEW_ZOOM_MIN)
			expect_close(t, view_clamp_zoom(12.0), VIEW_ZOOM_MAX)

			// Quantize then clamp: 0.24 → 0.2 → min 0.25.
			expect_close(t, view_clamp_zoom(0.24), VIEW_ZOOM_MIN)
			// 8.04 → 8.0 stays at max.
			expect_close(t, view_clamp_zoom(8.04), VIEW_ZOOM_MAX)
			// 8.05 → 8.1 → clamped to max.
			expect_close(t, view_clamp_zoom(8.05), VIEW_ZOOM_MAX)

			state.view.zoom_min = 1.5
			state.view.zoom_max = 3.5
			expect_close(t, view_clamp_zoom(1.0), 1.5)
			expect_close(t, view_clamp_zoom(4.0), 3.5)
			expect_close(t, view_clamp_zoom(2.24), 2.2)
		},
	)
}

@(test)
view_set_zoom_nil_leaves_existing_view_untouched :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			view_set_zoom(2.5)
			view_set_pan({3, 4})
			state.view.zoom_min = 0.5
			state.view.zoom_max = 4

			expect_view_unchanged_while_nil(
				t,
				proc(t: ^testing.T) {
					view_set_zoom(99)
					view_set_zoom(0.01)
				},
			)
		},
	)
}

@(test)
view_set_pan_and_pan_by_nil_leave_existing_view_untouched :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			view_set_zoom(1.5)
			view_set_pan({12, -8})

			expect_view_unchanged_while_nil(
				t,
				proc(t: ^testing.T) {
					view_set_pan({0, 0})
					view_pan_by({100, -100})
				},
			)
		},
	)
}

@(test)
view_set_zoom_stores_clamped_value :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			view_set_zoom(2.0)
			expect_close(t, state.view.zoom, 2.0)
			expect_close(t, view_effective_zoom(), 2.0)

			view_set_zoom(1.04)
			expect_close(t, state.view.zoom, 1.0)

			// Clamping from below stores the raw zoom_min (0.25), which is off-grid.
			view_set_zoom(0.01)
			expect_close(t, state.view.zoom, VIEW_ZOOM_MIN)
			expect_close(t, view_effective_zoom(), 0.3)

			// Setting exactly VIEW_ZOOM_MIN stores the quantized 0.3.
			view_set_zoom(VIEW_ZOOM_MIN)
			expect_close(t, state.view.zoom, 0.3)
			expect_close(t, view_effective_zoom(), 0.3)

			view_set_zoom(99)
			expect_close(t, state.view.zoom, VIEW_ZOOM_MAX)

			state.view.zoom_min = 0.8
			state.view.zoom_max = 1.5
			view_set_zoom(0.5)
			expect_close(t, state.view.zoom, 0.8)
			view_set_zoom(3.0)
			expect_close(t, state.view.zoom, 1.5)
		},
	)
}

@(test)
view_set_pan_and_pan_by_update_offset :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			view_set_pan({12.5, -4})
			expect_vec2(t, state.view.pan, {12.5, -4})

			view_pan_by({2.5, 6})
			expect_vec2(t, state.view.pan, {15, 2})

			view_pan_by({-15, -2})
			expect_vec2(t, state.view.pan, {})

			view_set_pan({-100, 200})
			expect_vec2(t, state.view.pan, {-100, 200})
		},
	)
}

@(test)
view_screen_world_nil_returns_identity :: proc(t: ^testing.T) {
	with_nil_state(
		t,
		proc(t: ^testing.T) {
			p := Vec2{42, -7}
			expect_vec2(t, view_screen_to_world(p), p)
			expect_vec2(t, view_world_to_screen(p), p)
		},
	)
}

@(test)
view_screen_world_identity_at_default :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			p := Vec2{100, 50}
			expect_vec2(t, view_screen_to_world(p), p)
			expect_vec2(t, view_world_to_screen(p), p)
		},
	)
}

@(test)
view_screen_world_applies_zoom_and_pan :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			view_set_zoom(2)
			view_set_pan({10, 20})

			// world = (screen - pan) / zoom
			expect_vec2(t, view_screen_to_world({50, 70}), {20, 25})
			// screen = world * zoom + pan
			expect_vec2(t, view_world_to_screen({20, 25}), {50, 70})

			view_set_zoom(0.5)
			view_set_pan({-8, 4})
			expect_vec2(t, view_screen_to_world({12, 14}), {40, 20})
			expect_vec2(t, view_world_to_screen({40, 20}), {12, 14})
		},
	)
}

@(test)
view_screen_world_roundtrip :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			configs := []struct {
				zoom: f32,
				pan:  Vec2,
			}{
				{1, {}},
				{2, {10, -5}},
				{0.5, {100, 200}},
				{VIEW_ZOOM_MIN, {-3, 7}},
				{VIEW_ZOOM_MAX, {1.5, -2.25}},
				{1.5, {33.3, -44.4}},
			}
			points := []Vec2{{0, 0}, {1, 1}, {-20, 40}, {123.45, -67.89}, {800, 600}}

			for cfg in configs {
				view_set_zoom(cfg.zoom)
				view_set_pan(cfg.pan)
				for p in points {
					world := view_screen_to_world(p)
					back := view_world_to_screen(world)
					expect_vec2(t, back, p)

					screen := view_world_to_screen(p)
					round := view_screen_to_world(screen)
					expect_vec2(t, round, p)
				}
			}
		},
	)
}

@(test)
view_screen_to_world_zero_effective_zoom_returns_screen :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			// Allow effective zoom to become exactly 0.
			state.view.zoom_min = 0
			state.view.zoom_max = 8
			state.view.zoom = 0
			state.view.pan = {5, 9}

			screen := Vec2{30, 40}
			expect_vec2(t, view_screen_to_world(screen), screen)
			// world_to_screen still multiplies by 0: world*0 + pan.
			expect_vec2(t, view_world_to_screen({100, 200}), state.view.pan)
		},
	)
}

@(test)
view_zoom_mutators_nil_leave_existing_view_untouched :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			view_set_zoom(1.2)
			view_set_pan({40, 20})

			expect_view_unchanged_while_nil(
				t,
				proc(t: ^testing.T) {
					view_zoom_at_screen({100, 100}, 4)
					view_zoom_by_screen({50, 50}, 2)
					view_zoom_in_screen({10, 10})
					view_zoom_out_screen({10, 10})
					view_reset()
				},
			)
		},
	)
}

@(test)
view_zoom_at_screen_keeps_world_under_anchor :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			anchor := Vec2{200, 150}
			view_set_pan({40, 20})
			view_set_zoom(1)

			world_before := view_screen_to_world(anchor)
			view_zoom_at_screen(anchor, 2)
			expect_close(t, state.view.zoom, 2)
			expect_vec2(t, view_screen_to_world(anchor), world_before)
			expect_vec2(t, view_world_to_screen(world_before), anchor)

			view_zoom_at_screen(anchor, 0.5)
			expect_close(t, state.view.zoom, 0.5)
			expect_vec2(t, view_screen_to_world(anchor), world_before)

			// Clamped zoom still preserves the anchor.
			view_zoom_at_screen(anchor, 100)
			expect_close(t, state.view.zoom, VIEW_ZOOM_MAX)
			expect_vec2(t, view_screen_to_world(anchor), world_before)

			view_zoom_at_screen(anchor, 0.01)
			expect_close(t, state.view.zoom, VIEW_ZOOM_MIN)
			expect_vec2(t, view_screen_to_world(anchor), world_before)
		},
	)
}

@(test)
view_zoom_at_screen_updates_pan_formula :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			view_set_zoom(1)
			view_set_pan({})
			anchor := Vec2{100, 50}
			// world under anchor at zoom 1, pan 0 is the anchor itself.
			view_zoom_at_screen(anchor, 2)
			// pan = screen - world * z = 100 - 100*2, 50 - 50*2
			expect_vec2(t, state.view.pan, {-100, -50})
			expect_close(t, state.view.zoom, 2)
		},
	)
}

@(test)
view_zoom_by_screen_multiplies_around_anchor :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			anchor := Vec2{80, 60}
			view_set_zoom(1)
			view_set_pan({10, 20})
			world := view_screen_to_world(anchor)

			view_zoom_by_screen(anchor, 2)
			expect_close(t, state.view.zoom, 2)
			expect_vec2(t, view_screen_to_world(anchor), world)

			view_zoom_by_screen(anchor, 0.5)
			expect_close(t, state.view.zoom, 1)
			expect_vec2(t, view_screen_to_world(anchor), world)

			// Factor that would exceed max still clamps and keeps anchor.
			view_zoom_by_screen(anchor, 100)
			expect_close(t, state.view.zoom, VIEW_ZOOM_MAX)
			expect_vec2(t, view_screen_to_world(anchor), world)
		},
	)
}

@(test)
view_zoom_in_out_screen_use_step_and_preserve_anchor :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			anchor := Vec2{120, 80}
			view_set_zoom(1)
			view_set_pan({5, -5})
			world := view_screen_to_world(anchor)

			view_zoom_in_screen(anchor)
			expect_close(t, state.view.zoom, view_clamp_zoom(1 * VIEW_ZOOM_STEP))
			expect_vec2(t, view_screen_to_world(anchor), world)

			zoomed := state.view.zoom
			view_zoom_out_screen(anchor)
			expect_close(t, state.view.zoom, view_clamp_zoom(zoomed / VIEW_ZOOM_STEP))
			expect_vec2(t, view_screen_to_world(anchor), world)

			// From default, out then in should return near 1 after quantize/clamp.
			view_reset()
			world = view_screen_to_world(anchor)
			view_zoom_out_screen(anchor)
			expect_close(t, state.view.zoom, view_clamp_zoom(1 / VIEW_ZOOM_STEP))
			view_zoom_in_screen(anchor)
			expect_close(t, state.view.zoom, 1.0)
			expect_vec2(t, view_screen_to_world(anchor), world)
		},
	)
}

@(test)
view_zoom_in_out_hit_limits :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			anchor := Vec2{50, 50}
			view_set_zoom(VIEW_ZOOM_MAX)
			world_at_max := view_screen_to_world(anchor)
			view_zoom_in_screen(anchor)
			expect_close(t, state.view.zoom, VIEW_ZOOM_MAX)
			expect_vec2(t, view_screen_to_world(anchor), world_at_max)

			// Lowest on-grid zoom reachable via set_zoom of VIEW_ZOOM_MIN.
			view_set_zoom(VIEW_ZOOM_MIN)
			expect_close(t, state.view.zoom, 0.3)
			view_set_pan({})
			world_at_min := view_screen_to_world(anchor)
			view_zoom_out_screen(anchor)
			expect_close(t, state.view.zoom, 0.3)
			expect_vec2(t, view_screen_to_world(anchor), world_at_min)
			expect_vec2(t, world_at_min, anchor / 0.3)
		},
	)
}

@(test)
view_reset_restores_defaults :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			view_set_zoom(3)
			view_set_pan({99, -50})
			state.view.zoom_min = 0.5
			state.view.zoom_max = 2

			view_reset()
			d := view_default()
			expect_close(t, state.view.zoom, d.zoom)
			expect_vec2(t, state.view.pan, d.pan)
			expect_close(t, state.view.zoom_min, d.zoom_min)
			expect_close(t, state.view.zoom_max, d.zoom_max)
		},
	)
}

@(test)
view_transform_rect_screen_space_is_identity :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			view_set_zoom(2)
			view_set_pan({10, 20})
			r := Rect{5, 6, 7, 8}
			// Default draw space is SCREEN.
			testing.expect(t, draw_current_space() == .SCREEN)
			expect_rect(t, view_transform_rect(r), r)
		},
	)
}

@(test)
view_transform_rect_artboard_applies_view :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			view_set_zoom(2)
			view_set_pan({10, 20})
			r := Rect{5, 6, 7, 8}

			draw_push_space(.ARTBOARD)
			defer draw_pop_space()

			expect_rect(t, view_transform_rect(r), {5 * 2 + 10, 6 * 2 + 20, 7 * 2, 8 * 2})
		},
	)
}

@(test)
view_transform_rect_nested_spaces :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			view_set_zoom(3)
			view_set_pan({1, 2})
			r := Rect{10, 20, 30, 40}

			draw_push_space(.ARTBOARD)
			expect_rect(t, view_transform_rect(r), {10 * 3 + 1, 20 * 3 + 2, 30 * 3, 40 * 3})

			draw_push_space(.SCREEN)
			expect_rect(t, view_transform_rect(r), r)
			draw_pop_space()

			expect_rect(t, view_transform_rect(r), {10 * 3 + 1, 20 * 3 + 2, 30 * 3, 40 * 3})
			draw_pop_space()
			expect_rect(t, view_transform_rect(r), r)
		},
	)
}

@(test)
view_transform_point_screen_and_artboard :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			view_set_zoom(2)
			view_set_pan({10, 20})
			p := Vec2{15, 25}

			testing.expect(t, draw_current_space() == .SCREEN)
			expect_vec2(t, view_transform_point(p), p)

			draw_push_space(.ARTBOARD)
			defer draw_pop_space()
			expect_vec2(t, view_transform_point(p), view_world_to_screen(p))
			expect_vec2(t, view_transform_point(p), {15 * 2 + 10, 25 * 2 + 20})
		},
	)
}

@(test)
view_artboard_zoom_screen_vs_artboard :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			view_set_zoom(2.5)
			expect_close(t, view_artboard_zoom(), 1)

			draw_push_space(.ARTBOARD)
			expect_close(t, view_artboard_zoom(), 2.5)
			draw_pop_space()

			expect_close(t, view_artboard_zoom(), 1)

			// Off-grid stored min → effective 0.3 while drawing on the artboard.
			view_set_zoom(0.01)
			expect_close(t, state.view.zoom, VIEW_ZOOM_MIN)
			draw_push_space(.ARTBOARD)
			expect_close(t, view_artboard_zoom(), 0.3)
			draw_pop_space()
		},
	)
}

@(test)
view_artboard_zoom_nil_state_is_one :: proc(t: ^testing.T) {
	with_nil_state(
		t,
		proc(t: ^testing.T) {
			// No ARTBOARD space without state; defaults to SCREEN → 1.
			expect_close(t, view_artboard_zoom(), 1)
		},
	)
}

@(test)
draw_space_to_logical_screen_and_artboard :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			view_set_zoom(2)
			view_set_pan({10, 20})
			p := Vec2{50, 70}

			expect_vec2(t, draw_space_to_logical(p), p)

			draw_push_space(.ARTBOARD)
			defer draw_pop_space()
			expect_vec2(t, draw_space_to_logical(p), view_screen_to_world(p))
			expect_vec2(t, draw_space_to_logical(p), {20, 25})
		},
	)
}

@(test)
draw_space_to_logical_nil_is_identity :: proc(t: ^testing.T) {
	with_nil_state(
		t,
		proc(t: ^testing.T) {
			p := Vec2{9, 8}
			expect_vec2(t, draw_space_to_logical(p), p)
		},
	)
}

@(test)
view_quantized_zoom_used_consistently_across_converters :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			// Raw zoom that quantizes to 1.2.
			state.view.zoom = 1.16
			state.view.pan = {4, 8}
			z := view_effective_zoom()
			expect_close(t, z, 1.2)

			screen := Vec2{40, 80}
			world := view_screen_to_world(screen)
			expect_vec2(t, world, {(40 - 4) / z, (80 - 8) / z})
			expect_vec2(t, view_world_to_screen(world), screen)

			draw_push_space(.ARTBOARD)
			defer draw_pop_space()
			r := Rect{10, 20, 30, 40}
			expect_rect(t, view_transform_rect(r), {10 * z + 4, 20 * z + 8, 30 * z, 40 * z})
			expect_close(t, view_artboard_zoom(), z)
		},
	)
}

@(test)
view_zoom_sequence_preserves_multiple_anchors :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			anchors := []Vec2{{0, 0}, {100, 50}, {400, 300}, {-10, 20}}
			for anchor in anchors {
				view_reset()
				view_set_pan({15, -25})
				world := view_screen_to_world(anchor)

				view_zoom_in_screen(anchor)
				view_zoom_in_screen(anchor)
				view_zoom_out_screen(anchor)
				view_zoom_by_screen(anchor, 1.5)
				view_zoom_at_screen(anchor, 0.75)
				expect_vec2(t, view_screen_to_world(anchor), world)
			}
		},
	)
}

@(test)
view_pan_independent_of_zoom :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			view_set_zoom(3)
			view_set_pan({1, 2})
			view_pan_by({3, 4})
			expect_vec2(t, state.view.pan, {4, 6})
			expect_close(t, state.view.zoom, 3)

			// set_pan replaces rather than adding.
			view_set_pan({7, 8})
			expect_vec2(t, state.view.pan, {7, 8})
		},
	)
}

@(test)
view_effective_zoom_matches_stored_after_set :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			samples := []f32{0.01, 0.25, 0.3, 1, 1.04, 1.06, 2.49, 2.55, 7.9, 8, 8.1, 50}
			for z in samples {
				view_set_zoom(z)
				expect_close(t, state.view.zoom, view_clamp_zoom(z))
				expect_close(t, view_effective_zoom(), view_clamp_zoom(view_quantize_zoom(state.view.zoom)))
				testing.expect(t, view_effective_zoom() >= state.view.zoom_min - 1e-4)
				testing.expect(t, view_effective_zoom() <= state.view.zoom_max + 1e-4)

				// Effective zoom is always on the quantization grid.
				eff := view_effective_zoom()
				step := VIEW_ZOOM_QUANTIZE
				ratio := eff / step
				testing.expectf(
					t,
					abs(ratio - math.round(ratio)) < 1e-3,
					"effective zoom %v not on quantize grid (stored=%v from set %v)",
					eff,
					state.view.zoom,
					z,
				)
			}

			// Explicit: clamping from below can store off-grid zoom_min.
			view_set_zoom(0.01)
			expect_close(t, state.view.zoom, VIEW_ZOOM_MIN)
			testing.expect(t, abs(state.view.zoom / VIEW_ZOOM_QUANTIZE - math.round(state.view.zoom / VIEW_ZOOM_QUANTIZE)) > 1e-3)
			expect_close(t, view_effective_zoom(), 0.3)
		},
	)
}

@(test)
view_zoom_by_zero_and_negative_factors_clamp :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			anchor := Vec2{100, 100}
			view_set_zoom(2)
			view_set_pan({10, 20})
			world := view_screen_to_world(anchor)

			view_zoom_by_screen(anchor, 0)
			expect_close(t, state.view.zoom, VIEW_ZOOM_MIN)
			expect_vec2(t, view_screen_to_world(anchor), world)

			view_set_zoom(2)
			view_set_pan({10, 20})
			world = view_screen_to_world(anchor)
			view_zoom_by_screen(anchor, -1)
			// Negative zoom quantizes then clamps to min.
			expect_close(t, state.view.zoom, VIEW_ZOOM_MIN)
			expect_vec2(t, view_screen_to_world(anchor), world)
		},
	)
}

@(test)
view_set_zoom_does_not_mutate_pan :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			view_set_pan({12, -34})
			view_set_zoom(2)
			expect_vec2(t, state.view.pan, {12, -34})
			view_set_zoom(0.5)
			expect_vec2(t, state.view.pan, {12, -34})
		},
	)
}

@(test)
view_transform_rect_zero_and_negative_extents :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			view_set_zoom(2)
			view_set_pan({5, 7})
			draw_push_space(.ARTBOARD)
			defer draw_pop_space()

			expect_rect(t, view_transform_rect({10, 20, 0, 0}), {25, 47, 0, 0})
			expect_rect(t, view_transform_rect({10, 20, -4, 6}), {25, 47, -8, 12})
		},
	)
}

@(test)
view_custom_limits_affect_zoom_at_screen :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			state.view.zoom_min = 1
			state.view.zoom_max = 2
			anchor := Vec2{80, 40}
			view_set_zoom(1.5)
			view_set_pan({})
			world := view_screen_to_world(anchor)

			view_zoom_at_screen(anchor, 0.1)
			expect_close(t, state.view.zoom, 1)
			expect_vec2(t, view_screen_to_world(anchor), world)

			view_zoom_at_screen(anchor, 9)
			expect_close(t, state.view.zoom, 2)
			expect_vec2(t, view_screen_to_world(anchor), world)
		},
	)
}

@(test)
view_transform_rect_nil_state_returns_identity :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			view_set_zoom(2)
			view_set_pan({10, 20})
			r := Rect{5, 6, 7, 8}

			// With state: artboard transforms.
			draw_push_space(.ARTBOARD)
			expect_rect(t, view_transform_rect(r), {20, 32, 14, 16})
			draw_pop_space()

			// Nil state: early return (space is SCREEN without state).
			saved := state
			state = nil
			expect_rect(t, view_transform_rect(r), r)
			expect_vec2(t, view_transform_point({1, 2}), {1, 2})
			expect_close(t, view_artboard_zoom(), 1)
			expect_vec2(t, draw_space_to_logical({9, 8}), {9, 8})
			state = saved
		},
	)
}

@(test)
view_zoom_by_screen_multiplies_stored_not_effective_zoom :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			anchor := Vec2{100, 50}
			// Clamp-from-below stores off-grid 0.25 while effective is 0.3.
			view_set_zoom(0.01)
			expect_close(t, state.view.zoom, VIEW_ZOOM_MIN)
			expect_close(t, view_effective_zoom(), 0.3)
			view_set_pan({10, 20})
			world := view_screen_to_world(anchor)

			// zoom_by multiplies stored zoom (0.25 * 2 = 0.5), not effective (0.3 * 2).
			view_zoom_by_screen(anchor, 2)
			expect_close(t, state.view.zoom, 0.5)
			expect_close(t, view_effective_zoom(), 0.5)
			expect_vec2(t, view_screen_to_world(anchor), world)

			// Confirm it was not 0.3 * 2 = 0.6.
			testing.expect(t, abs(state.view.zoom - 0.6) > 1e-3)
		},
	)
}

@(test)
view_inverted_zoom_limits_clamp_behavior :: proc(t: ^testing.T) {
	with_view_env(
		t,
		proc(t: ^testing.T) {
			// min > max: clamp is min(max(z, min), max), so every value collapses to max.
			state.view.zoom_min = 4
			state.view.zoom_max = 1

			expect_close(t, view_clamp_zoom(0), 1)
			expect_close(t, view_clamp_zoom(2), 1)
			expect_close(t, view_clamp_zoom(10), 1)

			view_set_zoom(2)
			expect_close(t, state.view.zoom, 1)
			expect_close(t, view_effective_zoom(), 1)

			anchor := Vec2{30, 40}
			view_set_pan({5, 5})
			world := view_screen_to_world(anchor)
			view_zoom_at_screen(anchor, 3)
			expect_close(t, state.view.zoom, 1)
			expect_vec2(t, view_screen_to_world(anchor), world)
		},
	)
}

@(test)
view_readers_nil_are_identity_or_defaults :: proc(t: ^testing.T) {
	with_nil_state(
		t,
		proc(t: ^testing.T) {
			expect_close(t, view_effective_zoom(), VIEW_ZOOM_DEFAULT)
			expect_close(t, view_clamp_zoom(1.37), view_quantize_zoom(1.37))
			p := Vec2{11, -3}
			expect_vec2(t, view_screen_to_world(p), p)
			expect_vec2(t, view_world_to_screen(p), p)
			r := Rect{1, 2, 3, 4}
			expect_rect(t, view_transform_rect(r), r)
			expect_vec2(t, view_transform_point(p), p)
			expect_close(t, view_artboard_zoom(), 1)
			expect_vec2(t, draw_space_to_logical(p), p)
		},
	)
}
