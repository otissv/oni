package tengu

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

Slot_Init_Params :: struct($T: typeid) {
	slot:         ^Slot(T),
	value:        T,
	kind:         Transition_Kind,
	start_policy: Start_Policy,
}

Tween_To_Params :: struct($T: typeid) {
	slot:       ^Slot(T),
	target:     T,
	dt:         f32,
	options:    Tween_Slot_Options(T),
	anim:       Animatable(T),
	completion: Completion_Policy,
}

Spring_To_Params :: struct($T: typeid) {
	slot:       ^Slot(T),
	target:     T,
	dt:         f32,
	options:    Spring_Slot_Options(T),
	anim:       Animatable(T),
	completion: Completion_Policy,
	time:       Time_Policy,
}

Transition_To_Params :: struct($T: typeid) {
	slot:       ^Slot(T),
	target:     T,
	dt:         f32,
	anim:       Animatable(T),
	completion: Completion_Policy,
	time:       Time_Policy,
}

Slot_Sync_Spring_Params :: struct($T: typeid) {
	slot:    ^Slot(T),
	target:  T,
	options: Spring_Slot_Options(T),
	anim:    Animatable(T),
}

Slot_Sync_Tween_Params :: struct($T: typeid) {
	slot:    ^Slot(T),
	target:  T,
	options: Tween_Slot_Options(T),
	anim:    Animatable(T),
}

Slot_Begin_Tween_Params :: struct($T: typeid) {
	slot:    ^Slot(T),
	target:  T,
	options: Tween_Slot_Options(T),
	start:   T,
}

Slot_Begin_Spring_Params :: struct($T: typeid) {
	slot:    ^Slot(T),
	target:  T,
	options: Spring_Slot_Options(T),
	start:   T,
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

slot_init :: proc(p: Slot_Init_Params($T)) {
	p.slot.kind = p.kind
	p.slot.start_policy = p.start_policy
	p.slot.active = false
	p.slot.target = p.value
	p.slot.value = p.value
	p.slot.done = true
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
slot_begin_tween :: proc(p: Slot_Begin_Tween_Params($T)) {
	tween_init(&p.slot.tween, slot_tween_config(p.start, p.target, p.options))
	p.slot.tween_opts = p.options
	p.slot.kind = .TWEEN
	p.slot.active = true
	p.slot.target = p.target
	p.slot.value = p.start
	p.slot.done = false
}

@(private)
slot_begin_spring :: proc(p: Slot_Begin_Spring_Params($T)) {
	spring_init(
		Spring_Init_Params(T) {
			state = &p.slot.spring,
			config = slot_spring_config(p.target, p.options),
			start_value = p.start,
		},
	)
	p.slot.spring_opts = p.options
	p.slot.kind = .SPRING
	p.slot.active = true
	p.slot.target = p.target
	p.slot.value = p.start
	p.slot.done = false
}

@(private)
slot_tween_start_for_change :: proc(slot: ^Slot($T), options: Tween_Slot_Options(T)) -> T {
	if slot.start_policy == .FROM_START {
		return options.start
	}
	return slot.value
}

@(private)
slot_sync_spring :: proc(p: Slot_Sync_Spring_Params($T)) {
	target_changed := !p.slot.active || !slot_target_eq(p.slot.target, p.target, p.anim)
	config_changed :=
		!p.slot.active || !spring_slot_options_eq(p.slot.spring_opts, p.options, p.anim)

	if !p.slot.active || p.slot.kind != .SPRING {
		start := p.slot.value
		if p.slot.start_policy == .FROM_START {
			start = p.options.start
		}
		slot_begin_spring(
			Slot_Begin_Spring_Params(T) {
				slot = p.slot,
				target = p.target,
				options = p.options,
				start = start,
			},
		)
		return
	}

	if target_changed && p.slot.start_policy == .FROM_START {
		slot_begin_spring(
			Slot_Begin_Spring_Params(T) {
				slot = p.slot,
				target = p.target,
				options = p.options,
				start = p.options.start,
			},
		)
		return
	}

	if config_changed {
		spring_reconfigure(&p.slot.spring, slot_spring_config(p.target, p.options))
		p.slot.spring_opts = p.options
	}

	if target_changed {
		spring_set_target(&p.slot.spring, p.target)
		p.slot.target = p.target
	}
}

@(private)
slot_sync_tween :: proc(p: Slot_Sync_Tween_Params($T)) {
	target_changed := !p.slot.active || !slot_target_eq(p.slot.target, p.target, p.anim)
	config_changed :=
		!p.slot.active || !tween_slot_options_eq(p.slot.tween_opts, p.options, p.anim)

	if !p.slot.active || p.slot.kind != .TWEEN {
		start := p.slot.value
		if p.slot.start_policy == .FROM_START {
			start = p.options.start
		}
		slot_begin_tween(
			Slot_Begin_Tween_Params(T) {
				slot = p.slot,
				target = p.target,
				options = p.options,
				start = start,
			},
		)
		return
	}

	if !target_changed && !config_changed {
		return
	}

	start := slot_tween_start_for_change(p.slot, p.options)
	slot_begin_tween(
		Slot_Begin_Tween_Params(T) {
			slot = p.slot,
			target = p.target,
			options = p.options,
			start = start,
		},
	)
}

tween_to :: proc(p: Tween_To_Params($T)) -> Step_Result(T) {
	slot_sync_tween(
		Slot_Sync_Tween_Params(T) {
			slot = p.slot,
			target = p.target,
			options = p.options,
			anim = p.anim,
		},
	)
	result := tween_step(
		Step_Params(T){state = &p.slot.tween, dt = p.dt, anim = p.anim, completion = p.completion},
	)
	p.slot.value = result.value
	p.slot.done = result.done
	p.slot.target = p.target
	return result
}

spring_to :: proc(p: Spring_To_Params($T)) -> Step_Result(T) {
	slot_sync_spring(
		Slot_Sync_Spring_Params(T) {
			slot = p.slot,
			target = p.target,
			options = p.options,
			anim = p.anim,
		},
	)
	result := spring_step(
		Motion_Step_Params(T) {
			state = &p.slot.spring,
			dt = p.dt,
			anim = p.anim,
			completion = p.completion,
			time = p.time,
		},
	)
	p.slot.value = result.value
	p.slot.done = result.done
	p.slot.target = p.target
	return result
}

/*
Steps the slot using its stored transition kind and options.
*/
transition_to :: proc(p: Transition_To_Params($T)) -> Step_Result(T) {
	switch p.slot.kind {
	case .TWEEN:
		return tween_to(
			Tween_To_Params(T) {
				slot = p.slot,
				target = p.target,
				dt = p.dt,
				options = p.slot.tween_opts,
				anim = p.anim,
				completion = p.completion,
			},
		)
	case .SPRING:
		return spring_to(
			Spring_To_Params(T) {
				slot = p.slot,
				target = p.target,
				dt = p.dt,
				options = p.slot.spring_opts,
				anim = p.anim,
				completion = p.completion,
				time = p.time,
			},
		)
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
		slot_begin_tween(
			Slot_Begin_Tween_Params(T) {
				slot = slot,
				target = slot.target,
				options = slot.tween_opts,
				start = start,
			},
		)
	case .SPRING:
		start := slot.spring_opts.start
		if slot.start_policy == .FROM_CURRENT {
			start = slot.value
		}
		slot_begin_spring(
			Slot_Begin_Spring_Params(T) {
				slot = slot,
				target = slot.target,
				options = slot.spring_opts,
				start = start,
			},
		)
	}
}
