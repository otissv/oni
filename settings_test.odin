package oni

import "core:os"
import "core:strings"
import "core:testing"
import sdl "vendor:sdl3"

@(private)
settings_test_hook_count: int

@(private)
settings_test_apply_hook :: proc() {
	settings_test_hook_count += 1
}

@(private)
settings_test_write :: proc(path: string, doc: string) -> bool {
	return os.write_entire_file(path, transmute([]byte)doc) == nil
}

@(private)
settings_test_find_binding :: proc(id: string, key: Scancode, ctrl: bool) -> bool {
	for i in 0 ..< shortcut_binding_count() {
		b, ok := shortcut_binding_get(i)

		if ok && b.id == id && b.chord.key == key && b.chord.ctrl == ctrl {
			return true
		}
	}

	return false
}

@(test)
settings_parse_window_dpi_fonts_and_bind :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		doc := `
window {
	mode fullscreen
	title "Demo"
	width 800
	height 600
	min-width 200
	min-height 100
}
dpi scale=2
fonts {
	body-size 18
	heading-size 24
	family Inter {
		face {
			path "a.ttf"
			style italic
			weight bold
		}
	}
}
bind trigger="CTRL+P" action="demo.ping" enabled=#false
`
		parsed, err := settings_parse_document(doc)
		defer settings_destroy_value(parsed)
		testing.expect(t, err.ok)
		testing.expect_value(t, parsed.window_mode, Window_Mode.Fullscreen)
		testing.expect_value(t, parsed.window_title, "Demo")
		testing.expect_value(t, parsed.window_width, i32(800))
		testing.expect_value(t, parsed.window_height, i32(600))
		testing.expect_value(t, parsed.min_width, i32(200))
		testing.expect_value(t, parsed.min_height, i32(100))
		expect_close(t, parsed.dpi_scale, 2)
		testing.expect_value(t, parsed.font_family, "Inter")
		expect_close(t, parsed.font_body_size, 18)
		expect_close(t, parsed.font_heading_size, 24)
		testing.expect_value(t, len(parsed.font_faces), 1)
		testing.expect_value(t, parsed.font_faces[0].path, "a.ttf")
		style, style_ok := parsed.font_faces[0].style.(Font_Styles)
		testing.expect(t, style_ok && style == .ITALIC)
		weight, weight_ok := parsed.font_faces[0].weight.(Font_Weights)
		testing.expect(t, weight_ok && weight == .Bold)
		testing.expect_value(t, len(parsed.shortcut_rows), 1)
		testing.expect_value(t, parsed.shortcut_rows[0].id, "demo.ping")
		testing.expect(t, !parsed.shortcut_rows[0].enabled)
		testing.expect(t, parsed.shortcut_rows[0].chord.ctrl)
		testing.expect_value(t, parsed.shortcut_rows[0].chord.key, Scancode.P)
	})
}

@(test)
settings_parse_window_modes :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		cases := [?]struct {
			token: string,
			mode:  Window_Mode,
		} {
			{"window", .Window},
			{"borderless", .Borderless},
			{"maximize", .Maximize},
			{"fullscreen", .Fullscreen},
		}

		for c in cases {
			doc := strings.concatenate(
				{"window {\n\tmode ", c.token, "\n}\n"},
				context.temp_allocator,
			)
			parsed, err := settings_parse_document(doc)
			defer settings_destroy_value(parsed)
			testing.expectf(t, err.ok, "mode %s should parse", c.token)
			testing.expect_value(t, parsed.window_mode, c.mode)
		}

		bad, bad_err := settings_parse_document("window { mode no-such-mode }")
		settings_destroy_value(bad)
		testing.expect(t, !bad_err.ok)
	})
}

@(test)
settings_apply_window_mode_updates_state :: proc(t: ^testing.T) {
	with_engine_sdl_window_env(t, proc(t: ^testing.T) {
		settings_ensure()
		state.settings.window_mode = .Fullscreen
		settings_apply_window()
		testing.expect_value(t, state.settings.window_mode, Window_Mode.Fullscreen)
		testing.expect(t, state.fullscreen)

		state.settings.window_mode = .Window
		settings_apply_window()
		testing.expect_value(t, state.settings.window_mode, Window_Mode.Window)
		testing.expect(t, !state.fullscreen)

		state.settings.window_mode = .Borderless
		settings_apply_window()
		testing.expect_value(t, state.settings.window_mode, Window_Mode.Borderless)
		testing.expect(t, !state.fullscreen)

		state.settings.window_mode = .Maximize
		settings_apply_window()
		testing.expect_value(t, state.settings.window_mode, Window_Mode.Maximize)
		testing.expect(t, !state.fullscreen)
	})
}

@(test)
settings_export_includes_window_mode :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		settings_ensure()
		state.settings.window_mode = .Borderless
		data := settings_export(context.temp_allocator)
		testing.expect(t, strings.contains(data, "mode"))
		testing.expect(t, strings.contains(data, "borderless"))
	})
}

@(test)
settings_parse_dpi_auto_and_unknown_node_fails :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		parsed, err := settings_parse_document(`dpi scale="auto"`)
		defer settings_destroy_value(parsed)
		testing.expect(t, err.ok)
		expect_close(t, parsed.dpi_scale, 0)

		bad, bad_err := settings_parse_document("NOT_A_VALID_BINDING\n")
		settings_destroy_value(bad)
		testing.expect(t, !bad_err.ok)
		testing.expect(t, bad_err.line >= 1)
	})
}

@(test)
settings_parse_empty_uses_defaults :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		parsed, err := settings_parse_document("")
		defer settings_destroy_value(parsed)
		testing.expect(t, err.ok)
		testing.expect_value(t, parsed.window_title, SETTINGS_DEFAULT_WINDOW_TITLE)
		testing.expect_value(t, parsed.window_width, SETTINGS_DEFAULT_WINDOW_WIDTH)
		testing.expect_value(t, parsed.font_family, SETTINGS_DEFAULT_FONT_FAMILY)
		testing.expect_value(t, len(parsed.font_faces), 2)
		testing.expect_value(t, parsed.font_faces[0].path, SETTINGS_DEFAULT_FONT_REGULAR_PATH)
		testing.expect_value(t, parsed.font_faces[1].path, SETTINGS_DEFAULT_FONT_ITALIC_PATH)
		expect_close(t, parsed.dpi_scale, 0)
	})
}

@(test)
settings_parse_fonts_without_family_keeps_engine_faces :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		parsed, err := settings_parse_document("fonts { body-size 18 }")
		defer settings_destroy_value(parsed)
		testing.expect(t, err.ok)
		expect_close(t, parsed.font_body_size, 18)
		testing.expect_value(t, parsed.font_heading_size, SETTINGS_DEFAULT_FONT_HEADING_SIZE)
		testing.expect_value(t, parsed.font_family, SETTINGS_DEFAULT_FONT_FAMILY)
		testing.expect_value(t, len(parsed.font_faces), 2)
		testing.expect_value(t, parsed.font_faces[0].path, SETTINGS_DEFAULT_FONT_REGULAR_PATH)
		testing.expect_value(t, parsed.font_faces[1].path, SETTINGS_DEFAULT_FONT_ITALIC_PATH)
	})
}

@(test)
settings_parse_family_without_faces_falls_back_to_engine :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		parsed, err := settings_parse_document("fonts { family Demo { } }")
		defer settings_destroy_value(parsed)
		testing.expect(t, err.ok)
		testing.expect_value(t, parsed.font_family, "Demo")
		testing.expect_value(t, len(parsed.font_faces), 2)
		testing.expect_value(t, parsed.font_faces[0].path, SETTINGS_DEFAULT_FONT_REGULAR_PATH)
		testing.expect_value(t, parsed.font_faces[1].path, SETTINGS_DEFAULT_FONT_ITALIC_PATH)
	})
}

@(test)
settings_parse_shortcuts_block_scoped_bind_and_numeric_weight :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		doc := `
fonts {
	family Demo {
		face {
			path "bold.ttf"
			style normal
			weight 700
		}
	}
}
shortcuts {
	bind trigger="CTRL+P" action="demo.ping" scope="context" scope-key="artboard" priority=10
}
`
		parsed, err := settings_parse_document(doc)
		defer settings_destroy_value(parsed)
		testing.expect(t, err.ok)
		testing.expect_value(t, len(parsed.font_faces), 1)
		weight, weight_ok := parsed.font_faces[0].weight.(f32)
		testing.expect(t, weight_ok)
		expect_close(t, weight, 700)
		testing.expect_value(t, len(parsed.shortcut_rows), 1)
		testing.expect_value(t, parsed.shortcut_rows[0].id, "demo.ping")
		testing.expect_value(t, parsed.shortcut_rows[0].scope, Shortcut_Scope.Context)
		testing.expect_value(t, parsed.shortcut_rows[0].scope_key, "artboard")
		testing.expect_value(t, parsed.shortcut_rows[0].priority, i32(10))
	})
}

@(test)
settings_get_ensures_defaults :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		testing.expect(t, !state.settings.ready)
		s := settings_get()
		testing.expect(t, s != nil)
		testing.expect(t, s.ready)
		testing.expect_value(t, s.window_title, SETTINGS_DEFAULT_WINDOW_TITLE)
		testing.expect_value(t, s.window_mode, SETTINGS_DEFAULT_WINDOW_MODE)
		testing.expect_value(t, len(s.font_faces), 2)
		testing.expect_value(t, s.font_faces[0].path, SETTINGS_DEFAULT_FONT_REGULAR_PATH)
		testing.expect_value(t, s.font_faces[1].path, SETTINGS_DEFAULT_FONT_ITALIC_PATH)
		testing.expect(t, os.exists(SETTINGS_DEFAULT_FONT_REGULAR_PATH))
		testing.expect(t, os.exists(SETTINGS_DEFAULT_FONT_ITALIC_PATH))
		cfg := settings_window_config()
		testing.expect_value(t, string(cfg.title), SETTINGS_DEFAULT_WINDOW_TITLE)
		testing.expect_value(t, cfg.width, SETTINGS_DEFAULT_WINDOW_WIDTH)
		testing.expect_value(t, cfg.height, SETTINGS_DEFAULT_WINDOW_HEIGHT)
		testing.expect_value(t, cfg.min_width, SETTINGS_DEFAULT_MIN_WIDTH)
		testing.expect_value(t, cfg.min_height, SETTINGS_DEFAULT_MIN_HEIGHT)
		testing.expect_value(t, cfg.mode, SETTINGS_DEFAULT_WINDOW_MODE)
	})
}

@(test)
settings_load_missing_file_installs_defaults :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		path := "build/test/settings_missing_no_such_file.kdl"
		_ = os.remove(path)
		testing.expect(t, settings_load(path))
		testing.expect(t, state.settings.ready)
		testing.expect_value(t, state.settings.path, path)
		testing.expect_value(t, state.settings.window_title, SETTINGS_DEFAULT_WINDOW_TITLE)
		testing.expect_value(t, len(state.settings.font_faces), 2)
		testing.expect_value(t, state.settings.font_faces[0].path, SETTINGS_DEFAULT_FONT_REGULAR_PATH)
		testing.expect_value(t, state.settings.font_faces[1].path, SETTINGS_DEFAULT_FONT_ITALIC_PATH)
		testing.expect(t, !shortcut_load_bindings(path))
	})
}

@(test)
settings_load_parse_error_keeps_previous :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		good_path := "build/test/settings_keep_prev_good.kdl"
		bad_path := "build/test/settings_keep_prev_bad.kdl"
		testing.expect(t, settings_test_write(good_path, `dpi scale=2
window { title "KeepMe" }`))
		testing.expect(t, settings_test_write(bad_path, "NOT_A_VALID_BINDING\n"))
		defer os.remove(good_path)
		defer os.remove(bad_path)

		testing.expect(t, settings_load(good_path))
		testing.expect_value(t, state.settings.window_title, "KeepMe")
		expect_close(t, state.settings.dpi_scale, 2)

		err := settings_load_ex(bad_path)
		testing.expect(t, !err.ok)
		testing.expect_value(t, state.settings.window_title, "KeepMe")
		expect_close(t, state.settings.dpi_scale, 2)
		testing.expect_value(t, state.settings.path, good_path)
	})
}

@(test)
settings_save_and_reload_roundtrip :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		path := "build/test/settings_save_roundtrip.kdl"
		defer os.remove(path)

		shortcut_register_action("demo.ping", shortcut_test_action_set_flag)
		settings_ensure()
		testing.expect(t, shortcut_bind("demo.ping", {key = .P, ctrl = true}))
		if state.settings.window_title != "" {
			delete(state.settings.window_title)
		}

		state.settings.window_title = strings.clone("Saved Title")
		state.settings.window_width = 900
		state.settings.window_height = 500
		state.settings.dpi_scale = 1.5

		testing.expect(t, settings_save(path))
		testing.expect_value(t, state.settings.path, path)
		testing.expect(t, os.exists(path))

		settings_shutdown()
		shortcut_shutdown()
		testing.expect(t, settings_reload(path))
		testing.expect_value(t, state.settings.window_title, "Saved Title")
		testing.expect_value(t, state.settings.window_width, i32(900))
		testing.expect_value(t, state.settings.window_height, i32(500))
		expect_close(t, state.settings.dpi_scale, 1.5)
		testing.expect(t, settings_test_find_binding("demo.ping", .P, true))

		testing.expect(t, shortcut_save_bindings(path))
		testing.expect(t, shortcut_load_bindings(path, true))
		testing.expect(t, settings_test_find_binding("demo.ping", .P, true))
	})
}

@(test)
settings_export_roundtrip_user_bind :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_register_action("demo.ping", shortcut_test_action_set_flag)
		testing.expect(t, shortcut_bind("demo.ping", {key = .P, ctrl = true}))
		data := settings_export(context.temp_allocator)
		testing.expect(t, strings.contains(data, "window"))
		testing.expect(t, strings.contains(data, "dpi"))
		testing.expect(t, strings.contains(data, "fonts"))
		testing.expect(t, strings.contains(data, "CTRL+P"))
		testing.expect(t, strings.contains(data, "demo.ping"))

		shortcut_clear_user_bindings()
		testing.expect(t, shortcut_import_bindings(data, true))
		testing.expect(t, settings_test_find_binding("demo.ping", .P, true))
	})
}

@(test)
settings_reload_applies_dpi_and_shortcuts :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		doc := `
dpi scale=2
bind trigger="CTRL+P" action="demo.ping"
`
		path := "build/test/settings_reload_test.kdl"
		testing.expect(t, settings_test_write(path, doc))
		defer os.remove(path)

		shortcut_register_action("demo.ping", shortcut_test_action_set_flag)
		testing.expect(t, settings_reload(path))
		expect_close(t, state.settings.dpi_scale, 2)
		testing.expect_value(t, len(state.settings.shortcut_rows), 1)
		testing.expect(t, settings_test_find_binding("demo.ping", .P, true))
	})
}

@(test)
settings_apply_hook_invoked_from_runtime :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		settings_test_hook_count = 0
		settings_set_apply_hook(settings_test_apply_hook)
		settings_ensure()
		testing.expect(t, settings_apply_runtime())
		testing.expect_value(t, settings_test_hook_count, 1)
		settings_set_apply_hook(nil)
		testing.expect(t, settings_apply_runtime())
		testing.expect_value(t, settings_test_hook_count, 1)
	})
}

@(test)
settings_poll_reloads_on_mtime_change_with_cooldown :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		path := "build/test/settings_poll_watch.kdl"
		testing.expect(t, settings_test_write(path, `dpi scale=1
window { title "One" }`))
		defer os.remove(path)

		settings_test_hook_count = 0
		settings_set_apply_hook(settings_test_apply_hook)
		testing.expect(t, settings_load(path))
		testing.expect_value(t, state.settings.window_title, "One")

		testing.expect(t, settings_test_write(path, `dpi scale=2
window { title "Two" }`))
		state.settings.watch_mtime_nsec = 0
		state.settings.watch_cooldown = 0
		settings_poll()
		testing.expect_value(t, state.settings.window_title, "Two")
		expect_close(t, state.settings.dpi_scale, 2)
		testing.expect_value(t, settings_test_hook_count, 1)
		testing.expect(t, state.settings.watch_cooldown == SETTINGS_WATCH_COOLDOWN_FRAMES)

		testing.expect(t, settings_test_write(path, `dpi scale=3
window { title "Three" }`))
		state.settings.watch_mtime_nsec = 0
		settings_poll()
		testing.expect_value(t, state.settings.window_title, "Two")
		testing.expect(t, state.settings.watch_cooldown == SETTINGS_WATCH_COOLDOWN_FRAMES - 1)

		state.settings.watch_cooldown = 0
		state.settings.watch_mtime_nsec = 0
		settings_poll()
		testing.expect_value(t, state.settings.window_title, "Three")
		expect_close(t, state.settings.dpi_scale, 3)
		testing.expect_value(t, settings_test_hook_count, 2)
	})
}

@(test)
settings_poll_failed_reload_keeps_settings_and_updates_mtime :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		path := "build/test/settings_poll_bad.kdl"
		testing.expect(t, settings_test_write(path, `dpi scale=2
window { title "Good" }`))
		defer os.remove(path)

		testing.expect(t, settings_load(path))
		prev_mtime := state.settings.watch_mtime_nsec

		testing.expect(t, settings_test_write(path, "NOT_A_VALID_BINDING\n"))
		state.settings.watch_mtime_nsec = 0
		state.settings.watch_cooldown = 0
		settings_poll()
		testing.expect_value(t, state.settings.window_title, "Good")
		expect_close(t, state.settings.dpi_scale, 2)
		testing.expect(t, state.settings.watch_mtime_nsec != 0)
		testing.expect(t, state.settings.watch_mtime_nsec != prev_mtime || prev_mtime == 0)
	})
}

@(test)
settings_apply_window_updates_sdl_window :: proc(t: ^testing.T) {
	with_engine_sdl_window_env(t, proc(t: ^testing.T) {
		settings_ensure()
		if state.settings.window_title != "" {
			delete(state.settings.window_title)
		}

		state.settings.window_title = strings.clone("Settings Window")
		state.settings.window_width = 400
		state.settings.window_height = 300
		state.settings.min_width = 120
		state.settings.min_height = 90
		settings_apply_window()

		title := sdl.GetWindowTitle(state.window)
		testing.expect_value(t, string(title), "Settings Window")
		min_w, min_h: i32
		testing.expect(t, sdl.GetWindowMinimumSize(state.window, &min_w, &min_h))
		testing.expect_value(t, min_w, i32(120))
		testing.expect_value(t, min_h, i32(90))
		// Size is a compositor request and may be ignored (e.g. Wayland).
		testing.expect_value(t, state.settings.window_width, i32(400))
		testing.expect_value(t, state.settings.window_height, i32(300))
	})
}

@(test)
settings_dpi_override_applied_by_dpi_sync :: proc(t: ^testing.T) {
	with_engine_sdl_window_env(t, proc(t: ^testing.T) {
		settings_ensure()
		state.settings.dpi_scale = 2
		dpi_sync()
		expect_close(t, state.dpi.scale, 2)
		testing.expect(t, state.dpi.logical_w > 0)
		testing.expect(t, state.dpi.logical_h > 0)

		state.settings.dpi_scale = 0
		dpi_sync()
		testing.expect(t, state.dpi.scale > 0)
	})
}

@(test)
settings_parse_path_with_comma_and_register_fonts :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		if !os.exists(PIXEL_FONT_FIXTURE) || !os.exists(INTER_FONT_FIXTURE) {
			testing.expectf(t, false, "missing font fixtures")
			return
		}

		// Do not use fmt.tprintf with KDL braces — `{` is format syntax.
		comma_doc := strings.concatenate(
			{
				"fonts {\n\tfamily CommaFont {\n\t\tface {\n\t\t\tpath \"",
				INTER_FONT_FIXTURE,
				"\"\n\t\t\tstyle italic\n\t\t\tweight bold\n\t\t}\n\t}\n}\n",
			},
			context.temp_allocator,
		)
		comma_parsed, comma_err := settings_parse_document(comma_doc)
		defer settings_destroy_value(comma_parsed)
		testing.expectf(t, comma_err.ok, "comma path parse failed")
		testing.expect_value(t, comma_parsed.font_family, "CommaFont")
		testing.expect_value(t, len(comma_parsed.font_faces), 1)
		testing.expect_value(t, comma_parsed.font_faces[0].path, INTER_FONT_FIXTURE)

		normal_doc := `
fonts {
	body-size 16
	heading-size 22
	family SettingsFont {
		face {
			path "pixel.ttf"
			style normal
			weight normal
		}
	}
}
`
		normal_parsed, normal_err := settings_parse_document(normal_doc)
		defer settings_destroy_value(normal_parsed)
		testing.expectf(t, normal_err.ok, "normal style/weight parse failed")
		testing.expect_value(t, normal_parsed.font_family, "SettingsFont")
		testing.expect_value(t, len(normal_parsed.font_faces), 1)
		style, style_ok := normal_parsed.font_faces[0].style.(Font_Styles)
		testing.expect(t, style_ok && style == .NORMAL)
		weight, weight_ok := normal_parsed.font_faces[0].weight.(Font_Weights)
		testing.expect(t, weight_ok && weight == .Normal)
		expect_close(t, normal_parsed.font_heading_size, 22)

		settings_assign(settings_defaults())

		if state.settings.font_family != "" {
			delete(state.settings.font_family)
		}

		state.settings.font_family = strings.clone("SettingsFont")
		settings_kdl_clear_faces(&state.settings)
		append(
			&state.settings.font_faces,
			Font_Face_Desc {
				path = strings.clone(PIXEL_FONT_FIXTURE),
				style = .NORMAL,
				weight = .Normal,
			},
		)
		state.settings.font_body_size = 16
		state.settings.font_heading_size = 22

		handle, ok := settings_register_fonts()
		testing.expect(t, ok)
		// First registered family uses id 0.
		_ = handle
	})
}

@(test)
settings_defaults_register_engine_font_files :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		testing.expect(t, os.exists(SETTINGS_DEFAULT_FONT_REGULAR_PATH))
		testing.expect(t, os.exists(SETTINGS_DEFAULT_FONT_ITALIC_PATH))
		settings_ensure()
		handle, ok := settings_register_fonts()
		testing.expect(t, ok)
		testing.expect_value(t, handle.id, Asset_Id(0))
	})
}
