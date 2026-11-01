#+test
package main

import "core:testing"
import o "./oni"

@(test)
gallery_tengu_tick_uses_seconds_and_requests_only_active_animation_frames :: proc(t: ^testing.T) {
	state := new(Persistent)
	defer free(state)
	saved_state, saved_theme, saved_widgets := o.state, o.theme, o.w_ctx
	defer { o.state, o.theme, o.w_ctx = saved_state, saved_theme, saved_widgets }
	saved := persistent
	persistent = state
	defer persistent = saved
	o.Bind(&state.engine, &state.theme)
	m7_init_animation()
	state.engine.frame_dirty = false
	m7_tick(.5)
	testing.expect(t, state.engine.frame_dirty)
	testing.expect_value(t, state.motion.elapsed, f32(.5))
	testing.expect_value(t, state.animated_color.elapsed, f32(.5))
	testing.expect_value(t, state.animated_stroke.elapsed, f32(.5))
	testing.expect_value(t, state.animated_bend.elapsed, f32(.5))
	state.m7_playing = false
	state.engine.frame_dirty = false
	m7_tick(1)
	testing.expect(t, !state.engine.frame_dirty)
	testing.expect_value(t, state.motion.elapsed, f32(.5))
}

@(test)
m7_space_visibility_snapshot_is_captured_on_layout_not_draw :: proc(t: ^testing.T) {
	state := new(Persistent)
	defer free(state)
	saved := persistent
	persistent = state
	defer persistent = saved
	saved_state := o.state
	defer o.state = saved_state
	persistent.m7_show_spaces = true
	o.state.ui.pass = .Layout
	if o.ui_pass() == .Layout { persistent.m7_spaces_snapshot = persistent.m7_show_spaces }
	persistent.m7_show_spaces = false
	testing.expect(t, persistent.m7_spaces_snapshot)
	o.state.ui.pass = .Draw
	testing.expect(t, !persistent.m7_show_spaces)
	testing.expect(t, persistent.m7_spaces_snapshot)
}
