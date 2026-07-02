package tengu

/*
Per-stop authoring data. In `DURATION` mode each stop's `duration` is the time in
seconds to reach that value from the previous stop. In `OFFSET` mode each stop's
`offset` is a normalized position in `[0, 1]` along `Keyframes_Spec.total_duration`.
*/
Keyframe_Timing_Mode :: enum {
	DURATION,
	OFFSET,
}

Keyframe_Stop :: struct($T: typeid) {
	value:    T,
	duration: Seconds,
	offset:   f32,
	easing:   Tween_Easing,
}

/*
Authoring specification compiled into immutable segment data. The caller owns the
`stops` slice; compilation allocates the compiled `segments` slice separately.
*/
Keyframes_Spec :: struct($T: typeid) {
	start:          T,
	stops:          []Keyframe_Stop(T),
	timing_mode:    Keyframe_Timing_Mode,
	total_duration: Seconds,
	delay:          Seconds,
	repeat_count:   int,
	repeat_mode:    Tween_Repeat_Mode,
}

Keyframes_Compile_Error :: enum {
	NONE,
	INVALID_TOTAL_DURATION,
	INVALID_OFFSET_ORDER,
	INVALID_OFFSET_RANGE,
	OUT_OF_MEMORY,
}

/*
Compiled segment from one value stop to the next. `begin` is the absolute time in
seconds from the end of the keyframes delay.
*/
Keyframe_Segment :: struct($T: typeid) {
	start:    T,
	stop:     T,
	duration: f32,
	begin:    f32,
	easing:   Tween_Easing,
}

Keyframes_Config :: struct($T: typeid) {
	start:          T,
	segments:       []Keyframe_Segment(T),
	delay:          Seconds,
	repeat_count:   int,
	repeat_mode:    Tween_Repeat_Mode,
	total_duration: f32,
}

Keyframes_State :: struct($T: typeid) {
	config:  Keyframes_Config(T),
	elapsed: f32,
}

Keyframes_Sample_Cycle_At_Params :: struct($T: typeid) {
	config:     Keyframes_Config(T),
	cycle_time: f32,
	anim:       Animatable(T),
}

keyframes_stop_default :: proc(value: $T) -> Keyframe_Stop(T) {
	return Keyframe_Stop(T){value = value, easing = Ease.LINEAR}
}

keyframes_config_destroy :: proc(config: Keyframes_Config($T), allocator := context.allocator) {
	delete(config.segments, allocator)
}

/*
Compiles authoring stops into immutable segment data. The returned `segments` slice
must be released with `keyframes_config_destroy`.
*/
keyframes_compile :: proc(
	spec: Keyframes_Spec($T),
	allocator := context.allocator,
) -> (
	config: Keyframes_Config(T),
	err: Keyframes_Compile_Error,
) {
	config = Keyframes_Config(T) {
		start          = spec.start,
		delay          = spec.delay,
		repeat_count   = spec.repeat_count,
		repeat_mode    = spec.repeat_mode,
	}

	if len(spec.stops) == 0 {
		return config, .NONE
	}

	prev_offset: f32 = 0
	switch spec.timing_mode {
	case .OFFSET:
		total_duration := f32(spec.total_duration)
		if total_duration <= 0 do return config, .INVALID_TOTAL_DURATION

		for stop in spec.stops {
			if stop.offset < prev_offset do return config, .INVALID_OFFSET_ORDER
			if stop.offset < 0 || stop.offset > 1 do return config, .INVALID_OFFSET_RANGE
			prev_offset = stop.offset
		}
	case .DURATION:
	}

	segments := make([dynamic]Keyframe_Segment(T), 0, len(spec.stops), allocator)

	current_value := spec.start
	current_time: f32 = 0
	prev_offset = 0

	switch spec.timing_mode {
	case .DURATION:
		for stop in spec.stops {
			duration := f32(stop.duration)
			easing := stop.easing
			switch _ in easing {
			case Ease, Bezier:
			case:
				easing = Ease.LINEAR
			}
			segment := Keyframe_Segment(T) {
				start    = current_value,
				stop     = stop.value,
				duration = duration,
				begin    = current_time,
				easing   = easing,
			}
			append(&segments, segment)
			current_value = stop.value
			current_time += duration
		}
	case .OFFSET:
		total_duration := f32(spec.total_duration)
		for stop in spec.stops {
			duration := (stop.offset - prev_offset) * total_duration
			easing := stop.easing
			switch _ in easing {
			case Ease, Bezier:
			case:
				easing = Ease.LINEAR
			}
			segment := Keyframe_Segment(T) {
				start    = current_value,
				stop     = stop.value,
				duration = duration,
				begin    = current_time,
				easing   = easing,
			}
			append(&segments, segment)
			current_value = stop.value
			current_time += duration
			prev_offset = stop.offset
		}
	}

	config.segments = segments[:]
	config.total_duration = current_time
	return config, .NONE
}

keyframes_last_value :: proc(config: Keyframes_Config($T)) -> T {
	if len(config.segments) == 0 do return config.start
	return config.segments[len(config.segments) - 1].stop
}

keyframes_terminal_value :: proc(config: Keyframes_Config($T)) -> T {
	if tween_is_infinite(config.repeat_count) {
		return keyframes_last_value(config)
	}

	cycles := tween_cycle_count(config.repeat_count)
	if config.repeat_mode == .REVERSE && (cycles % 2) == 0 {
		return config.start
	}
	return keyframes_last_value(config)
}

keyframes_is_finished_at :: proc(config: Keyframes_Config($T), elapsed: f32) -> bool {
	if tween_is_infinite(config.repeat_count) do return false

	active := tween_active_elapsed(elapsed, f32(config.delay))
	total_duration := config.total_duration
	if total_duration <= 0 do return elapsed >= f32(config.delay)

	total_playback := f32(tween_cycle_count(config.repeat_count)) * total_duration
	return active >= total_playback
}

keyframes_is_finished :: proc(state: Keyframes_State($T)) -> bool {
	return keyframes_is_finished_at(state.config, state.elapsed)
}

keyframes_progress :: proc(state: Keyframes_State($T)) -> f32 {
	config := state.config
	if tween_is_infinite(config.repeat_count) do return 0

	active := tween_active_elapsed(state.elapsed, f32(config.delay))
	total_duration := config.total_duration
	if total_duration <= 0 {
		if state.elapsed < f32(config.delay) do return 0
		return 1
	}

	total_playback := f32(tween_cycle_count(config.repeat_count)) * total_duration
	if total_playback <= 0 do return 1
	return clamp01(active / total_playback)
}

@(private)
keyframes_sample_cycle_at :: proc(p: Keyframes_Sample_Cycle_At_Params($T)) -> T {
	if len(p.config.segments) == 0 do return p.config.start

	total_duration := p.config.total_duration
	if total_duration <= 0 do return keyframes_last_value(p.config)

	if p.cycle_time <= 0 do return p.config.segments[0].start
	if p.cycle_time >= total_duration do return keyframes_last_value(p.config)

	last_index := len(p.config.segments) - 1
	for segment, index in p.config.segments {
		segment_end := segment.begin + segment.duration
		is_last := index == last_index
		if p.cycle_time < segment_end || is_last {
			if segment.duration <= 0 do return segment.stop

			local_t := (p.cycle_time - segment.begin) / segment.duration
			if local_t < 0 do local_t = 0
			if local_t > 1 do local_t = 1
			mix_t := tween_easing_apply(segment.easing, local_t)
			return p.anim.mix(Mix_Params(T){a = segment.start, b = segment.stop, t = mix_t})
		}
	}

	return keyframes_last_value(p.config)
}

keyframes_sample_at :: proc(state: Keyframes_State($T), p: Sample_At_Params(T)) -> Step_Result(T) {
	config := state.config

	if p.elapsed < f32(config.delay) {
		return value_result(config.start, false)
	}

	active := p.elapsed - f32(config.delay)
	total_duration := config.total_duration

	if total_duration <= 0 {
		terminal := keyframes_terminal_value(config)
		done := !tween_is_infinite(config.repeat_count)
		value := terminal
		if done {
			value = snap_if_done(Snap_If_Done_Params(T){value = terminal, target = terminal, done = true, policy = p.completion})
		}
		return value_result(value, done)
	}

	cycle_params := Tween_Cycle_Position_Params{active = active, duration = total_duration, repeat_count = config.repeat_count}
	cycle_index := tween_cycle_index(cycle_params)
	local_t := tween_cycle_local_t(cycle_params)
	reverse := tween_is_reverse_cycle(config.repeat_mode, cycle_index)

	cycle_time := local_t * total_duration
	if reverse {
		cycle_time = total_duration - cycle_time
	}

	value := keyframes_sample_cycle_at(Keyframes_Sample_Cycle_At_Params(T){config = config, cycle_time = cycle_time, anim = p.anim})

	finished := keyframes_is_finished_at(config, p.elapsed)
	if finished {
		terminal := keyframes_terminal_value(config)
		value = snap_if_done(Snap_If_Done_Params(T){value = value, target = terminal, done = true, policy = p.completion})
		return value_result(value, true)
	}

	return value_result(value, false)
}

keyframes_init :: proc(state: ^Keyframes_State($T), config: Keyframes_Config(T)) {
	state.config = config
	state.elapsed = 0
}

keyframes_restart :: proc(state: ^Keyframes_State($T)) {
	state.elapsed = 0
}

keyframes_reconfigure :: proc(state: ^Keyframes_State($T), config: Keyframes_Config(T)) {
	state.config = config
	state.elapsed = 0
}

keyframes_seek :: proc(state: ^Keyframes_State($T), elapsed: f32) {
	if elapsed < 0 {
		state.elapsed = 0
		return
	}
	state.elapsed = elapsed
}

keyframes_step :: proc(p: Step_Params($T)) -> Step_Result(T) {
	state := (^Keyframes_State(T))(p.state)
	safe_dt := sanitize_dt(p.dt)
	if safe_dt > 0 {
		state.elapsed += safe_dt
	}
	return keyframes_sample_at(state^, Sample_At_Params(T){state = p.state, elapsed = state.elapsed, anim = p.anim, completion = p.completion})
}
