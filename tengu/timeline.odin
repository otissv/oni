package tengu

import "core:math"
import "core:strings"

/*
Authoring entry for one timeline track. `offset` is when the track begins on the
timeline; overlapping tracks run in parallel. The caller keeps every referenced
`stepper` state alive for the lifetime of the timeline.
*/
Timeline_Track_Spec :: struct($T: typeid) {
	name:       string,
	offset:     Seconds,
	stepper:    Stepper(T),
	hold_value: T,
}

/*
Named marker on the timeline clock. Labels are used for seek and inspection.
*/
Timeline_Label :: struct {
	name: string,
	time: Seconds,
}

/*
Caller-owned authoring data compiled into immutable timeline metadata. Track
`stepper` references are not copied; they are wired into runtime state at init.
*/
Timeline_Spec :: struct($T: typeid) {
	tracks:        []Timeline_Track_Spec(T),
	labels:        []Timeline_Label,
	primary_index: int,
}

Timeline_Compile_Error :: enum {
	NONE,
	DUPLICATE_LABEL,
	OUT_OF_MEMORY,
}

/*
Immutable compiled track metadata. `end_time` is `offset` plus the estimated
duration of the track stepper when that duration is finite.
*/
Timeline_Track :: struct($T: typeid) {
	name:       string,
	offset:     f32,
	end_time:   f32,
	hold_value: T,
}

/*
Compiled timeline data. `total_duration` is the latest finite `end_time` across
all tracks. Tracks with non-finite duration do not extend `total_duration`.
*/
Timeline_Config :: struct($T: typeid) {
	tracks:         []Timeline_Track(T),
	labels:         []Timeline_Label,
	total_duration: f32,
	primary_index:  int,
}

/*
Caller-owned timeline runtime state. Each track is a `Delay_State` that holds
`hold_value` until `offset`, then runs the track stepper. Tracks are stepped in
parallel so overlaps are orchestrated rather than reimplemented.
*/
Timeline_State :: struct($T: typeid) {
	config:   Timeline_Config(T),
	delays:   []Delay_State(T),
	steppers: []Stepper(T),
	parallel: Parallel_State(T),
	elapsed:  f32,
}

timeline_track_spec :: proc(
	name: string,
	offset: Seconds,
	stepper: Stepper($T),
	hold_value: T,
) -> Timeline_Track_Spec(T) {
	return Timeline_Track_Spec(T) {
		name = name,
		offset = offset,
		stepper = stepper,
		hold_value = hold_value,
	}
}

timeline_label :: proc(name: string, time: Seconds) -> Timeline_Label {
	return Timeline_Label{name = name, time = time}
}

timeline_spec :: proc(
	tracks: []Timeline_Track_Spec($T),
	labels: []Timeline_Label = nil,
	primary_index: int = 0,
) -> Timeline_Spec(T) {
	return Timeline_Spec(T) {
		tracks = tracks,
		labels = labels,
		primary_index = primary_index,
	}
}

timeline_config_destroy :: proc(config: Timeline_Config($T), allocator := context.allocator) {
	for track in config.tracks {
		delete(track.name, allocator)
	}
	delete(config.tracks, allocator)

	for label in config.labels {
		delete(label.name, allocator)
	}
	delete(config.labels, allocator)
}

@(private)
timeline_clone_label :: proc(
	label: Timeline_Label,
	allocator := context.allocator,
) -> (
	compiled: Timeline_Label,
	ok: bool,
) {
	if label.name == "" {
		return label, true
	}

	cloned := strings.clone(label.name, allocator)
	if cloned == "" do return {}, false
	return Timeline_Label{name = cloned, time = label.time}, true
}

/*
Compiles track metadata and label markers from a timeline specification. Returned
strings in `config` must be released with `timeline_config_destroy`.
*/
timeline_compile :: proc(
	spec: Timeline_Spec($T),
	anim: Animatable(T),
	allocator := context.allocator,
) -> (
	config: Timeline_Config(T),
	err: Timeline_Compile_Error,
) {
	for label, index in spec.labels {
		for prior in spec.labels[:index] {
			if label.name == prior.name do return config, .DUPLICATE_LABEL
		}
	}

	tracks := make([]Timeline_Track(T), len(spec.tracks), allocator)
	if len(spec.tracks) > 0 && tracks == nil do return config, .OUT_OF_MEMORY

	total_duration: f32 = 0

	for track_spec, index in spec.tracks {
		duration := stepper_estimated_duration(track_spec.stepper, anim)

		end_time: f32
		if math.is_inf(duration) {
			end_time = math.inf_f32(32)
		} else {
			end_time = f32(track_spec.offset) + duration
		}

		name := ""
		if track_spec.name != "" {
			cloned := strings.clone(track_spec.name, allocator)
			if cloned == "" {
				timeline_config_destroy(Timeline_Config(T){tracks = tracks[:index]}, allocator)
				return config, .OUT_OF_MEMORY
			}
			name = cloned
		}

		tracks[index] = Timeline_Track(T) {
			name       = name,
			offset     = f32(track_spec.offset),
			end_time   = end_time,
			hold_value = track_spec.hold_value,
		}

		if !math.is_inf(end_time) {
			total_duration = math.max(total_duration, end_time)
		}
	}

	labels := make([]Timeline_Label, len(spec.labels), allocator)
	if len(spec.labels) > 0 && labels == nil {
		timeline_config_destroy(Timeline_Config(T){tracks = tracks}, allocator)
		return config, .OUT_OF_MEMORY
	}

	for label, index in spec.labels {
		compiled, ok := timeline_clone_label(label, allocator)
		if !ok {
			timeline_config_destroy(
				Timeline_Config(T){tracks = tracks, labels = labels[:index]},
				allocator,
			)
			return config, .OUT_OF_MEMORY
		}
		labels[index] = compiled
	}

	primary_index := spec.primary_index
	if primary_index < 0 || primary_index >= len(tracks) do primary_index = 0

	config = Timeline_Config(T) {
		tracks         = tracks,
		labels         = labels,
		total_duration = total_duration,
		primary_index  = primary_index,
	}
	return config, .NONE
}

timeline_destroy :: proc(state: Timeline_State($T), allocator := context.allocator) {
	delete(state.delays, allocator)
	delete(state.steppers, allocator)
	timeline_config_destroy(state.config, allocator)
}

/*
Builds delay-wrapped parallel playback from a compiled config and the original
track stepper references in `spec`.
*/
timeline_init :: proc(
	state: ^Timeline_State($T),
	spec: Timeline_Spec(T),
	config: Timeline_Config(T),
	allocator := context.allocator,
) -> bool {
	if len(spec.tracks) != len(config.tracks) do return false

	delays := make([]Delay_State(T), len(spec.tracks), allocator)
	steppers := make([]Stepper(T), len(spec.tracks), allocator)
	if len(spec.tracks) > 0 && (delays == nil || steppers == nil) {
		delete(delays, allocator)
		delete(steppers, allocator)
		return false
	}

	for track, index in spec.tracks {
		delay_init(&delays[index], track.stepper, f32(track.offset), track.hold_value)
		steppers[index] = delay_stepper(&delays[index])
	}

	parallel_init(&state.parallel, steppers, config.primary_index)

	state.config = config
	state.delays = delays
	state.steppers = steppers
	state.elapsed = 0
	return true
}

timeline_restart :: proc(state: ^Timeline_State($T)) {
	state.elapsed = 0
	parallel_restart(&state.parallel)
}

timeline_reconfigure :: proc(
	state: ^Timeline_State($T),
	config: Timeline_Config(T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) {
	state.config = config
	timeline_sync(state, 0, anim, completion)
}

@(private)
timeline_sync :: proc(
	state: ^Timeline_State($T),
	elapsed: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) {
	clamped_elapsed := elapsed
	if clamped_elapsed < 0 do clamped_elapsed = 0
	state.elapsed = clamped_elapsed

	for &delay, index in state.delays {
		delay_restart(&delay)
		local_t := clamped_elapsed - state.config.tracks[index].offset
		if local_t > 0 {
			delay_step(&delay, local_t, anim, completion)
		}
	}
}

timeline_seek :: proc(
	state: ^Timeline_State($T),
	elapsed: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) {
	timeline_sync(state, elapsed, anim, completion)
}

timeline_label_time :: proc(config: Timeline_Config($T), name: string) -> (time: f32, found: bool) {
	for label in config.labels {
		if label.name == name do return f32(label.time), true
	}
	return 0, false
}

timeline_seek_to_label :: proc(
	state: ^Timeline_State($T),
	name: string,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	time, found := timeline_label_time(state.config, name)
	if !found do return false
	timeline_seek(state, time, anim, completion)
	return true
}

timeline_is_finished_at :: proc(config: Timeline_Config($T), elapsed: f32) -> bool {
	if len(config.tracks) == 0 do return true
	if config.total_duration > 0 && elapsed < config.total_duration do return false
	if config.total_duration <= 0 {
		for track in config.tracks {
			if math.is_inf(track.end_time) do return false
		}
	}
	return true
}

timeline_is_finished :: proc(
	state: Timeline_State($T),
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	return parallel_is_finished(state.parallel, anim, completion)
}

/*
Overall normalized progress in `[0, 1]` for timelines with finite `total_duration`.
Timelines with zero or non-finite duration return `0`.
*/
timeline_progress :: proc(state: Timeline_State($T)) -> f32 {
	total_duration := state.config.total_duration
	if total_duration <= 0 || math.is_inf(total_duration) do return 0
	return clamp01(state.elapsed / total_duration)
}

timeline_sample_at :: proc(
	state: ^Timeline_State($T),
	elapsed: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> Step_Result(T) {
	if len(state.steppers) == 0 do return value_result(anim.zero(), true)

	timeline_sync(state, elapsed, anim, completion)

	result := parallel_step(&state.parallel, 0, anim, completion)
	result.done = timeline_is_finished(state^, anim, completion)
	return result
}

timeline_step :: proc(
	state: ^Timeline_State($T),
	dt: f32,
	anim: Animatable(T),
	completion: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> Step_Result(T) {
	if len(state.steppers) == 0 do return value_result(anim.zero(), true)

	safe_dt := sanitize_dt(dt)
	if safe_dt > 0 do state.elapsed += safe_dt
	return parallel_step(&state.parallel, safe_dt, anim, completion)
}

timeline_stepper :: proc(state: ^Timeline_State($T)) -> Stepper(T) {
	return Stepper(T){state = state, tag = .Timeline}
}
