package tengu

import "core:math"
import "core:testing"

expect_close :: proc(t: ^testing.T, got, want: f32, epsilon: f32 = 1e-4, loc := #caller_location) {
	testing.expectf(
		t,
		approx_eq(got, want, epsilon),
		"got=%v want=%v epsilon=%v",
		got,
		want,
		epsilon,
		loc = loc,
	)
}

expect_vec2_close :: proc(t: ^testing.T, got, want: Vec2, epsilon: f32 = 1e-4, loc := #caller_location) {
	testing.expectf(
		t,
		approx_eq(got, want, epsilon),
		"got=%v want=%v epsilon=%v",
		got,
		want,
		epsilon,
		loc = loc,
	)
}

expect_rgba_close :: proc(t: ^testing.T, got, want: RGBA, epsilon: f32 = 1e-4, loc := #caller_location) {
	testing.expectf(
		t,
		approx_eq(got, want, epsilon),
		"got=%v want=%v epsilon=%v",
		got,
		want,
		epsilon,
		loc = loc,
	)
}

// --- contracts.odin ---

@(test)
plan_substeps_is_deterministic :: proc(t: ^testing.T) {
	policy := Time_Policy {
		max_dt       = 0.1,
		max_substeps = 4,
	}

	plan := plan_substeps(0.35, policy)
	testing.expect_value(t, plan.steps, 4)
	expect_close(t, plan.total_dt, 0.35)
	expect_close(t, plan.substep_dt, 0.0875)

	clamped := plan_substeps(1.25, policy)
	testing.expect_value(t, clamped.steps, 4)
	expect_close(t, clamped.total_dt, 0.4)
	expect_close(t, clamped.substep_dt, 0.1)
}

@(test)
plan_substeps_rejects_non_positive_input :: proc(t: ^testing.T) {
	policy := Time_Policy {
		max_dt       = 0.1,
		max_substeps = 4,
	}

	non_positive_dt := [2]f32{-0.01, 0.0}
	for dt in non_positive_dt {
		plan := plan_substeps(dt, policy)
		testing.expect_value(t, plan.steps, 0)
		expect_close(t, plan.total_dt, 0)
		expect_close(t, plan.substep_dt, 0)
	}

	invalid_policy := Time_Policy {
		max_dt       = 0,
		max_substeps = 4,
	}
	plan := plan_substeps(0.5, invalid_policy)
	testing.expect_value(t, plan.steps, 0)
}

@(test)
is_done_respects_distance_and_speed :: proc(t: ^testing.T) {
	policy := Completion_Policy {
		distance_epsilon     = 0.01,
		rest_speed_threshold = 0.05,
		snap_to_target       = true,
	}

	testing.expect(t, is_done(0.005, 0.01, policy))
	testing.expect(t, !is_done(0.02, 0.01, policy))
	testing.expect(t, !is_done(0.005, 0.1, policy))
}

@(test)
snap_if_done_snaps_only_when_enabled :: proc(t: ^testing.T) {
	target := f32(10)
	value := f32(9.9999)

	snapping := Completion_Policy {
		distance_epsilon     = 0.01,
		rest_speed_threshold = 0.05,
		snap_to_target       = true,
	}
	testing.expect_value(t, snap_if_done(value, target, true, snapping), target)
	testing.expect_value(t, snap_if_done(value, target, false, snapping), value)

	no_snap := Completion_Policy {
		distance_epsilon     = 0.01,
		rest_speed_threshold = 0.05,
		snap_to_target       = false,
	}
	testing.expect_value(t, snap_if_done(value, target, true, no_snap), value)
}

@(test)
step_results_carry_expected_fields :: proc(t: ^testing.T) {
	value := value_result(f32(3), true)
	testing.expect_value(t, value.value, f32(3))
	testing.expect_value(t, value.done, true)
	testing.expect_value(t, value.has_velocity, false)

	motion := motion_result(Vec2{1, 2}, Vec2{0.5, -0.5}, false)
	testing.expect(t, approx_eq(motion.value, Vec2{1, 2}))
	testing.expect(t, approx_eq(motion.velocity, Vec2{0.5, -0.5}))
	testing.expect_value(t, motion.has_velocity, true)
	testing.expect_value(t, motion.done, false)
}

// --- math.odin ---

@(test)
clamp_wrap_and_progress :: proc(t: ^testing.T) {
	expect_close(t, clamp(5, 0, 3), 3)
	expect_close(t, clamp(-1, 0, 3), 0)

	expect_close(t, wrap(5, 3), 2)
	expect_close(t, wrap(-1, 3), 2)
	expect_close(t, wrap(0, 0), 0)

	expect_close(t, wrap_range(13, 10, 20), 13)
	expect_close(t, wrap_range(21, 10, 20), 11)
	expect_close(t, wrap_range(10, 10, 10), 10)

	expect_close(t, inverse_lerp(0, 10, 5), 0.5)
	expect_close(t, inverse_lerp(5, 5, 7), 0)
	expect_close(t, progress(0, 10, 15), 1)
	expect_close(t, progress(0, 10, -2), 0)
	expect_close(t, lerp(0, 10, 0.25), 2.5)
}

@(test)
shortest_angle_and_mix_angle :: proc(t: ^testing.T) {
	expect_close(t, shortest_angle_delta_deg(350, 10), 20)
	expect_close(t, shortest_angle_delta_deg(10, 350), -20)
	expect_close(t, mix_angle_deg(350, 10, 0.5), 360)
	expect_close(t, mix_angle_deg(0, 90, 0.5), 45)

	pi := f32(math.PI)
	expect_close(t, shortest_angle_delta_rad(0, pi), pi)
	expect_close(t, mix_angle_rad(0, pi, 0.5), pi * 0.5)
}

@(test)
bezier_helpers_sample_curve :: proc(t: ^testing.T) {
	expect_close(t, bezier_sample_1d(0.25, 0.75, 0), 0)
	expect_close(t, bezier_sample_1d(0.25, 0.75, 1), 1)
	expect_close(t, ease_out_bounce(0), 0)
}

EASE_GOLDEN_SAMPLES :: [5]f32{0.0, 0.25, 0.5, 0.75, 1.0}

Ease_Golden :: struct {
	kind:   Ease,
	values: [5]f32,
}

// Reference outputs at EASE_GOLDEN_SAMPLES, generated from the easing formulas in math.odin.
EASE_GOLDEN_VALUES := [?]Ease_Golden {
	{.LINEAR, {0, 0.25, 0.5, 0.75, 1}},
	{.IN_SINE, {0, 0.0761204675, 0.292893219, 0.617316568, 1}},
	{.OUT_SINE, {0, 0.382683432, 0.707106781, 0.923879533, 1}},
	{.IN_OUT_SINE, {0, 0.146446609, 0.5, 0.853553391, 1}},
	{.IN_QUAD, {0, 0.0625, 0.25, 0.5625, 1}},
	{.OUT_QUAD, {0, 0.4375, 0.75, 0.9375, 1}},
	{.IN_OUT_QUAD, {0, 0.125, 0.5, 0.875, 1}},
	{.IN_CUBIC, {0, 0.015625, 0.125, 0.421875, 1}},
	{.OUT_CUBIC, {0, 0.578125, 0.875, 0.984375, 1}},
	{.IN_OUT_CUBIC, {0, 0.0625, 0.5, 0.9375, 1}},
	{.IN_QUART, {0, 0.00390625, 0.0625, 0.31640625, 1}},
	{.OUT_QUART, {0, 0.68359375, 0.9375, 0.99609375, 1}},
	{.IN_OUT_QUART, {0, 0.03125, 0.5, 0.96875, 1}},
	{.IN_QUINT, {0, 0.0009765625, 0.03125, 0.237304688, 1}},
	{.OUT_QUINT, {0, 0.762695312, 0.96875, 0.999023438, 1}},
	{.IN_OUT_QUINT, {0, 0.015625, 0.5, 0.984375, 1}},
	{.IN_EXPO, {0, 0.00552427173, 0.03125, 0.176776695, 1}},
	{.OUT_EXPO, {0, 0.823223305, 0.96875, 0.994475728, 1}},
	{.IN_OUT_EXPO, {0, 0.015625, 0.5, 0.984375, 1}},
	{.IN_CIRC, {0, 0.0317541634, 0.133974596, 0.338562172, 1}},
	{.OUT_CIRC, {0, 0.661437828, 0.866025404, 0.968245837, 1}},
	{.IN_OUT_CIRC, {0, 0.0669872981, 0.5, 0.933012702, 1}},
	{.IN_BACK, {0, -0.0641365625, -0.0876975, 0.182590312, 1}},
	{.OUT_BACK, {0, 0.817409688, 1.0876975, 1.06413656, 1}},
	{.IN_OUT_BACK, {0, -0.0996818437, 0.5, 1.09968184, 1}},
	{.IN_BOUNCE, {0, 0.02734375, 0.234375, 0.52734375, 1}},
	{.OUT_BOUNCE, {0, 0.47265625, 0.765625, 0.97265625, 1}},
	{.IN_OUT_BOUNCE, {0, 0.1171875, 0.5, 0.8828125, 1}},
	{.IN_ELASTIC, {0, -0.00552427173, -0.015625, 0.0883883476, 1}},
	{.OUT_ELASTIC, {0, 0.911611652, 1.015625, 1.00552427, 1}},
	{.IN_OUT_ELASTIC, {0, 0.0119694444, 0.5, 0.988030556, 1}},
	{.CSS_EASE, {0, 0.408510591, 0.802403388, 0.960458978, 1}},
	{.CSS_EASE_IN, {0, 0.0934646507, 0.315356813, 0.621861869, 1}},
	{.CSS_EASE_OUT, {0, 0.378138131, 0.684643187, 0.906535349, 1}},
	{.CSS_EASE_IN_OUT, {0, 0.129161931, 0.5, 0.870838069, 1}},
}

@(test)
ease_matches_golden_reference_values :: proc(t: ^testing.T) {
	testing.expect_value(t, len(EASE_GOLDEN_VALUES), len(Ease))

	covered: [len(Ease)]bool

	for entry in EASE_GOLDEN_VALUES {
		covered[entry.kind] = true

		for sample, i in EASE_GOLDEN_SAMPLES {
			got := ease(entry.kind, sample)
			want := entry.values[i]
			testing.expectf(
				t,
				approx_eq(got, want, 1e-5),
				"%v at t=%v got=%v want=%v",
				entry.kind,
				sample,
				got,
				want,
			)
		}
	}

	for kind in Ease {
		testing.expectf(t, covered[kind], "missing golden values for %v", kind)
	}
}

@(test)
mix_rgba_with_policy_interpolates_premultiplied :: proc(t: ^testing.T) {
	a := RGBA{1, 0, 0, 1}
	b := RGBA{0, 0, 1, 1}
	mixed := mix_rgba_with_policy(a, b, 0.5, .PREMULTIPLIED_ALPHA)
	expect_rgba_close(t, mixed, RGBA{0.5, 0, 0.5, 1})
}

// --- builtins.odin ---

@(test)
clamp01_and_scalar_builtins :: proc(t: ^testing.T) {
	expect_close(t, clamp01(1.5), 1)
	expect_close(t, clamp01(-0.2), 0)
	expect_close(t, add_f32(2, 3), 5)
	expect_close(t, sub_f32(5, 2), 3)
	expect_close(t, scale_f32(4, 2.5), 10)
	expect_close(t, mix_f32(0, 10, 0.3), 3)
	expect_close(t, distance_f32(2, 7), 5)
}

@(test)
vector_builtins :: proc(t: ^testing.T) {
	a := Vec2{1, 2}
	b := Vec2{4, 6}
	expect_vec2_close(t, add_vec2(a, b), Vec2{5, 8})
	expect_vec2_close(t, sub_vec2(b, a), Vec2{3, 4})
	expect_vec2_close(t, scale_vec2(a, 2), Vec2{2, 4})
	expect_vec2_close(t, mix_vec2(a, b, 0.5), Vec2{2.5, 4})
	expect_close(t, distance_vec2({0, 0}, {3, 4}), 5)

	v3a := Vec3{1, 0, 2}
	v3b := Vec3{3, 4, 2}
	expect_close(t, distance_vec3(v3a, v3b), math.sqrt(f32(20)))

	v4a := Vec4{1, 0, 0, 0}
	v4b := Vec4{0, 3, 4, 0}
	expect_close(t, distance_vec4(v4a, v4b), math.sqrt(f32(26)))
}

@(test)
rgba_builtins_and_premultiply :: proc(t: ^testing.T) {
	c := RGBA{1, 0.5, 0.25, 0.5}
	premul := premultiply_rgba(c)
	expect_rgba_close(t, premul, RGBA{0.5, 0.25, 0.125, 0.5})
	expect_rgba_close(t, unpremultiply_rgba(premul), c)
	testing.expect(t, approx_eq(unpremultiply_rgba(RGBA{}), RGBA{}))

	expect_rgba_close(t, add_rgba(RGBA{1, 0, 0, 1}, RGBA{0, 1, 0, 0}), RGBA{1, 1, 0, 1})
	expect_rgba_close(t, scale_rgba(RGBA{1, 2, 3, 4}, 0.5), RGBA{0.5, 1, 1.5, 2})
	expect_rgba_close(t, mix_rgba(RGBA{1, 0, 0, 1}, RGBA{0, 0, 1, 1}, 0.5), RGBA{0.5, 0, 0.5, 1})
	expect_close(t, distance_rgba(RGBA{0, 0, 0, 0}, RGBA{3, 4, 0, 0}), 5)
}

@(test)
rect_builtins :: proc(t: ^testing.T) {
	a := Rect{1, 2, 3, 4}
	b := Rect{5, 1, 1, 2}
	expect_close(t, distance_rect(a, b), math.sqrt(f32(25)))
	expect_close(t, mix_rect(a, b, 0.5).x, 3)
	expect_close(t, mix_rect(a, b, 0.5).y, 1.5)
}

@(test)
animatable_adapters_match_builtins :: proc(t: ^testing.T) {
	f32_anim := F32_Animatable()
	expect_close(t, f32_anim.mix(0, 10, 0.5), 5)
	expect_close(t, f32_anim.distance(2, 7), 5)
	testing.expect_value(t, f32_anim.velocity_support, Velocity_Support.VALUE_TYPE)

	vec2_anim := animatable_of(Vec2{})
	expect_vec2_close(t, vec2_anim.mix(Vec2{0, 0}, Vec2{10, 20}, 0.5), Vec2{5, 10})
	expect_close(t, vec2_anim.distance(Vec2{0, 0}, Vec2{3, 4}), 5)

	rgba_anim := RGBA_Animatable()
	expect_rgba_close(
		t,
		rgba_anim.mix(RGBA{1, 0, 0, 1}, RGBA{0, 0, 1, 1}, 0.5),
		RGBA{0.5, 0, 0.5, 1},
	)

	rect_anim := animatable_of(Rect{})
	expect_close(t, rect_anim.zero().w, 0)
	expect_close(t, rect_anim.scale(Rect{1, 2, 3, 4}, 2).h, 8)
}

@(test)
approx_eq_uses_distance_epsilon :: proc(t: ^testing.T) {
	testing.expect(t, approx_eq(1, 1.00005))
	testing.expect(t, !approx_eq(1, 1.01))
	testing.expect(t, approx_eq(Vec2{1, 2}, Vec2{1.00005, 2.00005}))
}

// --- tween.odin ---

tween_f32_config :: proc(
	start, target: f32,
	duration: Seconds,
	delay: Seconds = 0,
	easing: Tween_Easing = Ease.LINEAR,
	repeat_count: int = 1,
	repeat_mode: Tween_Repeat_Mode = .RESTART,
) -> Tween_Config(f32) {
	return Tween_Config(f32) {
		start        = start,
		target       = target,
		duration     = duration,
		delay        = delay,
		easing       = easing,
		repeat_count = repeat_count,
		repeat_mode  = repeat_mode,
	}
}

step_tween :: proc(state: ^Tween_State(f32), dt: f32) -> Step_Result(f32) {
	return tween_step(state, dt, F32_Animatable())
}

@(test)
tween_linear_completes_and_snaps :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(&state, tween_f32_config(0, 10, 1.0))

	result := step_tween(&state, 0.5)
	expect_close(t, result.value, 5)
	testing.expect_value(t, result.done, false)

	result = step_tween(&state, 0.5)
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
	testing.expect(t, tween_is_finished(state))
	expect_close(t, tween_progress(state), 1)
}

@(test)
tween_delay_holds_start :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(
		&state,
		tween_f32_config(0, 10, 1.0, 0.25),
	)

	result := step_tween(&state, 0.1)
	expect_close(t, result.value, 0)
	testing.expect_value(t, result.done, false)

	result = step_tween(&state, 0.15)
	expect_close(t, result.value, 0)
	testing.expect_value(t, result.done, false)

	result = step_tween(&state, 0.25)
	expect_close(t, result.value, 2.5)
	testing.expect_value(t, result.done, false)
}

@(test)
tween_zero_duration_snaps_after_delay :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(
		&state,
		tween_f32_config(3, 9, 0, 0.1),
	)

	result := step_tween(&state, 0.05)
	expect_close(t, result.value, 3)
	testing.expect_value(t, result.done, false)

	result = step_tween(&state, 0.05)
	expect_close(t, result.value, 9)
	testing.expect_value(t, result.done, true)
}

@(test)
tween_zero_duration_without_delay :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(&state, tween_f32_config(2, 8, 0))

	result := step_tween(&state, 0)
	expect_close(t, result.value, 8)
	testing.expect_value(t, result.done, true)
}

@(test)
tween_easing_affects_midpoint :: proc(t: ^testing.T) {
	linear: Tween_State(f32)
	tween_init(
		&linear,
		tween_f32_config(0, 10, 1.0, 0, Ease.LINEAR),
	)
	quad: Tween_State(f32)
	tween_init(
		&quad,
		tween_f32_config(0, 10, 1.0, 0, Ease.IN_QUAD),
	)

	linear_result := step_tween(&linear, 0.5)
	quad_result := step_tween(&quad, 0.5)
	expect_close(t, linear_result.value, 5)
	expect_close(t, quad_result.value, 2.5)
}

@(test)
tween_bezier_easing :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(
		&state,
		tween_f32_config(0, 10, 1.0, 0, CSS_EASE),
	)

	result := step_tween(&state, 0.5)
	want := 10 * bezier_ease(CSS_EASE, 0.5)
	expect_close(t, result.value, want, 1e-3)
}

@(test)
tween_repeat_restart :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(
		&state,
		tween_f32_config(0, 10, 0.5, 0, Ease.LINEAR, 2, .RESTART),
	)

	result := step_tween(&state, 0.25)
	expect_close(t, result.value, 5)
	testing.expect_value(t, result.done, false)

	result = step_tween(&state, 0.25)
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, false)

	result = step_tween(&state, 0.25)
	expect_close(t, result.value, 5)
	testing.expect_value(t, result.done, false)

	result = step_tween(&state, 0.25)
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
}

@(test)
tween_repeat_reverse :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(
		&state,
		tween_f32_config(0, 10, 0.5, 0, Ease.LINEAR, 2, .REVERSE),
	)

	result := step_tween(&state, 0.5)
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, false)

	result = step_tween(&state, 0.5)
	expect_close(t, result.value, 0)
	testing.expect_value(t, result.done, true)
}

@(test)
tween_reverse_odd_cycles_end_at_target :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(
		&state,
		tween_f32_config(0, 10, 0.5, 0, Ease.LINEAR, 3, .REVERSE),
	)

	_ = step_tween(&state, 1.5)
	result := step_tween(&state, 0)
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
}

@(test)
tween_infinite_repeat_never_finishes :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(
		&state,
		tween_f32_config(0, 10, 0.25, 0, Ease.LINEAR, 0, .RESTART),
	)

	_ = step_tween(&state, 10)
	testing.expect(t, !tween_is_finished(state))
	result := tween_sample_at(state, state.elapsed, F32_Animatable())
	testing.expect_value(t, result.done, false)
}

@(test)
tween_seek_samples_without_stepping :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(&state, tween_f32_config(0, 10, 1.0))

	tween_seek(&state, 0.25)
	result := tween_sample_at(state, state.elapsed, F32_Animatable())
	expect_close(t, result.value, 2.5)
	testing.expect_value(t, state.elapsed, 0.25)
	testing.expect_value(t, result.done, false)

	tween_seek(&state, 1.0)
	result = tween_sample_at(state, state.elapsed, F32_Animatable())
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
}

@(test)
tween_seek_clamps_negative_elapsed :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(&state, tween_f32_config(0, 10, 1.0))
	tween_seek(&state, -1)
	testing.expect_value(t, state.elapsed, 0)
}

@(test)
tween_negative_dt_does_not_advance :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(&state, tween_f32_config(0, 10, 1.0))

	_ = step_tween(&state, 0.25)
	result := step_tween(&state, -0.1)
	expect_close(t, result.value, 2.5)
	testing.expect_value(t, state.elapsed, 0.25)
}

@(test)
tween_restart_resets_elapsed :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(&state, tween_f32_config(0, 10, 1.0))

	_ = step_tween(&state, 0.75)
	tween_restart(&state)
	testing.expect_value(t, state.elapsed, 0)

	result := step_tween(&state, 0.5)
	expect_close(t, result.value, 5)
}

@(test)
tween_reconfigure_restarts_playback :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(&state, tween_f32_config(0, 10, 1.0))
	_ = step_tween(&state, 1.0)

	tween_reconfigure(&state, tween_f32_config(0, 20, 1.0))
	testing.expect_value(t, state.elapsed, 0)
	result := step_tween(&state, 0.5)
	expect_close(t, result.value, 10)
}

@(test)
tween_vec2_values :: proc(t: ^testing.T) {
	state: Tween_State(Vec2)
	tween_init(
		&state,
		Tween_Config(Vec2) {
			start = {0, 0},
			target = {10, 20},
			duration = 1.0,
			easing = Ease.LINEAR,
			repeat_count = 1,
		},
	)

	result := tween_step(&state, 0.5, Vec2_Animatable())
	expect_vec2_close(t, result.value, Vec2{5, 10})

	result = tween_step(&state, 0.5, Vec2_Animatable())
	expect_vec2_close(t, result.value, Vec2{10, 20})
	testing.expect_value(t, result.done, true)
}

@(test)
tween_snap_can_be_disabled :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(&state, tween_f32_config(0, 10, 1.0))

	no_snap := Completion_Policy {
		distance_epsilon     = DEFAULT_DISTANCE_EPSILON,
		rest_speed_threshold = DEFAULT_REST_SPEED_THRESHOLD,
		snap_to_target       = false,
	}

	_ = tween_step(&state, 1.0, F32_Animatable(), no_snap)
	result := tween_sample_at(state, state.elapsed, F32_Animatable(), no_snap)
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
}

// --- spring.odin ---

run_spring_until_done :: proc(
	state: ^Spring_State($T),
	dt: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
	max_frames: int = 10_000,
) -> Step_Result(T) {
	result: Step_Result(T)
	for _ in 0 ..< max_frames {
		result = spring_step(state, dt, anim, completion)
		if result.done do break
	}
	return result
}

SPRING_TEST_COMPLETION :: Completion_Policy {
	distance_epsilon     = 1e-3,
	rest_speed_threshold = 1e-3,
	snap_to_target       = true,
}

step_spring :: proc(state: ^Spring_State(f32), dt: f32) -> Step_Result(f32) {
	return spring_step(state, dt, F32_Animatable())
}

@(test)
spring_reaches_target_and_snaps :: proc(t: ^testing.T) {
	state: Spring_State(f32)
	spring_init(&state, spring_config(f32(100), 200, 30, 1), 0)

	result := run_spring_until_done(&state, 1.0 / 60.0, F32_Animatable(), SPRING_TEST_COMPLETION)
	expect_close(t, result.value, 100)
	testing.expect_value(t, result.done, true)
	testing.expect_value(t, result.has_velocity, true)
	expect_close(t, result.velocity, 0)
	testing.expect(t, spring_is_at_rest(state, F32_Animatable(), SPRING_TEST_COMPLETION))
}

@(test)
spring_initial_velocity_affects_motion :: proc(t: ^testing.T) {
	no_velocity: Spring_State(f32)
	spring_init(&no_velocity, spring_config(f32(0), 200, 26, 1), 0)
	with_velocity: Spring_State(f32)
	spring_init(
		&with_velocity,
		spring_config_with_velocity(f32(0), 50, 200, 26, 1),
		0,
	)

	no_velocity_result := step_spring(&no_velocity, 0.05)
	with_velocity_result := step_spring(&with_velocity, 0.05)

	testing.expect(t, with_velocity_result.value > no_velocity_result.value)
	testing.expect(t, with_velocity_result.velocity > no_velocity_result.velocity)
}

@(test)
spring_rest_thresholds_gate_completion :: proc(t: ^testing.T) {
	state: Spring_State(f32)
	spring_init(&state, spring_config(f32(0), 200, 26, 1), 0.001)

	loose := Completion_Policy {
		distance_epsilon     = 0.01,
		rest_speed_threshold = 1.0,
		snap_to_target       = true,
	}
	strict := Completion_Policy {
		distance_epsilon     = 1e-8,
		rest_speed_threshold = 1e-8,
		snap_to_target       = true,
	}

	loose_result := spring_step(&state, 0, F32_Animatable(), loose)
	strict_result := spring_step(&state, 0, F32_Animatable(), strict)
	testing.expect_value(t, loose_result.done, true)
	testing.expect_value(t, strict_result.done, false)
}

@(test)
spring_large_dt_uses_deterministic_substeps :: proc(t: ^testing.T) {
	config := spring_config(f32(10), 180, 24, 1)

	single: Spring_State(f32)
	spring_init(&single, config, 0)
	single_result := spring_step(&single, 0.5, F32_Animatable())

	substepped: Spring_State(f32)
	spring_init(&substepped, config, 0)
	substep_plan := plan_substeps(0.5, DEFAULT_TIME_POLICY)
	substepped_result: Step_Result(f32)
	for _ in 0 ..< substep_plan.steps {
		substepped_result = spring_step(&substepped, substep_plan.substep_dt, F32_Animatable())
	}

	expect_close(t, single_result.value, substepped_result.value)
	expect_close(t, single_result.velocity, substepped_result.velocity)
	testing.expect(t, single_result.value > 0)
	testing.expect(t, single_result.value < 10)
}

@(test)
spring_mid_flight_target_change_continues_from_current_value :: proc(t: ^testing.T) {
	state: Spring_State(f32)
	spring_init(&state, spring_config(f32(100), 200, 26, 1), 0)

	_ = step_spring(&state, 0.1)
	value_before_retarget := state.value
	velocity_before_retarget := state.velocity
	testing.expect(t, value_before_retarget > 0 && value_before_retarget < 100)

	spring_set_target(&state, 50)
	testing.expect_value(t, state.value, value_before_retarget)
	testing.expect_value(t, state.velocity, velocity_before_retarget)

	result := run_spring_until_done(&state, 1.0 / 60.0, F32_Animatable(), SPRING_TEST_COMPLETION)
	expect_close(t, result.value, 50)
	testing.expect_value(t, result.done, true)
}

@(test)
spring_target_change_via_config_preserves_motion :: proc(t: ^testing.T) {
	state: Spring_State(f32)
	spring_init(&state, spring_config(f32(100), 200, 26, 1), 0)
	_ = step_spring(&state, 0.1)

	value_before := state.value
	velocity_before := state.velocity
	state.config.target = 75

	testing.expect_value(t, state.value, value_before)
	testing.expect_value(t, state.velocity, velocity_before)

	result := run_spring_until_done(&state, 1.0 / 60.0, F32_Animatable(), SPRING_TEST_COMPLETION)
	expect_close(t, result.value, 75)
	testing.expect_value(t, result.done, true)
}

@(test)
spring_reconfigure_preserves_motion :: proc(t: ^testing.T) {
	state: Spring_State(f32)
	spring_init(&state, spring_config(f32(100), 200, 26, 1), 0)
	_ = step_spring(&state, 0.1)

	value_before := state.value
	velocity_before := state.velocity
	spring_reconfigure(&state, spring_config(f32(100), 400, 40, 1))

	testing.expect_value(t, state.value, value_before)
	testing.expect_value(t, state.velocity, velocity_before)
}

@(test)
spring_restart_applies_initial_velocity :: proc(t: ^testing.T) {
	state: Spring_State(f32)
	spring_init(
		&state,
		spring_config_with_velocity(f32(0), 25, 200, 26, 1),
		10,
	)
	_ = step_spring(&state, 0.2)

	spring_restart(&state, 5)
	testing.expect_value(t, state.value, 5)
	expect_close(t, state.velocity, 25)
}

@(test)
spring_negative_dt_does_not_advance :: proc(t: ^testing.T) {
	state: Spring_State(f32)
	spring_init(&state, spring_config(f32(10), 200, 26, 1), 0)

	_ = step_spring(&state, 0.1)
	value_before := state.value
	velocity_before := state.velocity

	result := step_spring(&state, -0.05)
	testing.expect_value(t, state.value, value_before)
	testing.expect_value(t, state.velocity, velocity_before)
	expect_close(t, result.value, value_before)
	expect_close(t, result.velocity, velocity_before)
}

@(test)
spring_snap_can_be_disabled :: proc(t: ^testing.T) {
	state: Spring_State(f32)
	spring_init(&state, spring_config(f32(0), 200, 26, 1), 0.001)

	no_snap := Completion_Policy {
		distance_epsilon     = 0.01,
		rest_speed_threshold = 1.0,
		snap_to_target       = false,
	}

	result := spring_step(&state, 0, F32_Animatable(), no_snap)
	testing.expect_value(t, result.done, true)
	expect_close(t, result.value, 0.001)
}

@(test)
spring_config_from_frequency_sets_physics :: proc(t: ^testing.T) {
	config := spring_config_from_frequency(f32(10), 2, 0.8, 1)
	omega := f32(2 * math.PI) * 2
	expect_close(t, config.stiffness, omega * omega)
	expect_close(t, config.damping, 2 * 0.8 * omega)

	state: Spring_State(f32)
	spring_init(&state, config, 0)
	result := run_spring_until_done(&state, 1.0 / 60.0, F32_Animatable(), SPRING_TEST_COMPLETION)
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
}

@(test)
spring_vec2_values :: proc(t: ^testing.T) {
	state: Spring_State(Vec2)
	spring_init(
		&state,
		spring_config(Vec2{20, 40}, 200, 26, 1),
		Vec2{0, 0},
	)

	result := spring_step(&state, 1.0 / 60.0, Vec2_Animatable())
	testing.expect(t, result.value.x > 0 && result.value.y > 0)
	testing.expect_value(t, result.has_velocity, true)

	result = run_spring_until_done(&state, 1.0 / 60.0, Vec2_Animatable(), SPRING_TEST_COMPLETION)
	expect_vec2_close(t, result.value, Vec2{20, 40})
	testing.expect_value(t, result.done, true)
}

@(test)
spring_interruption_sequence_is_stable :: proc(t: ^testing.T) {
	state: Spring_State(f32)
	spring_init(&state, spring_config(f32(100), 200, 26, 1), 0)

	_ = step_spring(&state, 0.08)
	spring_set_target(&state, 80)
	_ = step_spring(&state, 0.08)
	spring_set_target(&state, 60)
	_ = step_spring(&state, 0.08)
	spring_set_target(&state, 40)

	result := run_spring_until_done(&state, 1.0 / 60.0, F32_Animatable(), SPRING_TEST_COMPLETION)
	expect_close(t, result.value, 40)
	testing.expect_value(t, result.done, true)
}

@(test)
spring_default_config_matches_package_defaults :: proc(t: ^testing.T) {
	config := spring_default_config(f32(7))
	expect_close(t, config.target, 7)
	expect_close(t, config.stiffness, DEFAULT_SPRING_STIFFNESS)
	expect_close(t, config.damping, DEFAULT_SPRING_DAMPING)
	expect_close(t, config.mass, DEFAULT_SPRING_MASS)
	expect_close(t, config.initial_velocity, 0)
}
