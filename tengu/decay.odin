package tengu

import "core:math"

/*
Velocity-driven motion with exponential friction. Velocity decays as
`e^(-t / time_constant)`; displacement over each step uses the closed-form
integral so stepping stays stable under large `dt`.
*/
Decay_Bounds_Mode :: enum {
	UNBOUNDED,
	CLAMP,
	BOUNCE,
}

Decay_Config :: struct($T: typeid) {
	initial_velocity: T,
	time_constant:    f32,
	bounds_min:       T,
	bounds_max:       T,
	bounds_mode:      Decay_Bounds_Mode,
	bounce:           f32,
}

/*
Caller-owned decay runtime state. `value` and `velocity` are the displayed
motion state; `decay_reconfigure` and `decay_set_velocity` preserve position
unless the motion is explicitly restarted.
*/
Decay_State :: struct($T: typeid) {
	config:   Decay_Config(T),
	value:    T,
	velocity: T,
}

DEFAULT_DECAY_TIME_CONSTANT :: f32(0.35)
DEFAULT_DECAY_BOUNCE :: f32(0.5)

MIN_DECAY_TIME_CONSTANT :: f32(1e-6)

decay_default_config :: proc(initial_velocity: $T) -> Decay_Config(T) {
	return decay_config(initial_velocity, DEFAULT_DECAY_TIME_CONSTANT)
}

decay_config :: proc(initial_velocity: $T, time_constant: f32 = DEFAULT_DECAY_TIME_CONSTANT) -> Decay_Config(T) {
	zero: T
	return Decay_Config(T) {
		initial_velocity = initial_velocity,
		time_constant = time_constant,
		bounds_min = zero,
		bounds_max = zero,
		bounds_mode = .UNBOUNDED,
		bounce = DEFAULT_DECAY_BOUNCE,
	}
}

decay_config_bounded :: proc(
	initial_velocity: $T,
	bounds_min, bounds_max: T,
	time_constant: f32 = DEFAULT_DECAY_TIME_CONSTANT,
	bounds_mode: Decay_Bounds_Mode = .CLAMP,
	bounce: f32 = DEFAULT_DECAY_BOUNCE,
) -> Decay_Config(T) {
	return Decay_Config(T) {
		initial_velocity = initial_velocity,
		time_constant = time_constant,
		bounds_min = bounds_min,
		bounds_max = bounds_max,
		bounds_mode = bounds_mode,
		bounce = bounce,
	}
}

decay_velocity_speed :: proc(velocity: $T, anim: Animatable(T)) -> f32 {
	return anim.distance(anim.zero(), velocity)
}

decay_is_at_rest :: proc(
	state: Decay_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	speed := decay_velocity_speed(state.velocity, anim)
	return is_done(0, speed, completion)
}

decay_init :: proc(state: ^Decay_State($T), config: Decay_Config(T), start_value: T) {
	state.config = config
	state.value = start_value
	state.velocity = config.initial_velocity
}

/*
Replaces configuration while preserving the current displayed motion. Use
`decay_restart` to apply `initial_velocity` again from a chosen value.
*/
decay_reconfigure :: proc(state: ^Decay_State($T), config: Decay_Config(T)) {
	state.config = config
}

/*
Continues from the current displayed value with a new velocity. This is the
normal interruption path for user-driven inertia updates.
*/
decay_set_velocity :: proc(state: ^Decay_State($T), velocity: T) {
	state.velocity = velocity
}

decay_restart :: proc(state: ^Decay_State($T), value: T) {
	state.value = value
	state.velocity = state.config.initial_velocity
}

@(private)
decay_safe_time_constant :: proc(time_constant: f32) -> f32 {
	return math.max(time_constant, MIN_DECAY_TIME_CONSTANT)
}

@(private)
decay_snap_bounded_at_rest :: proc(
	value: $T,
	config: Decay_Config(T),
	epsilon: f32 = DEFAULT_DISTANCE_EPSILON,
) -> T {
	if config.bounds_mode != .CLAMP do return value

	when T == f32 {
		return decay_snap_axis_at_rest(value, config.bounds_min, config.bounds_max, epsilon)
	} else when T == Vec2 {
		return {
			decay_snap_axis_at_rest(value.x, config.bounds_min.x, config.bounds_max.x, epsilon),
			decay_snap_axis_at_rest(value.y, config.bounds_min.y, config.bounds_max.y, epsilon),
		}
	} else when T == Vec3 {
		return {
			decay_snap_axis_at_rest(value.x, config.bounds_min.x, config.bounds_max.x, epsilon),
			decay_snap_axis_at_rest(value.y, config.bounds_min.y, config.bounds_max.y, epsilon),
			decay_snap_axis_at_rest(value.z, config.bounds_min.z, config.bounds_max.z, epsilon),
		}
	} else when T == Vec4 {
		return {
			decay_snap_axis_at_rest(value.x, config.bounds_min.x, config.bounds_max.x, epsilon),
			decay_snap_axis_at_rest(value.y, config.bounds_min.y, config.bounds_max.y, epsilon),
			decay_snap_axis_at_rest(value.z, config.bounds_min.z, config.bounds_max.z, epsilon),
			decay_snap_axis_at_rest(value.w, config.bounds_min.w, config.bounds_max.w, epsilon),
		}
	} else when T == Rect {
		return {
			decay_snap_axis_at_rest(value.x, config.bounds_min.x, config.bounds_max.x, epsilon),
			decay_snap_axis_at_rest(value.y, config.bounds_min.y, config.bounds_max.y, epsilon),
			decay_snap_axis_at_rest(value.w, config.bounds_min.w, config.bounds_max.w, epsilon),
			decay_snap_axis_at_rest(value.h, config.bounds_min.h, config.bounds_max.h, epsilon),
		}
	} else {
		return value
	}
}

@(private)
decay_integrate_exponential :: proc(value, velocity: $T, time_constant, dt: f32, anim: Animatable(T)) -> (
	next_value: T,
	next_velocity: T,
) {
	safe_tau := decay_safe_time_constant(time_constant)
	decay_factor := math.exp(-dt / safe_tau)
	displacement := anim.scale(velocity, safe_tau * (1 - decay_factor))
	next_velocity = anim.scale(velocity, decay_factor)
	next_value = anim.add(value, displacement)
	return
}

@(private)
decay_bounce_scalar :: proc(velocity, bounce: f32) -> f32 {
	return velocity * clamp01(bounce)
}

@(private)
decay_apply_bounds_axis :: proc(
	value, velocity, bounds_min, bounds_max: f32,
	mode: Decay_Bounds_Mode,
	bounce: f32,
) -> (
	next_value: f32,
	next_velocity: f32,
) {
	if mode == .UNBOUNDED do return value, velocity

	next_value = value
	next_velocity = velocity

	if next_value < bounds_min {
		next_value = bounds_min
		switch mode {
		case .UNBOUNDED:
			unreachable()
		case .CLAMP:
			if next_velocity < 0 do next_velocity = 0
		case .BOUNCE:
			next_velocity = decay_bounce_scalar(-next_velocity, bounce)
		}
	} else if next_value > bounds_max {
		next_value = bounds_max
		switch mode {
		case .UNBOUNDED:
			unreachable()
		case .CLAMP:
			if next_velocity > 0 do next_velocity = 0
		case .BOUNCE:
			next_velocity = decay_bounce_scalar(-next_velocity, bounce)
		}
	}

	return
}

@(private)
decay_snap_axis_at_rest :: proc(value, bounds_min, bounds_max, epsilon: f32) -> f32 {
	if math.abs(value - bounds_min) <= epsilon do return bounds_min
	if math.abs(value - bounds_max) <= epsilon do return bounds_max
	return value
}

@(private)
decay_apply_bounds_f32 :: proc(
	value, velocity: f32,
	bounds_min, bounds_max: f32,
	mode: Decay_Bounds_Mode,
	bounce: f32,
) -> (
	next_value: f32,
	next_velocity: f32,
) {
	return decay_apply_bounds_axis(value, velocity, bounds_min, bounds_max, mode, bounce)
}

@(private)
decay_apply_bounds_vec2 :: proc(
	value, velocity: Vec2,
	bounds_min, bounds_max: Vec2,
	mode: Decay_Bounds_Mode,
	bounce: f32,
) -> (
	next_value: Vec2,
	next_velocity: Vec2,
) {
	if mode == .UNBOUNDED do return value, velocity

	next_value.x, next_velocity.x = decay_apply_bounds_axis(
		value.x,
		velocity.x,
		bounds_min.x,
		bounds_max.x,
		mode,
		bounce,
	)
	next_value.y, next_velocity.y = decay_apply_bounds_axis(
		value.y,
		velocity.y,
		bounds_min.y,
		bounds_max.y,
		mode,
		bounce,
	)
	return
}

@(private)
decay_apply_bounds_vec3 :: proc(
	value, velocity: Vec3,
	bounds_min, bounds_max: Vec3,
	mode: Decay_Bounds_Mode,
	bounce: f32,
) -> (
	next_value: Vec3,
	next_velocity: Vec3,
) {
	if mode == .UNBOUNDED do return value, velocity

	next_value.x, next_velocity.x = decay_apply_bounds_axis(
		value.x,
		velocity.x,
		bounds_min.x,
		bounds_max.x,
		mode,
		bounce,
	)
	next_value.y, next_velocity.y = decay_apply_bounds_axis(
		value.y,
		velocity.y,
		bounds_min.y,
		bounds_max.y,
		mode,
		bounce,
	)
	next_value.z, next_velocity.z = decay_apply_bounds_axis(
		value.z,
		velocity.z,
		bounds_min.z,
		bounds_max.z,
		mode,
		bounce,
	)
	return
}

@(private)
decay_apply_bounds_vec4 :: proc(
	value, velocity: Vec4,
	bounds_min, bounds_max: Vec4,
	mode: Decay_Bounds_Mode,
	bounce: f32,
) -> (
	next_value: Vec4,
	next_velocity: Vec4,
) {
	if mode == .UNBOUNDED do return value, velocity

	next_value.x, next_velocity.x = decay_apply_bounds_axis(
		value.x,
		velocity.x,
		bounds_min.x,
		bounds_max.x,
		mode,
		bounce,
	)
	next_value.y, next_velocity.y = decay_apply_bounds_axis(
		value.y,
		velocity.y,
		bounds_min.y,
		bounds_max.y,
		mode,
		bounce,
	)
	next_value.z, next_velocity.z = decay_apply_bounds_axis(
		value.z,
		velocity.z,
		bounds_min.z,
		bounds_max.z,
		mode,
		bounce,
	)
	next_value.w, next_velocity.w = decay_apply_bounds_axis(
		value.w,
		velocity.w,
		bounds_min.w,
		bounds_max.w,
		mode,
		bounce,
	)
	return
}

@(private)
decay_apply_bounds_rect :: proc(
	value, velocity: Rect,
	bounds_min, bounds_max: Rect,
	mode: Decay_Bounds_Mode,
	bounce: f32,
) -> (
	next_value: Rect,
	next_velocity: Rect,
) {
	if mode == .UNBOUNDED do return value, velocity

	next_value.x, next_velocity.x = decay_apply_bounds_axis(
		value.x,
		velocity.x,
		bounds_min.x,
		bounds_max.x,
		mode,
		bounce,
	)
	next_value.y, next_velocity.y = decay_apply_bounds_axis(
		value.y,
		velocity.y,
		bounds_min.y,
		bounds_max.y,
		mode,
		bounce,
	)
	next_value.w, next_velocity.w = decay_apply_bounds_axis(
		value.w,
		velocity.w,
		bounds_min.w,
		bounds_max.w,
		mode,
		bounce,
	)
	next_value.h, next_velocity.h = decay_apply_bounds_axis(
		value.h,
		velocity.h,
		bounds_min.h,
		bounds_max.h,
		mode,
		bounce,
	)
	return
}

@(private)
decay_apply_bounds :: proc(
	value, velocity: $T,
	config: Decay_Config(T),
) -> (
	next_value: T,
	next_velocity: T,
) {
	when T == f32 {
		return decay_apply_bounds_f32(
			value,
			velocity,
			config.bounds_min,
			config.bounds_max,
			config.bounds_mode,
			config.bounce,
		)
	} else when T == Vec2 {
		return decay_apply_bounds_vec2(
			value,
			velocity,
			config.bounds_min,
			config.bounds_max,
			config.bounds_mode,
			config.bounce,
		)
	} else when T == Vec3 {
		return decay_apply_bounds_vec3(
			value,
			velocity,
			config.bounds_min,
			config.bounds_max,
			config.bounds_mode,
			config.bounce,
		)
	} else when T == Vec4 {
		return decay_apply_bounds_vec4(
			value,
			velocity,
			config.bounds_min,
			config.bounds_max,
			config.bounds_mode,
			config.bounce,
		)
	} else when T == Rect {
		return decay_apply_bounds_rect(
			value,
			velocity,
			config.bounds_min,
			config.bounds_max,
			config.bounds_mode,
			config.bounce,
		)
	} else {
		return value, velocity
	}
}

@(private)
decay_integrate_substep :: proc(
	value, velocity: $T,
	config: Decay_Config(T),
	dt: f32,
	anim: Animatable(T),
) -> (
	next_value: T,
	next_velocity: T,
) {
	integrated_value, integrated_velocity := decay_integrate_exponential(
		value,
		velocity,
		config.time_constant,
		dt,
		anim,
	)
	return decay_apply_bounds(integrated_value, integrated_velocity, config)
}

/*
Advances decay by `dt` seconds using deterministic substeps for large frame
times. Negative `dt` leaves state unchanged. When velocity reaches rest, it
snaps to zero while the value remains at its current position.
*/
decay_step :: proc(
	state: ^Decay_State($T),
	dt: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
	time: Time_Policy = DEFAULT_TIME_POLICY,
) -> Step_Result(T) {
	safe_dt := sanitize_dt(dt)
	if safe_dt <= 0 {
		done := decay_is_at_rest(state^, anim, completion)
		value := state.value
		velocity := state.velocity
		if done {
			velocity = anim.zero()
		}
		return motion_result(value, velocity, done)
	}

	plan := plan_substeps(safe_dt, time)
	value := state.value
	velocity := state.velocity
	config := state.config

	for _ in 0 ..< plan.steps {
		value, velocity = decay_integrate_substep(value, velocity, config, plan.substep_dt, anim)
	}

	state.value = value
	state.velocity = velocity

	speed := decay_velocity_speed(velocity, anim)
	done := is_done(0, speed, completion)

	if done {
		value = decay_snap_bounded_at_rest(value, config, completion.distance_epsilon)
		velocity = anim.zero()
		state.value = value
		state.velocity = velocity
	}

	return motion_result(value, velocity, done)
}
