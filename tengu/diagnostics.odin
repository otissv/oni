package tengu

/*
Additive observability over finalized animators. Query procs read caller-owned state
without changing stepping contracts or introducing hidden ownership.
*/

Animator_Status :: enum {
	IDLE,
	ACTIVE,
}

Config_Validity :: enum {
	VALID,
	NEGATIVE_DURATION,
	NEGATIVE_DELAY,
	INVALID_MASS,
	NEGATIVE_STIFFNESS,
	NEGATIVE_DAMPING,
	INVALID_TIME_CONSTANT,
	INVALID_BOUNCE,
	INVALID_TIME_POLICY,
	NEGATIVE_SEGMENT_DURATION,
}

Trace_Kind :: enum {
	STEP,
	SEEK,
	RESTART,
	RECONFIGURE,
}

Trace_Info :: struct($T: typeid) {
	kind:        Trace_Kind,
	tag:         Stepper_Tag,
	dt:          f32,
	elapsed:     f32,
	has_elapsed: bool,
	progress:    f32,
	value:       T,
	target:      T,
	has_target:  bool,
	done:        bool,
}

@(private)
trace_type_id: typeid

@(private)
trace_callback: rawptr

@(private)
trace_user_data: rawptr

debug_assert :: proc(condition: bool, message: string) {
	when ODIN_DEBUG {
		assert(condition, message)
	}
}

set_animation_trace_hook :: proc(
	$T: typeid,
	callback: proc(info: Trace_Info(T), user_data: rawptr),
	user_data: rawptr = nil,
) {
	when ODIN_DEBUG {
		trace_type_id = T
		trace_callback = rawptr(callback)
		trace_user_data = user_data
	}
}

clear_animation_trace_hook :: proc() {
	when ODIN_DEBUG {
		trace_type_id = nil
		trace_callback = nil
		trace_user_data = nil
	}
}

@(private)
trace_emit :: proc(info: Trace_Info($T)) {
	when ODIN_DEBUG {
		if trace_type_id == T && trace_callback != nil {
			callback := cast(proc(info: Trace_Info(T), user_data: rawptr))trace_callback
			callback(info, trace_user_data)
		}
	}
}

@(private)
trace_step_result :: proc(
	tag: Stepper_Tag,
	state: rawptr,
	dt: f32,
	result: Step_Result($T),
	anim: Animatable(T),
	completion: Completion_Policy,
) {
	when ODIN_DEBUG {
		if trace_callback == nil do return

		info := Trace_Info(T) {
			kind     = .STEP,
			tag      = tag,
			dt       = dt,
			value    = result.value,
			done     = result.done,
			progress = stepper_progress_from_state(tag, state, anim, completion),
		}
		info.elapsed, info.has_elapsed = stepper_elapsed_impl(tag, state, T)
		info.target, info.has_target = stepper_target_impl(tag, state, anim)
		trace_emit(info)
	}
}

tween_elapsed :: proc(state: Tween_State($T)) -> f32 {
	return state.elapsed
}

tween_target :: proc(state: Tween_State($T)) -> T {
	return state.config.target
}

tween_is_idle :: proc(state: Tween_State($T)) -> bool {
	return tween_is_finished(state)
}

tween_is_active :: proc(state: Tween_State($T)) -> bool {
	return !tween_is_idle(state)
}

tween_status :: proc(state: Tween_State($T)) -> Animator_Status {
	if tween_is_idle(state) do return .IDLE
	return .ACTIVE
}

spring_target :: proc(state: Spring_State($T)) -> T {
	return state.config.target
}

spring_is_idle :: proc(
	state: Spring_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	return spring_is_at_rest(state, anim, completion)
}

spring_is_active :: proc(
	state: Spring_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	return !spring_is_idle(state, anim, completion)
}

spring_status :: proc(
	state: Spring_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> Animator_Status {
	if spring_is_idle(state, anim, completion) do return .IDLE
	return .ACTIVE
}

/*
Motion primitives report `1` at rest and `0` while moving.
*/
spring_progress :: proc(
	state: Spring_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> f32 {
	if spring_is_idle(state, anim, completion) do return 1
	return 0
}

decay_is_idle :: proc(
	state: Decay_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	return decay_is_at_rest(state, anim, completion)
}

decay_is_active :: proc(
	state: Decay_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	return !decay_is_idle(state, anim, completion)
}

decay_status :: proc(
	state: Decay_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> Animator_Status {
	if decay_is_idle(state, anim, completion) do return .IDLE
	return .ACTIVE
}

decay_progress :: proc(
	state: Decay_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> f32 {
	if decay_is_idle(state, anim, completion) do return 1
	return 0
}

keyframes_elapsed :: proc(state: Keyframes_State($T)) -> f32 {
	return state.elapsed
}

keyframes_target :: proc(state: Keyframes_State($T)) -> T {
	return keyframes_terminal_value(state.config)
}

keyframes_is_idle :: proc(state: Keyframes_State($T)) -> bool {
	return keyframes_is_finished(state)
}

keyframes_is_active :: proc(state: Keyframes_State($T)) -> bool {
	return !keyframes_is_idle(state)
}

keyframes_status :: proc(state: Keyframes_State($T)) -> Animator_Status {
	if keyframes_is_idle(state) do return .IDLE
	return .ACTIVE
}

timeline_elapsed :: proc(state: Timeline_State($T)) -> f32 {
	return state.elapsed
}

timeline_is_idle :: proc(
	state: Timeline_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	return timeline_is_finished(state, anim, completion)
}

timeline_is_active :: proc(
	state: Timeline_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	return !timeline_is_idle(state, anim, completion)
}

timeline_status :: proc(
	state: Timeline_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> Animator_Status {
	if timeline_is_idle(state, anim, completion) do return .IDLE
	return .ACTIVE
}

delay_elapsed :: proc(state: Delay_State($T)) -> f32 {
	return state.elapsed
}

delay_progress :: proc(state: Delay_State($T)) -> f32 {
	if state.delay <= 0 do return 1
	return clamp01(state.elapsed / state.delay)
}

delay_is_idle :: proc(
	state: Delay_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	return delay_is_finished(state, anim, completion)
}

delay_is_active :: proc(
	state: Delay_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	return !delay_is_idle(state, anim, completion)
}

repeat_progress :: proc(
	state: Repeat_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> f32 {
	if repeat_is_infinite(state.repeat_count) do return 0

	total := f32(state.repeat_count)
	if total <= 0 do return 1

	child_progress := stepper_progress(state.child, anim, completion)
	return clamp01((f32(state.cycles_done) + child_progress) / total)
}

sequence_progress :: proc(
	state: Sequence_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> f32 {
	count := len(state.children)
	if count == 0 do return 1
	if state.index >= count do return 1

	completed := f32(state.index)
	child_progress := stepper_progress(state.children[state.index], anim, completion)
	return clamp01((completed + child_progress) / f32(count))
}

parallel_progress :: proc(
	state: Parallel_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> f32 {
	if len(state.children) == 0 do return 1

	primary := state.primary_index
	if primary < 0 || primary >= len(state.children) do primary = 0
	return stepper_progress(state.children[primary], anim, completion)
}

stagger_progress :: proc(
	state: Stagger_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> f32 {
	if len(state.delays) == 0 do return 1

	primary := state.primary_index
	if primary < 0 || primary >= len(state.delays) do primary = 0

	delay := state.delays[primary]
	if delay.elapsed < delay.delay {
		return delay_progress(delay) / f32(len(state.delays))
	}
	return stepper_progress(delay.child, anim, completion)
}

slot_elapsed :: proc(slot: Slot($T)) -> f32 {
	if !slot.active do return 0
	switch slot.kind {
	case .TWEEN:
		return slot.tween.elapsed
	case .SPRING:
		return 0
	}
	unreachable()
}

slot_progress :: proc(
	slot: Slot($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> f32 {
	if !slot.active do return 1
	switch slot.kind {
	case .TWEEN:
		return tween_progress(slot.tween)
	case .SPRING:
		return spring_progress(slot.spring, anim, completion)
	}
	unreachable()
}

slot_is_idle :: proc(slot: Slot($T)) -> bool {
	return !slot.active || slot.done
}

slot_status :: proc(slot: Slot($T)) -> Animator_Status {
	if slot_is_idle(slot) do return .IDLE
	return .ACTIVE
}

Animator_Snapshot :: struct($T: typeid) {
	tag:         Stepper_Tag,
	status:      Animator_Status,
	progress:    f32,
	elapsed:     f32,
	has_elapsed: bool,
	value:       T,
	target:      T,
	has_target:  bool,
	done:        bool,
}

@(private)
stepper_elapsed_impl :: proc(tag: Stepper_Tag, state: rawptr, $T: typeid) -> (elapsed: f32, has_elapsed: bool) {
	switch tag {
	case .Tween:
		return (^Tween_State(T))(state).elapsed, true
	case .Keyframes:
		return (^Keyframes_State(T))(state).elapsed, true
	case .Timeline:
		return (^Timeline_State(T))(state).elapsed, true
	case .Delay:
		return (^Delay_State(T))(state).elapsed, true
	case .Spring, .Decay, .Sequence, .Parallel, .Repeat, .Stagger:
		return 0, false
	}
	unreachable()
}

@(private)
stepper_target_impl :: proc(
	tag: Stepper_Tag,
	state: rawptr,
	anim: Animatable($T),
) -> (
	target: T,
	has_target: bool,
) {
	switch tag {
	case .Tween:
		return (^Tween_State(T))(state).config.target, true
	case .Spring:
		return (^Spring_State(T))(state).config.target, true
	case .Keyframes:
		return keyframes_target((^Keyframes_State(T))(state)^), true
	case .Decay:
		return anim.zero(), false
	case .Delay:
		delay := (^Delay_State(T))(state)
		if delay.elapsed < delay.delay {
			return delay.hold_value, true
		}
		return stepper_target(delay.child, anim)
	case .Sequence:
		sequence := (^Sequence_State(T))(state)
		if len(sequence.children) == 0 do return anim.zero(), false
		index := sequence.index
		if index >= len(sequence.children) do index = len(sequence.children) - 1
		return stepper_target(sequence.children[index], anim)
	case .Parallel:
		parallel := (^Parallel_State(T))(state)
		if len(parallel.children) == 0 do return anim.zero(), false
		primary := parallel.primary_index
		if primary < 0 || primary >= len(parallel.children) do primary = 0
		return stepper_target(parallel.children[primary], anim)
	case .Repeat:
		return stepper_target((^Repeat_State(T))(state).child, anim)
	case .Stagger:
		stagger := (^Stagger_State(T))(state)
		if len(stagger.delays) == 0 do return anim.zero(), false
		primary := stagger.primary_index
		if primary < 0 || primary >= len(stagger.delays) do primary = 0
		delay := &stagger.delays[primary]
		if delay.elapsed < delay.delay {
			return delay.hold_value, true
		}
		return stepper_target(delay.child, anim)
	case .Timeline:
		return anim.zero(), false
	}
	unreachable()
}

@(private)
stepper_value_impl :: proc(tag: Stepper_Tag, state: rawptr, $T: typeid, anim: Animatable(T)) -> T {
	switch tag {
	case .Tween:
		tween := (^Tween_State(T))(state)
		return tween_sample_at(tween^, tween.elapsed, anim).value
	case .Spring:
		return (^Spring_State(T))(state).value
	case .Keyframes:
		keyframes := (^Keyframes_State(T))(state)
		return keyframes_sample_at(keyframes^, keyframes.elapsed, anim).value
	case .Decay:
		return (^Decay_State(T))(state).value
	case .Delay:
		delay := (^Delay_State(T))(state)
		if delay.elapsed < delay.delay do return delay.hold_value
		return stepper_value(delay.child, anim)
	case .Sequence:
		sequence := (^Sequence_State(T))(state)
		if len(sequence.children) == 0 do return anim.zero()
		index := sequence.index
		if index >= len(sequence.children) do index = len(sequence.children) - 1
		return stepper_value(sequence.children[index], anim)
	case .Parallel:
		parallel := (^Parallel_State(T))(state)
		if len(parallel.children) == 0 do return anim.zero()
		primary := parallel.primary_index
		if primary < 0 || primary >= len(parallel.children) do primary = 0
		return stepper_value(parallel.children[primary], anim)
	case .Repeat:
		return stepper_value((^Repeat_State(T))(state).child, anim)
	case .Stagger:
		stagger := (^Stagger_State(T))(state)
		if len(stagger.delays) == 0 do return anim.zero()
		primary := stagger.primary_index
		if primary < 0 || primary >= len(stagger.delays) do primary = 0
		delay := &stagger.delays[primary]
		if delay.elapsed < delay.delay do return delay.hold_value
		return stepper_value(delay.child, anim)
	case .Timeline:
		timeline := (^Timeline_State(T))(state)
		return timeline_sample_at(timeline, timeline.elapsed, anim).value
	}
	unreachable()
}

stepper_elapsed :: proc(stepper: Stepper($T)) -> (elapsed: f32, has_elapsed: bool) {
	return stepper_elapsed_impl(stepper.tag, stepper.state, T)
}

stepper_has_target :: proc(stepper: Stepper($T), anim: Animatable(T)) -> bool {
	_, has_target := stepper_target_impl(stepper.tag, stepper.state, anim)
	return has_target
}

stepper_target :: proc(stepper: Stepper($T), anim: Animatable(T)) -> (target: T, has_target: bool) {
	return stepper_target_impl(stepper.tag, stepper.state, anim)
}

stepper_value :: proc(stepper: Stepper($T), anim: Animatable(T)) -> T {
	return stepper_value_impl(stepper.tag, stepper.state, T, anim)
}

stepper_is_idle :: proc(
	stepper: Stepper($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	return stepper_is_done(stepper, anim, completion)
}

stepper_is_active :: proc(
	stepper: Stepper($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	return !stepper_is_idle(stepper, anim, completion)
}

stepper_status :: proc(
	stepper: Stepper($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> Animator_Status {
	if stepper_is_idle(stepper, anim, completion) do return .IDLE
	return .ACTIVE
}

stepper_progress :: proc(
	stepper: Stepper($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> f32 {
	return stepper_progress_from_state(stepper.tag, stepper.state, anim, completion)
}

@(private)
stepper_progress_from_state :: proc(
	tag: Stepper_Tag,
	state: rawptr,
	anim: Animatable($T),
	completion: Completion_Policy,
) -> f32 {
	switch tag {
	case .Tween:
		return tween_progress((^Tween_State(T))(state)^)
	case .Spring:
		return spring_progress((^Spring_State(T))(state)^, anim, completion)
	case .Keyframes:
		return keyframes_progress((^Keyframes_State(T))(state)^)
	case .Decay:
		return decay_progress((^Decay_State(T))(state)^, anim, completion)
	case .Delay:
		return delay_progress((^Delay_State(T))(state)^)
	case .Sequence:
		return sequence_progress((^Sequence_State(T))(state)^, anim, completion)
	case .Parallel:
		return parallel_progress((^Parallel_State(T))(state)^, anim, completion)
	case .Repeat:
		return repeat_progress((^Repeat_State(T))(state)^, anim, completion)
	case .Stagger:
		return stagger_progress((^Stagger_State(T))(state)^, anim, completion)
	case .Timeline:
		return timeline_progress((^Timeline_State(T))(state)^)
	}
	unreachable()
}

stepper_snapshot :: proc(
	stepper: Stepper($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> Animator_Snapshot(T) {
	target, has_target := stepper_target(stepper, anim)
	elapsed, has_elapsed := stepper_elapsed(stepper)
	return Animator_Snapshot(T) {
		tag         = stepper.tag,
		status      = stepper_status(stepper, anim, completion),
		progress    = stepper_progress(stepper, anim, completion),
		elapsed     = elapsed,
		has_elapsed = has_elapsed,
		value       = stepper_value(stepper, anim),
		target      = target,
		has_target  = has_target,
		done        = stepper_is_idle(stepper, anim, completion),
	}
}

validate_time_policy :: proc(policy: Time_Policy) -> Config_Validity {
	if policy.max_dt <= 0 || policy.max_substeps <= 0 do return .INVALID_TIME_POLICY
	return .VALID
}

validate_tween_config :: proc(config: Tween_Config($T)) -> Config_Validity {
	if f32(config.duration) < 0 do return .NEGATIVE_DURATION
	if f32(config.delay) < 0 do return .NEGATIVE_DELAY
	return .VALID
}

validate_spring_config :: proc(config: Spring_Config($T)) -> Config_Validity {
	if config.mass < MIN_SPRING_MASS do return .INVALID_MASS
	if config.stiffness < 0 do return .NEGATIVE_STIFFNESS
	if config.damping < 0 do return .NEGATIVE_DAMPING
	return .VALID
}

validate_decay_config :: proc(config: Decay_Config($T)) -> Config_Validity {
	if config.time_constant < MIN_DECAY_TIME_CONSTANT do return .INVALID_TIME_CONSTANT
	if config.bounce < 0 || config.bounce > 1 do return .INVALID_BOUNCE
	return .VALID
}

validate_keyframes_config :: proc(config: Keyframes_Config($T)) -> Config_Validity {
	if f32(config.delay) < 0 do return .NEGATIVE_DELAY
	for segment in config.segments {
		if segment.duration < 0 do return .NEGATIVE_SEGMENT_DURATION
	}
	return .VALID
}

debug_assert_time_policy :: proc(policy: Time_Policy) {
	debug_assert(validate_time_policy(policy) == .VALID, "invalid time policy")
}

debug_assert_tween_config :: proc(config: Tween_Config($T)) {
	debug_assert(validate_tween_config(config) == .VALID, "invalid tween config")
}

debug_assert_spring_config :: proc(config: Spring_Config($T)) {
	debug_assert(validate_spring_config(config) == .VALID, "invalid spring config")
}

debug_assert_decay_config :: proc(config: Decay_Config($T)) {
	debug_assert(validate_decay_config(config) == .VALID, "invalid decay config")
}

debug_assert_keyframes_config :: proc(config: Keyframes_Config($T)) {
	debug_assert(validate_keyframes_config(config) == .VALID, "invalid keyframes config")
}

debug_assert_stepper :: proc(stepper: Stepper($T)) {
	debug_assert(stepper.state != nil, "stepper state is nil")
}

tween_step_traced :: proc(
	state: ^Tween_State($T),
	dt: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> Step_Result(T) {
	result := tween_step(state, dt, anim, completion)
	trace_step_result(.Tween, state, dt, result, anim, completion)
	return result
}

spring_step_traced :: proc(
	state: ^Spring_State($T),
	dt: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
	time: Time_Policy = DEFAULT_TIME_POLICY,
) -> Step_Result(T) {
	result := spring_step(state, dt, anim, completion, time)
	trace_step_result(.Spring, state, dt, result, anim, completion)
	return result
}

keyframes_step_traced :: proc(
	state: ^Keyframes_State($T),
	dt: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> Step_Result(T) {
	result := keyframes_step(state, dt, anim, completion)
	trace_step_result(.Keyframes, state, dt, result, anim, completion)
	return result
}

decay_step_traced :: proc(
	state: ^Decay_State($T),
	dt: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
	time: Time_Policy = DEFAULT_TIME_POLICY,
) -> Step_Result(T) {
	result := decay_step(state, dt, anim, completion, time)
	trace_step_result(.Decay, state, dt, result, anim, completion)
	return result
}

stepper_step_traced :: proc(
	stepper: Stepper($T),
	dt: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> Step_Result(T) {
	result := stepper_step(stepper, dt, anim, completion)
	trace_step_result(stepper.tag, stepper.state, dt, result, anim, completion)
	return result
}

tween_to_traced :: proc(
	slot: ^Slot($T),
	target: T,
	dt: f32,
	options: Tween_Slot_Options(T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> Step_Result(T) {
	result := tween_to(slot, target, dt, options, anim, completion)
	trace_step_result(.Tween, &slot.tween, dt, result, anim, completion)
	return result
}

spring_to_traced :: proc(
	slot: ^Slot($T),
	target: T,
	dt: f32,
	options: Spring_Slot_Options(T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
	time: Time_Policy = DEFAULT_TIME_POLICY,
) -> Step_Result(T) {
	result := spring_to(slot, target, dt, options, anim, completion, time)
	trace_step_result(.Spring, &slot.spring, dt, result, anim, completion)
	return result
}

transition_to_traced :: proc(
	slot: ^Slot($T),
	target: T,
	dt: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
	time: Time_Policy = DEFAULT_TIME_POLICY,
) -> Step_Result(T) {
	switch slot.kind {
	case .TWEEN:
		return tween_to_traced(slot, target, dt, slot.tween_opts, anim, completion)
	case .SPRING:
		return spring_to_traced(slot, target, dt, slot.spring_opts, anim, completion, time)
	}
	unreachable()
}
