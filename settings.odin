package oni

import "core:os"
import "core:strings"
import "core:time"
import sdl "vendor:sdl3"

SETTINGS_DEFAULT_PATH :: "settings.kdl"

SETTINGS_DEFAULT_WINDOW_TITLE :: "Oni GUI"
SETTINGS_DEFAULT_WINDOW_WIDTH :: i32(1280)
SETTINGS_DEFAULT_WINDOW_HEIGHT :: i32(720)
SETTINGS_DEFAULT_MIN_WIDTH :: i32(320)
SETTINGS_DEFAULT_MIN_HEIGHT :: i32(180)
SETTINGS_DEFAULT_WINDOW_MODE :: Window_Mode.Window
SETTINGS_DEFAULT_FONT_FAMILY :: "Inter"
SETTINGS_DEFAULT_FONT_BODY_SIZE :: f32(16)
SETTINGS_DEFAULT_FONT_HEADING_SIZE :: f32(20)
SETTINGS_DEFAULT_FONTS_DIR :: #directory + "assets/fonts/"
SETTINGS_DEFAULT_FONT_REGULAR_PATH :: SETTINGS_DEFAULT_FONTS_DIR + "Inter-VariableFont_opsz,wght.ttf"
SETTINGS_DEFAULT_FONT_ITALIC_PATH :: SETTINGS_DEFAULT_FONTS_DIR + "Inter-Italic-VariableFont_opsz,wght.ttf"

// Frames to wait after a settings.kdl write before applying (editors often write twice).
SETTINGS_WATCH_COOLDOWN_FRAMES :: 10

Settings_Apply_Hook :: proc()

@(private)
settings_apply_hook: Settings_Apply_Hook

/*
Loaded application settings: window, DPI, fonts, and user shortcut rows.

Heap strings and face/shortcut arrays are owned by this struct. `dpi_scale`
of 0 means follow the OS (SDL drawable / logical size).
*/
Settings :: struct {
	ready:             bool,
	path:              string,
	window_title:      string,
	window_width:      i32,
	window_height:     i32,
	min_width:         i32,
	min_height:         i32,
	window_mode:       Window_Mode,
	dpi_scale:         f32,
	font_family:       string,
	font_body_size:    f32,
	font_heading_size: f32,
	font_faces:        [dynamic]Font_Face_Desc,
	shortcut_rows:     [dynamic]Shortcut_Parsed_Binding,
	// Disk watch: unix-nsec mtime of `path`; cooldown absorbs multi-write editors.
	watch_mtime_nsec:  i64,
	watch_cooldown:    int,
}

/*
Returns engine-owned settings, filling defaults when nothing has been loaded.
*/
settings_get :: proc() -> ^Settings {
	if state == nil do return nil
	settings_ensure()
	return &state.settings
}

/*
Fills `state.settings` with compiled defaults when it has not been loaded.
*/
settings_ensure :: proc() {
	if state == nil do return
	if state.settings.ready do return
	settings_assign(settings_defaults())
}

/*
Replaces engine settings with `src` and marks them ready.

Destroys any previously owned settings storage.
*/
settings_assign :: proc(src: Settings) {
	if state == nil {
		settings_destroy_value(src)
		return
	}

	settings_destroy(&state.settings)
	state.settings = src
	state.settings.ready = true
}

/*
Heap-owned default settings. Face paths are engine-owned (`oni/assets/fonts`).
*/
settings_defaults :: proc(allocator := context.allocator) -> Settings {
	s: Settings
	s.ready = true
	s.path = strings.clone(SETTINGS_DEFAULT_PATH, allocator)
	s.window_title = strings.clone(SETTINGS_DEFAULT_WINDOW_TITLE, allocator)
	s.window_width = SETTINGS_DEFAULT_WINDOW_WIDTH
	s.window_height = SETTINGS_DEFAULT_WINDOW_HEIGHT
	s.min_width = SETTINGS_DEFAULT_MIN_WIDTH
	s.min_height = SETTINGS_DEFAULT_MIN_HEIGHT
	s.window_mode = SETTINGS_DEFAULT_WINDOW_MODE
	s.dpi_scale = 0
	s.font_family = strings.clone(SETTINGS_DEFAULT_FONT_FAMILY, allocator)
	s.font_body_size = SETTINGS_DEFAULT_FONT_BODY_SIZE
	s.font_heading_size = SETTINGS_DEFAULT_FONT_HEADING_SIZE
	s.font_faces = make([dynamic]Font_Face_Desc, allocator)
	settings_append_default_faces(&s, allocator)
	s.shortcut_rows = make([dynamic]Shortcut_Parsed_Binding, allocator)
	return s
}

/*
Appends engine Inter faces from `oni/assets/fonts`.
*/
settings_append_default_faces :: proc(s: ^Settings, allocator := context.allocator) {
	append(
		&s.font_faces,
		Font_Face_Desc {
			path = strings.clone(SETTINGS_DEFAULT_FONT_REGULAR_PATH, allocator),
			style = .NORMAL,
			weight = .Normal,
		},
	)
	append(
		&s.font_faces,
		Font_Face_Desc {
			path = strings.clone(SETTINGS_DEFAULT_FONT_ITALIC_PATH, allocator),
			style = .ITALIC,
			weight = .Normal,
		},
	)
}

/*
Restores engine Inter faces when the document listed a family with no faces.
*/
settings_ensure_default_faces :: proc(s: ^Settings, allocator := context.allocator) {
	if s == nil {
		return
	}

	if len(s.font_faces) > 0 {
		return
	}

	if s.font_faces == nil {
		s.font_faces = make([dynamic]Font_Face_Desc, allocator)
	}

	settings_append_default_faces(s, allocator)
}

/*
Frees heap fields on `s` and zeroes it.
*/
settings_destroy :: proc(s: ^Settings) {
	if s == nil do return
	settings_destroy_value(s^)
	s^ = {}
}

settings_destroy_value :: proc(s: Settings) {
	if s.path != "" do delete(s.path)
	if s.window_title != "" do delete(s.window_title)
	if s.font_family != "" do delete(s.font_family)
	for face in s.font_faces {
		if face.path != "" do delete(face.path)
	}
	if s.font_faces != nil do delete(s.font_faces)
	for row in s.shortcut_rows {
		if row.id != "" do delete(row.id)
		if row.scope_key != "" do delete(row.scope_key)
	}
	if s.shortcut_rows != nil do delete(s.shortcut_rows)
}

/*
Frees settings owned by engine state. Safe when state is nil.
*/
settings_shutdown :: proc() {
	if state == nil do return
	settings_destroy(&state.settings)
	settings_apply_hook = nil
}

/*
SDL window config from the loaded settings.
*/
settings_window_config :: proc() -> Window_Config {
	if state == nil do return {}
	settings_ensure()
	title := state.settings.window_title
	if title == "" do title = SETTINGS_DEFAULT_WINDOW_TITLE
	return {
		title      = strings.clone_to_cstring(title, context.temp_allocator),
		width      = state.settings.window_width,
		height     = state.settings.window_height,
		min_width  = state.settings.min_width,
		min_height = state.settings.min_height,
		mode       = state.settings.window_mode,
	}
}

/*
Reads `path` into engine settings. A missing file installs defaults and returns true.

Parse errors leave previous settings in place and return false.
*/
settings_load :: proc(path: string) -> bool {
	err := settings_load_ex(path)
	return err.ok
}

settings_load_ex :: proc(path: string) -> Shortcut_Import_Error {
	if state == nil || path == "" do return {ok = false, line = 0}

	resolved := path
	data, read_err := os.read_entire_file(resolved, context.temp_allocator)
	if read_err != nil {
		s := settings_defaults()
		if s.path != "" do delete(s.path)
		s.path = strings.clone(resolved)
		settings_assign(s)
		settings_watch_sync_mtime()
		return {ok = true, line = 0}
	}

	parsed, err := settings_parse_document(string(data))
	if !err.ok {
		settings_destroy_value(parsed)
		return err
	}

	if parsed.path != "" do delete(parsed.path)
	parsed.path = strings.clone(resolved)
	settings_assign(parsed)
	settings_watch_sync_mtime()
	return {ok = true, line = 0}
}

/*
Writes window, DPI, fonts, and current user shortcuts to `path` as KDL.

Refreshes the watch mtime so the subsequent poll does not re-apply this write.
*/
settings_save :: proc(path: string) -> bool {
	if state == nil || path == "" do return false
	settings_ensure()
	data := settings_export(context.temp_allocator)
	if os.write_entire_file(path, transmute([]byte)data) != nil do return false
	if state.settings.path != path {
		if state.settings.path != "" do delete(state.settings.path)
		state.settings.path = strings.clone(path)
	}
	settings_watch_sync_mtime()
	return true
}

/*
Installs parsed user shortcut rows into the bindings table.

Call after builtin defaults are installed. When `replace_user` is true, existing
user bindings are cleared first.
*/
settings_apply_shortcuts :: proc(replace_user := true) -> bool {
	if state == nil do return false
	settings_ensure()
	shortcut_init()

	if replace_user {
		shortcut_clear_user_bindings()
	}

	for row in state.settings.shortcut_rows {
		shortcut_remove_trigger_matches(row)
		if !shortcut_apply_parsed(row) do return false
	}

	return true
}

/*
Registers the app hook invoked after a live settings reload (theme rebuild).

Re-register after hot reload; the hook pointer is package-level, not in Persistent.
*/
settings_set_apply_hook :: proc(hook: Settings_Apply_Hook) {
	settings_apply_hook = hook
}

/*
Applies loaded settings to the live window, DPI, fonts, shortcuts, then the hook.

Safe when the window or GPU is not ready yet (skips those steps).
*/
settings_apply_runtime :: proc() -> bool {
	if state == nil do return false
	settings_ensure()
	settings_apply_window()
	dpi_sync()
	_ = settings_apply_shortcuts(true)
	if settings_apply_hook != nil {
		settings_apply_hook()
	} else if state.fonts.library != nil {
		// Only refresh faces when the font stack is already live; do not
		// lazily FT_Init from settings apply (tests / early boot).
		_, _ = settings_register_fonts()
	}
	return true
}

/*
Polls settings.kdl for changes and applies them (dev and production).

Call once per frame. Debounces multi-write editors via SETTINGS_WATCH_COOLDOWN_FRAMES.
*/
settings_poll :: proc() {
	if state == nil || !state.settings.ready do return

	path := state.settings.path
	if path == "" do return

	if state.settings.watch_cooldown > 0 {
		state.settings.watch_cooldown -= 1
		return
	}

	mtime, ok := settings_file_mtime_nsec(path)
	if !ok do return
	if mtime == state.settings.watch_mtime_nsec do return

	if !settings_load(path) {
		state.settings.watch_mtime_nsec = mtime
		log_errorf("settings_poll: failed to reload %s", path)
		return
	}

	state.settings.watch_cooldown = SETTINGS_WATCH_COOLDOWN_FRAMES
	_ = settings_apply_runtime()
}

/*
Reloads settings from disk and applies them immediately (no cooldown).
*/
settings_reload :: proc(path := "") -> bool {
	if state == nil do return false
	resolved := path
	if resolved == "" {
		settings_ensure()
		resolved = state.settings.path
	}
	if resolved == "" {
		resolved = SETTINGS_DEFAULT_PATH
	}
	if !settings_load(resolved) do return false
	return settings_apply_runtime()
}

@(private)
settings_file_mtime_nsec :: proc(path: string) -> (i64, bool) {
	mod_time, err := os.last_write_time_by_name(path)
	if err != os.ERROR_NONE do return 0, false
	return time.time_to_unix_nano(mod_time), true
}

@(private)
settings_watch_sync_mtime :: proc() {
	if state == nil do return
	path := state.settings.path
	if path == "" do return
	mtime, ok := settings_file_mtime_nsec(path)
	if ok {
		state.settings.watch_mtime_nsec = mtime
	}
}

/*
Pushes window title, size, and minimum size from settings to the SDL window.
*/
settings_apply_window :: proc() {
	if state == nil || state.window == nil do return
	settings_ensure()
	s := state.settings
	title := s.window_title
	if title == "" do title = SETTINGS_DEFAULT_WINDOW_TITLE
	_ = sdl.SetWindowTitle(state.window, strings.clone_to_cstring(title, context.temp_allocator))
	if s.window_width > 0 &&
	   s.window_height > 0 &&
	   (s.window_mode == .Window || s.window_mode == .Borderless) {
		_ = sdl.SetWindowSize(state.window, s.window_width, s.window_height)
	}
	_ = sdl.SetWindowMinimumSize(state.window, s.min_width, s.min_height)
	_ = set_window_mode(s.window_mode)
}

/*
Destroys registered font families and re-registers from settings.

Returns the new family handle. Call before rebuilding Theme font fields.
*/
settings_register_fonts :: proc() -> (Font_Handle, bool) {
	if state == nil do return {}, false
	settings_ensure()
	if !font_init() do return {}, false

	font_atlas_reset()
	font_destroy_faces()
	font_destroy_families()

	s := state.settings
	if len(s.font_faces) == 0 do return {}, false
	return font_register_family(s.font_family, s.font_faces[:])
}
