package tengu

import "core:math"

Stepper_Tag :: enum u8 {
	Tween,
	Spring,
	Keyframes,
	Decay,
	Delay,
	Sequence,
	Parallel,
	Repeat,
	Stagger,
	Timeline,
}

/*
Uniform step interface for composition. Each stepper references caller-owned state
through `state`; composition combinators never allocate child animator state.
*/
Stepper :: struct($T: typeid) {
	state: rawptr,
	tag:   Stepper_Tag,
}

stepper_step :: proc(
	stepper: Stepper($T),
	dt: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> Step_Result(T) {
	safe_dt := sanitize_dt(dt)
	switch stepper.tag {
	case .Tween:
		return tween_step((^Tween_State(T))(stepper.state), safe_dt, anim, completion)
	case .Spring:
		return spring_step((^Spring_State(T))(stepper.state), safe_dt, anim, completion)
	case .Keyframes:
		return keyframes_step((^Keyframes_State(T))(stepper.state), safe_dt, anim, completion)
	case .Decay:
		return decay_step((^Decay_State(T))(stepper.state), safe_dt, anim, completion)
	case .Delay:
		return delay_step((^Delay_State(T))(stepper.state), safe_dt, anim, completion)
	case .Sequence:
		return sequence_step((^Sequence_State(T))(stepper.state), safe_dt, anim, completion)
	case .Parallel:
		return parallel_step((^Parallel_State(T))(stepper.state), safe_dt, anim, completion)
	case .Repeat:
		return repeat_step((^Repeat_State(T))(stepper.state), safe_dt, anim, completion)
	case .Stagger:
		return stagger_step((^Stagger_State(T))(stepper.state), safe_dt, anim, completion)
	case .Timeline:
		return timeline_step((^Timeline_State(T))(stepper.state), safe_dt, anim, completion)
	}
	unreachable()
}

stepper_is_done :: proc(
	stepper: Stepper($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	switch stepper.tag {
	case .Tween:
		return tween_is_finished((^Tween_State(T))(stepper.state)^)
	case .Spring:
		return spring_is_at_rest((^Spring_State(T))(stepper.state)^, anim, completion)
	case .Keyframes:
		return keyframes_is_finished((^Keyframes_State(T))(stepper.state)^)
	case .Decay:
		return decay_is_at_rest((^Decay_State(T))(stepper.state)^, anim, completion)
	case .Delay:
		return delay_is_finished((^Delay_State(T))(stepper.state)^, anim, completion)
	case .Sequence:
		return sequence_is_finished((^Sequence_State(T))(stepper.state)^, anim, completion)
	case .Parallel:
		return parallel_is_finished((^Parallel_State(T))(stepper.state)^, anim, completion)
	case .Repeat:
		return repeat_is_finished((^Repeat_State(T))(stepper.state)^, anim, completion)
	case .Stagger:
		return stagger_is_finished((^Stagger_State(T))(stepper.state)^, anim, completion)
	case .Timeline:
		return timeline_is_finished((^Timeline_State(T))(stepper.state)^, anim, completion)
	}
	unreachable()
}

stepper_restart :: proc(stepper: Stepper($T)) {
	switch stepper.tag {
	case .Tween:
		tween_restart((^Tween_State(T))(stepper.state))
	case .Spring:
		spring := (^Spring_State(T))(stepper.state)
		spring_restart(spring, spring.value)
	case .Keyframes:
		keyframes_restart((^Keyframes_State(T))(stepper.state))
	case .Decay:
		decay := (^Decay_State(T))(stepper.state)
		decay_restart(decay, decay.value)
	case .Delay:
		delay_restart((^Delay_State(T))(stepper.state))
	case .Sequence:
		sequence_restart((^Sequence_State(T))(stepper.state))
	case .Parallel:
		parallel_restart((^Parallel_State(T))(stepper.state))
	case .Repeat:
		repeat_restart((^Repeat_State(T))(stepper.state))
	case .Stagger:
		stagger_restart((^Stagger_State(T))(stepper.state))
	case .Timeline:
		timeline_restart((^Timeline_State(T))(stepper.state))
	}
}

stepper_reset_to :: proc(stepper: Stepper($T), value: T) {
	switch stepper.tag {
	case .Tween:
		tween_restart((^Tween_State(T))(stepper.state))
	case .Spring:
		spring_restart((^Spring_State(T))(stepper.state), value)
	case .Keyframes:
		keyframes_restart((^Keyframes_State(T))(stepper.state))
	case .Decay:
		decay_restart((^Decay_State(T))(stepper.state), value)
	case .Delay:
		delay := (^Delay_State(T))(stepper.state)
		delay.hold_value = value
		delay_restart(delay)
	case .Sequence:
		sequence_restart((^Sequence_State(T))(stepper.state))
	case .Parallel:
		parallel_restart((^Parallel_State(T))(stepper.state))
	case .Repeat:
		repeat := (^Repeat_State(T))(stepper.state)
		repeat.cycle_start = value
		repeat_restart(repeat)
	case .Stagger:
		stagger_restart((^Stagger_State(T))(stepper.state))
	case .Timeline:
		timeline_restart((^Timeline_State(T))(stepper.state))
	}
}

tween_stepper :: proc(state: ^Tween_State($T)) -> Stepper(T) {
	return Stepper(T){state = state, tag = .Tween}
}

spring_stepper :: proc(state: ^Spring_State($T)) -> Stepper(T) {
	return Stepper(T){state = state, tag = .Spring}
}

keyframes_stepper :: proc(state: ^Keyframes_State($T)) -> Stepper(T) {
	return Stepper(T){state = state, tag = .Keyframes}
}

decay_stepper :: proc(state: ^Decay_State($T)) -> Stepper(T) {
	return Stepper(T){state = state, tag = .Decay}
}

/*
Holds `hold_value` for `delay` seconds, then runs `child`. Overflow `dt` crossing
the delay boundary is applied to the child in the same step.
*/
Delay_State :: struct($T: typeid) {
	child:      Stepper(T),
	delay:      f32,
	elapsed:    f32,
	hold_value: T,
}

delay_init :: proc(state: ^Delay_State($T), child: Stepper(T), delay: f32, hold_value: T) {
	state.child = child
	state.delay = delay
	state.elapsed = 0
	state.hold_value = hold_value
}

delay_is_finished :: proc(
	state: Delay_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	if state.elapsed < state.delay do return false
	return stepper_is_done(state.child, anim, completion)
}

delay_restart :: proc(state: ^Delay_State($T)) {
	state.elapsed = 0
	stepper_restart(state.child)
}

delay_step :: proc(
	state: ^Delay_State($T),
	dt: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> Step_Result(T) {
	if state.elapsed < state.delay {
		if dt <= 0 {
			return value_result(state.hold_value, false)
		}

		remaining := state.delay - state.elapsed
		if dt < remaining {
			state.elapsed += dt
			return value_result(state.hold_value, false)
		}

		state.elapsed = state.delay
		overflow := dt - remaining
		if overflow <= 0 {
			return value_result(state.hold_value, false)
		}
		return stepper_step(state.child, overflow, anim, completion)
	}

	return stepper_step(state.child, dt, anim, completion)
}

delay_stepper :: proc(state: ^Delay_State($T)) -> Stepper(T) {
	return Stepper(T){state = state, tag = .Delay}
}

/*
Runs `children` one after another. The caller keeps the `children` slice alive for
the lifetime of the sequence state.
*/
Sequence_State :: struct($T: typeid) {
	children: []Stepper(T),
	index:    int,
}

sequence_init :: proc(state: ^Sequence_State($T), children: []Stepper(T)) {
	state.children = children
	state.index = 0
}

sequence_is_finished :: proc(
	state: Sequence_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	if len(state.children) == 0 do return true
	if state.index >= len(state.children) do return true
	if state.index < len(state.children) - 1 do return false
	return stepper_is_done(state.children[state.index], anim, completion)
}

sequence_restart :: proc(state: ^Sequence_State($T)) {
	state.index = 0
	for child in state.children {
		stepper_restart(child)
	}
}

sequence_step :: proc(
	state: ^Sequence_State($T),
	dt: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> Step_Result(T) {
	if len(state.children) == 0 {
		return value_result(anim.zero(), true)
	}

	if state.index >= len(state.children) {
		last := state.children[len(state.children) - 1]
		result := stepper_step(last, 0, anim, completion)
		result.done = true
		return result
	}

	remaining_dt := dt
	for state.index < len(state.children) {
		result := stepper_step(state.children[state.index], remaining_dt, anim, completion)
		if !result.done || state.index >= len(state.children) - 1 {
			return result
		}
		state.index += 1
		remaining_dt = 0
	}

	last := state.children[len(state.children) - 1]
	result := stepper_step(last, 0, anim, completion)
	result.done = true
	return result
}

sequence_stepper :: proc(state: ^Sequence_State($T)) -> Stepper(T) {
	return Stepper(T){state = state, tag = .Sequence}
}

/*
Steps every child each frame. The returned value and velocity come from
`primary_index`.
*/
Parallel_State :: struct($T: typeid) {
	children:      []Stepper(T),
	primary_index: int,
}

parallel_init :: proc(state: ^Parallel_State($T), children: []Stepper(T), primary_index: int = 0) {
	state.children = children
	if primary_index < 0 || primary_index >= len(children) {
		state.primary_index = 0
	} else {
		state.primary_index = primary_index
	}
}

parallel_is_finished :: proc(
	state: Parallel_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	if len(state.children) == 0 do return true
	for child in state.children {
		if !stepper_is_done(child, anim, completion) do return false
	}
	return true
}

parallel_restart :: proc(state: ^Parallel_State($T)) {
	for child in state.children {
		stepper_restart(child)
	}
}

parallel_step :: proc(
	state: ^Parallel_State($T),
	dt: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> Step_Result(T) {
	if len(state.children) == 0 {
		return value_result(anim.zero(), true)
	}

	primary := state.primary_index
	if primary < 0 || primary >= len(state.children) do primary = 0

	result: Step_Result(T)
	all_done := true

	for child, index in state.children {
		child_result := stepper_step(child, dt, anim, completion)
		if index == primary {
			result = child_result
		}
		if !child_result.done do all_done = false
	}

	result.done = all_done
	return result
}

parallel_stepper :: proc(state: ^Parallel_State($T)) -> Stepper(T) {
	return Stepper(T){state = state, tag = .Parallel}
}

/*
Repeats `child` for `repeat_count` completed cycles. `repeat_count <= 0` loops
forever. `cycle_start` is restored at the beginning of each cycle.
*/
Repeat_State :: struct($T: typeid) {
	child:        Stepper(T),
	repeat_count: int,
	cycles_done:  int,
	cycle_start:  T,
}

repeat_is_infinite :: proc(repeat_count: int) -> bool {
	return repeat_count <= 0
}

repeat_init :: proc(
	state: ^Repeat_State($T),
	child: Stepper(T),
	repeat_count: int,
	cycle_start: T,
) {
	state.child = child
	state.repeat_count = repeat_count
	state.cycles_done = 0
	state.cycle_start = cycle_start
}

repeat_is_finished :: proc(
	state: Repeat_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	if repeat_is_infinite(state.repeat_count) do return false
	if state.cycles_done < state.repeat_count {
		if state.cycles_done == state.repeat_count - 1 {
			return stepper_is_done(state.child, anim, completion)
		}
		return false
	}
	return true
}

repeat_restart :: proc(state: ^Repeat_State($T)) {
	state.cycles_done = 0
	stepper_reset_to(state.child, state.cycle_start)
}

repeat_step :: proc(
	state: ^Repeat_State($T),
	dt: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> Step_Result(T) {
	result := stepper_step(state.child, dt, anim, completion)
	if !result.done do return result

	if repeat_is_infinite(state.repeat_count) {
		stepper_reset_to(state.child, state.cycle_start)
		result.done = false
		return result
	}

	state.cycles_done += 1
	if state.cycles_done >= state.repeat_count {
		return result
	}

	stepper_reset_to(state.child, state.cycle_start)
	result.done = false
	return result
}

repeat_stepper :: proc(state: ^Repeat_State($T)) -> Stepper(T) {
	return Stepper(T){state = state, tag = .Repeat}
}

Stagger_Init_Error :: enum {
	NONE,
	CHILD_COUNT_MISMATCH,
	OUT_OF_MEMORY,
}

/*
Starts each child after `interval * index` seconds. `hold_values` must match
`children` in length. `delays` is allocated from `allocator` and freed by
`stagger_destroy`.
*/
Stagger_State :: struct($T: typeid) {
	delays:        []Delay_State(T),
	primary_index: int,
}

stagger_init :: proc(
	state: ^Stagger_State($T),
	children: []Stepper(T),
	hold_values: []T,
	interval: f32,
	primary_index: int = 0,
	allocator := context.allocator,
) -> Stagger_Init_Error {
	if len(children) != len(hold_values) do return .CHILD_COUNT_MISMATCH

	delays := make([]Delay_State(T), len(children), allocator)
	if len(children) > 0 && delays == nil do return .OUT_OF_MEMORY

	for child, index in children {
		delay_init(&delays[index], child, interval * f32(index), hold_values[index])
	}

	state.delays = delays
	if primary_index < 0 || primary_index >= len(delays) {
		state.primary_index = 0
	} else {
		state.primary_index = primary_index
	}

	return .NONE
}

stagger_destroy :: proc(state: Stagger_State($T), allocator := context.allocator) {
	delete(state.delays, allocator)
}

stagger_is_finished :: proc(
	state: Stagger_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	if len(state.delays) == 0 do return true
	for delay in state.delays {
		if !delay_is_finished(delay, anim, completion) do return false
	}
	return true
}

stagger_restart :: proc(state: ^Stagger_State($T)) {
	for &delay in state.delays {
		delay_restart(&delay)
	}
}

stagger_step :: proc(
	state: ^Stagger_State($T),
	dt: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> Step_Result(T) {
	if len(state.delays) == 0 {
		return value_result(anim.zero(), true)
	}

	primary := state.primary_index
	if primary < 0 || primary >= len(state.delays) do primary = 0

	result: Step_Result(T)
	all_done := true

	for &delay, index in state.delays {
		delay_result := delay_step(&delay, dt, anim, completion)
		if index == primary {
			result = delay_result
		}
		if !delay_result.done do all_done = false
	}

	result.done = all_done
	return result
}

stagger_stepper :: proc(state: ^Stagger_State($T)) -> Stepper(T) {
	return Stepper(T){state = state, tag = .Stagger}
}

/*
Returns the estimated playback duration for finite steppers. Motion primitives and
infinitely repeating children return positive infinity.
*/
stepper_estimated_duration :: proc(stepper: Stepper($T), anim: Animatable(T)) -> f32 {
	switch stepper.tag {
	case .Tween:
		tween := (^Tween_State(T))(stepper.state)^
		if tween_is_infinite(tween.config.repeat_count) do return math.inf_f32(32)
		cycles := f32(tween_cycle_count(tween.config.repeat_count))
		return f32(tween.config.delay) + f32(tween.config.duration) * cycles
	case .Keyframes:
		keyframes := (^Keyframes_State(T))(stepper.state)^
		if tween_is_infinite(keyframes.config.repeat_count) do return math.inf_f32(32)
		cycles := f32(tween_cycle_count(keyframes.config.repeat_count))
		return f32(keyframes.config.delay) + keyframes.config.total_duration * cycles
	case .Delay:
		delay := (^Delay_State(T))(stepper.state)^
		child_duration := stepper_estimated_duration(delay.child, anim)
		if math.is_inf(child_duration) do return math.inf_f32(32)
		return delay.delay + child_duration
	case .Sequence:
		sequence := (^Sequence_State(T))(stepper.state)^
		total: f32 = 0
		for child in sequence.children {
			child_duration := stepper_estimated_duration(child, anim)
			if math.is_inf(child_duration) do return math.inf_f32(32)
			total += child_duration
		}
		return total
	case .Parallel:
		parallel := (^Parallel_State(T))(stepper.state)^
		max_duration: f32 = 0
		for child in parallel.children {
			child_duration := stepper_estimated_duration(child, anim)
			if math.is_inf(child_duration) do return math.inf_f32(32)
			max_duration = math.max(max_duration, child_duration)
		}
		return max_duration
	case .Repeat:
		repeat := (^Repeat_State(T))(stepper.state)^
		child_duration := stepper_estimated_duration(repeat.child, anim)
		if math.is_inf(child_duration) || repeat_is_infinite(repeat.repeat_count) {
			return math.inf_f32(32)
		}
		return child_duration * f32(repeat.repeat_count)
	case .Stagger:
		stagger := (^Stagger_State(T))(stepper.state)^
		if len(stagger.delays) == 0 do return 0
		max_end: f32 = 0
		for delay in stagger.delays {
			child_duration := stepper_estimated_duration(delay.child, anim)
			if math.is_inf(child_duration) do return math.inf_f32(32)
			max_end = math.max(max_end, delay.delay + child_duration)
		}
		return max_end
	case .Timeline:
		timeline := (^Timeline_State(T))(stepper.state)^
		return timeline.config.total_duration
	case .Spring, .Decay:
		return math.inf_f32(32)
	}
	unreachable()
}
