package tengu

import "core:math"
import "core:mem"
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

Timeline_Compile_Params :: struct($T: typeid) {
	spec:      Timeline_Spec(T),
	anim:      Animatable(T),
	allocator: mem.Allocator,
}

Timeline_Init_Params :: struct($T: typeid) {
	state:     ^Timeline_State(T),
	spec:      Timeline_Spec(T),
	config:    Timeline_Config(T),
	allocator: mem.Allocator,
}

Timeline_Reconfigure_Params :: struct($T: typeid) {
	state:      ^Timeline_State(T),
	config:     Timeline_Config(T),
	anim:       Animatable(T),
	completion: Completion_Policy,
}

Timeline_Sync_Params :: struct($T: typeid) {
	state:      ^Timeline_State(T),
	elapsed:    f32,
	anim:       Animatable(T),
	completion: Completion_Policy,
}

Timeline_Seek_Params :: struct($T: typeid) {
	state:      ^Timeline_State(T),
	elapsed:    f32,
	anim:       Animatable(T),
	completion: Completion_Policy,
}

Timeline_Seek_To_Label_Params :: struct($T: typeid) {
	state:      ^Timeline_State(T),
	name:       string,
	anim:       Animatable(T),
	completion: Completion_Policy,
}

Timeline_Is_Finished_Params :: struct($T: typeid) {
	state:      Timeline_State(T),
	anim:       Animatable(T),
	completion: Completion_Policy,
}

Timeline_Sample_At_Params :: struct($T: typeid) {
	state:      ^Timeline_State(T),
	elapsed:    f32,
	anim:       Animatable(T),
	completion: Completion_Policy,
}

timeline_label :: proc(name: string, time: Seconds) -> Timeline_Label {
	return Timeline_Label{name = name, time = time}
}

Timeline_Spec_Params :: struct($T: typeid) {
	tracks:        []Timeline_Track_Spec(T),
	labels:        []Timeline_Label,
	primary_index: int,
}

timeline_spec :: proc(p: Timeline_Spec_Params($T)) -> Timeline_Spec(T) {
	return Timeline_Spec(T) {
		tracks = p.tracks,
		labels = p.labels,
		primary_index = p.primary_index,
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
timeline_compile :: proc(p: Timeline_Compile_Params($T)) -> (
	config: Timeline_Config(T),
	err: Timeline_Compile_Error,
) {
	allocator := p.allocator
	if allocator.procedure == nil do allocator = context.allocator

	for label, index in p.spec.labels {
		for prior in p.spec.labels[:index] {
			if label.name == prior.name do return config, .DUPLICATE_LABEL
		}
	}

	tracks := make([]Timeline_Track(T), len(p.spec.tracks), allocator)
	if len(p.spec.tracks) > 0 && tracks == nil do return config, .OUT_OF_MEMORY

	total_duration: f32 = 0

	for track_spec, index in p.spec.tracks {
		duration := stepper_estimated_duration(track_spec.stepper, p.anim)

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

	labels := make([]Timeline_Label, len(p.spec.labels), allocator)
	if len(p.spec.labels) > 0 && labels == nil {
		timeline_config_destroy(Timeline_Config(T){tracks = tracks}, allocator)
		return config, .OUT_OF_MEMORY
	}

	for label, index in p.spec.labels {
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

	primary_index := p.spec.primary_index
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
timeline_init :: proc(p: Timeline_Init_Params($T)) -> bool {
	if len(p.spec.tracks) != len(p.config.tracks) do return false

	allocator := p.allocator
	if allocator.procedure == nil do allocator = context.allocator

	delays := make([]Delay_State(T), len(p.spec.tracks), allocator)
	steppers := make([]Stepper(T), len(p.spec.tracks), allocator)
	if len(p.spec.tracks) > 0 && (delays == nil || steppers == nil) {
		delete(delays, allocator)
		delete(steppers, allocator)
		return false
	}

	for track, index in p.spec.tracks {
		delay_init(Delay_Init_Params(T){state = &delays[index], child = track.stepper, delay = f32(track.offset), hold_value = track.hold_value})
		steppers[index] = delay_stepper(&delays[index])
	}

	parallel_init(Parallel_Init_Params(T){state = &p.state.parallel, children = steppers, primary_index = p.config.primary_index})

	p.state.config = p.config
	p.state.delays = delays
	p.state.steppers = steppers
	p.state.elapsed = 0
	return true
}

timeline_restart :: proc(state: ^Timeline_State($T)) {
	state.elapsed = 0
	parallel_restart(&state.parallel)
}

timeline_reconfigure :: proc(p: Timeline_Reconfigure_Params($T)) {
	p.state.config = p.config
	timeline_sync(Timeline_Sync_Params(T){state = p.state, elapsed = 0, anim = p.anim, completion = p.completion})
}

@(private)
timeline_sync :: proc(p: Timeline_Sync_Params($T)) {
	clamped_elapsed := p.elapsed
	if clamped_elapsed < 0 do clamped_elapsed = 0
	p.state.elapsed = clamped_elapsed

	for &delay, index in p.state.delays {
		delay_restart(&delay)
		local_t := clamped_elapsed - p.state.config.tracks[index].offset
		if local_t > 0 {
			delay_step(Delay_Step_Params(T){state = &delay, dt = local_t, anim = p.anim, completion = p.completion})
		}
	}
}

timeline_seek :: proc(p: Timeline_Seek_Params($T)) {
	timeline_sync(Timeline_Sync_Params(T){state = p.state, elapsed = p.elapsed, anim = p.anim, completion = p.completion})
}

timeline_label_time :: proc(config: Timeline_Config($T), name: string) -> (time: f32, found: bool) {
	for label in config.labels {
		if label.name == name do return f32(label.time), true
	}
	return 0, false
}

timeline_seek_to_label :: proc(p: Timeline_Seek_To_Label_Params($T)) -> bool {
	time, found := timeline_label_time(p.state.config, p.name)
	if !found do return false
	timeline_seek(Timeline_Seek_Params(T){state = p.state, elapsed = time, anim = p.anim, completion = p.completion})
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

timeline_is_finished :: proc(p: Timeline_Is_Finished_Params($T)) -> bool {
	return parallel_is_finished(Parallel_Is_Finished_Params(T){state = p.state.parallel, anim = p.anim, completion = p.completion})
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

timeline_sample_at :: proc(p: Timeline_Sample_At_Params($T)) -> Step_Result(T) {
	if len(p.state.steppers) == 0 do return value_result(p.anim.zero(), true)

	timeline_sync(Timeline_Sync_Params(T){state = p.state, elapsed = p.elapsed, anim = p.anim, completion = p.completion})

	result := parallel_step(Parallel_Step_Params(T){state = &p.state.parallel, dt = 0, anim = p.anim, completion = p.completion})
	result.done = timeline_is_finished(Timeline_Is_Finished_Params(T){state = p.state^, anim = p.anim, completion = p.completion})
	return result
}

timeline_step :: proc(p: Step_Params($T)) -> Step_Result(T) {
	state := (^Timeline_State(T))(p.state)
	if len(state.steppers) == 0 do return value_result(p.anim.zero(), true)

	safe_dt := sanitize_dt(p.dt)
	if safe_dt > 0 do state.elapsed += safe_dt
	return parallel_step(Parallel_Step_Params(T){state = &state.parallel, dt = safe_dt, anim = p.anim, completion = p.completion})
}

timeline_stepper :: proc(state: ^Timeline_State($T)) -> Stepper(T) {
	return Stepper(T){state = state, tag = .Timeline}
}
