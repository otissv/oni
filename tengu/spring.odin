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

spring_default_config :: proc(target: $T) -> Spring_Config(T) {
	return Spring_Config(T) {
		target = target,
		stiffness = DEFAULT_SPRING_STIFFNESS,
		damping = DEFAULT_SPRING_DAMPING,
		mass = DEFAULT_SPRING_MASS,
		initial_velocity = {},
	}
}

spring_config :: proc(
	target: $T,
	stiffness: f32 = DEFAULT_SPRING_STIFFNESS,
	damping: f32 = DEFAULT_SPRING_DAMPING,
	mass: f32 = DEFAULT_SPRING_MASS,
) -> Spring_Config(T) {
	return Spring_Config(T) {
		target = target,
		stiffness = stiffness,
		damping = damping,
		mass = mass,
		initial_velocity = {},
	}
}

spring_config_with_velocity :: proc(
	target: $T,
	initial_velocity: T,
	stiffness: f32 = DEFAULT_SPRING_STIFFNESS,
	damping: f32 = DEFAULT_SPRING_DAMPING,
	mass: f32 = DEFAULT_SPRING_MASS,
) -> Spring_Config(T) {
	return Spring_Config(T) {
		target = target,
		stiffness = stiffness,
		damping = damping,
		mass = mass,
		initial_velocity = initial_velocity,
	}
}

/*
Builds a stiffness/damping/mass configuration from natural frequency in hertz
and a unitless damping ratio. Critical damping uses `damping_ratio = 1`.
*/
spring_config_from_frequency :: proc(
	target: $T,
	frequency: f32,
	damping_ratio: f32,
	mass: f32 = DEFAULT_SPRING_MASS,
) -> Spring_Config(T) {
	safe_mass := math.max(mass, MIN_SPRING_MASS)
	omega := f32(2 * math.PI) * frequency
	stiffness := safe_mass * omega * omega
	damping := 2 * safe_mass * damping_ratio * omega
	return spring_config(target, stiffness, damping, safe_mass)
}

spring_config_from_frequency_with_velocity :: proc(
	target: $T,
	initial_velocity: T,
	frequency: f32,
	damping_ratio: f32,
	mass: f32 = DEFAULT_SPRING_MASS,
) -> Spring_Config(T) {
	config := spring_config_from_frequency(target, frequency, damping_ratio, mass)
	config.initial_velocity = initial_velocity
	return config
}

spring_velocity_speed :: proc(velocity: $T, anim: Animatable(T)) -> f32 {
	return anim.distance(anim.zero(), velocity)
}

spring_displacement :: proc(value, target: $T, anim: Animatable(T)) -> f32 {
	return anim.distance(value, target)
}

spring_is_at_rest :: proc(
	state: Spring_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	displacement := spring_displacement(state.value, state.config.target, anim)
	speed := spring_velocity_speed(state.velocity, anim)
	return is_done(displacement, speed, completion)
}

spring_init :: proc(state: ^Spring_State($T), config: Spring_Config(T), start_value: T) {
	state.config = config
	state.value = start_value
	state.velocity = config.initial_velocity
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
spring_integrate_substep :: proc(
	value, velocity: $T,
	target: T,
	stiffness, damping, mass, dt: f32,
	anim: Animatable(T),
) -> (
	next_value: T,
	next_velocity: T,
) {
	safe_mass := math.max(mass, MIN_SPRING_MASS)
	displacement := anim.sub(value, target)
	spring_force := anim.scale(displacement, -stiffness)
	damping_force := anim.scale(velocity, -damping)
	acceleration := anim.scale(anim.add(spring_force, damping_force), 1 / safe_mass)

	next_velocity = anim.add(velocity, anim.scale(acceleration, dt))
	next_value = anim.add(value, anim.scale(next_velocity, dt))
	return
}

/*
Advances the spring by `dt` seconds using deterministic substeps for large
frame times. Negative `dt` leaves state unchanged. When the spring is at rest,
the value snaps to `target` and velocity becomes zero.
*/
spring_step :: proc(
	state: ^Spring_State($T),
	dt: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
	time: Time_Policy = DEFAULT_TIME_POLICY,
) -> Step_Result(T) {
	safe_dt := sanitize_dt(dt)
	if safe_dt <= 0 {
		done := spring_is_at_rest(state^, anim, completion)
		value := state.value
		velocity := state.velocity
		if done {
			value = snap_if_done(value, state.config.target, true, completion)
			velocity = anim.zero()
		}
		return motion_result(value, velocity, done)
	}

	plan := plan_substeps(safe_dt, time)
	value := state.value
	velocity := state.velocity
	target := state.config.target
	stiffness := state.config.stiffness
	damping := state.config.damping
	mass := state.config.mass

	for _ in 0 ..< plan.steps {
		value, velocity = spring_integrate_substep(
			value,
			velocity,
			target,
			stiffness,
			damping,
			mass,
			plan.substep_dt,
			anim,
		)
	}

	state.value = value
	state.velocity = velocity

	displacement := spring_displacement(value, target, anim)
	speed := spring_velocity_speed(velocity, anim)
	done := is_done(displacement, speed, completion)

	if done {
		value = snap_if_done(value, target, true, completion)
		velocity = anim.zero()
		state.value = value
		state.velocity = velocity
	}

	return motion_result(value, velocity, done)
}
