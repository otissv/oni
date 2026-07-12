package widgets

import o ".."
import "core:testing"

@(private)
lifecycle_mount_calls: int
@(private)
lifecycle_unmount_calls: int

@(test)
widget_can_interact_blocks_disabled_unmounting_and_mounting :: proc(t: ^testing.T) {
	handlers := Widget_Lifecycle_Handlers(o.Widget_Frame_State){}

	enabled := o.Widget_Frame_State{}
	testing.expect(t, widget_can_interact(handlers, &enabled))

	disabled := o.Widget_Frame_State {
		is_disabled = true,
	}
	testing.expect(t, !widget_can_interact(handlers, &disabled))

	unmounting := o.Widget_Frame_State {
		unmounting = .RUNNING,
	}
	testing.expect(t, !widget_can_interact(handlers, &unmounting))

	mounting := o.Widget_Frame_State {
		mounting = .RUNNING,
	}
	testing.expect(t, !widget_can_interact(handlers, &mounting))

	interactive_handlers := Widget_Lifecycle_Handlers(o.Widget_Frame_State) {
		can_interactive_during_mount = true,
	}
	testing.expect(t, widget_can_interact(interactive_handlers, &mounting))
}

@(test)
widget_run_layout_lifecycle_mount_completes_and_persists :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			lifecycle_mount_calls = 0
			handlers := Widget_Lifecycle_Handlers(o.Widget_Frame_State) {
				on_mount = proc(frame_state: o.Widget_Frame_State) -> o.Mount {
					_ = frame_state
					lifecycle_mount_calls += 1
					return .COMPLETED
				},
			}

			frame := o.Widget_Frame_State{}
			layout_id := o.ui_id("mount-me")

			skip, ran_unmount := widget_run_layout_lifecycle(handlers, layout_id, true, &frame)
			testing.expect(t, !skip)
			testing.expect(t, !ran_unmount)
			testing.expect_value(t, lifecycle_mount_calls, 1)
			testing.expect(t, frame.mounting == .COMPLETED)

			entry := o.widget_lifecycle_entry(layout_id)
			testing.expect(t, entry.mounting == .COMPLETED)

			skip, _ = widget_run_layout_lifecycle(handlers, layout_id, true, &frame)
			testing.expect(t, !skip)
			testing.expect_value(t, lifecycle_mount_calls, 1)
		},
	)
}

@(test)
widget_run_layout_lifecycle_unmount_skips_layout_when_completed :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			lifecycle_unmount_calls = 0
			handlers := Widget_Lifecycle_Handlers(o.Widget_Frame_State) {
				unmount = true,
				on_unmount = proc(frame_state: o.Widget_Frame_State) -> o.Mount {
					_ = frame_state
					lifecycle_unmount_calls += 1
					return .COMPLETED
				},
			}

			frame := o.Widget_Frame_State{}
			layout_id := o.ui_id("bye")

			skip, ran := widget_run_layout_lifecycle(handlers, layout_id, true, &frame)
			testing.expect(t, skip)
			testing.expect(t, ran)
			testing.expect_value(t, lifecycle_unmount_calls, 1)
		},
	)
}

@(test)
widget_prepare_draw_returns_false_without_layout_node :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			handlers := Widget_Lifecycle_Handlers(o.Widget_Frame_State) {
				unmount = true,
			}
			frame := o.Widget_Frame_State{}
			layout_id := o.ui_id("ghost")
			testing.expect(t, !widget_prepare_draw(handlers, layout_id, &frame))
		},
	)
}

@(test)
widget_prepare_draw_syncs_lifecycle_when_node_exists :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			layout_id := o.ui_id("alive")
			cfg := o.Resolved_Widget_Config {
				kind = .RECT,
				width = len_fixed(40),
				height = len_fixed(20),
			}
			o.layout_push_node(layout_id, cfg)
			o.layout_pop_node()
			widget_test_finish_layout()

			entry := o.widget_lifecycle_entry(layout_id)
			entry.mounting = .COMPLETED

			handlers := Widget_Lifecycle_Handlers(o.Widget_Frame_State){}
			frame := o.Widget_Frame_State{}
			testing.expect(t, widget_prepare_draw(handlers, layout_id, &frame))
			testing.expect(t, frame.mounting == .COMPLETED)
		},
	)
}
