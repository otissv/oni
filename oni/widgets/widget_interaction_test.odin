package widgets

import o ".."
import "core:testing"
import set "../set"
import sdl "vendor:sdl3"

@(private)
interaction_clicked: int
@(private)
interaction_entered: int
@(private)
interaction_key: o.Scancode

@(test)
widget_event_and_config_merge_theme_with_overrides :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			props := Rectangle_Props {
				config = {
					id = "panel",
					background = set.Background(o.Color.PRIMARY),
				},
			}
			frame := Rectangle_State{}
			config := widget_config(props, &frame, rect_theme_base)
			testing.expect(t, config.kind == .RECT)
			testing.expect_value(t, config.id, "panel")

			event := widget_event(frame, mouse_button = sdl.BUTTON_LEFT, key = o.Scancode.SPACE)
			testing.expect_value(t, event.mouse_button, sdl.BUTTON_LEFT)
			testing.expect(t, event.key == o.Scancode.SPACE)
		},
	)
}

@(test)
widget_dispatch_events_fires_click_on_pointer_release :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			interaction_clicked = 0
			interaction_entered = 0
			props := Rectangle_Props {
				on_click = proc(event: Rectangle_Event) {
					_ = event
					interaction_clicked += 1
				},
				on_mouse_enter = proc(event: Rectangle_Event) {
					_ = event
					interaction_entered += 1
				},
			}

			frame := Rectangle_State {
				is_hovered = true,
			}
			handlers := widget_lifecycle_handlers(props, Rectangle_State)
			event := widget_event(frame)

			o.w_ctx.left_mouse.pressed = true
			widget_dispatch_events(props, &frame, handlers, event, "rect", false, false)
			testing.expect_value(t, interaction_entered, 1)
			testing.expect_value(t, interaction_clicked, 0)

			o.w_ctx.left_mouse.pressed = false
			o.w_ctx.left_mouse.released = true
			widget_dispatch_events(props, &frame, handlers, event, "rect", false, false)
			testing.expect_value(t, interaction_clicked, 1)
		},
	)
}

@(test)
widget_dispatch_events_keyboard_click_when_focused :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			interaction_clicked = 0
			interaction_key = o.Scancode(0)
			props := Rectangle_Props {
				on_click = proc(event: Rectangle_Event) {
					interaction_clicked += 1
					interaction_key = event.key
				},
			}
			frame := Rectangle_State {
				is_focused = true,
			}
			handlers := widget_lifecycle_handlers(props, Rectangle_State)
			event := widget_event(frame)

			o.w_ctx.keys[int(sdl.Scancode.RETURN)].pressed = true
			widget_dispatch_events(props, &frame, handlers, event, "rect", false, false)
			testing.expect_value(t, interaction_clicked, 1)
			testing.expect(t, interaction_key == o.Scancode(sdl.Scancode.RETURN))
		},
	)
}

@(test)
widget_dispatch_events_skips_when_cannot_interact :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			interaction_clicked = 0
			props := Rectangle_Props {
				on_click = proc(event: Rectangle_Event) {
					_ = event
					interaction_clicked += 1
				},
			}
			frame := Rectangle_State {
				is_hovered = true,
				is_disabled = true,
			}
			handlers := widget_lifecycle_handlers(props, Rectangle_State)
			event := widget_event(frame)
			o.w_ctx.left_mouse.pressed = true
			o.w_ctx.left_mouse.released = true
			widget_dispatch_events(props, &frame, handlers, event, "rect", false, false)
			testing.expect_value(t, interaction_clicked, 0)
		},
	)
}

@(test)
widget_handle_interaction_sets_hover_and_click_flags :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			props := Rectangle_Props{}
			frame := Rectangle_State{}
			handlers := widget_lifecycle_handlers(props, Rectangle_State)
			config := o.Resolved_Widget_Config {
				space = .SCREEN,
				tabbable = true,
			}

			o.w_ctx.mouse_x = 15
			o.w_ctx.mouse_y = 15
			o.w_ctx.left_mouse.pressed = true
			o.w_ctx.left_mouse.down = true

			got, lost := widget_handle_interaction(
				props,
				&frame,
				handlers,
				"hit",
				false,
				true,
				{0, 0, 40, 40},
				config,
			)
			testing.expect(t, frame.is_hovered)
			testing.expect(t, frame.is_left_clicked)
			testing.expect(t, frame.is_Pressed)
			testing.expect(t, got && !lost)
			testing.expect(t, frame.is_focused)
		},
	)
}
