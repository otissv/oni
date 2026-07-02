package tengu

import "core:math"

/*
Damped spring configuration using stiffness, damping, and mass. Displacement is
measured from `target`; `initial_velocity` is applied only when the spring is
explicitly initialized or restarted, not when the target changes mid-flight.
*/
Spring_Config :: struct($T: typeid) {
	target:           T,
	stiffness:        f32,
	damping:          f32,
	mass:             f32,
	initial_velocity: T,
}

/*
Caller-owned spring runtime state. `value` and `velocity` are the displayed
motion state; changing `config.target` continues from the current motion.
*/
Spring_State :: struct($T: typeid) {
	config:   Spring_Config(T),
	value:    T,
	velocity: T,
}

DEFAULT_SPRING_STIFFNESS :: f32(170)
DEFAULT_SPRING_DAMPING :: f32(26)
DEFAULT_SPRING_MASS :: f32(1)

MIN_SPRING_MASS :: f32(1e-6)

Spring_Displacement_Params :: struct($T: typeid) {
	value, target: T,
	anim:          Animatable(T),
}

Spring_Init_Params :: struct($T: typeid) {
	state:         ^Spring_State(T),
	config:        Spring_Config(T),
	start_value:   T,
}

Spring_Integrate_Substep_Params :: struct($T: typeid) {
	value, velocity:              T,
	target:                       T,
	stiffness, damping, mass, dt: f32,
	anim:                         Animatable(T),
}

spring_default_config :: proc(target: $T) -> Spring_Config(T) {
	return Spring_Config(T) {
		target = target,
		stiffness = DEFAULT_SPRING_STIFFNESS,
		damping = DEFAULT_SPRING_DAMPING,
		mass = DEFAULT_SPRING_MASS,
		initial_velocity = {},
	}
}

spring_velocity_speed :: proc(velocity: $T, anim: Animatable(T)) -> f32 {
	return anim.distance(anim.zero(), velocity)
}

spring_displacement :: proc(p: Spring_Displacement_Params($T)) -> f32 {
	return p.anim.distance(p.value, p.target)
}

spring_is_at_rest :: proc(p: Animatable_Query_Params($T)) -> bool {
	state := (^Spring_State(T))(p.state)
	displacement := spring_displacement(Spring_Displacement_Params(T){value = state.value, target = state.config.target, anim = p.anim})
	speed := spring_velocity_speed(state.velocity, p.anim)
	return is_done(Is_Done_Params{distance_to_target = displacement, speed = speed, policy = p.completion})
}

spring_init :: proc(p: Spring_Init_Params($T)) {
	p.state.config = p.config
	p.state.value = p.start_value
	p.state.velocity = p.config.initial_velocity
}

/*
Updates only the target. Position and velocity continue unchanged so the spring
settles toward the new target from the current displayed value.
*/
spring_set_target :: proc(state: ^Spring_State($T), target: T) {
	state.config.target = target
}

/*
Replaces configuration while preserving the current displayed motion. Use
`spring_restart` to apply `initial_velocity` again from a chosen value.
*/
spring_reconfigure :: proc(state: ^Spring_State($T), config: Spring_Config(T)) {
	state.config = config
}

spring_restart :: proc(state: ^Spring_State($T), value: T) {
	state.value = value
	state.velocity = state.config.initial_velocity
}

@(private)
spring_integrate_substep :: proc(p: Spring_Integrate_Substep_Params($T)) -> (
	next_value: T,
	next_velocity: T,
) {
	safe_mass := math.max(p.mass, MIN_SPRING_MASS)
	displacement := p.anim.sub(p.value, p.target)
	spring_force := p.anim.scale(displacement, -p.stiffness)
	damping_force := p.anim.scale(p.velocity, -p.damping)
	acceleration := p.anim.scale(p.anim.add(spring_force, damping_force), 1 / safe_mass)

	next_velocity = p.anim.add(p.velocity, p.anim.scale(acceleration, p.dt))
	next_value = p.anim.add(p.value, p.anim.scale(next_velocity, p.dt))
	return
}

/*
Advances the spring by `dt` seconds using deterministic substeps for large
frame times. Negative `dt` leaves state unchanged. When the spring is at rest,
the value snaps to `target` and velocity becomes zero.
*/
spring_step :: proc(p: Motion_Step_Params($T)) -> Step_Result(T) {
	state := (^Spring_State(T))(p.state)
	safe_dt := sanitize_dt(p.dt)
	if safe_dt <= 0 {
		done := spring_is_at_rest(Animatable_Query_Params(T){state = p.state, anim = p.anim, completion = p.completion})
		value := state.value
		velocity := state.velocity
		if done {
			value = snap_if_done(Snap_If_Done_Params(T){value = value, target = state.config.target, done = true, policy = p.completion})
			velocity = p.anim.zero()
		}
		return motion_result(Motion_Result_Params(T){value = value, velocity = velocity, done = done})
	}

	plan := plan_substeps(safe_dt, p.time)
	value := state.value
	velocity := state.velocity
	target := state.config.target
	stiffness := state.config.stiffness
	damping := state.config.damping
	mass := state.config.mass

	for _ in 0 ..< plan.steps {
		value, velocity = spring_integrate_substep(Spring_Integrate_Substep_Params(T){
			value = value,
			velocity = velocity,
			target = target,
			stiffness = stiffness,
			damping = damping,
			mass = mass,
			dt = plan.substep_dt,
			anim = p.anim,
		})
	}

	state.value = value
	state.velocity = velocity

	displacement := spring_displacement(Spring_Displacement_Params(T){value = value, target = target, anim = p.anim})
	speed := spring_velocity_speed(velocity, p.anim)
	done := is_done(Is_Done_Params{distance_to_target = displacement, speed = speed, policy = p.completion})

	if done {
		value = snap_if_done(Snap_If_Done_Params(T){value = value, target = target, done = true, policy = p.completion})
		velocity = p.anim.zero()
		state.value = value
		state.velocity = velocity
	}

	return motion_result(Motion_Result_Params(T){value = value, velocity = velocity, done = done})
}
