package tengu

import "core:math"

/*
Immediate-mode transition slots wrap finalized tween and spring primitives. Callers
declare a desired value each frame; the slot owns persistent animator state and
applies start-from-current behavior on target changes by default.
*/
Start_Policy :: enum {
	FROM_CURRENT,
	FROM_START,
}

Transition_Kind :: enum {
	TWEEN,
	SPRING,
}

/*
Tween parameters for slot use. `start` is used only when `Start_Policy.FROM_START`
is active on the slot.
*/
Tween_Slot_Options :: struct($T: typeid) {
	duration:     Seconds,
	delay:        Seconds,
	easing:       Tween_Easing,
	repeat_count: int,
	repeat_mode:  Tween_Repeat_Mode,
	start:        T,
}

/*
Spring parameters for slot use. `start` is used only when `Start_Policy.FROM_START`
is active on the slot.
*/
Spring_Slot_Options :: struct($T: typeid) {
	stiffness:        f32,
	damping:          f32,
	mass:             f32,
	initial_velocity: T,
	start:            T,
}

/*
Persistent caller-owned state for one animated property.
*/
Slot :: struct($T: typeid) {
	kind:         Transition_Kind,
	start_policy: Start_Policy,
	active:       bool,
	target:       T,
	value:        T,
	done:         bool,
	tween:        Tween_State(T),
	spring:       Spring_State(T),
	tween_opts:   Tween_Slot_Options(T),
	spring_opts:  Spring_Slot_Options(T),
}

tween_easing_eq :: proc(a, b: Tween_Easing) -> bool {
	switch va in a {
	case Ease:
		vb, ok := b.(Ease)
		return ok && va == vb
	case Bezier:
		vb, ok := b.(Bezier)
		return ok && va == vb
	}
	return false
}

tween_slot_options_eq :: proc(a, b: Tween_Slot_Options($T), anim: Animatable(T)) -> bool {
	return(
		a.duration == b.duration &&
		a.delay == b.delay &&
		tween_easing_eq(a.easing, b.easing) &&
		a.repeat_count == b.repeat_count &&
		a.repeat_mode == b.repeat_mode &&
		anim.distance(a.start, b.start) <= DEFAULT_DISTANCE_EPSILON \
	)
}

spring_slot_options_eq :: proc(a, b: Spring_Slot_Options($T), anim: Animatable(T)) -> bool {
	return(
		a.stiffness == b.stiffness &&
		a.damping == b.damping &&
		a.mass == b.mass &&
		anim.distance(a.initial_velocity, b.initial_velocity) <= DEFAULT_DISTANCE_EPSILON &&
		anim.distance(a.start, b.start) <= DEFAULT_DISTANCE_EPSILON \
	)
}

slot_target_eq :: proc(a, b: $T, anim: Animatable(T)) -> bool {
	return anim.distance(a, b) <= DEFAULT_DISTANCE_EPSILON
}

tween_slot_options :: proc(
	start: $T,
	duration: Seconds,
	delay: Seconds = 0,
	easing: Tween_Easing = Ease.LINEAR,
	repeat_count: int = 1,
	repeat_mode: Tween_Repeat_Mode = .RESTART,
) -> Tween_Slot_Options(T) {
	return Tween_Slot_Options(T) {
		duration = duration,
		delay = delay,
		easing = easing,
		repeat_count = repeat_count,
		repeat_mode = repeat_mode,
		start = start,
	}
}

spring_slot_options :: proc(
	start: $T,
	stiffness: f32 = DEFAULT_SPRING_STIFFNESS,
	damping: f32 = DEFAULT_SPRING_DAMPING,
	mass: f32 = DEFAULT_SPRING_MASS,
) -> Spring_Slot_Options(T) {
	zero: T
	return Spring_Slot_Options(T) {
		stiffness = stiffness,
		damping = damping,
		mass = mass,
		initial_velocity = zero,
		start = start,
	}
}

spring_slot_options_with_velocity :: proc(
	start: $T,
	initial_velocity: T,
	stiffness: f32 = DEFAULT_SPRING_STIFFNESS,
	damping: f32 = DEFAULT_SPRING_DAMPING,
	mass: f32 = DEFAULT_SPRING_MASS,
) -> Spring_Slot_Options(T) {
	return Spring_Slot_Options(T) {
		stiffness = stiffness,
		damping = damping,
		mass = mass,
		initial_velocity = initial_velocity,
		start = start,
	}
}

spring_slot_options_from_frequency :: proc(
	start: $T,
	frequency: f32,
	damping_ratio: f32,
	mass: f32 = DEFAULT_SPRING_MASS,
) -> Spring_Slot_Options(T) {
	zero: T
	return spring_slot_options_from_frequency_with_velocity(
		start,
		zero,
		frequency,
		damping_ratio,
		mass,
	)
}

spring_slot_options_from_frequency_with_velocity :: proc(
	start: $T,
	initial_velocity: T,
	frequency: f32,
	damping_ratio: f32,
	mass: f32 = DEFAULT_SPRING_MASS,
) -> Spring_Slot_Options(T) {
	safe_mass := math.max(mass, MIN_SPRING_MASS)
	omega := f32(2 * math.PI) * frequency
	stiffness := safe_mass * omega * omega
	damping := 2 * safe_mass * damping_ratio * omega
	return spring_slot_options_with_velocity(
		start,
		initial_velocity,
		stiffness,
		damping,
		safe_mass,
	)
}

slot_init :: proc(
	slot: ^Slot($T),
	value: T,
	kind: Transition_Kind,
	start_policy: Start_Policy = .FROM_CURRENT,
) {
	slot.kind = kind
	slot.start_policy = start_policy
	slot.active = false
	slot.target = value
	slot.value = value
	slot.done = true
}

slot_set_start_policy :: proc(slot: ^Slot($T), policy: Start_Policy) {
	slot.start_policy = policy
}

slot_value :: proc(slot: Slot($T)) -> T {
	return slot.value
}

slot_target :: proc(slot: Slot($T)) -> T {
	return slot.target
}

slot_is_active :: proc(slot: Slot($T)) -> bool {
	return slot.active
}

slot_is_done :: proc(slot: Slot($T)) -> bool {
	return slot.done
}

slot_reset :: proc(slot: ^Slot($T), value: T) {
	slot.active = false
	slot.target = value
	slot.value = value
	slot.done = true
}

@(private)
slot_tween_config :: proc(start, target: $T, options: Tween_Slot_Options(T)) -> Tween_Config(T) {
	return Tween_Config(T) {
		start = start,
		target = target,
		duration = options.duration,
		delay = options.delay,
		easing = options.easing,
		repeat_count = options.repeat_count,
		repeat_mode = options.repeat_mode,
	}
}

@(private)
slot_spring_config :: proc(target: $T, options: Spring_Slot_Options(T)) -> Spring_Config(T) {
	return Spring_Config(T) {
		target = target,
		stiffness = options.stiffness,
		damping = options.damping,
		mass = options.mass,
		initial_velocity = options.initial_velocity,
	}
}

@(private)
slot_begin_tween :: proc(slot: ^Slot($T), target: T, options: Tween_Slot_Options(T), start: T) {
	tween_init(&slot.tween, slot_tween_config(start, target, options))
	slot.tween_opts = options
	slot.kind = .TWEEN
	slot.active = true
	slot.target = target
	slot.value = start
	slot.done = false
}

@(private)
slot_begin_spring :: proc(slot: ^Slot($T), target: T, options: Spring_Slot_Options(T), start: T) {
	spring_init(&slot.spring, slot_spring_config(target, options), start)
	slot.spring_opts = options
	slot.kind = .SPRING
	slot.active = true
	slot.target = target
	slot.value = start
	slot.done = false
}

@(private)
slot_tween_start_for_change :: proc(slot: ^Slot($T), options: Tween_Slot_Options(T)) -> T {
	if slot.start_policy == .FROM_START {
		return options.start
	}
	return slot.value
}

@(private)
slot_sync_spring :: proc(
	slot: ^Slot($T),
	target: T,
	options: Spring_Slot_Options(T),
	anim: Animatable(T),
) {
	target_changed := !slot.active || !slot_target_eq(slot.target, target, anim)
	config_changed := !slot.active || !spring_slot_options_eq(slot.spring_opts, options, anim)

	if !slot.active || slot.kind != .SPRING {
		start := slot.value
		if slot.start_policy == .FROM_START {
			start = options.start
		}
		slot_begin_spring(slot, target, options, start)
		return
	}

	if target_changed && slot.start_policy == .FROM_START {
		slot_begin_spring(slot, target, options, options.start)
		return
	}

	if config_changed {
		spring_reconfigure(&slot.spring, slot_spring_config(target, options))
		slot.spring_opts = options
	}

	if target_changed {
		spring_set_target(&slot.spring, target)
		slot.target = target
	}
}

@(private)
slot_sync_tween :: proc(
	slot: ^Slot($T),
	target: T,
	options: Tween_Slot_Options(T),
	anim: Animatable(T),
) {
	target_changed := !slot.active || !slot_target_eq(slot.target, target, anim)
	config_changed := !slot.active || !tween_slot_options_eq(slot.tween_opts, options, anim)

	if !slot.active || slot.kind != .TWEEN {
		start := slot.value
		if slot.start_policy == .FROM_START {
			start = options.start
		}
		slot_begin_tween(slot, target, options, start)
		return
	}

	if !target_changed && !config_changed {
		return
	}

	start := slot_tween_start_for_change(slot, options)
	slot_begin_tween(slot, target, options, start)
}

tween_to :: proc(
	slot: ^Slot($T),
	target: T,
	dt: f32,
	options: Tween_Slot_Options(T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> Step_Result(T) {
	slot_sync_tween(slot, target, options, anim)
	result := tween_step(&slot.tween, dt, anim, completion)
	slot.value = result.value
	slot.done = result.done
	slot.target = target
	return result
}

spring_to :: proc(
	slot: ^Slot($T),
	target: T,
	dt: f32,
	options: Spring_Slot_Options(T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
	time: Time_Policy = DEFAULT_TIME_POLICY,
) -> Step_Result(T) {
	slot_sync_spring(slot, target, options, anim)
	result := spring_step(&slot.spring, dt, anim, completion, time)
	slot.value = result.value
	slot.done = result.done
	slot.target = target
	return result
}

/*
Steps the slot using its stored transition kind and options.
*/
transition_to :: proc(
	slot: ^Slot($T),
	target: T,
	dt: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
	time: Time_Policy = DEFAULT_TIME_POLICY,
) -> Step_Result(T) {
	switch slot.kind {
	case .TWEEN:
		return tween_to(slot, target, dt, slot.tween_opts, anim, completion)
	case .SPRING:
		return spring_to(slot, target, dt, slot.spring_opts, anim, completion, time)
	}
	unreachable()
}

/*
Restarts the active transition from the configured start value without changing
target or options.
*/
slot_restart :: proc(slot: ^Slot($T)) {
	if !slot.active do return

	switch slot.kind {
	case .TWEEN:
		start := slot.tween_opts.start
		if slot.start_policy == .FROM_CURRENT {
			start = slot.value
		}
		slot_begin_tween(slot, slot.target, slot.tween_opts, start)
	case .SPRING:
		start := slot.spring_opts.start
		if slot.start_policy == .FROM_CURRENT {
			start = slot.value
		}
		slot_begin_spring(slot, slot.target, slot.spring_opts, start)
	}
}
