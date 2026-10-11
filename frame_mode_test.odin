package oni

import "core:testing"
import sdl "vendor:sdl3"

@(test)
frame_mode_set_and_request_frame :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		testing.expect_value(t, frame_mode(), Frame_Mode.Continuous)
		testing.expect(t, !state.frame_dirty)

		frame_mode_set(.On_Demand)
		testing.expect_value(t, frame_mode(), Frame_Mode.On_Demand)
		testing.expect(t, state.frame_dirty)

		state.frame_dirty = false
		request_frame()
		testing.expect(t, state.frame_dirty)
	})
}

@(test)
frame_pacing_effective_respects_mode_and_focus :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		state.window_focused = true
		frame_mode_set(.Continuous)
		testing.expect_value(t, frame_pacing_effective(), Frame_Pacing.Continuous)
		testing.expect(t, !frame_pacing_is_on_demand())

		frame_mode_set(.On_Demand)
		testing.expect_value(t, frame_pacing_effective(), Frame_Pacing.On_Demand)
		testing.expect(t, frame_pacing_is_on_demand())

		frame_mode_set(.Focused)
		state.window_focused = true
		testing.expect_value(t, frame_pacing_effective(), Frame_Pacing.Continuous)
		state.window_focused = false
		testing.expect_value(t, frame_pacing_effective(), Frame_Pacing.On_Demand)
	})
}

@(test)
frame_wake_for_extends_deadline_and_requests_frame :: proc(t: ^testing.T) {
	with_engine_sdl_env(t, proc(t: ^testing.T) {
		state.frame_dirty = false
		state.wake_until_ns = 0

		wake_for(0.25)
		testing.expect(t, state.frame_dirty)
		first := state.wake_until_ns
		testing.expect(t, first > sdl.GetTicksNS())

		state.frame_dirty = false
		wake_for(0.05)
		testing.expect_value(t, state.wake_until_ns, first)
		testing.expect(t, state.frame_dirty)

		later := sdl.GetTicksNS() + 1_000_000_000
		wake_until_ns(later)
		testing.expect_value(t, wake_deadline_ns(), later)
	})
}

@(test)
settings_rejects_frame_mode_node :: proc(t: ^testing.T) {
	parsed, err := settings_parse_document(`frame-mode on-demand
window { title "Pace" }`)
	defer settings_destroy_value(parsed)
	testing.expect(t, !err.ok)
}

@(test)
frame_consume_dirty_clears_oneshot_keeps_active_wake :: proc(t: ^testing.T) {
	with_engine_sdl_env(t, proc(t: ^testing.T) {
		state.frame_dirty = true
		state.wake_until_ns = sdl.GetTicksNS() + 500_000_000
		frame_consume_dirty()
		testing.expect(t, !state.frame_dirty)
		testing.expect(t, state.wake_until_ns != 0)
		testing.expect(t, frame_work_pending())

		state.wake_until_ns = 1
		_ = frame_wake_active(sdl.GetTicksNS())
		testing.expect_value(t, state.wake_until_ns, u64(0))
	})
}

@(test)
frame_after_present_preserves_mid_frame_request :: proc(t: ^testing.T) {
	with_engine_sdl_env(t, proc(t: ^testing.T) {
		state.frame_dirty = true
		frame_consume_dirty()
		testing.expect(t, !state.frame_dirty)

		request_frame()
		frame_after_present()
		testing.expect(t, state.frame_dirty)
		testing.expect(t, frame_work_pending())
	})
}

@(test)
run_frame_on_demand_skips_when_idle :: proc(t: ^testing.T) {
	with_runtime_sdl_env(t, proc(t: ^testing.T) {
		test_hook_skip_frame_wait = true
		theme = nil
		state.window = nil
		state.gpu = nil
		ui_init()
		defer ui_shutdown()

		frame_mode_set(.On_Demand)
		state.frame_dirty = false
		state.wake_until_ns = 0
		state.can_render = true
		runtime_test_reset_counters()

		run_frame(runtime_test_tick, runtime_test_draw, runtime_test_init)
		testing.expect_value(t, runtime_test_tick_calls, 0)
		testing.expect_value(t, runtime_test_draw_calls, 0)

		request_frame()
		run_frame(runtime_test_tick, runtime_test_draw, runtime_test_init)
		testing.expect_value(t, runtime_test_tick_calls, 1)
		testing.expect(t, !state.frame_dirty)

		// Mid-frame Request_Frame must schedule another on-demand frame.
		runtime_test_reset_counters()
		runtime_test_tick_request_frame = true
		request_frame()
		run_frame(runtime_test_tick, runtime_test_draw, runtime_test_init)
		testing.expect_value(t, runtime_test_tick_calls, 1)
		testing.expect(t, state.frame_dirty)

		runtime_test_tick_request_frame = false
		runtime_test_reset_counters()
		run_frame(runtime_test_tick, runtime_test_draw, runtime_test_init)
		testing.expect_value(t, runtime_test_tick_calls, 1)
		testing.expect(t, !state.frame_dirty)
	})
}

@(test)
run_frame_continuous_always_ticks :: proc(t: ^testing.T) {
	with_runtime_sdl_env(t, proc(t: ^testing.T) {
		test_hook_skip_frame_wait = true
		theme = nil
		state.window = nil
		state.gpu = nil
		ui_init()
		defer ui_shutdown()

		frame_mode_set(.Continuous)
		state.frame_dirty = false
		state.can_render = true
		runtime_test_reset_counters()

		run_frame(runtime_test_tick, runtime_test_draw, runtime_test_init)
		testing.expect_value(t, runtime_test_tick_calls, 1)
	})
}

@(test)
engine_focus_gain_and_loss_update_flag_and_dirty :: proc(t: ^testing.T) {
	with_engine_sdl_env(t, proc(t: ^testing.T) {
		state.window_focused = true
		state.frame_dirty = false
		engine_test_push(t, {type = .WINDOW_FOCUS_LOST})
		poll_events()
		testing.expect(t, !state.window_focused)
		testing.expect(t, state.frame_dirty)

		state.frame_dirty = false
		engine_test_push(t, {type = .WINDOW_FOCUS_GAINED})
		poll_events()
		testing.expect(t, state.window_focused)
		testing.expect(t, state.frame_dirty)
	})
}
