package oni

import sdl "vendor:sdl3"

/*
Engine-wide frame pacing policy.

Continuous always runs a full frame each host iteration. On-demand waits for
input, a wake deadline, or an idle timeout. Focused is continuous while the
window has focus and on-demand when it does not.
*/
Frame_Mode :: enum {
	Continuous,
	On_Demand,
	Focused,
}

/*
Resolved per-iteration pacing after applying window focus to Frame_Mode.
*/
Frame_Pacing :: enum {
	Continuous,
	On_Demand,
}

// Idle wait when effective pacing is on-demand (settings / hot-reload housekeeping).
FRAME_IDLE_TIMEOUT_MS :: i32(100)
// Longer wait while a Focused app is unfocused to save CPU.
FRAME_IDLE_TIMEOUT_UNFOCUSED_MS :: i32(500)

/*
Returns the active frame mode, or Continuous when engine state is unavailable.
*/
frame_mode :: proc() -> Frame_Mode {
	if state == nil do return .Continuous

	return state.frame_mode
}

/*
Sets the active frame mode and requests a frame so the new pacing applies immediately.
*/
frame_mode_set :: proc(mode: Frame_Mode) {
	if state == nil do return

	if state.frame_mode != mode {
		state.frame_mode = mode
	}

	request_frame()
}

/*
Resolves continuous vs on-demand pacing from the selected mode and window focus.
*/
frame_pacing_effective :: proc() -> Frame_Pacing {
	if state == nil do return .Continuous

	switch state.frame_mode {
	case .Continuous:
		return .Continuous
	case .On_Demand:
		return .On_Demand
	case .Focused:
		if state.window_focused {
			return .Continuous
		}

		return .On_Demand
	}

	return .Continuous
}

/*
Returns whether effective pacing is on-demand (app wake APIs are required).
*/
frame_pacing_is_on_demand :: proc() -> bool {
	return frame_pacing_effective() == .On_Demand
}

/*
Schedules at least one more full frame.

Harmless when effective pacing is continuous.
*/
request_frame :: proc() {
	if state == nil do return

	state.frame_dirty = true
}

/*
Keeps waking frames until `duration` seconds from now.

Extends an existing wake deadline when the new one is later. Harmless when
effective pacing is continuous.
*/
wake_for :: proc(duration: f64) {
	if state == nil do return

	if duration <= 0 {
		request_frame()
		return
	}

	now := frame_now_ns()
	add_ns := u64(duration * 1_000_000_000.0)
	until := now + add_ns

	if until < now {
		until = max(u64)
	}

	wake_until_ns(until)
}

/*
Keeps waking frames until the absolute SDL tick deadline (nanoseconds).
*/
wake_until_ns :: proc(deadline_ns: u64) {
	if state == nil do return

	if deadline_ns == 0 {
		request_frame()
		return
	}

	if deadline_ns > state.wake_until_ns {
		state.wake_until_ns = deadline_ns
	}

	request_frame()
}

/*
Returns the current wake-until deadline in SDL ticks (0 when none).
*/
wake_deadline_ns :: proc() -> u64 {
	if state == nil do return 0

	return state.wake_until_ns
}

@(private)
frame_now_ns :: proc() -> u64 {
	return sdl.GetTicksNS()
}

@(private)
frame_wake_active :: proc(now: u64) -> bool {
	if state == nil do return false

	if state.wake_until_ns == 0 do return false

	if now < state.wake_until_ns do return true

	state.wake_until_ns = 0
	return false
}

@(private)
frame_work_pending :: proc() -> bool {
	if state == nil do return false

	if state.frame_dirty do return true

	return frame_wake_active(frame_now_ns())
}

@(private)
frame_idle_timeout_ms :: proc() -> i32 {
	if state == nil do return FRAME_IDLE_TIMEOUT_MS

	if state.frame_mode == .Focused && !state.window_focused {
		return FRAME_IDLE_TIMEOUT_UNFOCUSED_MS
	}

	return FRAME_IDLE_TIMEOUT_MS
}

/*
Waits for an SDL event, wake deadline, or idle timeout when on-demand and idle.

No-op when work is already pending, effective pacing is continuous, or tests
disable waiting. Uses HasEvents so already-queued events skip the wait.
*/
@(private)
frame_wait_if_idle :: proc() {
	if state == nil do return

	if test_hook_skip_frame_wait do return

	if frame_pacing_effective() != .On_Demand do return

	if frame_work_pending() do return

	if sdl.HasEvents(sdl.EventType.FIRST, sdl.EventType.LAST) do return

	timeout_ms := frame_idle_timeout_ms()
	now := frame_now_ns()

	if state.wake_until_ns != 0 && state.wake_until_ns > now {
		remaining_ms := i32((state.wake_until_ns - now) / 1_000_000)

		if remaining_ms < timeout_ms {
			timeout_ms = max(remaining_ms, i32(0))
		}
	}

	event: sdl.Event
	if sdl.WaitEventTimeout(&event, timeout_ms) {
		_ = sdl.PushEvent(&event)
		request_frame()
	}
}

/*
Consumes one-shot dirty when a full frame is about to run.

Must run before tick/draw so `request_frame` during the frame still schedules
the next iteration under on-demand pacing.
*/
@(private)
frame_consume_dirty :: proc() {
	if state == nil do return

	state.frame_dirty = false
}

/*
Expires an elapsed wake deadline after a presented frame.

Does not clear `frame_dirty` — that is consumed at frame start so mid-frame
`request_frame` calls survive to the next iteration.
*/
@(private)
frame_after_present :: proc() {
	if state == nil do return

	_ = frame_wake_active(frame_now_ns())
}
