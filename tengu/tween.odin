package tengu

import "core:math"

/*
Easing for tweens: named curves from `Ease` or an explicit cubic-bezier.
*/
Tween_Easing :: union {
	Ease,
	Bezier,
}

Tween_Repeat_Mode :: enum {
	RESTART,
	REVERSE,
}

/*
Duration-driven animation configuration. `repeat_count` is the total number of
cycles: 1 plays once, 0 loops forever, and values greater than 1 play that
many cycles. `REVERSE` alternates direction each cycle; the final value after
an even number of cycles is `start`, after an odd number it is `target`.
*/
Tween_Config :: struct($T: typeid) {
	start:        T,
	target:       T,
	duration:     Seconds,
	delay:        Seconds,
	easing:       Tween_Easing,
	repeat_count: int,
	repeat_mode:  Tween_Repeat_Mode,
}

/*
Caller-owned tween runtime state. `elapsed` is total time in seconds from the
start of playback, including delay.
*/
Tween_State :: struct($T: typeid) {
	config:  Tween_Config(T),
	elapsed: f32,
}

Tween_Cycle_Position_Params :: struct {
	active, duration: f32,
	repeat_count:     int,
}

Tween_Mix_T_Params :: struct {
	easing:           Tween_Easing,
	local_t:          f32,
	reverse:          bool,
}

tween_easing_apply :: proc(e: Tween_Easing, t: f32) -> f32 {
	switch v in e {
	case Ease:
		return ease(v, t)
	case Bezier:
		return bezier_ease(v, t)
	}
	unreachable()
}

tween_cycle_count :: proc(repeat_count: int) -> int {
	if repeat_count <= 0 do return 0
	return repeat_count
}

tween_is_infinite :: proc(repeat_count: int) -> bool {
	return repeat_count <= 0
}

tween_active_elapsed :: proc(elapsed, delay: f32) -> f32 {
	if elapsed <= delay do return 0
	return elapsed - delay
}

tween_cycle_index :: proc(p: Tween_Cycle_Position_Params) -> int {
	cycle_index, _ := tween_cycle_position(p)
	return cycle_index
}

tween_cycle_local_t :: proc(p: Tween_Cycle_Position_Params) -> f32 {
	_, local_t := tween_cycle_position(p)
	return local_t
}

@(private)
tween_cycle_position :: proc(p: Tween_Cycle_Position_Params) -> (
	cycle_index: int,
	local_t: f32,
) {
	if p.duration <= 0 do return 0, 1

	progress_cycles := p.active / p.duration
	cycle_index = int(math.floor(progress_cycles))
	local_t = progress_cycles - f32(cycle_index)

	if local_t == 0 && cycle_index > 0 {
		cycle_index -= 1
		local_t = 1
	}

	if !tween_is_infinite(p.repeat_count) {
		max_index := tween_cycle_count(p.repeat_count) - 1
		if cycle_index > max_index {
			cycle_index = max_index
			local_t = 1
		}
	}

	return cycle_index, local_t
}

tween_is_reverse_cycle :: proc(mode: Tween_Repeat_Mode, cycle_index: int) -> bool {
	return mode == .REVERSE && (cycle_index % 2) == 1
}

tween_mix_t :: proc(p: Tween_Mix_T_Params) -> f32 {
	t := p.local_t
	if p.reverse do t = 1 - t
	return tween_easing_apply(p.easing, t)
}

/*
Returns the value the tween settles on when playback is finished. For finite
`REVERSE` tweens with an even cycle count the terminal value is `start`.
*/
tween_terminal_value :: proc(config: Tween_Config($T)) -> T {
	if tween_is_infinite(config.repeat_count) {
		return config.target
	}

	cycles := tween_cycle_count(config.repeat_count)
	if config.repeat_mode == .REVERSE && (cycles % 2) == 0 {
		return config.start
	}
	return config.target
}

tween_is_finished_at :: proc(config: Tween_Config($T), elapsed: f32) -> bool {
	if tween_is_infinite(config.repeat_count) do return false

	active := tween_active_elapsed(elapsed, f32(config.delay))
	duration := f32(config.duration)
	if duration <= 0 do return elapsed >= f32(config.delay)

	total_duration := f32(tween_cycle_count(config.repeat_count)) * duration
	return active >= total_duration
}

/*
True when a finite tween has reached its terminal time.
*/
tween_is_finished :: proc(state: Tween_State($T)) -> bool {
	return tween_is_finished_at(state.config, state.elapsed)
}

/*
Overall normalized progress in `[0, 1]` for finite tweens. Infinite tweens
return `0` while still playing.
*/
tween_progress :: proc(state: Tween_State($T)) -> f32 {
	config := state.config
	if tween_is_infinite(config.repeat_count) do return 0

	active := tween_active_elapsed(state.elapsed, f32(config.delay))
	duration := f32(config.duration)
	if duration <= 0 {
		if state.elapsed < f32(config.delay) do return 0
		return 1
	}

	total_duration := f32(tween_cycle_count(config.repeat_count)) * duration
	if total_duration <= 0 do return 1
	return clamp01(active / total_duration)
}

/*
Samples the tween at an arbitrary elapsed time without mutating state.
*/
tween_sample_at :: proc(state: Tween_State($T), p: Sample_At_Params(T)) -> Step_Result(T) {
	config := state.config

	if p.elapsed < f32(config.delay) {
		return value_result(config.start, false)
	}

	active := p.elapsed - f32(config.delay)
	duration := f32(config.duration)

	if duration <= 0 {
		terminal := tween_terminal_value(config)
		done := !tween_is_infinite(config.repeat_count)
		value := terminal
		if done {
			value = snap_if_done(Snap_If_Done_Params(T){value = terminal, target = terminal, done = true, policy = p.completion})
		}
		return value_result(value, done)
	}

	cycle_params := Tween_Cycle_Position_Params{active = active, duration = duration, repeat_count = config.repeat_count}
	cycle_index := tween_cycle_index(cycle_params)
	local_t := tween_cycle_local_t(cycle_params)
	reverse := tween_is_reverse_cycle(config.repeat_mode, cycle_index)
	mix_t := tween_mix_t(Tween_Mix_T_Params{easing = config.easing, local_t = local_t, reverse = reverse})
	value := p.anim.mix(Mix_Params(T){a = config.start, b = config.target, t = mix_t})

	finished := tween_is_finished_at(config, p.elapsed)
	if finished {
		terminal := tween_terminal_value(config)
		value = snap_if_done(Snap_If_Done_Params(T){value = value, target = terminal, done = true, policy = p.completion})
		return value_result(value, true)
	}

	return value_result(value, false)
}

tween_init :: proc(state: ^Tween_State($T), config: Tween_Config(T)) {
	state.config = tween_normalize_config(config)
	state.elapsed = 0
}

tween_normalize_config :: proc(config: Tween_Config($T)) -> Tween_Config(T) {
	c := config
	switch _ in c.easing {
	case Ease, Bezier:
	case:
		c.easing = Ease.LINEAR
	}
	return c
}

tween_restart :: proc(state: ^Tween_State($T)) {
	state.elapsed = 0
}

tween_reconfigure :: proc(state: ^Tween_State($T), config: Tween_Config(T)) {
	state.config = config
	state.elapsed = 0
}

tween_seek :: proc(state: ^Tween_State($T), elapsed: f32) {
	if elapsed < 0 {
		state.elapsed = 0
		return
	}
	state.elapsed = elapsed
}

/*
Advances elapsed time by `dt` seconds and returns the sampled value. Negative
`dt` is ignored.
*/
tween_step :: proc(p: Step_Params($T)) -> Step_Result(T) {
	state := (^Tween_State(T))(p.state)
	safe_dt := sanitize_dt(p.dt)
	if safe_dt > 0 {
		state.elapsed += safe_dt
	}
	return tween_sample_at(state^, Sample_At_Params(T){state = p.state, elapsed = state.elapsed, anim = p.anim, completion = p.completion})
}
