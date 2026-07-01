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

expect_vec2_close :: proc(
	t: ^testing.T,
	got, want: Vec2,
	epsilon: f32 = 1e-4,
	loc := #caller_location,
) {
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

expect_rgba_close :: proc(
	t: ^testing.T,
	got, want: RGBA,
	epsilon: f32 = 1e-4,
	loc := #caller_location,
) {
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

expect_vec3_close :: proc(
	t: ^testing.T,
	got, want: Vec3,
	epsilon: f32 = 1e-4,
	loc := #caller_location,
) {
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

expect_vec4_close :: proc(
	t: ^testing.T,
	got, want: Vec4,
	epsilon: f32 = 1e-4,
	loc := #caller_location,
) {
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

expect_rect_close :: proc(
	t: ^testing.T,
	got, want: Rect,
	epsilon: f32 = 1e-4,
	loc := #caller_location,
) {
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
		start = start,
		target = target,
		duration = duration,
		delay = delay,
		easing = easing,
		repeat_count = repeat_count,
		repeat_mode = repeat_mode,
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
	tween_init(&state, tween_f32_config(0, 10, 1.0, 0.25))

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
	tween_init(&state, tween_f32_config(3, 9, 0, 0.1))

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
	tween_init(&linear, tween_f32_config(0, 10, 1.0, 0, Ease.LINEAR))
	quad: Tween_State(f32)
	tween_init(&quad, tween_f32_config(0, 10, 1.0, 0, Ease.IN_QUAD))

	linear_result := step_tween(&linear, 0.5)
	quad_result := step_tween(&quad, 0.5)
	expect_close(t, linear_result.value, 5)
	expect_close(t, quad_result.value, 2.5)
}

@(test)
tween_bezier_easing :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(&state, tween_f32_config(0, 10, 1.0, 0, CSS_EASE))

	result := step_tween(&state, 0.5)
	want := 10 * bezier_ease(CSS_EASE, 0.5)
	expect_close(t, result.value, want, 1e-3)
}

@(test)
tween_repeat_restart :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(&state, tween_f32_config(0, 10, 0.5, 0, Ease.LINEAR, 2, .RESTART))

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
	tween_init(&state, tween_f32_config(0, 10, 0.5, 0, Ease.LINEAR, 2, .REVERSE))

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
	tween_init(&state, tween_f32_config(0, 10, 0.5, 0, Ease.LINEAR, 3, .REVERSE))

	_ = step_tween(&state, 1.5)
	result := step_tween(&state, 0)
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
}

@(test)
tween_infinite_repeat_never_finishes :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(&state, tween_f32_config(0, 10, 0.25, 0, Ease.LINEAR, 0, .RESTART))

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
	spring_init(&with_velocity, spring_config_with_velocity(f32(0), 50, 200, 26, 1), 0)

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
	spring_init(&state, spring_config_with_velocity(f32(0), 25, 200, 26, 1), 10)
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
	spring_init(&state, spring_config(Vec2{20, 40}, 200, 26, 1), Vec2{0, 0})

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

// --- slot.odin ---

run_slot_spring_until_done :: proc(
	slot: ^Slot($T),
	target: T,
	options: Spring_Slot_Options(T),
	dt: f32,
	anim: Animatable(T),
	completion: Completion_Policy = SPRING_TEST_COMPLETION,
	max_frames: int = 10_000,
) -> Step_Result(T) {
	result: Step_Result(T)
	for _ in 0 ..< max_frames {
		result = spring_to(slot, target, dt, options, anim, completion)
		if result.done do break
	}
	return result
}

@(test)
slot_init_starts_idle_at_value :: proc(t: ^testing.T) {
	slot: Slot(f32)
	slot_init(&slot, 3, .SPRING)

	testing.expect_value(t, slot_value(slot), f32(3))
	testing.expect_value(t, slot_target(slot), f32(3))
	testing.expect(t, slot_is_done(slot))
	testing.expect(t, !slot_is_active(slot))
}

@(test)
spring_to_reaches_target_from_current :: proc(t: ^testing.T) {
	slot: Slot(f32)
	slot_init(&slot, 0, .SPRING)
	options := spring_slot_options(f32(0))

	result := run_slot_spring_until_done(&slot, 100, options, 1.0 / 60.0, F32_Animatable())
	expect_close(t, result.value, 100)
	testing.expect_value(t, result.done, true)
	testing.expect(t, slot_is_active(slot))
	testing.expect(t, slot_is_done(slot))
}

@(test)
spring_to_target_change_continues_from_current_value :: proc(t: ^testing.T) {
	slot: Slot(f32)
	slot_init(&slot, 0, .SPRING)
	options := spring_slot_options(f32(0))

	_ = spring_to(&slot, 100, 0.1, options, F32_Animatable())
	value_before := slot_value(slot)
	velocity_before := slot.spring.velocity
	testing.expect(t, value_before > 0 && value_before < 100)

	result := spring_to(&slot, 50, 0, options, F32_Animatable())
	testing.expect_value(t, slot_value(slot), value_before)
	testing.expect_value(t, slot.spring.velocity, velocity_before)
	testing.expect_value(t, result.done, false)

	result = run_slot_spring_until_done(&slot, 50, options, 1.0 / 60.0, F32_Animatable())
	expect_close(t, result.value, 50)
	testing.expect_value(t, result.done, true)
}

@(test)
spring_to_from_start_policy_restarts_on_target_change :: proc(t: ^testing.T) {
	slot: Slot(f32)
	slot_init(&slot, 0, .SPRING, .FROM_START)
	options := spring_slot_options(f32(0))

	_ = spring_to(&slot, 100, 0.1, options, F32_Animatable())
	_ = spring_to(&slot, 100, 0.1, options, F32_Animatable())

	options = spring_slot_options(f32(25))
	_ = spring_to(&slot, 75, 0, options, F32_Animatable())
	expect_close(t, slot_value(slot), 25)
	expect_close(t, slot.spring.velocity, 0)
}

@(test)
spring_to_config_change_preserves_motion :: proc(t: ^testing.T) {
	slot: Slot(f32)
	slot_init(&slot, 0, .SPRING)
	options := spring_slot_options(f32(0))

	_ = spring_to(&slot, 100, 0.1, options, F32_Animatable())
	value_before := slot_value(slot)
	velocity_before := slot.spring.velocity

	stiffer := spring_slot_options(f32(0), 400, 40, 1)
	_ = spring_to(&slot, 100, 0, stiffer, F32_Animatable())

	testing.expect_value(t, slot_value(slot), value_before)
	testing.expect_value(t, slot.spring.velocity, velocity_before)
	expect_close(t, slot.spring.config.stiffness, 400)
}

@(test)
tween_to_completes_and_reports_done :: proc(t: ^testing.T) {
	slot: Slot(f32)
	slot_init(&slot, 0, .TWEEN)
	options := tween_slot_options(f32(0), 1.0)

	result := tween_to(&slot, 10, 0.5, options, F32_Animatable())
	expect_close(t, result.value, 5)
	testing.expect_value(t, result.done, false)
	testing.expect(t, slot_is_active(slot))

	result = tween_to(&slot, 10, 0.5, options, F32_Animatable())
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
	testing.expect(t, slot_is_done(slot))
}

@(test)
tween_to_target_change_restarts_from_current_value :: proc(t: ^testing.T) {
	slot: Slot(f32)
	slot_init(&slot, 0, .TWEEN)
	options := tween_slot_options(f32(0), 1.0)

	_ = tween_to(&slot, 10, 0.5, options, F32_Animatable())
	expect_close(t, slot_value(slot), 5)

	result := tween_to(&slot, 20, 0, options, F32_Animatable())
	expect_close(t, result.value, 5)
	testing.expect_value(t, slot.tween.config.start, f32(5))
	testing.expect_value(t, slot.tween.config.target, f32(20))
	testing.expect_value(t, slot.tween.elapsed, f32(0))

	result = tween_to(&slot, 20, 0.5, options, F32_Animatable())
	expect_close(t, result.value, 12.5)
}

@(test)
tween_to_from_start_policy_uses_explicit_start :: proc(t: ^testing.T) {
	slot: Slot(f32)
	slot_init(&slot, 0, .TWEEN, .FROM_START)
	options := tween_slot_options(f32(5), 1.0)

	result := tween_to(&slot, 15, 0.5, options, F32_Animatable())
	expect_close(t, result.value, 10)
	testing.expect_value(t, slot.tween.config.start, f32(5))

	options = tween_slot_options(f32(2), 1.0)
	_ = tween_to(&slot, 15, 1.0, options, F32_Animatable())
	testing.expect(t, slot_is_done(slot))

	result = tween_to(&slot, 30, 0, options, F32_Animatable())
	expect_close(t, result.value, 2)
	testing.expect_value(t, slot.tween.config.start, f32(2))
}

@(test)
tween_to_config_change_restarts_from_current_value :: proc(t: ^testing.T) {
	slot: Slot(f32)
	slot_init(&slot, 0, .TWEEN)
	options := tween_slot_options(f32(0), 1.0)

	_ = tween_to(&slot, 10, 0.5, options, F32_Animatable())
	expect_close(t, slot_value(slot), 5)

	slower := tween_slot_options(f32(0), Seconds(2.0))
	result := tween_to(&slot, 10, 0, slower, F32_Animatable())
	expect_close(t, result.value, 5)
	testing.expect_value(t, slot.tween.config.duration, Seconds(2.0))
	testing.expect_value(t, slot.tween.elapsed, f32(0))
}

@(test)
transition_to_uses_slot_kind :: proc(t: ^testing.T) {
	slot: Slot(f32)
	slot_init(&slot, 0, .TWEEN)
	slot.tween_opts = tween_slot_options(f32(0), 1.0)

	result := transition_to(&slot, 10, 0.5, F32_Animatable())
	expect_close(t, result.value, 5)

	slot_init(&slot, 0, .SPRING)
	slot.spring_opts = spring_slot_options(f32(0))
	result = transition_to(&slot, 10, 1.0 / 60.0, F32_Animatable())
	testing.expect(t, result.value > 0)
	testing.expect_value(t, result.done, false)
}

@(test)
slot_reset_clears_active_transition :: proc(t: ^testing.T) {
	slot: Slot(f32)
	slot_init(&slot, 0, .TWEEN)
	options := tween_slot_options(f32(0), 1.0)

	_ = tween_to(&slot, 10, 0.25, options, F32_Animatable())
	testing.expect(t, slot_is_active(slot))

	slot_reset(&slot, 7)
	testing.expect(t, !slot_is_active(slot))
	testing.expect(t, slot_is_done(slot))
	expect_close(t, slot_value(slot), 7)
	expect_close(t, slot_target(slot), 7)
}

@(test)
slot_restart_replays_active_transition :: proc(t: ^testing.T) {
	slot: Slot(f32)
	slot_init(&slot, 0, .TWEEN)
	options := tween_slot_options(f32(0), 1.0)

	_ = tween_to(&slot, 10, 0.75, options, F32_Animatable())
	expect_close(t, slot_value(slot), 7.5)

	slot_restart(&slot)
	testing.expect_value(t, slot.tween.elapsed, f32(0))
	expect_close(t, slot_value(slot), 7.5)
	testing.expect_value(t, slot.tween.config.start, f32(7.5))

	result := tween_to(&slot, 10, 0.25, options, F32_Animatable())
	expect_close(t, result.value, 8.125)
}

@(test)
slot_mode_switch_reinitializes_animator :: proc(t: ^testing.T) {
	slot: Slot(f32)
	slot_init(&slot, 0, .SPRING)
	spring_opts := spring_slot_options(f32(0))

	_ = spring_to(&slot, 10, 0.1, spring_opts, F32_Animatable())
	spring_value := slot_value(slot)

	tween_opts := tween_slot_options(f32(0), 1.0)
	result := tween_to(&slot, 20, 0, tween_opts, F32_Animatable())
	testing.expect_value(t, slot.kind, Transition_Kind.TWEEN)
	expect_close(t, result.value, spring_value)
	testing.expect_value(t, slot.tween.config.target, f32(20))
}

@(test)
spring_to_vec2_slot :: proc(t: ^testing.T) {
	slot: Slot(Vec2)
	slot_init(&slot, Vec2{0, 0}, .SPRING)
	options := spring_slot_options(Vec2{0, 0})

	result := run_slot_spring_until_done(
		&slot,
		Vec2{20, 40},
		options,
		1.0 / 60.0,
		Vec2_Animatable(),
	)
	expect_vec2_close(t, result.value, Vec2{20, 40})
	testing.expect_value(t, result.done, true)
}

@(test)
tween_to_same_target_and_config_does_not_restart :: proc(t: ^testing.T) {
	slot: Slot(f32)
	slot_init(&slot, 0, .TWEEN)
	options := tween_slot_options(f32(0), 1.0)

	_ = tween_to(&slot, 10, 0.25, options, F32_Animatable())
	elapsed_before := slot.tween.elapsed

	_ = tween_to(&slot, 10, 0.25, options, F32_Animatable())
	testing.expect_value(t, slot.tween.elapsed, elapsed_before + 0.25)
}

@(test)
spring_slot_options_from_frequency_sets_physics :: proc(t: ^testing.T) {
	options := spring_slot_options_from_frequency(f32(0), 2, 0.8, 1)
	omega := f32(2 * math.PI) * 2
	expect_close(t, options.stiffness, omega * omega)
	expect_close(t, options.damping, 2 * 0.8 * omega)
}

@(test)
slot_set_start_policy_affects_next_target_change :: proc(t: ^testing.T) {
	slot: Slot(f32)
	slot_init(&slot, 0, .SPRING, .FROM_CURRENT)
	options := spring_slot_options(f32(0))

	_ = spring_to(&slot, 100, 0.1, options, F32_Animatable())
	mid_value := slot_value(slot)

	slot_set_start_policy(&slot, .FROM_START)
	options = spring_slot_options(f32(4))
	_ = spring_to(&slot, 40, 0, options, F32_Animatable())
	expect_close(t, slot_value(slot), 4)

	_ = spring_to(&slot, 40, 0.05, options, F32_Animatable())
	testing.expect(t, slot_value(slot) != mid_value)
}

// --- keyframes.odin ---

keyframes_f32_stops :: proc(stops: []Keyframe_Stop(f32)) -> Keyframes_Spec(f32) {
	return keyframes_spec_duration(f32(0), stops)
}

compile_keyframes_f32 :: proc(stops: []Keyframe_Stop(f32), allocator := context.allocator) -> Keyframes_Config(f32) {
	spec := keyframes_f32_stops(stops)
	config, err := keyframes_compile(spec, allocator)
	if err != .NONE do panic("keyframes compile failed")
	return config
}

step_keyframes :: proc(state: ^Keyframes_State(f32), dt: f32) -> Step_Result(f32) {
	return keyframes_step(state, dt, F32_Animatable())
}

@(test)
keyframes_compile_duration_mode :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(f32) {
		keyframes_stop_duration(f32(10), 1.0),
		keyframes_stop_duration(f32(20), 1.0),
	}
	config, err := keyframes_compile(keyframes_f32_stops(stops))
	defer keyframes_config_destroy(config)
	testing.expect_value(t, err, Keyframes_Compile_Error.NONE)
	testing.expect_value(t, len(config.segments), 2)
	expect_close(t, config.total_duration, 2)
	expect_close(t, config.segments[0].begin, 0)
	expect_close(t, config.segments[0].duration, 1)
	expect_close(t, config.segments[1].begin, 1)
	expect_close(t, config.segments[1].duration, 1)
}

@(test)
keyframes_compile_offset_mode :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(f32) {
		keyframes_stop_offset(f32(10), 0.5),
		keyframes_stop_offset(f32(20), 1.0),
	}
	spec := keyframes_spec_offset(f32(0), stops, 2.0)
	config, err := keyframes_compile(spec)
	defer keyframes_config_destroy(config)
	testing.expect_value(t, err, Keyframes_Compile_Error.NONE)
	testing.expect_value(t, len(config.segments), 2)
	expect_close(t, config.total_duration, 2)
	expect_close(t, config.segments[0].duration, 1)
	expect_close(t, config.segments[1].duration, 1)
}

@(test)
keyframes_compile_rejects_invalid_offsets :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(f32) {
		keyframes_stop_offset(f32(10), 0.75),
		keyframes_stop_offset(f32(20), 0.5),
	}
	spec := keyframes_spec_offset(f32(0), stops, 1.0)
	_, err := keyframes_compile(spec)
	testing.expect_value(t, err, Keyframes_Compile_Error.INVALID_OFFSET_ORDER)

	out_of_range := []Keyframe_Stop(f32){keyframes_stop_offset(f32(10), 1.5)}
	spec = keyframes_spec_offset(f32(0), out_of_range, 1.0)
	_, err = keyframes_compile(spec)
	testing.expect_value(t, err, Keyframes_Compile_Error.INVALID_OFFSET_RANGE)

	_, err = keyframes_compile(keyframes_spec_offset(f32(0), out_of_range, 0))
	testing.expect_value(t, err, Keyframes_Compile_Error.INVALID_TOTAL_DURATION)
}

@(test)
keyframes_linear_completes_and_snaps :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(f32) {
		keyframes_stop_duration(f32(10), 1.0),
		keyframes_stop_duration(f32(20), 1.0),
	}
	config := compile_keyframes_f32(stops)
	defer keyframes_config_destroy(config)

	state: Keyframes_State(f32)
	keyframes_init(&state, config)

	result := step_keyframes(&state, 0.5)
	expect_close(t, result.value, 5)
	testing.expect_value(t, result.done, false)

	result = step_keyframes(&state, 0.5)
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, false)

	result = step_keyframes(&state, 1.0)
	expect_close(t, result.value, 20)
	testing.expect_value(t, result.done, true)
	testing.expect(t, keyframes_is_finished(state))
	expect_close(t, keyframes_progress(state), 1)
}

@(test)
keyframes_delay_holds_start :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(f32){keyframes_stop_duration(f32(10), 1.0)}
	spec := keyframes_spec_duration(f32(0), stops, 0.25)
	config, err := keyframes_compile(spec)
	defer keyframes_config_destroy(config)
	testing.expect_value(t, err, Keyframes_Compile_Error.NONE)

	state: Keyframes_State(f32)
	keyframes_init(&state, config)

	result := step_keyframes(&state, 0.1)
	expect_close(t, result.value, 0)
	testing.expect_value(t, result.done, false)

	result = step_keyframes(&state, 0.15)
	expect_close(t, result.value, 0)
	testing.expect_value(t, result.done, false)

	result = step_keyframes(&state, 0.25)
	expect_close(t, result.value, 2.5)
	testing.expect_value(t, result.done, false)
}

@(test)
keyframes_zero_duration_snaps_after_delay :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(f32){keyframes_stop_duration(f32(9), 0)}
	spec := keyframes_spec_duration(f32(3), stops, 0.1)
	config, err := keyframes_compile(spec)
	defer keyframes_config_destroy(config)
	testing.expect_value(t, err, Keyframes_Compile_Error.NONE)

	state: Keyframes_State(f32)
	keyframes_init(&state, config)

	result := step_keyframes(&state, 0.05)
	expect_close(t, result.value, 3)
	testing.expect_value(t, result.done, false)

	result = step_keyframes(&state, 0.05)
	expect_close(t, result.value, 9)
	testing.expect_value(t, result.done, true)
}

@(test)
keyframes_per_segment_easing :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(f32) {
		keyframes_stop_duration(f32(10), 1.0, Ease.LINEAR),
		keyframes_stop_duration(f32(20), 1.0, Ease.IN_QUAD),
	}
	config := compile_keyframes_f32(stops)
	defer keyframes_config_destroy(config)

	state: Keyframes_State(f32)
	keyframes_init(&state, config)

	result := step_keyframes(&state, 1.5)
	want := 10 + 10 * ease(Ease.IN_QUAD, 0.5)
	expect_close(t, result.value, want)
}

@(test)
keyframes_repeat_restart :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(f32){keyframes_stop_duration(f32(10), 0.5)}
	spec := keyframes_spec_duration(f32(0), stops, 0, 2, .RESTART)
	config, err := keyframes_compile(spec)
	defer keyframes_config_destroy(config)
	testing.expect_value(t, err, Keyframes_Compile_Error.NONE)

	state: Keyframes_State(f32)
	keyframes_init(&state, config)

	result := step_keyframes(&state, 0.25)
	expect_close(t, result.value, 5)
	testing.expect_value(t, result.done, false)

	result = step_keyframes(&state, 0.25)
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, false)

	result = step_keyframes(&state, 0.25)
	expect_close(t, result.value, 5)
	testing.expect_value(t, result.done, false)

	result = step_keyframes(&state, 0.25)
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
}

@(test)
keyframes_repeat_reverse :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(f32){keyframes_stop_duration(f32(10), 0.5)}
	spec := keyframes_spec_duration(f32(0), stops, 0, 2, .REVERSE)
	config, err := keyframes_compile(spec)
	defer keyframes_config_destroy(config)
	testing.expect_value(t, err, Keyframes_Compile_Error.NONE)

	state: Keyframes_State(f32)
	keyframes_init(&state, config)

	result := step_keyframes(&state, 0.5)
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, false)

	result = step_keyframes(&state, 0.5)
	expect_close(t, result.value, 0)
	testing.expect_value(t, result.done, true)
}

@(test)
keyframes_reverse_odd_cycles_end_at_last_value :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(f32){keyframes_stop_duration(f32(10), 0.5)}
	spec := keyframes_spec_duration(f32(0), stops, 0, 3, .REVERSE)
	config, err := keyframes_compile(spec)
	defer keyframes_config_destroy(config)
	testing.expect_value(t, err, Keyframes_Compile_Error.NONE)

	state: Keyframes_State(f32)
	keyframes_init(&state, config)

	_ = step_keyframes(&state, 1.5)
	result := step_keyframes(&state, 0)
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
}

@(test)
keyframes_infinite_repeat_never_finishes :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(f32){keyframes_stop_duration(f32(10), 0.25)}
	spec := keyframes_spec_duration(f32(0), stops, 0, 0, .RESTART)
	config, err := keyframes_compile(spec)
	defer keyframes_config_destroy(config)
	testing.expect_value(t, err, Keyframes_Compile_Error.NONE)

	state: Keyframes_State(f32)
	keyframes_init(&state, config)

	_ = step_keyframes(&state, 10)
	testing.expect(t, !keyframes_is_finished(state))
	result := keyframes_sample_at(state, state.elapsed, F32_Animatable())
	testing.expect_value(t, result.done, false)
}

@(test)
keyframes_seek_samples_without_stepping :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(f32) {
		keyframes_stop_duration(f32(10), 1.0),
		keyframes_stop_duration(f32(20), 1.0),
	}
	config := compile_keyframes_f32(stops)
	defer keyframes_config_destroy(config)

	state: Keyframes_State(f32)
	keyframes_init(&state, config)

	keyframes_seek(&state, 0.5)
	result := keyframes_sample_at(state, state.elapsed, F32_Animatable())
	expect_close(t, result.value, 5)
	testing.expect_value(t, state.elapsed, 0.5)
	testing.expect_value(t, result.done, false)

	keyframes_seek(&state, 2.0)
	result = keyframes_sample_at(state, state.elapsed, F32_Animatable())
	expect_close(t, result.value, 20)
	testing.expect_value(t, result.done, true)
}

@(test)
keyframes_seek_clamps_negative_elapsed :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(f32){keyframes_stop_duration(f32(10), 1.0)}
	config := compile_keyframes_f32(stops)
	defer keyframes_config_destroy(config)

	state: Keyframes_State(f32)
	keyframes_init(&state, config)
	keyframes_seek(&state, -1)
	testing.expect_value(t, state.elapsed, 0)
}

@(test)
keyframes_negative_dt_does_not_advance :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(f32){keyframes_stop_duration(f32(10), 1.0)}
	config := compile_keyframes_f32(stops)
	defer keyframes_config_destroy(config)

	state: Keyframes_State(f32)
	keyframes_init(&state, config)

	_ = step_keyframes(&state, 0.25)
	result := step_keyframes(&state, -0.1)
	expect_close(t, result.value, 2.5)
	testing.expect_value(t, state.elapsed, 0.25)
}

@(test)
keyframes_restart_resets_elapsed :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(f32){keyframes_stop_duration(f32(10), 1.0)}
	config := compile_keyframes_f32(stops)
	defer keyframes_config_destroy(config)

	state: Keyframes_State(f32)
	keyframes_init(&state, config)

	_ = step_keyframes(&state, 0.75)
	keyframes_restart(&state)
	testing.expect_value(t, state.elapsed, 0)

	result := step_keyframes(&state, 0.5)
	expect_close(t, result.value, 5)
}

@(test)
keyframes_reconfigure_restarts_playback :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(f32){keyframes_stop_duration(f32(10), 1.0)}
	config := compile_keyframes_f32(stops)
	defer keyframes_config_destroy(config)

	state: Keyframes_State(f32)
	keyframes_init(&state, config)
	_ = step_keyframes(&state, 1.0)

	new_stops := []Keyframe_Stop(f32){keyframes_stop_duration(f32(20), 1.0)}
	new_config := compile_keyframes_f32(new_stops)
	defer keyframes_config_destroy(new_config)

	keyframes_reconfigure(&state, new_config)
	testing.expect_value(t, state.elapsed, 0)
	result := step_keyframes(&state, 0.5)
	expect_close(t, result.value, 10)
}

@(test)
keyframes_empty_stops_hold_start :: proc(t: ^testing.T) {
	config, err := keyframes_compile(keyframes_f32_stops(nil))
	defer keyframes_config_destroy(config)
	testing.expect_value(t, err, Keyframes_Compile_Error.NONE)

	state: Keyframes_State(f32)
	keyframes_init(&state, config)

	result := step_keyframes(&state, 1.0)
	expect_close(t, result.value, 0)
	testing.expect_value(t, result.done, true)
}

@(test)
keyframes_vec2_values :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(Vec2) {
		keyframes_stop_duration(Vec2{10, 20}, 1.0),
	}
	spec := keyframes_spec_duration(Vec2{0, 0}, stops)
	config, err := keyframes_compile(spec)
	defer keyframes_config_destroy(config)
	testing.expect_value(t, err, Keyframes_Compile_Error.NONE)

	state: Keyframes_State(Vec2)
	keyframes_init(&state, config)

	result := keyframes_step(&state, 0.5, Vec2_Animatable())
	expect_vec2_close(t, result.value, Vec2{5, 10})

	result = keyframes_step(&state, 0.5, Vec2_Animatable())
	expect_vec2_close(t, result.value, Vec2{10, 20})
	testing.expect_value(t, result.done, true)
}

@(test)
keyframes_snap_can_be_disabled :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(f32){keyframes_stop_duration(f32(10), 1.0)}
	config := compile_keyframes_f32(stops)
	defer keyframes_config_destroy(config)

	state: Keyframes_State(f32)
	keyframes_init(&state, config)

	no_snap := Completion_Policy {
		distance_epsilon     = DEFAULT_DISTANCE_EPSILON,
		rest_speed_threshold = DEFAULT_REST_SPEED_THRESHOLD,
		snap_to_target       = false,
	}

	_ = keyframes_step(&state, 1.0, F32_Animatable(), no_snap)
	result := keyframes_sample_at(state, state.elapsed, F32_Animatable(), no_snap)
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
}

// --- decay.odin ---

run_decay_until_done :: proc(
	state: ^Decay_State($T),
	dt: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
	max_frames: int = 10_000,
) -> Step_Result(T) {
	result: Step_Result(T)
	for _ in 0 ..< max_frames {
		result = decay_step(state, dt, anim, completion)
		if result.done do break
	}
	return result
}

DECAY_TEST_COMPLETION :: Completion_Policy {
	distance_epsilon     = 1e-3,
	rest_speed_threshold = 1e-3,
	snap_to_target       = true,
}

step_decay :: proc(state: ^Decay_State(f32), dt: f32) -> Step_Result(f32) {
	return decay_step(state, dt, F32_Animatable())
}

decay_exponential_displacement :: proc(velocity, time_constant, dt: f32) -> f32 {
	safe_tau := math.max(time_constant, MIN_DECAY_TIME_CONSTANT)
	return velocity * safe_tau * (1 - math.exp(-dt / safe_tau))
}

decay_exponential_velocity :: proc(velocity, time_constant, dt: f32) -> f32 {
	safe_tau := math.max(time_constant, MIN_DECAY_TIME_CONSTANT)
	return velocity * math.exp(-dt / safe_tau)
}

@(test)
decay_reaches_rest_and_zeros_velocity :: proc(t: ^testing.T) {
	state: Decay_State(f32)
	decay_init(&state, decay_config(f32(100), 0.5), 0)

	result := run_decay_until_done(&state, 1.0 / 60.0, F32_Animatable(), DECAY_TEST_COMPLETION)
	testing.expect_value(t, result.done, true)
	testing.expect_value(t, result.has_velocity, true)
	expect_close(t, result.velocity, 0)
	testing.expect(t, result.value > 0)
	testing.expect(t, decay_is_at_rest(state, F32_Animatable(), DECAY_TEST_COMPLETION))
}

@(test)
decay_exponential_step_matches_closed_form :: proc(t: ^testing.T) {
	state: Decay_State(f32)
	decay_init(&state, decay_config(f32(80), 0.4), 5)

	result := step_decay(&state, 0.1)
	want_value := 5 + decay_exponential_displacement(80, 0.4, 0.1)
	want_velocity := decay_exponential_velocity(80, 0.4, 0.1)
	expect_close(t, result.value, want_value)
	expect_close(t, result.velocity, want_velocity)
	testing.expect_value(t, result.done, false)
}

@(test)
decay_initial_velocity_affects_motion :: proc(t: ^testing.T) {
	slow: Decay_State(f32)
	decay_init(&slow, decay_config(f32(20), 0.5), 0)
	fast: Decay_State(f32)
	decay_init(&fast, decay_config(f32(80), 0.5), 0)

	slow_result := step_decay(&slow, 0.05)
	fast_result := step_decay(&fast, 0.05)

	testing.expect(t, fast_result.value > slow_result.value)
	testing.expect(t, fast_result.velocity > slow_result.velocity)
}

@(test)
decay_rest_thresholds_gate_completion :: proc(t: ^testing.T) {
	state: Decay_State(f32)
	decay_init(&state, decay_config(f32(0.001), 0.5), 0)

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

	loose_result := decay_step(&state, 0, F32_Animatable(), loose)
	strict_result := decay_step(&state, 0, F32_Animatable(), strict)
	testing.expect_value(t, loose_result.done, true)
	testing.expect_value(t, strict_result.done, false)
}

@(test)
decay_large_dt_uses_deterministic_substeps :: proc(t: ^testing.T) {
	config := decay_config(f32(50), 0.35)

	single: Decay_State(f32)
	decay_init(&single, config, 0)
	single_result := decay_step(&single, 0.5, F32_Animatable())

	substepped: Decay_State(f32)
	decay_init(&substepped, config, 0)
	substep_plan := plan_substeps(0.5, DEFAULT_TIME_POLICY)
	substepped_result: Step_Result(f32)
	for _ in 0 ..< substep_plan.steps {
		substepped_result = decay_step(&substepped, substep_plan.substep_dt, F32_Animatable())
	}

	expect_close(t, single_result.value, substepped_result.value)
	expect_close(t, single_result.velocity, substepped_result.velocity)
	testing.expect(t, single_result.value > 0)
}

@(test)
decay_set_velocity_interrupts_from_current_value :: proc(t: ^testing.T) {
	state: Decay_State(f32)
	decay_init(&state, decay_config(f32(100), 0.5), 0)

	_ = step_decay(&state, 0.1)
	value_before := state.value
	velocity_before := state.velocity
	testing.expect(t, velocity_before > 0)

	decay_set_velocity(&state, -40)
	testing.expect_value(t, state.value, value_before)
	expect_close(t, state.velocity, -40)

	result := step_decay(&state, 0.05)
	testing.expect(t, result.value < value_before)
	testing.expect(t, result.velocity < 0)
}

@(test)
decay_reconfigure_preserves_motion :: proc(t: ^testing.T) {
	state: Decay_State(f32)
	decay_init(&state, decay_config(f32(100), 0.5), 0)
	_ = step_decay(&state, 0.1)

	value_before := state.value
	velocity_before := state.velocity
	decay_reconfigure(&state, decay_config(f32(0), 0.2))

	testing.expect_value(t, state.value, value_before)
	testing.expect_value(t, state.velocity, velocity_before)
	expect_close(t, state.config.time_constant, 0.2)
}

@(test)
decay_restart_applies_initial_velocity :: proc(t: ^testing.T) {
	state: Decay_State(f32)
	decay_init(&state, decay_config(f32(60), 0.5), 10)
	_ = step_decay(&state, 0.2)

	decay_restart(&state, 4)
	testing.expect_value(t, state.value, 4)
	expect_close(t, state.velocity, 60)
}

@(test)
decay_negative_dt_does_not_advance :: proc(t: ^testing.T) {
	state: Decay_State(f32)
	decay_init(&state, decay_config(f32(50), 0.5), 0)

	_ = step_decay(&state, 0.1)
	value_before := state.value
	velocity_before := state.velocity

	result := step_decay(&state, -0.05)
	testing.expect_value(t, state.value, value_before)
	testing.expect_value(t, state.velocity, velocity_before)
	expect_close(t, result.value, value_before)
	expect_close(t, result.velocity, velocity_before)
}

@(test)
decay_bounded_clamp_stops_at_limit :: proc(t: ^testing.T) {
	state: Decay_State(f32)
	decay_init(
		&state,
		decay_config_bounded(f32(200), 0, 50, 0.25, .CLAMP),
		0,
	)

	result := run_decay_until_done(&state, 1.0 / 60.0, F32_Animatable(), DECAY_TEST_COMPLETION)
	expect_close(t, result.value, 50)
	testing.expect_value(t, result.done, true)
	expect_close(t, result.velocity, 0)
}

@(test)
decay_bounded_bounce_reflects_velocity :: proc(t: ^testing.T) {
	state: Decay_State(f32)
	decay_init(
		&state,
		decay_config_bounded(f32(500), 0, 20, 0.15, .BOUNCE, 0.5),
		0,
	)

	result := step_decay(&state, 0.05)
	expect_close(t, result.value, 20, 1e-2)
	testing.expect(t, result.velocity < 0)
	testing.expect(t, math.abs(result.velocity) > DECAY_TEST_COMPLETION.rest_speed_threshold)
}

@(test)
decay_unbounded_negative_velocity_moves_downward :: proc(t: ^testing.T) {
	state: Decay_State(f32)
	decay_init(&state, decay_config(f32(-90), 0.4), 25)

	result := step_decay(&state, 0.1)
	testing.expect(t, result.value < 25)
	testing.expect(t, result.velocity < 0)
}

@(test)
decay_default_config_matches_package_defaults :: proc(t: ^testing.T) {
	config := decay_default_config(f32(12))
	expect_close(t, config.initial_velocity, 12)
	expect_close(t, config.time_constant, DEFAULT_DECAY_TIME_CONSTANT)
	testing.expect_value(t, config.bounds_mode, Decay_Bounds_Mode.UNBOUNDED)
	expect_close(t, config.bounce, DEFAULT_DECAY_BOUNCE)
}

@(test)
decay_vec2_values :: proc(t: ^testing.T) {
	state: Decay_State(Vec2)
	decay_init(&state, decay_config(Vec2{40, -30}, 0.45), Vec2{1, 2})

	result := decay_step(&state, 1.0 / 60.0, Vec2_Animatable())
	testing.expect(t, result.value.x > 1)
	testing.expect(t, result.value.y < 2)
	testing.expect_value(t, result.has_velocity, true)

	result = run_decay_until_done(&state, 1.0 / 60.0, Vec2_Animatable(), DECAY_TEST_COMPLETION)
	expect_close(t, result.velocity.x, 0)
	expect_close(t, result.velocity.y, 0)
	testing.expect_value(t, result.done, true)
}

@(test)
decay_vec2_bounded_clamp :: proc(t: ^testing.T) {
	state: Decay_State(Vec2)
	decay_init(
		&state,
		decay_config_bounded(
			Vec2{100, -100},
			Vec2{-10, -10},
			Vec2{10, 10},
			0.25,
			.CLAMP,
		),
		Vec2{0, 0},
	)

	result := run_decay_until_done(&state, 1.0 / 60.0, Vec2_Animatable(), DECAY_TEST_COMPLETION)
	expect_close(t, result.value.x, 10)
	expect_close(t, result.value.y, -10)
	testing.expect_value(t, result.done, true)
}

// --- compose.odin ---

compose_tween :: proc(start, target: f32, duration: Seconds) -> Tween_State(f32) {
	state: Tween_State(f32)
	tween_init(&state, tween_f32_config(start, target, duration))
	return state
}

@(test)
delay_holds_value_then_runs_child :: proc(t: ^testing.T) {
	child := compose_tween(0, 10, 1.0)
	delay_state: Delay_State(f32)
	delay_init(&delay_state, tween_stepper(&child), 0.25, 0)

	result := delay_step(&delay_state, 0.1, F32_Animatable())
	expect_close(t, result.value, 0)
	testing.expect_value(t, result.done, false)

	result = delay_step(&delay_state, 0.15, F32_Animatable())
	expect_close(t, result.value, 0)
	testing.expect_value(t, result.done, false)

	result = delay_step(&delay_state, 0.25, F32_Animatable())
	expect_close(t, result.value, 2.5)
	testing.expect_value(t, result.done, false)
}

@(test)
delay_passes_overflow_dt_to_child :: proc(t: ^testing.T) {
	child := compose_tween(0, 10, 1.0)
	delay_state: Delay_State(f32)
	delay_init(&delay_state, tween_stepper(&child), 0.2, 0)

	result := delay_step(&delay_state, 0.35, F32_Animatable())
	expect_close(t, result.value, 1.5)
	testing.expect_value(t, result.done, false)
}

@(test)
delay_stepper_wraps_tween :: proc(t: ^testing.T) {
	child := compose_tween(0, 10, 0.5)
	delay_state: Delay_State(f32)
	delay_init(&delay_state, tween_stepper(&child), 0.1, 0)

	stepper := delay_stepper(&delay_state)
	_ = stepper_step(stepper, 0.1, F32_Animatable())
	result := stepper_step(stepper, 0.25, F32_Animatable())
	expect_close(t, result.value, 5)
	testing.expect_value(t, result.done, false)
}

@(test)
sequence_runs_children_in_order :: proc(t: ^testing.T) {
	first := compose_tween(0, 10, 0.5)
	second := compose_tween(10, 20, 0.5)

	steppers := [2]Stepper(f32){tween_stepper(&first), tween_stepper(&second)}
	sequence_state: Sequence_State(f32)
	sequence_init(&sequence_state, steppers[:])

	result := sequence_step(&sequence_state, 0.25, F32_Animatable())
	expect_close(t, result.value, 5)
	testing.expect_value(t, result.done, false)

	result = sequence_step(&sequence_state, 0.25, F32_Animatable())
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, false)

	result = sequence_step(&sequence_state, 0.25, F32_Animatable())
	expect_close(t, result.value, 15)
	testing.expect_value(t, result.done, false)

	result = sequence_step(&sequence_state, 0.25, F32_Animatable())
	expect_close(t, result.value, 20)
	testing.expect_value(t, result.done, true)
}

@(test)
sequence_empty_is_immediately_done :: proc(t: ^testing.T) {
	sequence_state: Sequence_State(f32)
	sequence_init(&sequence_state, nil)

	result := sequence_step(&sequence_state, 0.1, F32_Animatable())
	expect_close(t, result.value, 0)
	testing.expect_value(t, result.done, true)
}

@(test)
parallel_steps_all_children :: proc(t: ^testing.T) {
	fast := compose_tween(0, 10, 0.5)
	slow := compose_tween(0, 100, 1.0)

	steppers := [2]Stepper(f32){tween_stepper(&fast), tween_stepper(&slow)}
	parallel_state: Parallel_State(f32)
	parallel_init(&parallel_state, steppers[:], 0)

	result := parallel_step(&parallel_state, 0.25, F32_Animatable())
	expect_close(t, result.value, 5)
	testing.expect_value(t, result.done, false)

	result = parallel_step(&parallel_state, 0.25, F32_Animatable())
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, false)

	result = parallel_step(&parallel_state, 0.5, F32_Animatable())
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
}

@(test)
repeat_restarts_child_for_finite_cycles :: proc(t: ^testing.T) {
	child := compose_tween(0, 10, 0.5)
	repeat_state: Repeat_State(f32)
	repeat_init(&repeat_state, tween_stepper(&child), 2, 0)

	result := repeat_step(&repeat_state, 0.5, F32_Animatable())
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, false)

	result = repeat_step(&repeat_state, 0.5, F32_Animatable())
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
}

@(test)
repeat_infinite_never_finishes :: proc(t: ^testing.T) {
	child := compose_tween(0, 10, 0.25)
	repeat_state: Repeat_State(f32)
	repeat_init(&repeat_state, tween_stepper(&child), 0, 0)

	_ = repeat_step(&repeat_state, 1.0, F32_Animatable())
	testing.expect(t, !repeat_is_finished(repeat_state, F32_Animatable()))
}

@(test)
stagger_offsets_child_starts :: proc(t: ^testing.T) {
	first := compose_tween(0, 10, 0.5)
	second := compose_tween(0, 20, 0.5)

	children := [2]Stepper(f32){tween_stepper(&first), tween_stepper(&second)}
	hold_values := [2]f32{0, 0}

	stagger_state: Stagger_State(f32)
	err := stagger_init(&stagger_state, children[:], hold_values[:], 0.2)
	defer stagger_destroy(stagger_state)
	testing.expect_value(t, err, Stagger_Init_Error.NONE)

	result := stagger_step(&stagger_state, 0.1, F32_Animatable())
	expect_close(t, result.value, 2)
	testing.expect_value(t, result.done, false)

	result = stagger_step(&stagger_state, 0.1, F32_Animatable())
	expect_close(t, result.value, 4)
	testing.expect_value(t, result.done, false)

	result = stagger_step(&stagger_state, 0.4, F32_Animatable())
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, false)

	result = stagger_step(&stagger_state, 0.4, F32_Animatable())
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
}

@(test)
compose_steppers_work_with_spring :: proc(t: ^testing.T) {
	spring_state: Spring_State(f32)
	spring_init(&spring_state, spring_config(f32(10), 200, 26, 1), 0)

	delay_state: Delay_State(f32)
	delay_init(&delay_state, spring_stepper(&spring_state), 0.05, 0)

	_ = delay_step(&delay_state, 0.05, F32_Animatable())
	result := run_spring_until_done(
		&spring_state,
		1.0 / 60.0,
		F32_Animatable(),
		SPRING_TEST_COMPLETION,
	)
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
}

@(test)
compose_steppers_work_with_keyframes :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(f32){keyframes_stop_duration(f32(10), 0.5)}
	config := compile_keyframes_f32(stops)
	defer keyframes_config_destroy(config)

	keyframe_state: Keyframes_State(f32)
	keyframes_init(&keyframe_state, config)

	repeat_state: Repeat_State(f32)
	repeat_init(&repeat_state, keyframes_stepper(&keyframe_state), 2, f32(0))

	result := repeat_step(&repeat_state, 0.5, F32_Animatable())
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, false)

	result = repeat_step(&repeat_state, 0.5, F32_Animatable())
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
}

@(test)
compose_steppers_work_with_decay :: proc(t: ^testing.T) {
	decay_state: Decay_State(f32)
	decay_init(&decay_state, decay_config(f32(80), 0.4), 0)

	sequence_children := [1]Stepper(f32){decay_stepper(&decay_state)}
	sequence_state: Sequence_State(f32)
	sequence_init(&sequence_state, sequence_children[:])

	result := run_decay_until_done(&decay_state, 1.0 / 60.0, F32_Animatable(), DECAY_TEST_COMPLETION)
	testing.expect_value(t, result.done, true)
	testing.expect(t, sequence_is_finished(sequence_state, F32_Animatable(), DECAY_TEST_COMPLETION))
}

@(test)
nested_sequence_of_delay_and_tween :: proc(t: ^testing.T) {
	inner := compose_tween(0, 5, 0.5)
	inner_delay: Delay_State(f32)
	delay_init(&inner_delay, tween_stepper(&inner), 0.1, 0)

	outer := compose_tween(5, 15, 0.5)
	steppers := [2]Stepper(f32){delay_stepper(&inner_delay), tween_stepper(&outer)}
	sequence_state: Sequence_State(f32)
	sequence_init(&sequence_state, steppers[:])

	_ = sequence_step(&sequence_state, 0.1, F32_Animatable())
	result := sequence_step(&sequence_state, 0.35, F32_Animatable())
	expect_close(t, result.value, 3.5)
	testing.expect_value(t, result.done, false)

	result = sequence_step(&sequence_state, 0.25, F32_Animatable())
	expect_close(t, result.value, 5)
	testing.expect_value(t, result.done, false)

	result = sequence_step(&sequence_state, 0.25, F32_Animatable())
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, false)
}

// --- timeline.odin ---

compile_timeline_f32 :: proc(
	tracks: []Timeline_Track_Spec(f32),
	labels: []Timeline_Label = nil,
	primary_index: int = 0,
	allocator := context.allocator,
) -> Timeline_Config(f32) {
	spec := timeline_spec(tracks, labels, primary_index)
	config, err := timeline_compile(spec, F32_Animatable(), allocator)
	if err != .NONE do panic("timeline compile failed")
	return config
}

init_timeline_f32 :: proc(
	state: ^Timeline_State(f32),
	tracks: []Timeline_Track_Spec(f32),
	labels: []Timeline_Label = nil,
	primary_index: int = 0,
	allocator := context.allocator,
) -> Timeline_Config(f32) {
	spec := timeline_spec(tracks, labels, primary_index)
	config := compile_timeline_f32(tracks, labels, primary_index, allocator)
	if !timeline_init(state, spec, config, allocator) do panic("timeline init failed")
	return config
}

step_timeline :: proc(state: ^Timeline_State(f32), dt: f32) -> Step_Result(f32) {
	return timeline_step(state, dt, F32_Animatable())
}

@(test)
timeline_compile_records_offsets_and_duration :: proc(t: ^testing.T) {
	first := compose_tween(0, 10, 0.5)
	second := compose_tween(0, 20, 1.0)

	tracks := [2]Timeline_Track_Spec(f32) {
		timeline_track_spec("alpha", 0, tween_stepper(&first), 0),
		timeline_track_spec("beta", 0.25, tween_stepper(&second), 0),
	}
	config := compile_timeline_f32(tracks[:])
	defer timeline_config_destroy(config)

	testing.expect_value(t, len(config.tracks), 2)
	expect_close(t, config.tracks[0].offset, 0)
	expect_close(t, config.tracks[1].offset, 0.25)
	expect_close(t, config.tracks[0].end_time, 0.5)
	expect_close(t, config.tracks[1].end_time, 1.25)
	expect_close(t, config.total_duration, 1.25)
}

@(test)
timeline_compile_rejects_duplicate_labels :: proc(t: ^testing.T) {
	first := compose_tween(0, 10, 0.5)
	tracks := [1]Timeline_Track_Spec(f32){timeline_track_spec("alpha", 0, tween_stepper(&first), 0)}
	labels := [2]Timeline_Label{timeline_label("intro", 0), timeline_label("intro", 0.25)}

	_, err := timeline_compile(timeline_spec(tracks[:], labels[:]), F32_Animatable())
	testing.expect_value(t, err, Timeline_Compile_Error.DUPLICATE_LABEL)
}

@(test)
timeline_overlapping_tracks_run_in_parallel :: proc(t: ^testing.T) {
	fast := compose_tween(0, 10, 0.5)
	slow := compose_tween(0, 100, 1.0)

	tracks := [2]Timeline_Track_Spec(f32) {
		timeline_track_spec("fast", 0, tween_stepper(&fast), 0),
		timeline_track_spec("slow", 0.25, tween_stepper(&slow), 0),
	}

	timeline_state: Timeline_State(f32)
	config := init_timeline_f32(&timeline_state, tracks[:], nil, 0)
	defer timeline_destroy(timeline_state)

	result := step_timeline(&timeline_state, 0.25)
	expect_close(t, result.value, 5)
	testing.expect_value(t, result.done, false)

	result = step_timeline(&timeline_state, 0.25)
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, false)

	result = step_timeline(&timeline_state, 0.5)
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, false)

	result = step_timeline(&timeline_state, 0.5)
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
	expect_close(t, timeline_progress(timeline_state), 1)
	_ = config
}

@(test)
timeline_primary_track_selects_returned_value :: proc(t: ^testing.T) {
	fast := compose_tween(0, 10, 0.5)
	slow := compose_tween(0, 100, 1.0)

	tracks := [2]Timeline_Track_Spec(f32) {
		timeline_track_spec("fast", 0, tween_stepper(&fast), 0),
		timeline_track_spec("slow", 0, tween_stepper(&slow), 0),
	}

	timeline_state: Timeline_State(f32)
	_ = init_timeline_f32(&timeline_state, tracks[:], nil, 1)
	defer timeline_destroy(timeline_state)

	result := step_timeline(&timeline_state, 0.25)
	expect_close(t, result.value, 25)
}

@(test)
timeline_labels_compile_and_seek :: proc(t: ^testing.T) {
	tween_state := compose_tween(0, 10, 1.0)
	tracks := [1]Timeline_Track_Spec(f32){timeline_track_spec("main", 0, tween_stepper(&tween_state), 0)}
	labels := [2]Timeline_Label{timeline_label("start", 0), timeline_label("mid", 0.5)}

	timeline_state: Timeline_State(f32)
	config := init_timeline_f32(&timeline_state, tracks[:], labels[:])
	defer timeline_destroy(timeline_state)

	time, found := timeline_label_time(config, "mid")
	testing.expect(t, found)
	expect_close(t, time, 0.5)

	testing.expect(t, timeline_seek_to_label(&timeline_state, "mid", F32_Animatable()))
	result := timeline_sample_at(&timeline_state, timeline_state.elapsed, F32_Animatable())
	expect_close(t, result.value, 5)
	testing.expect_value(t, timeline_state.elapsed, 0.5)
}

@(test)
timeline_seek_samples_without_stepping :: proc(t: ^testing.T) {
	tween_state := compose_tween(0, 10, 1.0)
	tracks := [1]Timeline_Track_Spec(f32){timeline_track_spec("main", 0, tween_stepper(&tween_state), 0)}

	timeline_state: Timeline_State(f32)
	_ = init_timeline_f32(&timeline_state, tracks[:])
	defer timeline_destroy(timeline_state)

	timeline_seek(&timeline_state, 0.25, F32_Animatable())
	result := timeline_sample_at(&timeline_state, timeline_state.elapsed, F32_Animatable())
	expect_close(t, result.value, 2.5)
	testing.expect_value(t, timeline_state.elapsed, 0.25)
	testing.expect_value(t, result.done, false)

	timeline_seek(&timeline_state, 1.0, F32_Animatable())
	result = timeline_sample_at(&timeline_state, timeline_state.elapsed, F32_Animatable())
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
}

@(test)
timeline_seek_clamps_negative_elapsed :: proc(t: ^testing.T) {
	tween_state := compose_tween(0, 10, 1.0)
	tracks := [1]Timeline_Track_Spec(f32){timeline_track_spec("main", 0, tween_stepper(&tween_state), 0)}

	timeline_state: Timeline_State(f32)
	_ = init_timeline_f32(&timeline_state, tracks[:])
	defer timeline_destroy(timeline_state)

	timeline_seek(&timeline_state, -1, F32_Animatable())
	testing.expect_value(t, timeline_state.elapsed, 0)
}

@(test)
timeline_negative_dt_does_not_advance :: proc(t: ^testing.T) {
	tween_state := compose_tween(0, 10, 1.0)
	tracks := [1]Timeline_Track_Spec(f32){timeline_track_spec("main", 0, tween_stepper(&tween_state), 0)}

	timeline_state: Timeline_State(f32)
	_ = init_timeline_f32(&timeline_state, tracks[:])
	defer timeline_destroy(timeline_state)

	_ = step_timeline(&timeline_state, 0.25)
	result := step_timeline(&timeline_state, -0.1)
	expect_close(t, result.value, 2.5)
	testing.expect_value(t, timeline_state.elapsed, 0.25)
}

@(test)
timeline_restart_resets_playback :: proc(t: ^testing.T) {
	tween_state := compose_tween(0, 10, 1.0)
	tracks := [1]Timeline_Track_Spec(f32){timeline_track_spec("main", 0, tween_stepper(&tween_state), 0)}

	timeline_state: Timeline_State(f32)
	_ = init_timeline_f32(&timeline_state, tracks[:])
	defer timeline_destroy(timeline_state)

	_ = step_timeline(&timeline_state, 0.75)
	timeline_restart(&timeline_state)
	testing.expect_value(t, timeline_state.elapsed, 0)

	result := step_timeline(&timeline_state, 0.5)
	expect_close(t, result.value, 5)
}

@(test)
timeline_empty_is_immediately_done :: proc(t: ^testing.T) {
	timeline_state: Timeline_State(f32)
	tracks: []Timeline_Track_Spec(f32)
	config := compile_timeline_f32(tracks)
	defer timeline_config_destroy(config)
	testing.expect(t, timeline_init(&timeline_state, timeline_spec(tracks), config))

	result := step_timeline(&timeline_state, 0.1)
	expect_close(t, result.value, 0)
	testing.expect_value(t, result.done, true)
	testing.expect(t, timeline_is_finished(timeline_state, F32_Animatable()))
}

@(test)
timeline_progress_reports_normalized_time :: proc(t: ^testing.T) {
	tween_state := compose_tween(0, 10, 1.0)
	tracks := [1]Timeline_Track_Spec(f32){timeline_track_spec("main", 0, tween_stepper(&tween_state), 0)}

	timeline_state: Timeline_State(f32)
	_ = init_timeline_f32(&timeline_state, tracks[:])
	defer timeline_destroy(timeline_state)

	_ = step_timeline(&timeline_state, 0.25)
	expect_close(t, timeline_progress(timeline_state), 0.25)

	_ = step_timeline(&timeline_state, 0.75)
	expect_close(t, timeline_progress(timeline_state), 1)
}

@(test)
timeline_stepper_wraps_runtime_state :: proc(t: ^testing.T) {
	tween_state := compose_tween(0, 10, 0.5)
	tracks := [1]Timeline_Track_Spec(f32){timeline_track_spec("main", 0, tween_stepper(&tween_state), 0)}

	timeline_state: Timeline_State(f32)
	_ = init_timeline_f32(&timeline_state, tracks[:])
	defer timeline_destroy(timeline_state)

	stepper := timeline_stepper(&timeline_state)
	_ = stepper_step(stepper, 0.25, F32_Animatable())
	result := stepper_step(stepper, 0.25, F32_Animatable())
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
}

@(test)
timeline_reconfigure_restarts_playback :: proc(t: ^testing.T) {
	tween_state := compose_tween(0, 10, 1.0)
	tracks := [1]Timeline_Track_Spec(f32){timeline_track_spec("main", 0, tween_stepper(&tween_state), 0)}

	timeline_state: Timeline_State(f32)
	config := init_timeline_f32(&timeline_state, tracks[:])
	defer timeline_destroy(timeline_state)

	_ = step_timeline(&timeline_state, 1.0)

	timeline_reconfigure(&timeline_state, config, F32_Animatable())
	testing.expect_value(t, timeline_state.elapsed, 0)

	result := step_timeline(&timeline_state, 0.5)
	expect_close(t, result.value, 5)
}

@(test)
timeline_offset_holds_track_value_before_start :: proc(t: ^testing.T) {
	tween_state := compose_tween(0, 10, 0.5)
	tracks := [1]Timeline_Track_Spec(f32){timeline_track_spec("main", 0.2, tween_stepper(&tween_state), 3)}

	timeline_state: Timeline_State(f32)
	_ = init_timeline_f32(&timeline_state, tracks[:])
	defer timeline_destroy(timeline_state)

	result := step_timeline(&timeline_state, 0.1)
	expect_close(t, result.value, 3)
	testing.expect_value(t, result.done, false)

	result = step_timeline(&timeline_state, 0.15)
	expect_close(t, result.value, 1)
	testing.expect_value(t, result.done, false)
}

@(test)
timeline_sequence_track_respects_offset :: proc(t: ^testing.T) {
	first := compose_tween(0, 10, 0.5)
	second := compose_tween(10, 20, 0.5)
	steppers := [2]Stepper(f32){tween_stepper(&first), tween_stepper(&second)}

	sequence_state: Sequence_State(f32)
	sequence_init(&sequence_state, steppers[:])

	tracks := [1]Timeline_Track_Spec(f32) {
		timeline_track_spec("sequence", 0.1, sequence_stepper(&sequence_state), 0),
	}

	timeline_state: Timeline_State(f32)
	_ = init_timeline_f32(&timeline_state, tracks[:])
	defer timeline_destroy(timeline_state)

	_ = step_timeline(&timeline_state, 0.1)
	result := step_timeline(&timeline_state, 0.35)
	expect_close(t, result.value, 7)
	testing.expect_value(t, result.done, false)
}

// --- diagnostics.odin ---

@(test)
tween_observability_reports_progress_elapsed_and_target :: proc(t: ^testing.T) {
	state := compose_tween(0, 10, 1.0)
	anim := F32_Animatable()

	testing.expect(t, tween_is_active(state))
	testing.expect(t, !tween_is_idle(state))
	testing.expect_value(t, tween_status(state), Animator_Status.ACTIVE)
	testing.expect_value(t, tween_target(state), f32(10))
	expect_close(t, tween_progress(state), 0)
	expect_close(t, tween_elapsed(state), 0)

	_ = tween_step(&state, 0.5, anim)
	expect_close(t, tween_progress(state), 0.5)
	expect_close(t, tween_elapsed(state), 0.5)

	_ = tween_step(&state, 0.5, anim)
	testing.expect(t, tween_is_idle(state))
	testing.expect_value(t, tween_status(state), Animator_Status.IDLE)
	expect_close(t, tween_progress(state), 1)
}

@(test)
spring_observability_reports_target_and_motion_progress :: proc(t: ^testing.T) {
	config := spring_config(f32(10))
	state: Spring_State(f32)
	spring_init(&state, config, 0)
	anim := F32_Animatable()

	testing.expect(t, spring_is_active(state, anim))
	testing.expect_value(t, spring_target(state), f32(10))
	expect_close(t, spring_progress(state, anim), 0)

	_ = run_spring_until_done(&state, 1.0 / 60.0, anim, SPRING_TEST_COMPLETION)
	testing.expect(t, spring_is_idle(state, anim))
	expect_close(t, spring_progress(state, anim), 1)
}

@(test)
decay_observability_reports_motion_progress :: proc(t: ^testing.T) {
	config := decay_config(f32(100))
	state: Decay_State(f32)
	decay_init(&state, config, 0)
	anim := F32_Animatable()

	testing.expect(t, decay_is_active(state, anim))
	expect_close(t, decay_progress(state, anim), 0)

	_ = run_decay_until_done(&state, 1.0 / 60.0, anim, DECAY_TEST_COMPLETION)
	testing.expect(t, decay_is_idle(state, anim))
	expect_close(t, decay_progress(state, anim), 1)
}

@(test)
slot_observability_reports_idle_active_and_progress :: proc(t: ^testing.T) {
	slot: Slot(f32)
	slot_init(&slot, 0, .TWEEN)
	anim := F32_Animatable()
	options := tween_slot_options(f32(0), 1.0)

	testing.expect(t, slot_is_idle(slot))
	testing.expect_value(t, slot_status(slot), Animator_Status.IDLE)
	expect_close(t, slot_progress(slot, anim), 1)
	expect_close(t, slot_elapsed(slot), 0)
	testing.expect_value(t, slot_target(slot), f32(0))

	_ = tween_to(&slot, 10, 0.5, options, anim)
	testing.expect(t, slot_is_active(slot))
	testing.expect(t, !slot_is_idle(slot))
	expect_close(t, slot_progress(slot, anim), 0.5)
	expect_close(t, slot_elapsed(slot), 0.5)
	testing.expect_value(t, slot_target(slot), f32(10))
}

@(test)
stepper_snapshot_reports_unified_fields :: proc(t: ^testing.T) {
	state := compose_tween(0, 10, 1.0)
	stepper := tween_stepper(&state)
	anim := F32_Animatable()

	_ = stepper_step(stepper, 0.25, anim)
	snapshot := stepper_snapshot(stepper, anim)

	testing.expect_value(t, snapshot.tag, Stepper_Tag.Tween)
	testing.expect_value(t, snapshot.status, Animator_Status.ACTIVE)
	expect_close(t, snapshot.progress, 0.25)
	testing.expect(t, snapshot.has_elapsed)
	expect_close(t, snapshot.elapsed, 0.25)
	expect_close(t, snapshot.value, 2.5)
	testing.expect(t, snapshot.has_target)
	expect_close(t, snapshot.target, 10)
	testing.expect_value(t, snapshot.done, false)
}

@(test)
stepper_elapsed_and_target_for_composition :: proc(t: ^testing.T) {
	child := compose_tween(0, 10, 1.0)
	delay_state: Delay_State(f32)
	delay_init(&delay_state, tween_stepper(&child), 0.5, 0)
	stepper := delay_stepper(&delay_state)
	anim := F32_Animatable()

	_ = stepper_step(stepper, 0.25, anim)
	elapsed, has_elapsed := stepper_elapsed(stepper)
	testing.expect(t, has_elapsed)
	expect_close(t, elapsed, 0.25)
	expect_close(t, stepper_progress(stepper, anim), 0.5)

	target, has_target := stepper_target(stepper, anim)
	testing.expect(t, has_target)
	expect_close(t, target, 0)

	_ = stepper_step(stepper, 0.25, anim)
	target, has_target = stepper_target(stepper, anim)
	testing.expect(t, has_target)
	expect_close(t, target, 10)
}

@(test)
sequence_progress_advances_with_child :: proc(t: ^testing.T) {
	first := compose_tween(0, 10, 1.0)
	second := compose_tween(10, 20, 1.0)
	steppers := [2]Stepper(f32){tween_stepper(&first), tween_stepper(&second)}

	sequence_state: Sequence_State(f32)
	sequence_init(&sequence_state, steppers[:])
	anim := F32_Animatable()

	expect_close(t, sequence_progress(sequence_state, anim), 0)
	_ = sequence_step(&sequence_state, 0.5, anim)
	expect_close(t, sequence_progress(sequence_state, anim), 0.25)
	_ = sequence_step(&sequence_state, 0.5, anim)
	expect_close(t, sequence_progress(sequence_state, anim), 0.5)
}

@(test)
repeat_progress_tracks_completed_cycles :: proc(t: ^testing.T) {
	child := compose_tween(0, 10, 1.0)
	repeat_state: Repeat_State(f32)
	repeat_init(&repeat_state, tween_stepper(&child), 2, 0)
	anim := F32_Animatable()

	expect_close(t, repeat_progress(repeat_state, anim), 0)
	_ = repeat_step(&repeat_state, 1.0, anim)
	expect_close(t, repeat_progress(repeat_state, anim), 0.5)
	_ = repeat_step(&repeat_state, 1.0, anim)
	expect_close(t, repeat_progress(repeat_state, anim), 1)
}

@(test)
validate_config_rejects_invalid_parameters :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		validate_tween_config(Tween_Config(f32){duration = -1}),
		Config_Validity.NEGATIVE_DURATION,
	)
	testing.expect_value(
		t,
		validate_spring_config(Spring_Config(f32){mass = 0}),
		Config_Validity.INVALID_MASS,
	)
	testing.expect_value(
		t,
		validate_decay_config(Decay_Config(f32){time_constant = 0, bounce = 2}),
		Config_Validity.INVALID_TIME_CONSTANT,
	)
	testing.expect_value(
		t,
		validate_time_policy(Time_Policy{max_dt = 0, max_substeps = 4}),
		Config_Validity.INVALID_TIME_POLICY,
	)

	valid_tween := tween_f32_config(0, 10, 1.0)
	testing.expect_value(t, validate_tween_config(valid_tween), Config_Validity.VALID)
}

@(test)
trace_hook_receives_step_events :: proc(t: ^testing.T) {
	when ODIN_DEBUG {
		Trace_Test :: struct {
			count: int,
			last:  Trace_Info(f32),
		}

		ctx: Trace_Test
		trace_fn :: proc(info: Trace_Info(f32), user_data: rawptr) {
			ctx := cast(^Trace_Test)user_data
			ctx.count += 1
			ctx.last = info
		}

		set_animation_trace_hook(f32, trace_fn, &ctx)
		defer clear_animation_trace_hook()

		state := compose_tween(0, 10, 1.0)
		result := tween_step_traced(&state, 0.25, F32_Animatable())

		testing.expect_value(t, ctx.count, 1)
		testing.expect_value(t, ctx.last.kind, Trace_Kind.STEP)
		testing.expect_value(t, ctx.last.tag, Stepper_Tag.Tween)
		expect_close(t, ctx.last.dt, 0.25)
		expect_close(t, ctx.last.value, result.value)
		testing.expect(t, ctx.last.has_target)
		expect_close(t, ctx.last.target, 10)
		testing.expect_value(t, ctx.last.done, false)
	}
}

// --- harden.odin / version.odin (phase 12) ---

fuzz_rng_next :: proc(state: ^u64) -> u64 {
	// Deterministic LCG for reproducible fuzz inputs.
	state^ = state^ * 6364136223846793005 + 1
	return state^
}

fuzz_rng_f32 :: proc(state: ^u64) -> f32 {
	bits := u32(fuzz_rng_next(state) >> 32)
	return (f32(bits) / f32(max(u32))) * 2 - 1
}

fuzz_rng_dt :: proc(state: ^u64) -> f32 {
	choice := fuzz_rng_next(state) % 7
	switch choice {
	case 0:
		return 0
	case 1:
		return -fuzz_rng_f32(state)
	case 2:
		return math.nan_f32()
	case 3:
		return math.inf_f32(32)
	case 4:
		return 1.0 / 60.0
	case 5:
		return 0.5
	case:
		return fuzz_rng_f32(state) * 2
	}
}

expect_step_finite_f32 :: proc(t: ^testing.T, result: Step_Result(f32), loc := #caller_location) {
	testing.expectf(t, step_value_is_finite(result), "non-finite step result: %v", result, loc = loc)
}

@(test)
sanitize_dt_rejects_non_finite_and_non_positive :: proc(t: ^testing.T) {
	testing.expect_value(t, sanitize_dt(0.016), 0.016)
	testing.expect_value(t, sanitize_dt(0), 0)
	testing.expect_value(t, sanitize_dt(-1), 0)
	testing.expect_value(t, sanitize_dt(math.nan_f32()), 0)
	testing.expect_value(t, sanitize_dt(math.inf_f32(32)), math.inf_f32(32))
}

@(test)
plan_substeps_rejects_nan_dt :: proc(t: ^testing.T) {
	plan := plan_substeps(math.nan_f32())
	testing.expect_value(t, plan.steps, 0)
	expect_close(t, plan.total_dt, 0)
}

@(test)
clamp01_sanitizes_non_finite :: proc(t: ^testing.T) {
	expect_close(t, clamp01(math.nan_f32()), 0)
	expect_close(t, clamp01(math.inf_f32(32)), 0)
	expect_close(t, clamp01(-math.inf_f32(32)), 0)
}

@(test)
version_reports_stable_1_0_0 :: proc(t: ^testing.T) {
	testing.expect_value(t, VERSION_MAJOR, 1)
	testing.expect_value(t, VERSION_MINOR, 0)
	testing.expect_value(t, VERSION_PATCH, 0)
	testing.expect_value(t, version_string(), "1.0.0")
	testing.expect_value(t, API_STABILITY, API_Stability.STABLE)
	testing.expect(t, version_at_least(1, 0, 0))
	testing.expect(t, version_matches(1, 0, 0))
}

@(test)
ease_non_finite_input_returns_finite :: proc(t: ^testing.T) {
	invalid := [?]f32{math.nan_f32(), math.inf_f32(32), -math.inf_f32(32)}
	for kind in Ease {
		for v in invalid {
			got := ease(kind, v)
			testing.expectf(t, is_finite_f32(got), "%v at t=%v got=%v", kind, v, got)
		}
	}
}

@(test)
fuzz_tween_step_never_produces_non_finite_values :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(&state, tween_f32_config(0, 10, 1.0))
	anim := F32_Animatable()

	rng: u64 = 0xC0FFEE
	for _ in 0 ..< 512 {
		dt := fuzz_rng_dt(&rng)
		result := tween_step(&state, dt, anim)
		expect_step_finite_f32(t, result)
	}
}

@(test)
fuzz_spring_step_never_produces_non_finite_values :: proc(t: ^testing.T) {
	state: Spring_State(f32)
	spring_init(&state, spring_config(f32(10), 180, 24, 1), 0)
	anim := F32_Animatable()

	rng: u64 = 0xBEEF
	for _ in 0 ..< 512 {
		dt := fuzz_rng_dt(&rng)
		result := spring_step(&state, dt, anim)
		expect_step_finite_f32(t, result)
	}
}

@(test)
fuzz_decay_step_never_produces_non_finite_values :: proc(t: ^testing.T) {
	state: Decay_State(f32)
	decay_init(&state, decay_config(f32(80), 0.4), 0)
	anim := F32_Animatable()

	rng: u64 = 0xDEAD
	for _ in 0 ..< 512 {
		dt := fuzz_rng_dt(&rng)
		result := decay_step(&state, dt, anim)
		expect_step_finite_f32(t, result)
	}
}

@(test)
fuzz_keyframes_step_never_produces_non_finite_values :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(f32){keyframes_stop_duration(f32(10), 1.0)}
	config := compile_keyframes_f32(stops)
	defer keyframes_config_destroy(config)

	state: Keyframes_State(f32)
	keyframes_init(&state, config)
	anim := F32_Animatable()

	rng: u64 = 0xF00D
	for _ in 0 ..< 512 {
		dt := fuzz_rng_dt(&rng)
		result := keyframes_step(&state, dt, anim)
		expect_step_finite_f32(t, result)
	}
}

@(test)
fuzz_timeline_step_never_produces_non_finite_values :: proc(t: ^testing.T) {
	tween_state := compose_tween(0, 10, 1.0)
	tracks := [1]Timeline_Track_Spec(f32){timeline_track_spec("main", 0, tween_stepper(&tween_state), 0)}

	timeline_state: Timeline_State(f32)
	_ = init_timeline_f32(&timeline_state, tracks[:])
	defer timeline_destroy(timeline_state)
	anim := F32_Animatable()

	rng: u64 = 0xFACE
	for _ in 0 ..< 256 {
		dt := fuzz_rng_dt(&rng)
		result := timeline_step(&timeline_state, dt, anim)
		expect_step_finite_f32(t, result)
	}
}

Tween_Golden_Frame :: struct {
	dt:    f32,
	value: f32,
	done:  bool,
}

// Fixed 60 fps linear tween 0 -> 10 over 1 second.
TWEEN_GOLDEN_FRAMES := [?]Tween_Golden_Frame {
	{0.2, 2, false},
	{0.2, 4, false},
	{0.2, 6, false},
	{0.2, 8, false},
	{0.2, 10, true},
}

@(test)
tween_init_defaults_missing_easing_to_linear :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(&state, Tween_Config(f32){start = 0, target = 10, duration = 1.0})

	result := step_tween(&state, 0.5)
	expect_close(t, result.value, 5)
	testing.expect_value(t, result.done, false)
}

@(test)
tween_golden_frame_sequence :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(&state, tween_f32_config(0, 10, 1.0))
	anim := F32_Animatable()

	for frame in TWEEN_GOLDEN_FRAMES {
		result := tween_step(&state, frame.dt, anim)
		expect_close(t, result.value, frame.value, 1e-5)
		testing.expect_value(t, result.done, frame.done)
	}
}

Spring_Golden_Frame :: struct {
	dt:       f32,
	value:    f32,
	velocity: f32,
}

// First five 60 fps frames of a spring toward 10 from 0.
SPRING_GOLDEN_FRAMES := [?]Spring_Golden_Frame {
	{1.0 / 60.0, 0.472222239, 28.333334},
	{1.0 / 60.0, 1.1897378, 43.050926},
	{1.0 / 60.0, 2.01237011, 49.357936},
	{1.0 / 60.0, 2.85572219, 50.601116},
	{1.0 / 60.0, 3.67098999, 48.916084},
}

@(test)
spring_golden_frame_sequence :: proc(t: ^testing.T) {
	state: Spring_State(f32)
	spring_init(&state, spring_config(f32(10), 170, 26, 1), 0)
	anim := F32_Animatable()

	for frame in SPRING_GOLDEN_FRAMES {
		result := spring_step(&state, frame.dt, anim)
		expect_close(t, result.value, frame.value, 1e-4)
		expect_close(t, result.velocity, frame.velocity, 1e-3)
		testing.expect_value(t, result.done, false)
	}
}

@(test)
tween_large_dt_jumps_to_completion :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(&state, tween_f32_config(0, 10, 0.5))

	result := step_tween(&state, 5.0)
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
}

@(test)
keyframes_large_dt_completes_deterministically :: proc(t: ^testing.T) {
	stops := []Keyframe_Stop(f32) {
		keyframes_stop_duration(f32(10), 0.5),
		keyframes_stop_duration(f32(20), 0.5),
	}
	config := compile_keyframes_f32(stops)
	defer keyframes_config_destroy(config)

	state: Keyframes_State(f32)
	keyframes_init(&state, config)

	result := step_keyframes(&state, 10)
	expect_close(t, result.value, 20)
	testing.expect_value(t, result.done, true)
}

@(test)
tween_seek_past_end_snaps_to_terminal :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(&state, tween_f32_config(0, 10, 1.0, 0, Ease.LINEAR, 2, .REVERSE))

	tween_seek(&state, 100)
	result := tween_sample_at(state, state.elapsed, F32_Animatable())
	expect_close(t, result.value, 0)
	testing.expect_value(t, result.done, true)
}

@(test)
tween_infinite_repeat_at_zero_elapsed_starts_at_start :: proc(t: ^testing.T) {
	state: Tween_State(f32)
	tween_init(&state, tween_f32_config(0, 10, 0.5, 0, Ease.LINEAR, 0, .RESTART))

	result := step_tween(&state, 0)
	expect_close(t, result.value, 0)
	testing.expect_value(t, result.done, false)
}

@(test)
spring_infinite_dt_matches_substep_cap :: proc(t: ^testing.T) {
	config := spring_config(f32(10), 180, 24, 1)

	infinite: Spring_State(f32)
	spring_init(&infinite, config, 0)
	infinite_result := spring_step(&infinite, math.inf_f32(32), F32_Animatable())

	capped: Spring_State(f32)
	spring_init(&capped, config, 0)
	max_dt := DEFAULT_TIME_POLICY.max_dt * f32(DEFAULT_TIME_POLICY.max_substeps)
	capped_result := spring_step(&capped, max_dt, F32_Animatable())

	expect_close(t, infinite_result.value, capped_result.value)
	expect_close(t, infinite_result.velocity, capped_result.velocity)
}

@(test)
slot_interruption_chain_remains_finite :: proc(t: ^testing.T) {
	slot: Slot(f32)
	slot_init(&slot, 0, .SPRING)
	options := spring_slot_options(f32(0))
	anim := F32_Animatable()

	targets := [?]f32{100, 80, 60, 40, 20, 0}
	for target in targets {
		result := spring_to(&slot, target, 0.08, options, anim)
		expect_step_finite_f32(t, result)
	}

	result := run_slot_spring_until_done(&slot, 0, options, 1.0 / 60.0, anim)
	expect_step_finite_f32(t, result)
	expect_close(t, result.value, 0)
}

@(test)
timeline_seek_past_end_is_finished :: proc(t: ^testing.T) {
	tween_state := compose_tween(0, 10, 1.0)
	tracks := [1]Timeline_Track_Spec(f32){timeline_track_spec("main", 0, tween_stepper(&tween_state), 0)}

	timeline_state: Timeline_State(f32)
	_ = init_timeline_f32(&timeline_state, tracks[:])
	defer timeline_destroy(timeline_state)
	anim := F32_Animatable()

	timeline_seek(&timeline_state, 100, anim)
	result := timeline_sample_at(&timeline_state, timeline_state.elapsed, anim)
	expect_close(t, result.value, 10)
	testing.expect_value(t, result.done, true)
	testing.expect(t, timeline_is_finished(timeline_state, anim))
}

@(test)
timeline_unknown_label_seek_fails :: proc(t: ^testing.T) {
	tween_state := compose_tween(0, 10, 1.0)
	tracks := [1]Timeline_Track_Spec(f32){timeline_track_spec("main", 0, tween_stepper(&tween_state), 0)}

	timeline_state: Timeline_State(f32)
	config := init_timeline_f32(&timeline_state, tracks[:])
	defer timeline_destroy(timeline_state)

	_, found := timeline_label_time(config, "missing")
	testing.expect(t, !found)
	testing.expect(t, !timeline_seek_to_label(&timeline_state, "missing", F32_Animatable()))
}

@(test)
timeline_primary_out_of_range_falls_back :: proc(t: ^testing.T) {
	tween_state := compose_tween(0, 10, 1.0)
	tracks := [1]Timeline_Track_Spec(f32){timeline_track_spec("main", 0, tween_stepper(&tween_state), 0)}

	spec := timeline_spec(tracks[:], nil, 99)
	config, err := timeline_compile(spec, F32_Animatable())
	defer timeline_config_destroy(config)
	testing.expect_value(t, err, Timeline_Compile_Error.NONE)
	testing.expect_value(t, config.primary_index, 0)
}

@(test)
validate_keyframes_config_rejects_negative_segment :: proc(t: ^testing.T) {
	config := Keyframes_Config(f32) {
		segments = make([]Keyframe_Segment(f32), 1),
	}
	config.segments[0].duration = -1
	defer delete(config.segments)

	testing.expect_value(t, validate_keyframes_config(config), Config_Validity.NEGATIVE_SEGMENT_DURATION)
}

@(test)
repeat_seek_edge_zero_cycles_reports_done :: proc(t: ^testing.T) {
	child := compose_tween(0, 10, 0.5)
	repeat_state: Repeat_State(f32)
	repeat_init(&repeat_state, tween_stepper(&child), 0, 0)
	anim := F32_Animatable()

	result := repeat_step(&repeat_state, 0, anim)
	expect_close(t, result.value, 0)
	testing.expect_value(t, result.done, false)
}

// --- full proc coverage ---

@(test)
zero_helpers_and_remaining_builtins :: proc(t: ^testing.T) {
	expect_close(t, f32_zero(), 0)
	expect_vec2_close(t, vec2_zero(), Vec2{})
	expect_close(t, vec3_zero().x, 0)
	expect_close(t, vec4_zero().w, 0)
	expect_rgba_close(t, rgba_zero(), RGBA{})
	expect_close(t, rect_zero().w, 0)

	v3a := Vec3{1, 2, 3}
	v3b := Vec3{4, 5, 6}
	expect_vec2_close(t, Vec2{add_vec3(v3a, v3b).x, add_vec3(v3a, v3b).y}, Vec2{5, 7})
	expect_close(t, sub_vec3(v3b, v3a).z, 3)
	expect_close(t, scale_vec3(v3a, 2).y, 4)
	expect_close(t, mix_vec3(v3a, v3b, 0.5).x, 2.5)

	v4a := Vec4{1, 2, 3, 4}
	v4b := Vec4{5, 6, 7, 8}
	expect_close(t, add_vec4(v4a, v4b).w, 12)
	expect_close(t, sub_vec4(v4b, v4a).x, 4)
	expect_close(t, scale_vec4(v4a, 0.5).z, 1.5)
	expect_close(t, mix_vec4(v4a, v4b, 0.5).y, 4)

	expect_rgba_close(t, sub_rgba(RGBA{1, 1, 1, 1}, RGBA{0.25, 0.5, 0.75, 0.25}), RGBA{0.75, 0.5, 0.25, 0.75})

	ra := Rect{1, 2, 3, 4}
	rb := Rect{5, 6, 7, 8}
	expect_close(t, add_rect(ra, rb).x, 6)
	expect_close(t, sub_rect(rb, ra).h, 4)
	expect_close(t, scale_rect(ra, 2).w, 6)
}

@(test)
animatable_factory_and_approx_eq_overloads :: proc(t: ^testing.T) {
	_ = Vec3_Animatable()
	_ = Vec4_Animatable()
	_ = Rect_Animatable()

	_ = animatable_of_f32(0)
	_ = animatable_of_vec2(Vec2{})
	_ = animatable_of_vec3(Vec3{})
	_ = animatable_of_vec4(Vec4{})
	_ = animatable_of_rgba(RGBA{})
	_ = animatable_of_rect(Rect{})

	testing.expect(t, approx_eq_f32(1, 1.00005))
	testing.expect(t, approx_eq_vec2(Vec2{1, 2}, Vec2{1, 2}))
	testing.expect(t, approx_eq_vec3(Vec3{1, 2, 3}, Vec3{1, 2, 3}))
	testing.expect(t, approx_eq_vec4(Vec4{1, 2, 3, 4}, Vec4{1, 2, 3, 4}))
	testing.expect(t, approx_eq_rgba(RGBA{1, 0, 0, 1}, RGBA{1, 0, 0, 1}))
	testing.expect(t, approx_eq_rect(Rect{1, 2, 3, 4}, Rect{1, 2, 3, 4}))

	testing.expect(t, approx_eq(1.0, 1.0))
	testing.expect(t, approx_eq(Vec2{1, 1}, Vec2{1, 1}))
	testing.expect(t, mix(0.0, 10.0, 0.5) == 5.0)
	expect_vec2_close(t, mix(Vec2{0, 0}, Vec2{10, 10}, 0.5), Vec2{5, 5})
	expect_close(t, distance(3.0, 7.0), 4.0)
	expect_close(t, distance(Vec2{0, 0}, Vec2{3, 4}), 5)
}

@(test)
tween_helper_procs :: proc(t: ^testing.T) {
	curve := Bezier{x1 = 0.25, y1 = 0.1, x2 = 0.75, y2 = 0.9}
	expect_close(t, tween_easing_apply(Ease.LINEAR, 0.5), 0.5)
	expect_close(t, tween_easing_apply(curve, 0.5), bezier_ease(curve, 0.5), 1e-3)

	testing.expect_value(t, tween_cycle_count(3), 3)
	testing.expect_value(t, tween_cycle_count(0), 0)
	testing.expect(t, tween_is_infinite(0))
	testing.expect(t, !tween_is_infinite(1))

	expect_close(t, tween_active_elapsed(0.5, 0.2), 0.3)
	expect_close(t, tween_active_elapsed(0.1, 0.2), 0)

	testing.expect_value(t, tween_cycle_index(1.5, 1.0, 2), 1)
	expect_close(t, tween_cycle_local_t(0.5, 1.0, 1), 0.5)

	cycle_index, local_t := tween_cycle_position(2.0, 1.0, 2)
	testing.expect_value(t, cycle_index, 1)
	expect_close(t, local_t, 1)

	testing.expect(t, tween_is_reverse_cycle(.REVERSE, 1))
	testing.expect(t, !tween_is_reverse_cycle(.REVERSE, 0))
	expect_close(t, tween_mix_t(Ease.LINEAR, 0.25, true), 0.75)

	config := tween_f32_config(0, 10, 1.0, 0, Ease.LINEAR, 2, .REVERSE)
	expect_close(t, tween_terminal_value(config), 0)
	testing.expect(t, tween_is_finished_at(config, 2.5))
	testing.expect(t, !tween_is_finished_at(config, 1.5))

	normalized := tween_normalize_config(Tween_Config(f32){start = 0, target = 10, duration = 1.0})
	_, is_ease := normalized.easing.(Ease)
	testing.expect(t, is_ease)
}

@(test)
keyframes_helper_procs :: proc(t: ^testing.T) {
	stop := keyframes_stop_default(f32(5))
	expect_close(t, stop.value, 5)

	stops := []Keyframe_Stop(f32){keyframes_stop_duration(f32(10), 0.5)}
	config := compile_keyframes_f32(stops)
	defer keyframes_config_destroy(config)

	expect_close(t, keyframes_last_value(config), 10)
	expect_close(t, keyframes_terminal_value(config), 10)
	testing.expect(t, !keyframes_is_finished_at(config, 0.1))
	testing.expect(t, keyframes_is_finished_at(config, 1.0))

	expect_close(t, keyframes_sample_cycle_at(config, 0.25, F32_Animatable()), 5)
}

@(test)
spring_helper_procs :: proc(t: ^testing.T) {
	config := spring_config_from_frequency_with_velocity(f32(10), f32(5), 2.0, 0.8)
	expect_close(t, config.initial_velocity, 5)

	anim := F32_Animatable()
	expect_close(t, spring_velocity_speed(f32(3), anim), 3)
	expect_close(t, spring_displacement(f32(2), f32(10), anim), 8)

	value, velocity := spring_integrate_substep(
		f32(0),
		f32(0),
		f32(10),
		180,
		26,
		1,
		1.0 / 60.0,
		anim,
	)
	testing.expect(t, value > 0)
	testing.expect(t, velocity > 0)
}

@(test)
decay_helper_procs :: proc(t: ^testing.T) {
	anim := F32_Animatable()
	expect_close(t, decay_velocity_speed(f32(12), anim), 12)
	expect_close(t, decay_safe_time_constant(0), MIN_DECAY_TIME_CONSTANT)
	expect_close(t, decay_safe_time_constant(0.5), 0.5)

	config := decay_config_bounded(f32(0), 0, 100, 0.25, .CLAMP)
	expect_close(t, decay_snap_bounded_at_rest(f32(99.9999), config), 100)

	value, velocity := decay_integrate_exponential(f32(0), f32(100), 0.5, 0.1, anim)
	testing.expect(t, value > 0)
	testing.expect(t, velocity < 100)

	expect_close(t, decay_bounce_scalar(f32(-10), 0.5), -5)

	bv, bvel := decay_apply_bounds_f32(-1, f32(-20), 0, 10, .BOUNCE, 0.5)
	expect_close(t, bv, 0)
	testing.expect(t, bvel > 0)

	bv2, bvel2 := decay_apply_bounds_vec2(
		Vec2{-1, 11},
		Vec2{-5, 20},
		Vec2{0, 0},
		Vec2{10, 10},
		.CLAMP,
		0.5,
	)
	expect_close(t, bv2.x, 0)
	expect_close(t, bv2.y, 10)
	testing.expect_value(t, bvel2.y, 0)

	gv, gvel := decay_apply_bounds(f32(5), f32(10), decay_config(f32(10)))
	expect_close(t, gv, 5)
	expect_close(t, gvel, 10)

	sv, svel := decay_integrate_substep(f32(0), f32(50), decay_config(f32(50)), 0.1, anim)
	testing.expect(t, sv > 0)
	testing.expect(t, svel < 50)
}

@(test)
slot_helper_procs :: proc(t: ^testing.T) {
	anim := F32_Animatable()
	testing.expect(t, tween_easing_eq(Ease.LINEAR, Ease.LINEAR))
	testing.expect(t, !tween_easing_eq(Ease.LINEAR, Ease.OUT_QUAD))

	opts_a := tween_slot_options(f32(0), 1.0)
	opts_b := tween_slot_options(f32(0), 1.0)
	testing.expect(t, tween_slot_options_eq(opts_a, opts_b, anim))

	spring_opts := spring_slot_options(f32(0))
	testing.expect(t, spring_slot_options_eq(spring_opts, spring_opts, anim))
	testing.expect(t, slot_target_eq(f32(10), f32(10), anim))

	vel_opts := spring_slot_options_with_velocity(f32(0), f32(3))
	expect_close(t, vel_opts.initial_velocity, 3)

	freq_opts := spring_slot_options_from_frequency_with_velocity(f32(0), f32(2), 3.0, 0.7)
	expect_close(t, freq_opts.initial_velocity, 2)
	testing.expect(t, freq_opts.stiffness > 0)

	tween_cfg := slot_tween_config(f32(0), f32(10), opts_a)
	expect_close(t, tween_cfg.target, 10)

	spring_cfg := slot_spring_config(f32(10), spring_opts)
	expect_close(t, spring_cfg.target, 10)

	slot: Slot(f32)
	slot_init(&slot, 0, .TWEEN)
	slot_begin_tween(&slot, 10, opts_a, 0)
	testing.expect(t, slot.active)
	expect_close(t, slot_tween_start_for_change(&slot, opts_a), slot.value)

	slot_init(&slot, 0, .SPRING)
	slot_begin_spring(&slot, 10, spring_opts, 0)
	testing.expect(t, slot.active)
	expect_close(t, slot.value, 0)

	slot_init(&slot, 0, .SPRING)
	slot_sync_spring(&slot, 10, spring_opts, anim)
	testing.expect(t, slot.active)
	expect_close(t, slot.target, 10)

	slot_init(&slot, 5, .TWEEN)
	slot_sync_tween(&slot, 10, opts_a, anim)
	testing.expect(t, slot.active)
	expect_close(t, slot.value, 5)
}

@(test)
math_bezier_remaining_helpers :: proc(t: ^testing.T) {
	curve := Bezier{x1 = 0.42, y1 = 0, x2 = 0.58, y2 = 1}
	expect_close(t, bezier_slope_1d(curve.x1, curve.x2, 0.5), 0.87, 1e-2)
	solved_t := bezier_solve_t_for_x(curve, 0.5)
	expect_close(t, solved_t, 0.5, 1e-2)
}

@(test)
harden_remaining_helpers :: proc(t: ^testing.T) {
	expect_close(t, sanitize_finite_f32(3), 3)
	expect_close(t, sanitize_finite_f32(math.nan_f32(), 0), 0)
	expect_close(t, sanitize_finite_f32(math.nan_f32(), 7), 7)

	testing.expect(t, is_finite_vec2(Vec2{1, 2}))
	testing.expect(t, !is_finite_vec2(Vec2{math.nan_f32(), 1}))
	testing.expect(t, is_finite_vec3(Vec3{1, 2, 3}))
	testing.expect(t, is_finite_vec4(Vec4{1, 2, 3, 4}))
	testing.expect(t, is_finite_rgba(RGBA{1, 0, 0, 1}))
	testing.expect(t, is_finite_rect(Rect{1, 2, 3, 4}))
	testing.expect(t, is_finite(f32(1)))
	testing.expect(t, is_finite(Vec2{1, 1}))
}

@(test)
compose_remaining_procs :: proc(t: ^testing.T) {
	anim := F32_Animatable()
	child := compose_tween(0, 10, 1.0)
	stepper := tween_stepper(&child)

	_ = stepper_step(stepper, 0.5, anim)
	testing.expect(t, !stepper_is_done(stepper, anim))
	stepper_restart(stepper)
	expect_close(t, child.elapsed, 0)

	stepper_reset_to(stepper, 3)
	_ = stepper_step(stepper, 0.25, anim)

	delay_state: Delay_State(f32)
	delay_init(&delay_state, tween_stepper(&child), 0.2, 0)
	_ = delay_step(&delay_state, 0.1, anim)
	testing.expect(t, !delay_is_finished(delay_state, anim))
	delay_restart(&delay_state)
	expect_close(t, delay_state.elapsed, 0)

	first := compose_tween(0, 10, 0.5)
	second := compose_tween(10, 20, 0.5)
	seq_steppers := [2]Stepper(f32){tween_stepper(&first), tween_stepper(&second)}
	sequence_state: Sequence_State(f32)
	sequence_init(&sequence_state, seq_steppers[:])
	_ = sequence_step(&sequence_state, 0.25, anim)
	sequence_restart(&sequence_state)
	testing.expect_value(t, sequence_state.index, 0)

	par_child_a := compose_tween(0, 10, 0.5)
	par_child_b := compose_tween(0, 20, 1.0)
	par_steppers := [2]Stepper(f32){tween_stepper(&par_child_a), tween_stepper(&par_child_b)}
	parallel_state: Parallel_State(f32)
	parallel_init(&parallel_state, par_steppers[:], 0)
	_ = parallel_step(&parallel_state, 0.25, anim)
	testing.expect(t, !parallel_is_finished(parallel_state, anim))
	parallel_restart(&parallel_state)
	par_stepper := parallel_stepper(&parallel_state)
	_ = stepper_step(par_stepper, 0.25, anim)

	repeat_child := compose_tween(0, 10, 0.5)
	repeat_state: Repeat_State(f32)
	repeat_init(&repeat_state, tween_stepper(&repeat_child), 2, 0)
	testing.expect(t, !repeat_is_infinite(2))
	testing.expect(t, repeat_is_infinite(0))
	repeat_restart(&repeat_state)
	rep_stepper := repeat_stepper(&repeat_state)
	_ = stepper_step(rep_stepper, 0.25, anim)

	stag_a := compose_tween(0, 10, 0.5)
	stag_b := compose_tween(0, 20, 0.5)
	stag_children := [2]Stepper(f32){tween_stepper(&stag_a), tween_stepper(&stag_b)}
	stag_holds := [2]f32{0, 0}
	stagger_state: Stagger_State(f32)
	_ = stagger_init(&stagger_state, stag_children[:], stag_holds[:], 0.1)
	defer stagger_destroy(stagger_state)
	_ = stagger_step(&stagger_state, 0.9, anim)
	testing.expect(t, stagger_is_finished(stagger_state, anim))
	stagger_restart(&stagger_state)
	expect_close(t, stagger_state.delays[0].elapsed, 0)
	stag_stepper := stagger_stepper(&stagger_state)
	_ = stepper_step(stag_stepper, 0.1, anim)

	expect_close(t, stepper_estimated_duration(tween_stepper(&child), anim), 1.0)
}

@(test)
timeline_remaining_procs :: proc(t: ^testing.T) {
	anim := F32_Animatable()
	cloned, ok := timeline_clone_label(Timeline_Label{name = "intro", time = 0.5})
	defer delete(cloned.name)
	testing.expect(t, ok)
	testing.expect_value(t, cloned.name, "intro")
	expect_close(t, f32(cloned.time), 0.5)

	tween_state := compose_tween(0, 10, 1.0)
	tracks := [1]Timeline_Track_Spec(f32){timeline_track_spec("main", 0, tween_stepper(&tween_state), 0)}
	timeline_state: Timeline_State(f32)
	config := init_timeline_f32(&timeline_state, tracks[:])
	defer timeline_destroy(timeline_state)

	timeline_sync(&timeline_state, 0.5, anim)
	expect_close(t, timeline_state.elapsed, 0.5)
	testing.expect(t, timeline_is_finished_at(config, 1.0))
	testing.expect(t, !timeline_is_finished_at(config, 0.5))
}

@(test)
keyframes_and_timeline_observability :: proc(t: ^testing.T) {
	anim := F32_Animatable()
	stops := []Keyframe_Stop(f32){keyframes_stop_duration(f32(10), 1.0)}
	config := compile_keyframes_f32(stops)
	defer keyframes_config_destroy(config)

	kf_state: Keyframes_State(f32)
	keyframes_init(&kf_state, config)
	_ = keyframes_step(&kf_state, 0.5, anim)

	expect_close(t, keyframes_elapsed(kf_state), 0.5)
	expect_close(t, keyframes_target(kf_state), 10)
	testing.expect(t, keyframes_is_active(kf_state))
	testing.expect(t, !keyframes_is_idle(kf_state))
	testing.expect_value(t, keyframes_status(kf_state), Animator_Status.ACTIVE)

	tween_state := compose_tween(0, 10, 1.0)
	tracks := [1]Timeline_Track_Spec(f32){timeline_track_spec("main", 0, tween_stepper(&tween_state), 0)}
	timeline_state: Timeline_State(f32)
	_ = init_timeline_f32(&timeline_state, tracks[:])
	defer timeline_destroy(timeline_state)
	_ = step_timeline(&timeline_state, 0.25)

	expect_close(t, timeline_elapsed(timeline_state), 0.25)
	testing.expect(t, timeline_is_active(timeline_state, anim))
	testing.expect(t, !timeline_is_idle(timeline_state, anim))
	testing.expect_value(t, timeline_status(timeline_state, anim), Animator_Status.ACTIVE)
}

@(test)
delay_and_compose_observability :: proc(t: ^testing.T) {
	anim := F32_Animatable()
	child := compose_tween(0, 10, 1.0)
	delay_state: Delay_State(f32)
	delay_init(&delay_state, tween_stepper(&child), 0.4, 0)

	_ = delay_step(&delay_state, 0.2, anim)
	expect_close(t, delay_elapsed(delay_state), 0.2)
	expect_close(t, delay_progress(delay_state), 0.5)
	testing.expect(t, delay_is_active(delay_state, anim))
	testing.expect(t, !delay_is_idle(delay_state, anim))

	par_a := compose_tween(0, 10, 1.0)
	par_b := compose_tween(0, 20, 2.0)
	par_steppers := [2]Stepper(f32){tween_stepper(&par_a), tween_stepper(&par_b)}
	parallel_state: Parallel_State(f32)
	parallel_init(&parallel_state, par_steppers[:], 0)
	_ = parallel_step(&parallel_state, 0.25, anim)
	expect_close(t, parallel_progress(parallel_state, anim), 0.25)

	stag_a := compose_tween(0, 10, 0.5)
	stag_children := [1]Stepper(f32){tween_stepper(&stag_a)}
	stag_holds := [1]f32{0}
	stagger_state: Stagger_State(f32)
	_ = stagger_init(&stagger_state, stag_children[:], stag_holds[:], 0.2)
	defer stagger_destroy(stagger_state)
	_ = stagger_step(&stagger_state, 0.1, anim)
	expect_close(t, stagger_progress(stagger_state, anim), 0.2)
}

@(test)
spring_and_decay_status_helpers :: proc(t: ^testing.T) {
	anim := F32_Animatable()

	spring_state: Spring_State(f32)
	spring_init(&spring_state, spring_config(f32(10)), 0)
	testing.expect_value(t, spring_status(spring_state, anim), Animator_Status.ACTIVE)
	_ = run_spring_until_done(&spring_state, 1.0 / 60.0, anim, SPRING_TEST_COMPLETION)
	testing.expect_value(t, spring_status(spring_state, anim), Animator_Status.IDLE)

	decay_state: Decay_State(f32)
	decay_init(&decay_state, decay_config(f32(80)), 0)
	testing.expect_value(t, decay_status(decay_state, anim), Animator_Status.ACTIVE)
	_ = run_decay_until_done(&decay_state, 1.0 / 60.0, anim, DECAY_TEST_COMPLETION)
	testing.expect_value(t, decay_status(decay_state, anim), Animator_Status.IDLE)
}

@(test)
stepper_query_helpers :: proc(t: ^testing.T) {
	anim := F32_Animatable()
	state := compose_tween(0, 10, 1.0)
	stepper := tween_stepper(&state)

	_ = stepper_step(stepper, 0.25, anim)
	testing.expect(t, stepper_has_target(stepper, anim))
	expect_close(t, stepper_value(stepper, anim), 2.5)
	testing.expect(t, stepper_is_active(stepper, anim))
	testing.expect(t, !stepper_is_idle(stepper, anim))
	testing.expect_value(t, stepper_status(stepper, anim), Animator_Status.ACTIVE)
	expect_close(t, stepper_progress_from_state(.Tween, &state, anim, DEFAULT_COMPLETION_POLICY), 0.25)

	elapsed, has_elapsed := stepper_elapsed_impl(.Tween, &state, f32)
	testing.expect(t, has_elapsed)
	expect_close(t, elapsed, 0.25)

	target, has_target := stepper_target_impl(.Tween, &state, anim)
	testing.expect(t, has_target)
	expect_close(t, target, 10)

	expect_close(t, stepper_value_impl(.Tween, &state, f32, anim), 2.5)
}

@(test)
debug_assert_and_validate_helpers :: proc(t: ^testing.T) {
	debug_assert(true, "should not fire")
	debug_assert_time_policy(DEFAULT_TIME_POLICY)
	debug_assert_tween_config(tween_f32_config(0, 10, 1.0))
	debug_assert_spring_config(spring_config(f32(10)))
	debug_assert_decay_config(decay_config(f32(10)))
	debug_assert_keyframes_config(Keyframes_Config(f32){})

	child := compose_tween(0, 10, 1.0)
	stepper := tween_stepper(&child)
	debug_assert_stepper(stepper)
}

@(test)
traced_step_and_slot_helpers :: proc(t: ^testing.T) {
	when ODIN_DEBUG {
		anim := F32_Animatable()

		tween_state := compose_tween(0, 10, 1.0)
		_ = tween_step_traced(&tween_state, 0.1, anim)

		spring_state: Spring_State(f32)
		spring_init(&spring_state, spring_config(f32(10)), 0)
		_ = spring_step_traced(&spring_state, 1.0 / 60.0, anim)

		stops := []Keyframe_Stop(f32){keyframes_stop_duration(f32(10), 1.0)}
		kf_config := compile_keyframes_f32(stops)
		defer keyframes_config_destroy(kf_config)
		kf_state: Keyframes_State(f32)
		keyframes_init(&kf_state, kf_config)
		_ = keyframes_step_traced(&kf_state, 0.1, anim)

		decay_state: Decay_State(f32)
		decay_init(&decay_state, decay_config(f32(50)), 0)
		_ = decay_step_traced(&decay_state, 0.1, anim)

		stepper := tween_stepper(&tween_state)
		_ = stepper_step_traced(stepper, 0.1, anim)

		slot: Slot(f32)
		slot_init(&slot, 0, .TWEEN)
		opts := tween_slot_options(f32(0), 1.0)
		_ = tween_to_traced(&slot, 10, 0.1, opts, anim)

		slot_init(&slot, 0, .SPRING)
		s_opts := spring_slot_options(f32(0))
		_ = spring_to_traced(&slot, 10, 0.1, s_opts, anim)

		slot_init(&slot, 0, .TWEEN)
		_ = transition_to_traced(&slot, 10, 0.1, anim)

		trace_emit(Trace_Info(f32){kind = .STEP, tag = .Tween, value = 1})
		trace_step_result(.Tween, &tween_state, 0.1, Step_Result(f32){value = 1}, anim, DEFAULT_COMPLETION_POLICY)
	}
}

// --- compound.odin & expanded value domains ---

@(test)
compound_entry_f32_builds_typed_operations :: proc(t: ^testing.T) {
	entry := compound_entry_f32(0)

	a: f32
	b: f32 = 10
	entry.zero(&a)
	expect_close(t, a, 0)
	entry.add(&a, &a, &b)
	expect_close(t, a, 10)
	entry.scale(&a, &a, 0.5)
	expect_close(t, a, 5)
	entry.mix(&a, &a, &b, 0.5)
	expect_close(t, a, 7.5)
	expect_close(t, entry.distance(&a, &b), 2.5)
	testing.expect(t, entry.has_velocity)
}

@(test)
compound_entry_helpers_build_all_builtin_fields :: proc(t: ^testing.T) {
	_ = compound_entry_f32(0)
	_ = compound_entry_vec2(0)
	_ = compound_entry_vec3(0)
	_ = compound_entry_vec4(0)
	_ = compound_entry_rgba(0)
	_ = compound_entry_rect(0)
}

@(test)
compound_field_ptr_offsets_struct_field :: proc(t: ^testing.T) {
	style := Panel_Style{opacity = 0.5, offset = {10, 20}, scale = 2}
	opacity_ptr := (^f32)(compound_field_ptr(&style, offset_of(Panel_Style, opacity)))
	expect_close(t, opacity_ptr^, 0.5)
}

@(test)
compound_animatable_mixes_fields_independently :: proc(t: ^testing.T) {
	anim := Panel_Style_Animatable()
	start := Panel_Style{opacity = 0, offset = {0, 0}, scale = 1}
	target := Panel_Style{opacity = 1, offset = {10, 20}, scale = 3}
	mixed := anim.mix(start, target, 0.5)
	expect_close(t, mixed.opacity, 0.5)
	expect_vec2_close(t, mixed.offset, Vec2{5, 10})
	expect_close(t, mixed.scale, 2)
	expect_close(t, anim.distance(start, target), math.sqrt(f32(1 + 500 + 4)))
	testing.expect_value(t, anim.velocity_support, Velocity_Support.VALUE_TYPE)
}

@(test)
compound_ops_and_bind_cover_public_api :: proc(t: ^testing.T) {
	start := Panel_Style{opacity = 1, offset = {1, 2}, scale = 3}
	target := Panel_Style{opacity = 0.5, offset = {5, 10}, scale = 2}
	entries := panel_style_entries()
	testing.expect(t, compound_entries_have_velocity(entries[:]))

	zeroed := compound_zero(Panel_Style, entries[:])
	expect_close(t, zeroed.opacity, 0)
	expect_vec2_close(t, zeroed.offset, Vec2{})

	added := compound_add(start, target, entries[:])
	subbed := compound_sub(added, target, entries[:])
	expect_close(t, subbed.opacity, start.opacity)
	mixed := compound_mix(start, target, 0.5, entries[:])
	expect_close(t, mixed.opacity, 0.75)

	scaled := compound_scale(start, 2, entries[:])
	expect_close(t, scaled.opacity, 2)
	expect_vec2_close(t, scaled.offset, Vec2{2, 4})
	expect_close(t, scaled.scale, 6)

	anim := compound_bind(
		panel_style_zero,
		panel_style_add,
		panel_style_sub,
		panel_style_scale,
		panel_style_mix,
		panel_style_distance,
		.VALUE_TYPE,
	)
	expect_close(t, anim.distance(start, Panel_Style{}), compound_distance(start, Panel_Style{}, entries[:]))
}

@(test)
compound_tween_spring_keyframes_decay_and_slot :: proc(t: ^testing.T) {
	anim := Panel_Style_Animatable()
	start := Panel_Style{opacity = 0, offset = {0, 0}, scale = 1}
	target := Panel_Style{opacity = 1, offset = {10, 0}, scale = 2}

	tween_state: Tween_State(Panel_Style)
	tween_init(
		&tween_state,
		Tween_Config(Panel_Style){start = start, target = target, duration = 1.0},
	)
	tween_result := tween_step(&tween_state, 0.5, anim)
	expect_close(t, tween_result.value.opacity, 0.5)
	expect_vec2_close(t, tween_result.value.offset, Vec2{5, 0})
	testing.expect_value(t, tween_result.done, false)

	spring_state: Spring_State(Panel_Style)
	spring_init(&spring_state, spring_config(target), start)
	spring_result := run_spring_until_done(&spring_state, 1.0 / 60.0, anim, SPRING_TEST_COMPLETION)
	expect_close(t, spring_result.value.opacity, 1)
	expect_vec2_close(t, spring_result.value.offset, Vec2{10, 0})
	testing.expect_value(t, spring_result.done, true)

	stops := []Keyframe_Stop(Panel_Style){keyframes_stop_duration(target, 1.0)}
	spec := keyframes_spec_duration(start, stops)
	config, err := keyframes_compile(spec)
	defer keyframes_config_destroy(config)
	testing.expect_value(t, err, Keyframes_Compile_Error.NONE)
	keyframe_state: Keyframes_State(Panel_Style)
	keyframes_init(&keyframe_state, config)
	keyframe_result := keyframes_step(&keyframe_state, 1.0, anim)
	expect_close(t, keyframe_result.value.opacity, 1)
	testing.expect_value(t, keyframe_result.done, true)

	decay_state: Decay_State(Panel_Style)
	decay_init(&decay_state, decay_config(Panel_Style{opacity = 0, offset = {40, -30}, scale = 0}), start)
	decay_result := run_decay_until_done(&decay_state, 1.0 / 60.0, anim, DECAY_TEST_COMPLETION)
	testing.expect_value(t, decay_result.done, true)
	expect_close(t, decay_result.velocity.opacity, 0)

	slot: Slot(Panel_Style)
	slot_init(&slot, start, .SPRING)
	spring_opts := spring_slot_options(start)
	slot_result := spring_to(&slot, target, 1.0 / 60.0, spring_opts, anim)
	testing.expect(t, slot_result.value.opacity > start.opacity)
}

@(test)
tween_vec3_vec4_and_rect_complete :: proc(t: ^testing.T) {
	{
		state: Tween_State(Vec3)
		tween_init(
			&state,
			Tween_Config(Vec3) {
				start = {0, 0, 0},
				target = {10, 20, 30},
				duration = 1.0,
				easing = Ease.LINEAR,
				repeat_count = 1,
			},
		)
		result := tween_step(&state, 0.5, Vec3_Animatable())
		expect_vec3_close(t, result.value, Vec3{5, 10, 15})
		result = tween_step(&state, 0.5, Vec3_Animatable())
		expect_vec3_close(t, result.value, Vec3{10, 20, 30})
		testing.expect_value(t, result.done, true)
	}
	{
		state: Tween_State(Vec4)
		tween_init(
			&state,
			Tween_Config(Vec4) {
				start = {0, 0, 0, 0},
				target = {4, 8, 12, 16},
				duration = 1.0,
				easing = Ease.LINEAR,
				repeat_count = 1,
			},
		)
		result := tween_step(&state, 0.5, Vec4_Animatable())
		expect_vec4_close(t, result.value, Vec4{2, 4, 6, 8})
	}
	{
		state: Tween_State(Rect)
		tween_init(
			&state,
			Tween_Config(Rect) {
				start = {0, 0, 10, 10},
				target = {20, 40, 30, 50},
				duration = 1.0,
				easing = Ease.LINEAR,
				repeat_count = 1,
			},
		)
		result := tween_step(&state, 0.5, Rect_Animatable())
		expect_rect_close(t, result.value, Rect{10, 20, 20, 30})
	}
}

@(test)
spring_vec3_vec4_and_rect_reach_target :: proc(t: ^testing.T) {
	{
		state: Spring_State(Vec3)
		spring_init(&state, spring_config(Vec3{3, 6, 9}), Vec3{})
		result := run_spring_until_done(&state, 1.0 / 60.0, Vec3_Animatable(), SPRING_TEST_COMPLETION)
		expect_vec3_close(t, result.value, Vec3{3, 6, 9})
		testing.expect_value(t, result.done, true)
	}
	{
		state: Spring_State(Vec4)
		spring_init(&state, spring_config(Vec4{1, 2, 3, 4}), Vec4{})
		result := run_spring_until_done(&state, 1.0 / 60.0, Vec4_Animatable(), SPRING_TEST_COMPLETION)
		expect_vec4_close(t, result.value, Vec4{1, 2, 3, 4})
		testing.expect_value(t, result.done, true)
	}
	{
		state: Spring_State(Rect)
		spring_init(&state, spring_config(Rect{5, 10, 15, 20}), Rect{})
		result := run_spring_until_done(&state, 1.0 / 60.0, Rect_Animatable(), SPRING_TEST_COMPLETION)
		expect_rect_close(t, result.value, Rect{5, 10, 15, 20})
		testing.expect_value(t, result.done, true)
	}
}

@(test)
keyframes_vec3_vec4_and_rect_complete :: proc(t: ^testing.T) {
	{
		stops := []Keyframe_Stop(Vec3){keyframes_stop_duration(Vec3{9, 18, 27}, 1.0)}
		spec := keyframes_spec_duration(Vec3{}, stops)
		config, err := keyframes_compile(spec)
		defer keyframes_config_destroy(config)
		testing.expect_value(t, err, Keyframes_Compile_Error.NONE)
		state: Keyframes_State(Vec3)
		keyframes_init(&state, config)
		result := keyframes_step(&state, 1.0, Vec3_Animatable())
		expect_vec3_close(t, result.value, Vec3{9, 18, 27})
		testing.expect_value(t, result.done, true)
	}
	{
		stops := []Keyframe_Stop(Vec4){keyframes_stop_duration(Vec4{4, 8, 12, 16}, 1.0)}
		spec := keyframes_spec_duration(Vec4{}, stops)
		config, err := keyframes_compile(spec)
		defer keyframes_config_destroy(config)
		testing.expect_value(t, err, Keyframes_Compile_Error.NONE)
		state: Keyframes_State(Vec4)
		keyframes_init(&state, config)
		result := keyframes_step(&state, 1.0, Vec4_Animatable())
		expect_vec4_close(t, result.value, Vec4{4, 8, 12, 16})
		testing.expect_value(t, result.done, true)
	}
	{
		stops := []Keyframe_Stop(Rect){keyframes_stop_duration(Rect{10, 20, 30, 40}, 1.0)}
		spec := keyframes_spec_duration(Rect{}, stops)
		config, err := keyframes_compile(spec)
		defer keyframes_config_destroy(config)
		testing.expect_value(t, err, Keyframes_Compile_Error.NONE)
		state: Keyframes_State(Rect)
		keyframes_init(&state, config)
		result := keyframes_step(&state, 1.0, Rect_Animatable())
		expect_rect_close(t, result.value, Rect{10, 20, 30, 40})
		testing.expect_value(t, result.done, true)
	}
}

@(test)
decay_vec3_vec4_and_rect_reach_rest :: proc(t: ^testing.T) {
	{
		state: Decay_State(Vec3)
		decay_init(&state, decay_config(Vec3{30, -20, 10}, 0.4), Vec3{1, 2, 3})
		result := run_decay_until_done(&state, 1.0 / 60.0, Vec3_Animatable(), DECAY_TEST_COMPLETION)
		testing.expect_value(t, result.done, true)
		expect_vec3_close(t, result.velocity, Vec3{})
	}
	{
		state: Decay_State(Vec4)
		decay_init(&state, decay_config(Vec4{20, -10, 5, -5}, 0.35), Vec4{})
		result := run_decay_until_done(&state, 1.0 / 60.0, Vec4_Animatable(), DECAY_TEST_COMPLETION)
		testing.expect_value(t, result.done, true)
		expect_vec4_close(t, result.velocity, Vec4{})
	}
	{
		state: Decay_State(Rect)
		decay_init(&state, decay_config(Rect{50, -25, 10, -10}, 0.3), Rect{})
		result := run_decay_until_done(&state, 1.0 / 60.0, Rect_Animatable(), DECAY_TEST_COMPLETION)
		testing.expect_value(t, result.done, true)
		expect_rect_close(t, result.velocity, Rect{})
	}
}

@(test)
decay_vec3_vec4_and_rect_bounded_clamp :: proc(t: ^testing.T) {
	{
		state: Decay_State(Vec3)
		decay_init(
			&state,
			decay_config_bounded(
				Vec3{200, -200, 100},
				Vec3{-5, -5, 0},
				Vec3{5, 5, 10},
				0.25,
				.CLAMP,
			),
			Vec3{},
		)
		result := run_decay_until_done(&state, 1.0 / 60.0, Vec3_Animatable(), DECAY_TEST_COMPLETION)
		expect_vec3_close(t, result.value, Vec3{5, -5, 10})
		testing.expect_value(t, result.done, true)
	}
	{
		state: Decay_State(Vec4)
		decay_init(
			&state,
			decay_config_bounded(
				Vec4{300, -300, 50, -50},
				Vec4{0, 0, 0, 0},
				Vec4{10, 10, 10, 10},
				0.25,
				.CLAMP,
			),
			Vec4{},
		)
		result := run_decay_until_done(&state, 1.0 / 60.0, Vec4_Animatable(), DECAY_TEST_COMPLETION)
		expect_vec4_close(t, result.value, Vec4{10, 0, 10, 0})
		testing.expect_value(t, result.done, true)
	}
	{
		state: Decay_State(Rect)
		decay_init(
			&state,
			decay_config_bounded(
				Rect{0, 0, 500, 0},
				Rect{0, 0, 0, 0},
				Rect{20, 20, 40, 40},
				0.25,
				.CLAMP,
			),
			Rect{},
		)
		result := run_decay_until_done(&state, 1.0 / 60.0, Rect_Animatable(), DECAY_TEST_COMPLETION)
		expect_rect_close(t, result.value, Rect{0, 0, 40, 0})
		testing.expect_value(t, result.done, true)
	}
}

@(test)
decay_bounds_helpers_cover_vec3_vec4_and_rect :: proc(t: ^testing.T) {
	v3, vel3 := decay_apply_bounds_vec3(
		Vec3{-1, 6, 0},
		Vec3{-20, 30, 10},
		Vec3{0, 0, 0},
		Vec3{5, 5, 5},
		.BOUNCE,
		0.5,
	)
	expect_close(t, v3.x, 0)
	testing.expect(t, vel3.x > 0)

	v4, vel4 := decay_apply_bounds_vec4(
		Vec4{6, 0, 0, 0},
		Vec4{10, 0, 0, 0},
		Vec4{0, 0, 0, 0},
		Vec4{5, 5, 5, 5},
		.CLAMP,
		0.5,
	)
	expect_close(t, v4.x, 5)
	testing.expect_value(t, vel4.x, 0)

	rect, vel_rect := decay_apply_bounds_rect(
		Rect{0, 11, 0, 0},
		Rect{0, 40, 0, 0},
		Rect{0, 0, 0, 0},
		Rect{10, 10, 10, 10},
		.CLAMP,
		0.5,
	)
	expect_close(t, rect.y, 10)
	testing.expect_value(t, vel_rect.y, 0)

	config := decay_config_bounded(Vec3{0, 0, 0}, Vec3{0, 0, 0}, Vec3{5, 5, 5}, 0.25, .CLAMP)
	expect_vec3_close(t, decay_snap_bounded_at_rest(Vec3{4.9999, 0, 0}, config), Vec3{5, 0, 0}, 1e-3)

	value, velocity := decay_apply_bounds_axis(-2, -30, 0, 10, .BOUNCE, 0.5)
	expect_close(t, value, 0)
	testing.expect(t, velocity > 0)
	expect_close(t, decay_snap_axis_at_rest(9.9999, 0, 10, 1e-3), 10)
}

@(test)
slot_vec3_vec4_and_rect_transitions :: proc(t: ^testing.T) {
	{
		slot: Slot(Vec3)
		slot_init(&slot, Vec3{}, .TWEEN)
		opts := tween_slot_options(Vec3{}, 1.0)
		result := tween_to(&slot, Vec3{6, 9, 12}, 0.5, opts, Vec3_Animatable())
		expect_vec3_close(t, result.value, Vec3{3, 4.5, 6})
	}
	{
		slot: Slot(Vec4)
		slot_init(&slot, Vec4{}, .SPRING)
		opts := spring_slot_options(Vec4{})
		result := spring_to(&slot, Vec4{4, 8, 12, 16}, 1.0 / 60.0, opts, Vec4_Animatable())
		testing.expect(t, result.value.x > 0)
	}
	{
		slot: Slot(Rect)
		slot_init(&slot, Rect{}, .TWEEN)
		opts := tween_slot_options(Rect{}, 1.0)
		result := tween_to(&slot, Rect{20, 40, 60, 80}, 1.0, opts, Rect_Animatable())
		expect_rect_close(t, result.value, Rect{20, 40, 60, 80})
		testing.expect_value(t, result.done, true)
	}
}

