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

Decay_Init_Params :: struct($T: typeid) {
	state:       ^Decay_State(T),
	config:      Decay_Config(T),
	start_value: T,
}

Decay_Integrate_Exponential_Params :: struct($T: typeid) {
	value, velocity:      T,
	time_constant, dt:    f32,
	anim:                 Animatable(T),
}

Decay_Apply_Bounds_Axis_Params :: struct {
	value, velocity:              f32,
	bounds_min, bounds_max:       f32,
	mode:                         Decay_Bounds_Mode,
	bounce:                       f32,
}

Decay_Snap_Axis_At_Rest_Params :: struct {
	value, bounds_min, bounds_max: f32,
	epsilon:                       f32,
}

Decay_Snap_Bounded_At_Rest_Params :: struct($T: typeid) {
	value:   T,
	config:  Decay_Config(T),
	epsilon: f32,
}

Decay_Apply_Bounds_Params :: struct($T: typeid) {
	value, velocity: T,
	config:          Decay_Config(T),
}

Decay_Apply_Bounds_Vector_Params :: struct($T: typeid) {
	value, velocity:        T,
	bounds_min, bounds_max: T,
	mode:                   Decay_Bounds_Mode,
	bounce:                 f32,
}

Decay_Integrate_Substep_Params :: struct($T: typeid) {
	value, velocity: T,
	config:          Decay_Config(T),
	dt:              f32,
	anim:            Animatable(T),
}

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

decay_velocity_speed :: proc(velocity: $T, anim: Animatable(T)) -> f32 {
	return anim.distance(anim.zero(), velocity)
}

decay_is_at_rest :: proc(p: Animatable_Query_Params($T)) -> bool {
	state := (^Decay_State(T))(p.state)
	speed := decay_velocity_speed(state.velocity, p.anim)
	return is_done(Is_Done_Params{distance_to_target = 0, speed = speed, policy = p.completion})
}

decay_init :: proc(p: Decay_Init_Params($T)) {
	p.state.config = p.config
	p.state.value = p.start_value
	p.state.velocity = p.config.initial_velocity
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
decay_snap_bounded_at_rest :: proc(p: Decay_Snap_Bounded_At_Rest_Params($T)) -> T {
	value := p.value
	config := p.config
	if config.bounds_mode != .CLAMP do return value

	when T == f32 {
		return decay_snap_axis_at_rest({value = value, bounds_min = config.bounds_min, bounds_max = config.bounds_max, epsilon = p.epsilon})
	} else when T == Vec2 {
		return {
			decay_snap_axis_at_rest({value = value.x, bounds_min = config.bounds_min.x, bounds_max = config.bounds_max.x, epsilon = p.epsilon}),
			decay_snap_axis_at_rest({value = value.y, bounds_min = config.bounds_min.y, bounds_max = config.bounds_max.y, epsilon = p.epsilon}),
		}
	} else when T == Vec3 {
		return {
			decay_snap_axis_at_rest({value = value.x, bounds_min = config.bounds_min.x, bounds_max = config.bounds_max.x, epsilon = p.epsilon}),
			decay_snap_axis_at_rest({value = value.y, bounds_min = config.bounds_min.y, bounds_max = config.bounds_max.y, epsilon = p.epsilon}),
			decay_snap_axis_at_rest({value = value.z, bounds_min = config.bounds_min.z, bounds_max = config.bounds_max.z, epsilon = p.epsilon}),
		}
	} else when T == Vec4 {
		return {
			decay_snap_axis_at_rest({value = value.x, bounds_min = config.bounds_min.x, bounds_max = config.bounds_max.x, epsilon = p.epsilon}),
			decay_snap_axis_at_rest({value = value.y, bounds_min = config.bounds_min.y, bounds_max = config.bounds_max.y, epsilon = p.epsilon}),
			decay_snap_axis_at_rest({value = value.z, bounds_min = config.bounds_min.z, bounds_max = config.bounds_max.z, epsilon = p.epsilon}),
			decay_snap_axis_at_rest({value = value.w, bounds_min = config.bounds_min.w, bounds_max = config.bounds_max.w, epsilon = p.epsilon}),
		}
	} else when T == Rect {
		return {
			decay_snap_axis_at_rest({value = value.x, bounds_min = config.bounds_min.x, bounds_max = config.bounds_max.x, epsilon = p.epsilon}),
			decay_snap_axis_at_rest({value = value.y, bounds_min = config.bounds_min.y, bounds_max = config.bounds_max.y, epsilon = p.epsilon}),
			decay_snap_axis_at_rest({value = value.w, bounds_min = config.bounds_min.w, bounds_max = config.bounds_max.w, epsilon = p.epsilon}),
			decay_snap_axis_at_rest({value = value.h, bounds_min = config.bounds_min.h, bounds_max = config.bounds_max.h, epsilon = p.epsilon}),
		}
	} else {
		return value
	}
}

@(private)
decay_integrate_exponential :: proc(p: Decay_Integrate_Exponential_Params($T)) -> (
	next_value: T,
	next_velocity: T,
) {
	safe_tau := decay_safe_time_constant(p.time_constant)
	decay_factor := math.exp(-p.dt / safe_tau)
	displacement := p.anim.scale(p.velocity, safe_tau * (1 - decay_factor))
	next_velocity = p.anim.scale(p.velocity, decay_factor)
	next_value = p.anim.add(p.value, displacement)
	return
}

@(private)
decay_bounce_scalar :: proc(velocity, bounce: f32) -> f32 {
	return velocity * clamp01(bounce)
}

@(private)
decay_apply_bounds_axis :: proc(p: Decay_Apply_Bounds_Axis_Params) -> (
	next_value: f32,
	next_velocity: f32,
) {
	if p.mode == .UNBOUNDED do return p.value, p.velocity

	next_value = p.value
	next_velocity = p.velocity

	if next_value < p.bounds_min {
		next_value = p.bounds_min
		switch p.mode {
		case .UNBOUNDED:
			unreachable()
		case .CLAMP:
			if next_velocity < 0 do next_velocity = 0
		case .BOUNCE:
			next_velocity = decay_bounce_scalar(-next_velocity, p.bounce)
		}
	} else if next_value > p.bounds_max {
		next_value = p.bounds_max
		switch p.mode {
		case .UNBOUNDED:
			unreachable()
		case .CLAMP:
			if next_velocity > 0 do next_velocity = 0
		case .BOUNCE:
			next_velocity = decay_bounce_scalar(-next_velocity, p.bounce)
		}
	}

	return
}

@(private)
decay_snap_axis_at_rest :: proc(p: Decay_Snap_Axis_At_Rest_Params) -> f32 {
	if math.abs(p.value - p.bounds_min) <= p.epsilon do return p.bounds_min
	if math.abs(p.value - p.bounds_max) <= p.epsilon do return p.bounds_max
	return p.value
}

@(private)
decay_apply_bounds_f32 :: proc(p: Decay_Apply_Bounds_Axis_Params) -> (
	next_value: f32,
	next_velocity: f32,
) {
	return decay_apply_bounds_axis(p)
}

@(private)
decay_apply_bounds_vec2 :: proc(p: Decay_Apply_Bounds_Vector_Params(Vec2)) -> (
	next_value: Vec2,
	next_velocity: Vec2,
) {
	if p.mode == .UNBOUNDED do return p.value, p.velocity

	next_value.x, next_velocity.x = decay_apply_bounds_axis({
		value = p.value.x,
		velocity = p.velocity.x,
		bounds_min = p.bounds_min.x,
		bounds_max = p.bounds_max.x,
		mode = p.mode,
		bounce = p.bounce,
	})
	next_value.y, next_velocity.y = decay_apply_bounds_axis({
		value = p.value.y,
		velocity = p.velocity.y,
		bounds_min = p.bounds_min.y,
		bounds_max = p.bounds_max.y,
		mode = p.mode,
		bounce = p.bounce,
	})
	return
}

@(private)
decay_apply_bounds_vec3 :: proc(p: Decay_Apply_Bounds_Vector_Params(Vec3)) -> (
	next_value: Vec3,
	next_velocity: Vec3,
) {
	if p.mode == .UNBOUNDED do return p.value, p.velocity

	next_value.x, next_velocity.x = decay_apply_bounds_axis({
		value = p.value.x, velocity = p.velocity.x,
		bounds_min = p.bounds_min.x, bounds_max = p.bounds_max.x,
		mode = p.mode, bounce = p.bounce,
	})
	next_value.y, next_velocity.y = decay_apply_bounds_axis({
		value = p.value.y, velocity = p.velocity.y,
		bounds_min = p.bounds_min.y, bounds_max = p.bounds_max.y,
		mode = p.mode, bounce = p.bounce,
	})
	next_value.z, next_velocity.z = decay_apply_bounds_axis({
		value = p.value.z, velocity = p.velocity.z,
		bounds_min = p.bounds_min.z, bounds_max = p.bounds_max.z,
		mode = p.mode, bounce = p.bounce,
	})
	return
}

@(private)
decay_apply_bounds_vec4 :: proc(p: Decay_Apply_Bounds_Vector_Params(Vec4)) -> (
	next_value: Vec4,
	next_velocity: Vec4,
) {
	if p.mode == .UNBOUNDED do return p.value, p.velocity

	next_value.x, next_velocity.x = decay_apply_bounds_axis({
		value = p.value.x, velocity = p.velocity.x,
		bounds_min = p.bounds_min.x, bounds_max = p.bounds_max.x,
		mode = p.mode, bounce = p.bounce,
	})
	next_value.y, next_velocity.y = decay_apply_bounds_axis({
		value = p.value.y, velocity = p.velocity.y,
		bounds_min = p.bounds_min.y, bounds_max = p.bounds_max.y,
		mode = p.mode, bounce = p.bounce,
	})
	next_value.z, next_velocity.z = decay_apply_bounds_axis({
		value = p.value.z, velocity = p.velocity.z,
		bounds_min = p.bounds_min.z, bounds_max = p.bounds_max.z,
		mode = p.mode, bounce = p.bounce,
	})
	next_value.w, next_velocity.w = decay_apply_bounds_axis({
		value = p.value.w, velocity = p.velocity.w,
		bounds_min = p.bounds_min.w, bounds_max = p.bounds_max.w,
		mode = p.mode, bounce = p.bounce,
	})
	return
}

@(private)
decay_apply_bounds_rect :: proc(p: Decay_Apply_Bounds_Vector_Params(Rect)) -> (
	next_value: Rect,
	next_velocity: Rect,
) {
	if p.mode == .UNBOUNDED do return p.value, p.velocity

	next_value.x, next_velocity.x = decay_apply_bounds_axis({
		value = p.value.x, velocity = p.velocity.x,
		bounds_min = p.bounds_min.x, bounds_max = p.bounds_max.x,
		mode = p.mode, bounce = p.bounce,
	})
	next_value.y, next_velocity.y = decay_apply_bounds_axis({
		value = p.value.y, velocity = p.velocity.y,
		bounds_min = p.bounds_min.y, bounds_max = p.bounds_max.y,
		mode = p.mode, bounce = p.bounce,
	})
	next_value.w, next_velocity.w = decay_apply_bounds_axis({
		value = p.value.w, velocity = p.velocity.w,
		bounds_min = p.bounds_min.w, bounds_max = p.bounds_max.w,
		mode = p.mode, bounce = p.bounce,
	})
	next_value.h, next_velocity.h = decay_apply_bounds_axis({
		value = p.value.h, velocity = p.velocity.h,
		bounds_min = p.bounds_min.h, bounds_max = p.bounds_max.h,
		mode = p.mode, bounce = p.bounce,
	})
	return
}

@(private)
decay_apply_bounds :: proc(p: Decay_Apply_Bounds_Params($T)) -> (
	next_value: T,
	next_velocity: T,
) {
	when T == f32 {
		return decay_apply_bounds_f32({
			value = p.value,
			velocity = p.velocity,
			bounds_min = p.config.bounds_min,
			bounds_max = p.config.bounds_max,
			mode = p.config.bounds_mode,
			bounce = p.config.bounce,
		})
	} else when T == Vec2 {
		return decay_apply_bounds_vec2(Decay_Apply_Bounds_Vector_Params(Vec2) {
			value = p.value,
			velocity = p.velocity,
			bounds_min = p.config.bounds_min,
			bounds_max = p.config.bounds_max,
			mode = p.config.bounds_mode,
			bounce = p.config.bounce,
		})
	} else when T == Vec3 {
		return decay_apply_bounds_vec3(Decay_Apply_Bounds_Vector_Params(Vec3) {
			value = p.value,
			velocity = p.velocity,
			bounds_min = p.config.bounds_min,
			bounds_max = p.config.bounds_max,
			mode = p.config.bounds_mode,
			bounce = p.config.bounce,
		})
	} else when T == Vec4 {
		return decay_apply_bounds_vec4(Decay_Apply_Bounds_Vector_Params(Vec4) {
			value = p.value,
			velocity = p.velocity,
			bounds_min = p.config.bounds_min,
			bounds_max = p.config.bounds_max,
			mode = p.config.bounds_mode,
			bounce = p.config.bounce,
		})
	} else when T == Rect {
		return decay_apply_bounds_rect(Decay_Apply_Bounds_Vector_Params(Rect) {
			value = p.value,
			velocity = p.velocity,
			bounds_min = p.config.bounds_min,
			bounds_max = p.config.bounds_max,
			mode = p.config.bounds_mode,
			bounce = p.config.bounce,
		})
	} else {
		return p.value, p.velocity
	}
}

@(private)
decay_integrate_substep :: proc(p: Decay_Integrate_Substep_Params($T)) -> (
	next_value: T,
	next_velocity: T,
) {
	integrated_value, integrated_velocity := decay_integrate_exponential(Decay_Integrate_Exponential_Params(T){
		value = p.value,
		velocity = p.velocity,
		time_constant = p.config.time_constant,
		dt = p.dt,
		anim = p.anim,
	})
	return decay_apply_bounds(Decay_Apply_Bounds_Params(T){value = integrated_value, velocity = integrated_velocity, config = p.config})
}

/*
Advances decay by `dt` seconds using deterministic substeps for large frame
times. Negative `dt` leaves state unchanged. When velocity reaches rest, it
snaps to zero while the value remains at its current position.
*/
decay_step :: proc(p: Motion_Step_Params($T)) -> Step_Result(T) {
	state := (^Decay_State(T))(p.state)
	safe_dt := sanitize_dt(p.dt)
	if safe_dt <= 0 {
		done := decay_is_at_rest(Animatable_Query_Params(T){state = p.state, anim = p.anim, completion = p.completion})
		value := state.value
		velocity := state.velocity
		if done {
			velocity = p.anim.zero()
		}
		return motion_result(Motion_Result_Params(T){value = value, velocity = velocity, done = done})
	}

	plan := plan_substeps(safe_dt, p.time)
	value := state.value
	velocity := state.velocity
	config := state.config

	for _ in 0 ..< plan.steps {
		value, velocity = decay_integrate_substep(Decay_Integrate_Substep_Params(T){
			value = value,
			velocity = velocity,
			config = config,
			dt = plan.substep_dt,
			anim = p.anim,
		})
	}

	state.value = value
	state.velocity = velocity

	speed := decay_velocity_speed(velocity, p.anim)
	done := is_done(Is_Done_Params{distance_to_target = 0, speed = speed, policy = p.completion})

	if done {
		value = decay_snap_bounded_at_rest(Decay_Snap_Bounded_At_Rest_Params(T){value = value, config = config, epsilon = p.completion.distance_epsilon})
		velocity = p.anim.zero()
		state.value = value
		state.velocity = velocity
	}

	return motion_result(Motion_Result_Params(T){value = value, velocity = velocity, done = done})
}
