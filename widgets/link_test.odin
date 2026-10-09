package oni_widgets

import o ".."
import set "../set"
import sdl "vendor:sdl3"
import "core:testing"

@(private)
link_test_navigate_count: int

@(private)
link_test_click_count: int

@(private)
link_test_click_key: o.Scancode

@(private)
link_test_href: string

@(private)
link_test_child_count: int

@(private)
link_test_on_navigate :: proc(event: Link_Event) {
	link_test_navigate_count += 1
	link_test_href = event.frame_state.href
}

@(private)
link_test_on_click :: proc(event: Link_Event) {
	link_test_click_count += 1
	link_test_click_key = event.key
}

@(private)
link_test_child :: proc(_: Link_State) {
	link_test_child_count += 1
}

@(private)
link_test_reset_events :: proc() {
	link_test_navigate_count = 0
	link_test_click_count = 0
	link_test_click_key = o.Scancode(0)
	link_test_href = ""
	link_test_child_count = 0
}

@(private)
link_test_pointer_press_release :: proc(props: Link_Props, x: f32 = 8, y: f32 = 8) {
	widget_test_begin_layout()
	Link(props)
	widget_test_finish_layout()
	o.w_ctx.mouse_x = x
	o.w_ctx.mouse_y = y
	widget_test_begin_draw()
	o.w_ctx.left_mouse = {down = true, pressed = true}
	Link(props)
	widget_test_end_frame()

	widget_test_begin_layout()
	Link(props)
	widget_test_finish_layout()
	o.w_ctx.mouse_x = x
	o.w_ctx.mouse_y = y
	widget_test_begin_draw()
	o.w_ctx.left_mouse = {released = true}
	Link(props)
	widget_test_end_frame()
}

@(test)
link_theme_base_sets_link_defaults :: proc(t: ^testing.T) {
	frame := Link_State{}
	base := link_theme_base(&frame)

	testing.expect(t, base.kind == .LINK)
	testing.expect(t, o.cfg_style_bool(base.tabbable))
	testing.expect(t, base.text_decoration.mode == .Value)
}

@(test)
link_layout_registers_kind_and_tab_order :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Link({
			config = {
				id = "link-layout",
				width = set.Width(f32(80)),
				height = set.Height(f32(20)),
			},
			href = "https://example.com",
			text = "Example",
		})
		widget_test_finish_layout()

		expect_registered_id(t, "link-layout")
		expect_layout_kind(t, "link-layout", .LINK)
		expect_in_tab_order(t, "link-layout", true)
	})
}

@(test)
link_disabled_is_not_tabbable :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Link({
			config = {
				id = "link-disabled",
				width = set.Width(f32(80)),
				height = set.Height(f32(20)),
			},
			href = "https://example.com",
			text = "Example",
			disabled = true,
		})
		expect_in_tab_order(t, "link-disabled", false)
		widget_test_finish_layout()
	})
}

@(test)
link_config_override_preserves_kind :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		props := Link_Props {
			config = {id = "link-styled", color = set.Colors(o.Color.ACCENT)},
			href = "/docs",
			text = "Docs",
		}
		frame := Link_State {
			href = props.href,
			text = props.text,
		}
		event := link_refresh_merged(props, &frame)
		testing.expect(t, event.frame_state.config.kind == .LINK)
		testing.expect_value(t, event.frame_state.config.id, "link-styled")
	})
}

@(test)
link_enter_activates_when_focused :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		link_test_reset_events()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		props := Link_Props {
			config = {
				id = "link-enter",
				width = set.Width(f32(80)),
				height = set.Height(f32(20)),
			},
			href = "/route",
			text = "Go",
			suppress_open_url = true,
			on_navigate = link_test_on_navigate,
			on_click = link_test_on_click,
		}
		Link(props)
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("link-enter")
		o.w_ctx.keys[int(sdl.Scancode.RETURN)] = {down = true, pressed = true}
		Link(props)

		testing.expect_value(t, link_test_navigate_count, 1)
		testing.expect_value(t, link_test_click_count, 1)
		testing.expect_value(t, link_test_href, "/route")
		testing.expect(t, link_test_click_key == o.Scancode(sdl.Scancode.RETURN))
	})
}

@(test)
link_space_does_not_activate :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		link_test_reset_events()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		props := Link_Props {
			config = {
				id = "link-space",
				width = set.Width(f32(80)),
				height = set.Height(f32(20)),
			},
			href = "/route",
			text = "Go",
			suppress_open_url = true,
			on_navigate = link_test_on_navigate,
			on_click = link_test_on_click,
		}
		Link(props)
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("link-space")
		o.w_ctx.keys[int(sdl.Scancode.SPACE)] = {down = true, pressed = true}
		Link(props)

		testing.expect_value(t, link_test_navigate_count, 0)
		testing.expect_value(t, link_test_click_count, 0)
	})
}

@(test)
link_pointer_click_activates_without_mod :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		link_test_reset_events()
		props := Link_Props {
			config = {
				id = "link-pointer",
				width = set.Width(f32(80)),
				height = set.Height(f32(20)),
			},
			href = "/docs",
			text = "Docs",
			suppress_open_url = true,
			on_navigate = link_test_on_navigate,
			on_click = link_test_on_click,
		}

		link_test_pointer_press_release(props)

		testing.expect_value(t, link_test_navigate_count, 1)
		testing.expect_value(t, link_test_click_count, 1)
		testing.expect_value(t, link_test_href, "/docs")
	})
}

@(test)
link_mod_blocks_plain_pointer_click :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		link_test_reset_events()
		props := Link_Props {
			config = {
				id = "link-mod-block",
				width = set.Width(f32(80)),
				height = set.Height(f32(20)),
			},
			href = "https://example.com",
			text = "Example",
			mod = .CTRL,
			suppress_open_url = true,
			on_navigate = link_test_on_navigate,
			on_click = link_test_on_click,
		}

		o.state.input.modifiers = {}
		link_test_pointer_press_release(props)

		testing.expect_value(t, link_test_navigate_count, 0)
		testing.expect_value(t, link_test_click_count, 0)
	})
}

@(test)
link_mod_allows_modified_pointer_click :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		link_test_reset_events()
		props := Link_Props {
			config = {
				id = "link-mod-ok",
				width = set.Width(f32(80)),
				height = set.Height(f32(20)),
			},
			href = "https://example.com",
			text = "Example",
			mod = .CTRL,
			suppress_open_url = true,
			on_navigate = link_test_on_navigate,
			on_click = link_test_on_click,
		}

		o.state.input.modifiers = {ctrl = true}
		link_test_pointer_press_release(props)

		testing.expect_value(t, link_test_navigate_count, 1)
		testing.expect_value(t, link_test_click_count, 1)
		testing.expect_value(t, link_test_href, "https://example.com")
	})
}

@(test)
link_mod_enter_still_activates_without_modifier :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		link_test_reset_events()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		props := Link_Props {
			config = {
				id = "link-mod-enter",
				width = set.Width(f32(80)),
				height = set.Height(f32(20)),
			},
			href = "/route",
			text = "Go",
			mod = .PRIMARY,
			suppress_open_url = true,
			on_navigate = link_test_on_navigate,
			on_click = link_test_on_click,
		}
		Link(props)
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.state.input.modifiers = {}
		o.widget_set_focused_id("link-mod-enter")
		o.w_ctx.keys[int(sdl.Scancode.RETURN)] = {down = true, pressed = true}
		Link(props)

		testing.expect_value(t, link_test_navigate_count, 1)
		testing.expect_value(t, link_test_click_count, 1)
	})
}

@(test)
link_disabled_blocks_activation :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		link_test_reset_events()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		props := Link_Props {
			config = {
				id = "link-disabled-activate",
				width = set.Width(f32(80)),
				height = set.Height(f32(20)),
			},
			href = "/route",
			text = "Go",
			disabled = true,
			suppress_open_url = true,
			on_navigate = link_test_on_navigate,
		}
		Link(props)
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("link-disabled-activate")
		o.w_ctx.keys[int(sdl.Scancode.RETURN)] = {down = true, pressed = true}
		Link(props)

		testing.expect_value(t, link_test_navigate_count, 0)
	})
}

@(test)
link_custom_child_runs_instead_of_text :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		link_test_reset_events()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Link({
			config = {
				id = "link-child",
				width = set.Width(f32(80)),
				height = set.Height(f32(20)),
			},
			href = "/x",
			text = "ignored",
			child = link_test_child,
		})
		widget_test_finish_layout()
		widget_test_begin_draw()
		Link({
			config = {
				id = "link-child",
				width = set.Width(f32(80)),
				height = set.Height(f32(20)),
			},
			href = "/x",
			text = "ignored",
			child = link_test_child,
		})

		testing.expect_value(t, link_test_child_count, 2)
	})
}

@(test)
link_mod_satisfied_primary_matches_platform :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		o.state.input.modifiers = {}
		testing.expect(t, Link_Mod_Satisfied(.NONE))
		testing.expect(t, !Link_Mod_Satisfied(.CTRL))
		testing.expect(t, !Link_Mod_Satisfied(.PRIMARY))

		o.state.input.modifiers = {ctrl = true}
		testing.expect(t, Link_Mod_Satisfied(.CTRL))

		when ODIN_OS == .Darwin {
			testing.expect(t, !Link_Mod_Satisfied(.PRIMARY))
			o.state.input.modifiers = {super = true}
			testing.expect(t, Link_Mod_Satisfied(.PRIMARY))
			testing.expect(t, Link_Mod_Satisfied(.SUPER))
		} else {
			testing.expect(t, Link_Mod_Satisfied(.PRIMARY))
			o.state.input.modifiers = {super = true}
			testing.expect(t, !Link_Mod_Satisfied(.PRIMARY))
			testing.expect(t, Link_Mod_Satisfied(.SUPER))
		}
	})
}

@(test)
link_unmount_skips_layout_node :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Link({
			config = {
				id = "link-gone",
				width = set.Width(f32(40)),
				height = set.Height(f32(20)),
			},
			href = "/x",
			text = "Gone",
			unmount = true,
			on_unmount = proc(frame_state: Link_State) -> o.Mount {
				_ = frame_state

				return .COMPLETED
			},
		})
		_, ok := widget_test_layout_node("link-gone")
		testing.expect(t, !ok)
		widget_test_finish_layout()
	})
}
