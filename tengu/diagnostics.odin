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

Set_Animation_Trace_Hook_Params :: struct($T: typeid) {
	callback:  proc(info: Trace_Info(T), user_data: rawptr),
	user_data: rawptr,
}

Trace_Step_Result_Params :: struct($T: typeid) {
	tag:        Stepper_Tag,
	state:      rawptr,
	dt:         f32,
	result:     Step_Result(T),
	anim:       Animatable(T),
	completion: Completion_Policy,
}

Stepper_Query_Params :: struct($T: typeid) {
	stepper:    Stepper(T),
	anim:       Animatable(T),
	completion: Completion_Policy,
}

Stepper_Value_Impl_Params :: struct($T: typeid) {
	tag:   Stepper_Tag,
	state: rawptr,
	anim:  Animatable(T),
}

Stepper_Elapsed_Impl_Params :: struct($T: typeid) {
	tag:   Stepper_Tag,
	state: rawptr,
}

Stepper_Target_Impl_Params :: struct($T: typeid) {
	tag:   Stepper_Tag,
	state: rawptr,
	anim:  Animatable(T),
}

Stepper_Progress_From_State_Params :: struct($T: typeid) {
	tag:        Stepper_Tag,
	state:      rawptr,
	anim:       Animatable(T),
	completion: Completion_Policy,
}

Tween_Step_Traced_Params :: struct($T: typeid) {
	state:      ^Tween_State(T),
	dt:         f32,
	anim:       Animatable(T),
	completion: Completion_Policy,
}

Spring_Step_Traced_Params :: struct($T: typeid) {
	state:      ^Spring_State(T),
	dt:         f32,
	anim:       Animatable(T),
	completion: Completion_Policy,
	time:       Time_Policy,
}

Keyframes_Step_Traced_Params :: struct($T: typeid) {
	state:      ^Keyframes_State(T),
	dt:         f32,
	anim:       Animatable(T),
	completion: Completion_Policy,
}

Decay_Step_Traced_Params :: struct($T: typeid) {
	state:      ^Decay_State(T),
	dt:         f32,
	anim:       Animatable(T),
	completion: Completion_Policy,
	time:       Time_Policy,
}

Tween_To_Traced_Params :: struct($T: typeid) {
	slot:       ^Slot(T),
	target:     T,
	dt:         f32,
	options:    Tween_Slot_Options(T),
	anim:       Animatable(T),
	completion: Completion_Policy,
}

Spring_To_Traced_Params :: struct($T: typeid) {
	slot:       ^Slot(T),
	target:     T,
	dt:         f32,
	options:    Spring_Slot_Options(T),
	anim:       Animatable(T),
	completion: Completion_Policy,
	time:       Time_Policy,
}

Transition_To_Traced_Params :: struct($T: typeid) {
	slot:       ^Slot(T),
	target:     T,
	dt:         f32,
	anim:       Animatable(T),
	completion: Completion_Policy,
	time:       Time_Policy,
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

set_animation_trace_hook :: proc($T: typeid, p: Set_Animation_Trace_Hook_Params(T)) {
	when ODIN_DEBUG {
		trace_type_id = T
		trace_callback = rawptr(p.callback)
		trace_user_data = p.user_data
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
trace_step_result :: proc(p: Trace_Step_Result_Params($T)) {
	when ODIN_DEBUG {
		if trace_callback == nil do return

		info := Trace_Info(T) {
			kind     = .STEP,
			tag      = p.tag,
			dt       = p.dt,
			value    = p.result.value,
			done     = p.result.done,
			progress = stepper_progress_from_state(Stepper_Progress_From_State_Params(T){tag = p.tag, state = p.state, anim = p.anim, completion = p.completion}),
		}
		info.elapsed, info.has_elapsed = stepper_elapsed_impl(Stepper_Elapsed_Impl_Params(T){tag = p.tag, state = p.state})
		info.target, info.has_target = stepper_target_impl(Stepper_Target_Impl_Params(T){tag = p.tag, state = p.state, anim = p.anim})
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

spring_is_idle :: proc(p: Animatable_Query_Params($T)) -> bool {
	return spring_is_at_rest(p)
}

spring_is_active :: proc(p: Animatable_Query_Params($T)) -> bool {
	return !spring_is_idle(p)
}

spring_status :: proc(p: Animatable_Query_Params($T)) -> Animator_Status {
	if spring_is_idle(p) do return .IDLE
	return .ACTIVE
}

/*
Motion primitives report `1` at rest and `0` while moving.
*/
spring_progress :: proc(p: Animatable_Query_Params($T)) -> f32 {
	if spring_is_idle(p) do return 1
	return 0
}

decay_is_idle :: proc(p: Animatable_Query_Params($T)) -> bool {
	return decay_is_at_rest(p)
}

decay_is_active :: proc(p: Animatable_Query_Params($T)) -> bool {
	return !decay_is_idle(p)
}

decay_status :: proc(p: Animatable_Query_Params($T)) -> Animator_Status {
	if decay_is_idle(p) do return .IDLE
	return .ACTIVE
}

decay_progress :: proc(p: Animatable_Query_Params($T)) -> f32 {
	if decay_is_idle(p) do return 1
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

timeline_is_idle :: proc(p: Timeline_Is_Finished_Params($T)) -> bool {
	return timeline_is_finished(p)
}

timeline_is_active :: proc(p: Timeline_Is_Finished_Params($T)) -> bool {
	return !timeline_is_idle(p)
}

timeline_status :: proc(p: Timeline_Is_Finished_Params($T)) -> Animator_Status {
	if timeline_is_idle(p) do return .IDLE
	return .ACTIVE
}

delay_elapsed :: proc(state: Delay_State($T)) -> f32 {
	return state.elapsed
}

delay_progress :: proc(state: Delay_State($T)) -> f32 {
	if state.delay <= 0 do return 1
	return clamp01(state.elapsed / state.delay)
}

delay_is_idle :: proc(p: Delay_Is_Finished_Params($T)) -> bool {
	return delay_is_finished(p)
}

delay_is_active :: proc(p: Delay_Is_Finished_Params($T)) -> bool {
	return !delay_is_idle(p)
}

repeat_progress :: proc(p: Repeat_Is_Finished_Params($T)) -> f32 {
	if repeat_is_infinite(p.state.repeat_count) do return 0

	total := f32(p.state.repeat_count)
	if total <= 0 do return 1

	child_progress := stepper_progress(Stepper_Query_Params(T){stepper = p.state.child, anim = p.anim, completion = p.completion})
	return clamp01((f32(p.state.cycles_done) + child_progress) / total)
}

sequence_progress :: proc(p: Sequence_Is_Finished_Params($T)) -> f32 {
	count := len(p.state.children)
	if count == 0 do return 1
	if p.state.index >= count do return 1

	completed := f32(p.state.index)
	child_progress := stepper_progress(Stepper_Query_Params(T){stepper = p.state.children[p.state.index], anim = p.anim, completion = p.completion})
	return clamp01((completed + child_progress) / f32(count))
}

parallel_progress :: proc(p: Parallel_Is_Finished_Params($T)) -> f32 {
	if len(p.state.children) == 0 do return 1

	primary := p.state.primary_index
	if primary < 0 || primary >= len(p.state.children) do primary = 0
	return stepper_progress(Stepper_Query_Params(T){stepper = p.state.children[primary], anim = p.anim, completion = p.completion})
}

stagger_progress :: proc(p: Stagger_Is_Finished_Params($T)) -> f32 {
	if len(p.state.delays) == 0 do return 1

	primary := p.state.primary_index
	if primary < 0 || primary >= len(p.state.delays) do primary = 0

	delay := p.state.delays[primary]
	if delay.elapsed < delay.delay {
		return delay_progress(delay) / f32(len(p.state.delays))
	}
	return stepper_progress(Stepper_Query_Params(T){stepper = delay.child, anim = p.anim, completion = p.completion})
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

slot_progress :: proc(p: Animatable_Query_Params($T)) -> f32 {
	slot := (^Slot(T))(p.state)
	if !slot.active do return 1
	switch slot.kind {
	case .TWEEN:
		return tween_progress(slot.tween)
	case .SPRING:
		return spring_progress(p)
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
stepper_elapsed_impl :: proc(p: Stepper_Elapsed_Impl_Params($T)) -> (elapsed: f32, has_elapsed: bool) {
	switch p.tag {
	case .Tween:
		return (^Tween_State(T))(p.state).elapsed, true
	case .Keyframes:
		return (^Keyframes_State(T))(p.state).elapsed, true
	case .Timeline:
		return (^Timeline_State(T))(p.state).elapsed, true
	case .Delay:
		return (^Delay_State(T))(p.state).elapsed, true
	case .Spring, .Decay, .Sequence, .Parallel, .Repeat, .Stagger:
		return 0, false
	}
	unreachable()
}

@(private)
stepper_target_impl :: proc(p: Stepper_Target_Impl_Params($T)) -> (
	target: T,
	has_target: bool,
) {
	anim := p.anim
	state := p.state
	switch p.tag {
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
		return stepper_target(Stepper_Query_Params(T){stepper = delay.child, anim = anim})
	case .Sequence:
		sequence := (^Sequence_State(T))(state)
		if len(sequence.children) == 0 do return anim.zero(), false
		index := sequence.index
		if index >= len(sequence.children) do index = len(sequence.children) - 1
		return stepper_target(Stepper_Query_Params(T){stepper = sequence.children[index], anim = anim})
	case .Parallel:
		parallel := (^Parallel_State(T))(state)
		if len(parallel.children) == 0 do return anim.zero(), false
		primary := parallel.primary_index
		if primary < 0 || primary >= len(parallel.children) do primary = 0
		return stepper_target(Stepper_Query_Params(T){stepper = parallel.children[primary], anim = anim})
	case .Repeat:
		return stepper_target(Stepper_Query_Params(T){stepper = (^Repeat_State(T))(state).child, anim = anim})
	case .Stagger:
		stagger := (^Stagger_State(T))(state)
		if len(stagger.delays) == 0 do return anim.zero(), false
		primary := stagger.primary_index
		if primary < 0 || primary >= len(stagger.delays) do primary = 0
		delay := &stagger.delays[primary]
		if delay.elapsed < delay.delay {
			return delay.hold_value, true
		}
		return stepper_target(Stepper_Query_Params(T){stepper = delay.child, anim = anim})
	case .Timeline:
		return anim.zero(), false
	}
	unreachable()
}

@(private)
stepper_value_impl :: proc(p: Stepper_Value_Impl_Params($T)) -> T {
	switch p.tag {
	case .Tween:
		tween := (^Tween_State(T))(p.state)
		return tween_sample_at(tween^, Sample_At_Params(T){elapsed = tween.elapsed, anim = p.anim, completion = DEFAULT_COMPLETION_POLICY}).value
	case .Spring:
		return (^Spring_State(T))(p.state).value
	case .Keyframes:
		keyframes := (^Keyframes_State(T))(p.state)
		return keyframes_sample_at(keyframes^, Sample_At_Params(T){elapsed = keyframes.elapsed, anim = p.anim, completion = DEFAULT_COMPLETION_POLICY}).value
	case .Decay:
		return (^Decay_State(T))(p.state).value
	case .Delay:
		delay := (^Delay_State(T))(p.state)
		if delay.elapsed < delay.delay do return delay.hold_value
		return stepper_value(Stepper_Query_Params(T){stepper = delay.child, anim = p.anim})
	case .Sequence:
		sequence := (^Sequence_State(T))(p.state)
		if len(sequence.children) == 0 do return p.anim.zero()
		index := sequence.index
		if index >= len(sequence.children) do index = len(sequence.children) - 1
		return stepper_value(Stepper_Query_Params(T){stepper = sequence.children[index], anim = p.anim})
	case .Parallel:
		parallel := (^Parallel_State(T))(p.state)
		if len(parallel.children) == 0 do return p.anim.zero()
		primary := parallel.primary_index
		if primary < 0 || primary >= len(parallel.children) do primary = 0
		return stepper_value(Stepper_Query_Params(T){stepper = parallel.children[primary], anim = p.anim})
	case .Repeat:
		return stepper_value(Stepper_Query_Params(T){stepper = (^Repeat_State(T))(p.state).child, anim = p.anim})
	case .Stagger:
		stagger := (^Stagger_State(T))(p.state)
		if len(stagger.delays) == 0 do return p.anim.zero()
		primary := stagger.primary_index
		if primary < 0 || primary >= len(stagger.delays) do primary = 0
		delay := &stagger.delays[primary]
		if delay.elapsed < delay.delay do return delay.hold_value
		return stepper_value(Stepper_Query_Params(T){stepper = delay.child, anim = p.anim})
	case .Timeline:
		timeline := (^Timeline_State(T))(p.state)
		return timeline_sample_at(Timeline_Sample_At_Params(T){state = timeline, elapsed = timeline.elapsed, anim = p.anim, completion = DEFAULT_COMPLETION_POLICY}).value
	}
	unreachable()
}

stepper_elapsed :: proc(stepper: Stepper($T)) -> (elapsed: f32, has_elapsed: bool) {
	return stepper_elapsed_impl(Stepper_Elapsed_Impl_Params(T){tag = stepper.tag, state = stepper.state})
}

stepper_has_target :: proc(p: Stepper_Query_Params($T)) -> bool {
	_, has_target := stepper_target_impl(Stepper_Target_Impl_Params(T){tag = p.stepper.tag, state = p.stepper.state, anim = p.anim})
	return has_target
}

stepper_target :: proc(p: Stepper_Query_Params($T)) -> (target: T, has_target: bool) {
	return stepper_target_impl(Stepper_Target_Impl_Params(T){tag = p.stepper.tag, state = p.stepper.state, anim = p.anim})
}

stepper_value :: proc(p: Stepper_Query_Params($T)) -> T {
	return stepper_value_impl(Stepper_Value_Impl_Params(T){tag = p.stepper.tag, state = p.stepper.state, anim = p.anim})
}

stepper_is_idle :: proc(p: Stepper_Query_Params($T)) -> bool {
	return stepper_is_done(Stepper_Is_Done_Params(T){stepper = p.stepper, anim = p.anim, completion = p.completion})
}

stepper_is_active :: proc(p: Stepper_Query_Params($T)) -> bool {
	return !stepper_is_idle(p)
}

stepper_status :: proc(p: Stepper_Query_Params($T)) -> Animator_Status {
	if stepper_is_idle(p) do return .IDLE
	return .ACTIVE
}

stepper_progress :: proc(p: Stepper_Query_Params($T)) -> f32 {
	return stepper_progress_from_state(Stepper_Progress_From_State_Params(T){tag = p.stepper.tag, state = p.stepper.state, anim = p.anim, completion = p.completion})
}

@(private)
stepper_progress_from_state :: proc(p: Stepper_Progress_From_State_Params($T)) -> f32 {
	switch p.tag {
	case .Tween:
		return tween_progress((^Tween_State(T))(p.state)^)
	case .Spring:
		return spring_progress(Animatable_Query_Params(T){state = p.state, anim = p.anim, completion = p.completion})
	case .Keyframes:
		return keyframes_progress((^Keyframes_State(T))(p.state)^)
	case .Decay:
		return decay_progress(Animatable_Query_Params(T){state = p.state, anim = p.anim, completion = p.completion})
	case .Delay:
		return delay_progress((^Delay_State(T))(p.state)^)
	case .Sequence:
		return sequence_progress(Sequence_Is_Finished_Params(T){state = (^Sequence_State(T))(p.state)^, anim = p.anim, completion = p.completion})
	case .Parallel:
		return parallel_progress(Parallel_Is_Finished_Params(T){state = (^Parallel_State(T))(p.state)^, anim = p.anim, completion = p.completion})
	case .Repeat:
		return repeat_progress(Repeat_Is_Finished_Params(T){state = (^Repeat_State(T))(p.state)^, anim = p.anim, completion = p.completion})
	case .Stagger:
		return stagger_progress(Stagger_Is_Finished_Params(T){state = (^Stagger_State(T))(p.state)^, anim = p.anim, completion = p.completion})
	case .Timeline:
		return timeline_progress((^Timeline_State(T))(p.state)^)
	}
	unreachable()
}

stepper_snapshot :: proc(p: Stepper_Query_Params($T)) -> Animator_Snapshot(T) {
	target, has_target := stepper_target(p)
	elapsed, has_elapsed := stepper_elapsed(p.stepper)
	return Animator_Snapshot(T) {
		tag         = p.stepper.tag,
		status      = stepper_status(p),
		progress    = stepper_progress(p),
		elapsed     = elapsed,
		has_elapsed = has_elapsed,
		value       = stepper_value(p),
		target      = target,
		has_target  = has_target,
		done        = stepper_is_idle(p),
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

tween_step_traced :: proc(p: Tween_Step_Traced_Params($T)) -> Step_Result(T) {
	result := tween_step(Step_Params(T){state = p.state, dt = p.dt, anim = p.anim, completion = p.completion})
	trace_step_result(Trace_Step_Result_Params(T){tag = .Tween, state = p.state, dt = p.dt, result = result, anim = p.anim, completion = p.completion})
	return result
}

spring_step_traced :: proc(p: Spring_Step_Traced_Params($T)) -> Step_Result(T) {
	result := spring_step(Motion_Step_Params(T){state = p.state, dt = p.dt, anim = p.anim, completion = p.completion, time = p.time})
	trace_step_result(Trace_Step_Result_Params(T){tag = .Spring, state = p.state, dt = p.dt, result = result, anim = p.anim, completion = p.completion})
	return result
}

keyframes_step_traced :: proc(p: Keyframes_Step_Traced_Params($T)) -> Step_Result(T) {
	result := keyframes_step(Step_Params(T){state = p.state, dt = p.dt, anim = p.anim, completion = p.completion})
	trace_step_result(Trace_Step_Result_Params(T){tag = .Keyframes, state = p.state, dt = p.dt, result = result, anim = p.anim, completion = p.completion})
	return result
}

decay_step_traced :: proc(p: Decay_Step_Traced_Params($T)) -> Step_Result(T) {
	result := decay_step(Motion_Step_Params(T){state = p.state, dt = p.dt, anim = p.anim, completion = p.completion, time = p.time})
	trace_step_result(Trace_Step_Result_Params(T){tag = .Decay, state = p.state, dt = p.dt, result = result, anim = p.anim, completion = p.completion})
	return result
}

stepper_step_traced :: proc(p: Stepper_Step_Params($T)) -> Step_Result(T) {
	result := stepper_step(p)
	trace_step_result(Trace_Step_Result_Params(T){tag = p.stepper.tag, state = p.stepper.state, dt = p.dt, result = result, anim = p.anim, completion = p.completion})
	return result
}

tween_to_traced :: proc(p: Tween_To_Traced_Params($T)) -> Step_Result(T) {
	result := tween_to(Tween_To_Params(T){slot = p.slot, target = p.target, dt = p.dt, options = p.options, anim = p.anim, completion = p.completion})
	trace_step_result(Trace_Step_Result_Params(T){tag = .Tween, state = &p.slot.tween, dt = p.dt, result = result, anim = p.anim, completion = p.completion})
	return result
}

spring_to_traced :: proc(p: Spring_To_Traced_Params($T)) -> Step_Result(T) {
	result := spring_to(Spring_To_Params(T){slot = p.slot, target = p.target, dt = p.dt, options = p.options, anim = p.anim, completion = p.completion, time = p.time})
	trace_step_result(Trace_Step_Result_Params(T){tag = .Spring, state = &p.slot.spring, dt = p.dt, result = result, anim = p.anim, completion = p.completion})
	return result
}

transition_to_traced :: proc(p: Transition_To_Traced_Params($T)) -> Step_Result(T) {
	switch p.slot.kind {
	case .TWEEN:
		return tween_to_traced(Tween_To_Traced_Params(T){slot = p.slot, target = p.target, dt = p.dt, options = p.slot.tween_opts, anim = p.anim, completion = p.completion})
	case .SPRING:
		return spring_to_traced(Spring_To_Traced_Params(T){slot = p.slot, target = p.target, dt = p.dt, options = p.slot.spring_opts, anim = p.anim, completion = p.completion, time = p.time})
	}
	unreachable()
}
