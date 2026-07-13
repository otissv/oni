package oni

import "core:sync"
import "core:testing"

/*
Runs body with engine state, theme, and UI maps ready for style/widget/ui tests.

Shares the layout-test mutex so parallel `odin test` workers do not clobber globals.
*/
@(private)
with_ui_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	test_state: State
	test_theme := Theme {
		palette      = palette,
		border       = 0,
		border_color = .BLACK,
		background   = .TRANSPARENT,
		padding      = 0,
		radius       = 0,
		gap_x        = u16(0),
		gap_y        = u16(0),
		color        = .FOREGROUND,
		justify      = Justify_Pos{x = .START, y = .START},
		direction    = Direction_Layout.VERTICAL,
		font_body    = {},
		width        = 0,
		height       = 0,
	}

	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	saved_state := state
	saved_theme := theme
	saved_w_ctx := w_ctx
	defer {
		state = saved_state
		theme = saved_theme
		w_ctx = saved_w_ctx
	}

	state = &test_state
	theme = &test_theme
	w_ctx = &state.widget
	state.widget = {}
	state.dpi = {logical_w = 800, logical_h = 600, scale = 1}
	state.view = view_default()
	state.gpu_state.batch.vertex_capacity = 64 * 1024
	state.gpu_state.batch.index_capacity = 64 * 1024 * 6

	ui_init()
	defer {
		for len(state.ui.style_stack) > 0 {
			ui_pop_style()
		}
		ui_shutdown()
		delete(state.gpu_state.batch.vertices)
		delete(state.gpu_state.batch.indices)
		delete(state.gpu_state.batch.segments)
		delete(state.gpu_state.batch.clip_stack)
		delete(state.gpu_state.batch.space_stack)
		delete(state.gpu_state.batch.opacity_stack)
	}

	ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
	body(t)
}

@(private)
ui_test_frame_event :: proc() -> (frame: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) {
	frame = {}
	event = {frame_state = frame}
	return
}

@(private)
expect_pd :: proc(t: ^testing.T, got, want: Pd_px, loc := #caller_location) {
	expect_close(t, got.t, want.t, loc = loc)
	expect_close(t, got.b, want.b, loc = loc)
	expect_close(t, got.l, want.l, loc = loc)
	expect_close(t, got.r, want.r, loc = loc)
}

@(private)
expect_bd :: proc(t: ^testing.T, got, want: Bd_px, loc := #caller_location) {
	expect_close(t, got.t, want.t, loc = loc)
	expect_close(t, got.b, want.b, loc = loc)
	expect_close(t, got.l, want.l, loc = loc)
	expect_close(t, got.r, want.r, loc = loc)
}

@(private)
expect_radius :: proc(t: ^testing.T, got, want: Radius_px, loc := #caller_location) {
	expect_close(t, got.tl, want.tl, loc = loc)
	expect_close(t, got.tr, want.tr, loc = loc)
	expect_close(t, got.bl, want.bl, loc = loc)
	expect_close(t, got.br, want.br, loc = loc)
}
