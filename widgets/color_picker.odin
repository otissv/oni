package oni_widgets

import o ".."
import set "../set"
import "core:fmt"
import "core:strconv"
import "core:strings"

COLOR_PICKER_TYPE_SLOT_COUNT :: 7
COLOR_PICKER_TYPE_MAX_FIELDS :: 4
COLOR_PICKER_INPUT_ROW_H :: f32(32)
COLOR_PICKER_HEX_ROW_H :: f32(28)
COLOR_PICKER_TYPE_LABEL_W :: f32(14)
COLOR_PICKER_TYPE_INPUT_W :: f32(52)
COLOR_PICKER_TYPE_FIELD_GAP :: f32(6)
COLOR_PICKER_CHANNEL_ROW_H :: f32(22)
COLOR_PICKER_CHANNEL_LABEL_W :: f32(20)
COLOR_PICKER_SWATCH_W :: f32(56)

/*
Author-time style overrides for color picker chrome.
*/
Color_Picker_Style :: struct {
	field_size:    o.Cfg(o.Style_F32),
	slider_width:  o.Cfg(o.Style_F32),
	alpha_height:  o.Cfg(o.Style_F32),
	swatch_height: o.Cfg(o.Style_F32),
	radius:        o.Cfg(o.Radius),
	marker:        o.Cfg(o.Colors),
	border:        o.Cfg(o.Colors),
}

Color_Picker_Config :: o.Widget_Config

Color_Picker_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	value:             o.RGBA,
	previous:          o.RGBA,
	hsva:              o.HSVA,
	channel:           o.Color_Picker_Channel,
	web_only:          bool,
}

Color_Picker_Event :: o.Widget_Event(Color_Picker_State)

/*
Color picker root props (Radix-style).

`value`, `channel`, `previous`, and `web_only` are caller-owned and must be
passed every frame. Parts such as `Color_Picker_Field` must be descendants of
this root. Interaction reports updates through `on_value_change` /
`on_channel_change` / `on_web_only_change` only.
*/
Color_Picker_Props :: struct {
	config:                       Color_Picker_Config,
	value:                        o.RGBA,
	channel:                      o.Color_Picker_Channel,
	previous:                     o.RGBA,
	web_only:                     bool,
	disabled:                     bool,
	style:                        Color_Picker_Style,
	child:                        proc(frame_state: Color_Picker_State),
	on_value_change:              proc(value: o.RGBA),
	on_value_commit:              proc(value: o.RGBA),
	on_channel_change:            proc(channel: o.Color_Picker_Channel),
	on_web_only_change:           proc(web_only: bool),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Color_Picker_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Color_Picker_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	scroll_bar:                   Scroll_Bar_Style,
	on_focus:                     proc(event: Color_Picker_Event),
	on_blur:                      proc(event: Color_Picker_Event),
	on_mouse_enter:               proc(event: Color_Picker_Event),
	on_mouse_leave:               proc(event: Color_Picker_Event),
	on_mouse_pressed:             proc(event: Color_Picker_Event),
	on_mouse_down:                proc(event: Color_Picker_Event),
	on_mouse_released:            proc(event: Color_Picker_Event),
	on_mouse_move:                proc(event: Color_Picker_Event),
	on_click:                     proc(event: Color_Picker_Event),
	on_contextmenu:               proc(event: Color_Picker_Event),
	on_key_pressed:               proc(event: Color_Picker_Event),
	on_key_down:                  proc(event: Color_Picker_Event),
	on_key_released:              proc(event: Color_Picker_Event),
}

@(private)
Color_Picker_Type_Drafts :: struct {
	text:    [COLOR_PICKER_TYPE_MAX_FIELDS]string,
	editing: [COLOR_PICKER_TYPE_MAX_FIELDS]bool,
}

@(private)
Color_Picker_Runtime :: struct {
	hsva:         o.HSVA,
	focus_region: o.Color_Picker_Drag_Region,
	hex:          string,
	hex_editing:  bool,
	type_drafts:  [COLOR_PICKER_TYPE_SLOT_COUNT]Color_Picker_Type_Drafts,
	type_active:  [COLOR_PICKER_TYPE_SLOT_COUNT]bool,
	initialized:  bool,
}

@(private)
Color_Picker_Ctx :: struct {
	active:            bool,
	key:               string,
	root_layout_id:    o.UI_Id,
	runtime:           ^Color_Picker_Runtime,
	value:             o.RGBA,
	previous:          o.RGBA,
	hsva:              o.HSVA,
	channel:           o.Color_Picker_Channel,
	web_only:          bool,
	has_web_type:      bool,
	hex_include_alpha: bool,
	disabled:          bool,
	style:             Color_Picker_Style,
	on_value_change:    proc(value: o.RGBA),
	on_value_commit:    proc(value: o.RGBA),
	on_channel_change:  proc(channel: o.Color_Picker_Channel),
	on_web_only_change: proc(web_only: bool),
	on_key_down:        proc(event: Color_Picker_Event),
	on_key_pressed:     proc(event: Color_Picker_Event),
	on_key_released:    proc(event: Color_Picker_Event),
}

@(private)
COLOR_PICKER_CTX_MAX :: 8

@(private)
color_picker_ctx_stack: [COLOR_PICKER_CTX_MAX]Color_Picker_Ctx

@(private)
color_picker_ctx_depth: int

@(private)
color_picker_ctx_dummy: Color_Picker_Ctx

@(private)
color_picker_stack_warned: bool

@(private)
color_picker_runtimes: map[string]Color_Picker_Runtime

@(private)
color_picker_ctx_top :: proc() -> ^Color_Picker_Ctx {
	if color_picker_ctx_depth <= 0 {
		return &color_picker_ctx_dummy
	}

	return &color_picker_ctx_stack[color_picker_ctx_depth - 1]
}

@(private)
color_picker_ctx_ok :: proc() -> bool {
	ctx := color_picker_ctx_top()

	return color_picker_ctx_depth > 0 && ctx.active
}

@(private)
color_picker_ctx_push :: proc(ctx: Color_Picker_Ctx) -> bool {
	if color_picker_ctx_depth >= COLOR_PICKER_CTX_MAX {
		if !color_picker_stack_warned {
			color_picker_stack_warned = true
			o.Log_Warn("color picker context stack overflow")
		}

		return false
	}

	color_picker_ctx_stack[color_picker_ctx_depth] = ctx
	color_picker_ctx_depth += 1

	return true
}

@(private)
color_picker_ctx_pop :: proc() {
	if color_picker_ctx_depth <= 0 {
		return
	}

	color_picker_ctx_depth -= 1
	color_picker_ctx_stack[color_picker_ctx_depth] = {}
}

@(private)
color_picker_type_field_count :: proc(color_type: o.Color_Picker_Color_Type) -> int {
	switch color_type {
	case .RGB, .HSB, .HSL, .LAB, .WEB:
		return 3
	case .CMYK:
		return 4
	}

	return 3
}

@(private)
color_picker_type_row_width :: proc(color_type: o.Color_Picker_Color_Type) -> f32 {
	n := color_picker_type_field_count(color_type)
	unit := COLOR_PICKER_TYPE_LABEL_W + COLOR_PICKER_TYPE_INPUT_W + COLOR_PICKER_TYPE_FIELD_GAP

	return f32(n) * unit
}

/*
Releases heap-owned color picker runtime maps.

Called from widget `Shutdown`.
*/
color_picker_shutdown :: proc() {
	color_picker_ctx_depth = 0
	color_picker_ctx_stack = {}
	color_picker_ctx_dummy = {}
	color_picker_stack_warned = false
	color_picker_swatch_role = .CURRENT
	color_picker_hex_row_text = ""
	color_picker_type_row_props = {}
	color_picker_web_only_props = {}
	color_picker_layout = {}

	if color_picker_runtimes == nil {
		return
	}

	for key, &rt in color_picker_runtimes {
		color_picker_runtime_free(&rt)
		delete(key)
	}

	delete(color_picker_runtimes)
	color_picker_runtimes = nil
}

@(private)
color_picker_runtime_free_type_drafts :: proc(drafts: ^Color_Picker_Type_Drafts) {
	if drafts == nil {
		return
	}

	for i in 0 ..< COLOR_PICKER_TYPE_MAX_FIELDS {
		if drafts.text[i] != "" {
			delete(drafts.text[i])
			drafts.text[i] = ""
		}
	}
}

@(private)
color_picker_runtime_free :: proc(rt: ^Color_Picker_Runtime) {
	if rt == nil {
		return
	}

	if rt.hex != "" {
		delete(rt.hex)
		rt.hex = ""
	}

	for i in 0 ..< COLOR_PICKER_TYPE_SLOT_COUNT {
		color_picker_runtime_free_type_drafts(&rt.type_drafts[i])
	}

}

@(private)
color_picker_runtime_ensure :: proc(key: string) -> ^Color_Picker_Runtime {
	if key == "" {
		return nil
	}

	if color_picker_runtimes == nil {
		color_picker_runtimes = make(map[string]Color_Picker_Runtime)
	}

	if _, ok := color_picker_runtimes[key]; !ok {
		color_picker_runtimes[strings.clone(key)] = {}
	}

	return &color_picker_runtimes[key]
}

@(private)
color_picker_runtime_clear :: proc(key: string) {
	if color_picker_runtimes == nil || key == "" {
		return
	}

	if rt, ok := &color_picker_runtimes[key]; ok {
		color_picker_runtime_free(rt)
	}

	if _, ok := color_picker_runtimes[key]; !ok {
		return
	}

	for k in color_picker_runtimes {
		if k == key {
			delete_key(&color_picker_runtimes, k)
			delete(k)
			break
		}
	}
}

@(private)
color_picker_replace_string :: proc(dst: ^string, value: string) {
	if dst == nil {
		return
	}

	if dst^ == value {
		return
	}

	replacement := value != "" ? strings.clone(value) : ""

	if dst^ != "" {
		delete(dst^)
	}

	dst^ = replacement
}

/*
Takes ownership of a heap `value` (for example `Text_Input` `on_change` text).
*/
@(private)
color_picker_adopt_string :: proc(dst: ^string, value: string) {
	if dst == nil {
		delete(value)
		return
	}

	if dst^ != "" {
		delete(dst^)
	}

	dst^ = value
}

@(private)
color_picker_style_f32 :: proc(cfg: o.Cfg(o.Style_F32), fallback: f32) -> f32 {
	return o.cfg_style_f32(cfg, fallback)
}

@(private)
color_picker_channel_label :: proc(channel: o.Color_Picker_Channel) -> string {
	switch channel {
	case .H:
		return "H"
	case .S:
		return "S"
	case .V:
		return "V"
	case .R:
		return "R"
	case .G:
		return "G"
	case .B:
		return "B"
	}

	return "?"
}

@(private)
color_picker_comp_channel :: proc(index: int) -> o.Color_Picker_Channel {
	switch index {
	case 0:
		return .H
	case 1:
		return .S
	case 2:
		return .V
	case 3:
		return .R
	case 4:
		return .G
	case 5:
		return .B
	}

	return .H
}

@(private)
color_picker_type_field_label :: proc(
	color_type: o.Color_Picker_Color_Type,
	index: int,
) -> string {
	switch color_type {
	case .RGB, .WEB:
		switch index {
		case 0:
			return "R"
		case 1:
			return "G"
		case 2:
			return "B"
		}
	case .HSB:
		switch index {
		case 0:
			return "H"
		case 1:
			return "S"
		case 2:
			return "V"
		}
	case .HSL:
		switch index {
		case 0:
			return "H"
		case 1:
			return "S"
		case 2:
			return "L"
		}
	case .LAB:
		switch index {
		case 0:
			return "L"
		case 1:
			return "A"
		case 2:
			return "B"
		}
	case .CMYK:
		switch index {
		case 0:
			return "C"
		case 1:
			return "M"
		case 2:
			return "Y"
		case 3:
			return "K"
		}
	}

	return "?"
}

@(private)
color_picker_format_type_field :: proc(
	hsva: o.HSVA,
	rgba: o.RGBA,
	color_type: o.Color_Picker_Color_Type,
	index: int,
) -> string {
	switch color_type {
	case .RGB, .WEB:
		switch index {
		case 0:
			return fmt.tprintf("%d", int(rgba.r))
		case 1:
			return fmt.tprintf("%d", int(rgba.g))
		case 2:
			return fmt.tprintf("%d", int(rgba.b))
		}
	case .HSB:
		switch index {
		case 0:
			return fmt.tprintf("%.0f", o.color_hue_wrap(hsva.h))
		case 1:
			return fmt.tprintf("%.0f", o.color_clamp01(hsva.s) * 100)
		case 2:
			return fmt.tprintf("%.0f", o.color_clamp01(hsva.v) * 100)
		}
	case .HSL:
		hsla := o.rgba_to_hsla(rgba)

		switch index {
		case 0:
			return fmt.tprintf("%.0f", o.color_hue_wrap(hsla.h))
		case 1:
			return fmt.tprintf("%.0f", o.color_clamp01(hsla.s) * 100)
		case 2:
			return fmt.tprintf("%.0f", o.color_clamp01(hsla.l) * 100)
		}
	case .LAB:
		laba := o.rgba_to_laba(rgba)

		switch index {
		case 0:
			return fmt.tprintf("%.1f", laba.l)
		case 1:
			return fmt.tprintf("%.1f", laba.a)
		case 2:
			return fmt.tprintf("%.1f", laba.b)
		}
	case .CMYK:
		cmyk := o.rgba_to_cmyka(rgba)

		switch index {
		case 0:
			return fmt.tprintf("%.0f", o.color_clamp01(cmyk.c) * 100)
		case 1:
			return fmt.tprintf("%.0f", o.color_clamp01(cmyk.m) * 100)
		case 2:
			return fmt.tprintf("%.0f", o.color_clamp01(cmyk.y) * 100)
		case 3:
			return fmt.tprintf("%.0f", o.color_clamp01(cmyk.k) * 100)
		}
	}

	return ""
}

@(private)
color_picker_parse_type_field :: proc(
	text: string,
	color_type: o.Color_Picker_Color_Type,
	index: int,
) -> (
	f32,
	bool,
) {
	n, ok := color_picker_parse_f32(text)

	if !ok {
		return 0, false
	}

	switch color_type {
	case .RGB, .WEB:
		if n < 0 {
			return 0, true
		}

		if n > 255 {
			return 255, true
		}

		return n, true
	case .HSB:
		switch index {
		case 0:
			return o.color_hue_wrap(n), true
		case 1, 2:
			return o.color_clamp01(n / 100), true
		}
	case .HSL:
		switch index {
		case 0:
			return o.color_hue_wrap(n), true
		case 1, 2:
			return o.color_clamp01(n / 100), true
		}
	case .LAB:
		return n, true
	case .CMYK:
		return o.color_clamp01(n / 100), true
	}

	return 0, false
}

@(private)
color_picker_parse_f32 :: proc(text: string) -> (f32, bool) {
	s := text

	if len(s) == 0 {
		return 0, false
	}

	i := 0
	sign: f32 = 1

	if s[0] == '+' {
		i = 1
	} else if s[0] == '-' {
		sign = -1
		i = 1
	}

	if i >= len(s) {
		return 0, false
	}

	value: f32 = 0
	seen_digit := false
	seen_dot := false
	frac: f32 = 1

	for i < len(s) {
		c := s[i]

		if c == '.' {
			if seen_dot {
				return 0, false
			}

			seen_dot = true
			i += 1
			continue
		}

		if c < '0' || c > '9' {
			return 0, false
		}

		seen_digit = true
		digit := f32(c - '0')

		if seen_dot {
			frac *= 0.1
			value += digit * frac
		} else {
			value = value * 10 + digit
		}

		i += 1
	}

	if !seen_digit {
		return 0, false
	}

	return sign * value, true
}

@(private)
color_picker_apply_type_field :: proc(
	hsva: o.HSVA,
	rgba: o.RGBA,
	color_type: o.Color_Picker_Color_Type,
	index: int,
	raw: f32,
) -> (
	o.HSVA,
	o.RGBA,
) {
	out_hsva := hsva
	out_rgba := rgba

	switch color_type {
	case .RGB, .WEB:
		v := o.color_u8_from01(o.color_clamp01(raw / 255))

		switch index {
		case 0:
			out_rgba.r = v
		case 1:
			out_rgba.g = v
		case 2:
			out_rgba.b = v
		}

		out_hsva = o.color_picker_hsva_from_rgba(out_rgba, hsva)
	case .HSB:
		out_hsva = hsva

		switch index {
		case 0:
			out_hsva.h = raw
		case 1:
			out_hsva.s = raw
		case 2:
			out_hsva.v = raw
		}

		out_rgba = o.hsva_to_rgba(out_hsva)
		out_rgba.a = rgba.a
	case .HSL:
		hsla := o.rgba_to_hsla(rgba)

		switch index {
		case 0:
			hsla.h = raw
		case 1:
			hsla.s = raw
		case 2:
			hsla.l = raw
		}

		hsla.a = o.color_clamp01(f32(rgba.a) / 255)
		out_rgba = o.hsla_to_rgba(hsla)
		out_hsva = o.color_picker_hsva_from_rgba(out_rgba, hsva)
	case .LAB:
		laba := o.rgba_to_laba(rgba)

		switch index {
		case 0:
			laba.l = raw
		case 1:
			laba.a = raw
		case 2:
			laba.b = raw
		}

		laba.alpha = o.color_clamp01(f32(rgba.a) / 255)
		out_rgba = o.laba_to_rgba(laba)
		out_hsva = o.color_picker_hsva_from_rgba(out_rgba, hsva)
	case .CMYK:
		cmyk := o.rgba_to_cmyka(rgba)

		switch index {
		case 0:
			cmyk.c = raw
		case 1:
			cmyk.m = raw
		case 2:
			cmyk.y = raw
		case 3:
			cmyk.k = raw
		}

		cmyk.a = o.color_clamp01(f32(rgba.a) / 255)
		out_rgba = o.cmyka_to_rgba(cmyk)
		out_hsva = o.color_picker_hsva_from_rgba(out_rgba, hsva)
	}

	return out_hsva, out_rgba
}

@(private)
color_picker_maybe_web_snap :: proc(rgba: o.RGBA, web_only: bool, has_web_type: bool) -> o.RGBA {
	if web_only && has_web_type {
		return o.rgba_to_web_safe(rgba)
	}

	return rgba
}

@(private)
color_picker_sync_type_drafts :: proc(rt: ^Color_Picker_Runtime, hsva: o.HSVA, rgba: o.RGBA) {
	if rt == nil {
		return
	}

	for slot in 0 ..< COLOR_PICKER_TYPE_SLOT_COUNT {
		if !rt.type_active[slot] {
			continue
		}

		t := o.Color_Picker_Color_Type(slot)
		count := color_picker_type_field_count(t)
		drafts := &rt.type_drafts[slot]

		for i in 0 ..< count {
			if drafts.editing[i] {
				continue
			}

			color_picker_replace_string(
				&drafts.text[i],
				color_picker_format_type_field(hsva, rgba, t, i),
			)
		}
	}
}

@(private)
color_picker_sync_runtime_texts :: proc(rt: ^Color_Picker_Runtime, hsva: o.HSVA, rgba: o.RGBA) {
	if rt == nil {
		return
	}

	if !rt.hex_editing {
		color_picker_replace_string(
			&rt.hex,
			o.hex_format(rgba, false, context.temp_allocator),
		)
	}

	color_picker_sync_type_drafts(rt, hsva, rgba)
}

@(private)
color_picker_init_runtime :: proc(rt: ^Color_Picker_Runtime, value: o.RGBA) {
	if rt == nil || rt.initialized {
		return
	}

	rt.hsva = o.rgba_to_hsva(value)
	rt.focus_region = .FIELD
	rt.initialized = true
	color_picker_sync_runtime_texts(rt, rt.hsva, value)
}

@(private)
color_picker_sync_runtime_hsva :: proc(rt: ^Color_Picker_Runtime, value: o.RGBA) {
	if rt == nil {
		return
	}

	if !rt.initialized {
		color_picker_init_runtime(rt, value)

		return
	}

	rt.hsva = o.color_picker_hsva_from_rgba(value, rt.hsva)
	color_picker_sync_runtime_texts(rt, rt.hsva, value)
}

@(private)
color_picker_emit :: proc(ctx: ^Color_Picker_Ctx, rgba: o.RGBA, commit: bool) {
	if ctx == nil || !ctx.active {
		return
	}

	out_rgba := color_picker_maybe_web_snap(rgba, ctx.web_only, ctx.has_web_type)
	ctx.hsva = o.color_picker_hsva_from_rgba(out_rgba, ctx.hsva)

	if ctx.runtime != nil {
		ctx.runtime.hsva = ctx.hsva
		color_picker_sync_runtime_texts(ctx.runtime, ctx.hsva, out_rgba)
	}

	ctx.value = out_rgba

	if ctx.on_value_change != nil {
		ctx.on_value_change(out_rgba)
	}

	if commit && ctx.on_value_commit != nil {
		ctx.on_value_commit(out_rgba)
	}
}

@(private)
color_picker_set_channel :: proc(ctx: ^Color_Picker_Ctx, channel: o.Color_Picker_Channel) {
	if ctx == nil || !ctx.active {
		return
	}

	if ctx.channel == channel {
		return
	}

	ctx.channel = channel

	if ctx.on_channel_change != nil {
		ctx.on_channel_change(channel)
	}
}

@(private)
color_picker_theme_base :: proc(frame_state: ^Color_Picker_State) -> Color_Picker_Config {
	opacity := f32(1)

	if frame_state.is_disabled {
		opacity = 0.5
	}

	border := o.Colors(o.Color.BORDER)

	if frame_state.is_focused {
		border = o.Color.RING
	}

	return Color_Picker_Config {
		kind = .COLOR_PICKER,
		tabbable = set.Tabbable(true),
		direction = set.Direction(o.Direction_Layout.VERTICAL),
		gap_y = set.Gap_Y(u16(8)),
		padding = set.Padding(o.Pd_struct{x = 8, y = 8}),
		border = set.Border(f32(1)),
		border_color = set.Border_color(border),
		radius = set.Radius(f32(8)),
		background = set.Background(o.Color.CARD),
		color = set.Colors(o.Color.FOREGROUND),
		opacity = set.F32(opacity),
		overflow_x = set.Overflow_X(.HIDDEN),
		overflow_y = set.Overflow_Y(.HIDDEN),
	}
}

@(private)
color_picker_refresh_merged :: proc(
	props: Color_Picker_Props,
	frame_state: ^Color_Picker_State,
) -> Color_Picker_Event {
	event := widget_event(frame_state^)
	base := color_picker_theme_base(frame_state)
	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
color_picker_point_in_rect :: proc(p: o.Vec2, r: o.Rect) -> bool {
	return p.x >= r.x && p.x < r.x + r.w && p.y >= r.y && p.y < r.y + r.h
}

@(private)
color_picker_bind_channel_chrome :: proc(layout_id: o.UI_Id) {
	node, ok := o.layout_node_by_id(layout_id)

	if !ok {
		node, ok = o.layout_current_node()
	}

	if !ok {
		return
	}

	o.layout_set_color_picker_channels(
		node,
		{
			row_h = COLOR_PICKER_CHANNEL_ROW_H,
			active = true,
		},
	)
}

@(private)
color_picker_channel_hits :: proc(layout_id: o.UI_Id) -> (
	hits: [o.LAYOUT_COLOR_PICKER_CHANNEL_COUNT]o.Rect,
	ok: bool,
) {
	chrome := o.layout_color_picker_channels_result(layout_id)

	if chrome == nil {
		return {}, false
	}

	return chrome.hits, true
}

@(private)
color_picker_apply_pointer :: proc(
	ctx: ^Color_Picker_Ctx,
	region: o.Color_Picker_Drag_Region,
	mouse: o.Vec2,
	rect: o.Rect,
) {
	if ctx == nil || !ctx.active {
		return
	}

	switch region {
	case .FIELD:
		x, y, ok := o.color_picker_norm_in_rect(mouse, rect)

		if !ok {
			return
		}

		ctx.hsva, ctx.value = o.color_picker_apply_field(ctx.hsva, ctx.value, ctx.channel, x, y)
		color_picker_emit(ctx, ctx.value, false)
	case .SLIDER:
		_, y, ok := o.color_picker_norm_in_rect(mouse, rect)

		if !ok {
			return
		}

		unit := o.color_picker_slider_t_from_y(y)
		ctx.hsva, ctx.value = o.color_picker_apply_channel_unit(
			ctx.hsva,
			ctx.value,
			ctx.channel,
			unit,
		)
		color_picker_emit(ctx, ctx.value, false)
	case .ALPHA:
		x, _, ok := o.color_picker_norm_in_rect(mouse, rect)

		if !ok {
			return
		}

		ctx.hsva, ctx.value = o.color_picker_apply_alpha(ctx.hsva, ctx.value, x)
		color_picker_emit(ctx, ctx.value, false)
	case .NONE:
	}
}

@(private)
color_picker_part_drag :: proc(
	layout_id: o.UI_Id,
	region: o.Color_Picker_Drag_Region,
	hit_rect: o.Rect,
	hovered: bool,
	interactive: bool,
	disabled: bool,
) {
	ctx := color_picker_ctx_top()

	if !ctx.active {
		return
	}

	drag := o.color_picker_drag_get(layout_id)

	if drag != nil && drag.active && disabled {
		color_picker_emit(ctx, ctx.value, true)
		o.color_picker_drag_end(layout_id)
		o.Stop_Propagation()

		return
	}

	if !interactive || disabled {
		return
	}

	mouse := o.Vec2{o.w_ctx.mouse_x, o.w_ctx.mouse_y}

	if o.w_ctx.left_mouse.pressed && color_picker_point_in_rect(mouse, hit_rect) {
		drag = o.color_picker_drag_entry(layout_id)

		if drag == nil {
			return
		}

		drag.active = true
		drag.region = region

		if ctx.runtime != nil {
			ctx.runtime.focus_region = region
		}

		color_picker_apply_pointer(ctx, region, mouse, hit_rect)
		o.Stop_Propagation()
	}

	if drag == nil {
		return
	}

	if drag.active && o.w_ctx.left_mouse.down {
		color_picker_apply_pointer(ctx, drag.region, mouse, hit_rect)
		o.Stop_Propagation()
	}

	ended :=
		drag.active &&
		(o.w_ctx.left_mouse.released || (!o.w_ctx.left_mouse.down && !o.w_ctx.left_mouse.pressed))

	if ended {
		color_picker_emit(ctx, ctx.value, true)
		o.color_picker_drag_end(layout_id)
		o.Stop_Propagation()
	}
}

@(private)
color_picker_on_key_down :: proc(event: Color_Picker_Event) {
	ctx := color_picker_ctx_top()

	if !ctx.active {
		return
	}

	region := o.Color_Picker_Drag_Region.FIELD

	if ctx.runtime != nil {
		region = ctx.runtime.focus_region
	}

	if region == .NONE {
		region = .FIELD
	}

	step: f32 = 1.0 / 255.0

	if event.key == .UP ||
	   event.key == .DOWN ||
	   event.key == .LEFT ||
	   event.key == .RIGHT ||
	   event.key == .HOME ||
	   event.key == .END {
		if (event.key == .LEFT || event.key == .RIGHT) && (ctx.channel == .H || region == .FIELD) {
			step = 1.0 / 100.0
		}

		if ctx.channel == .H && region == .SLIDER {
			step = 1.0 / 360.0
		}

		hsva, rgba, handled := o.color_picker_nudge(
			ctx.hsva,
			ctx.value,
			ctx.channel,
			region,
			event.key,
			step,
		)

		if handled {
			ctx.hsva = hsva
			color_picker_emit(ctx, rgba, false)
			o.Stop_Propagation()
		}
	}

	if ctx.on_key_down != nil {
		ctx.on_key_down(event)
	}
}

@(private)
color_picker_on_key_pressed :: proc(event: Color_Picker_Event) {
	ctx := color_picker_ctx_top()

	if ctx.active && ctx.on_key_pressed != nil {
		ctx.on_key_pressed(event)
	}
}

@(private)
color_picker_on_key_released :: proc(event: Color_Picker_Event) {
	ctx := color_picker_ctx_top()

	if ctx.active && ctx.on_key_released != nil {
		ctx.on_key_released(event)
	}
}

@(private)
color_picker_draw_field :: proc(
	layout_id: o.UI_Id,
	rect: o.Rect,
	hsva: o.HSVA,
	rgba: o.RGBA,
	channel: o.Color_Picker_Channel,
) {
	if o.ui_layout_paint_skip(layout_id) || rect.w <= 0 || rect.h <= 0 {
		return
	}

	o.Draw_Push_Clip(rect)
	samples := o.COLOR_PICKER_FIELD_SAMPLES

	for row in 0 ..< samples {
		y0 := rect.y + f32(row) * rect.h / f32(samples)
		y1 := rect.y + f32(row + 1) * rect.h / f32(samples)
		y_norm := (f32(row) + 0.5) / f32(samples)

		for col in 0 ..< samples {
			x0 := rect.x + f32(col) * rect.w / f32(samples)
			x1 := rect.x + f32(col + 1) * rect.w / f32(samples)
			x_norm := (f32(col) + 0.5) / f32(samples)
			color := o.color_picker_sample_field(hsva, rgba, channel, x_norm, y_norm)
			cell := o.Rect {
				x = x0,
				y = y0,
				w = max(f32(1), x1 - x0) + 1,
				h = max(f32(1), y1 - y0) + 1,
			}
			o.Draw_Rectangle(cell, color)
		}
	}

	o.Draw_Pop_Clip()

	mx, my := o.color_picker_field_marker(hsva, rgba, channel)
	size := o.COLOR_PICKER_THUMB_SIZE
	marker := o.Rect {
		x = rect.x + mx * rect.w - size * 0.5,
		y = rect.y + my * rect.h - size * 0.5,
		w = size,
		h = size,
	}
	round := o.Radius_px {
		tl = 9999,
		tr = 9999,
		br = 9999,
		bl = 9999,
	}
	o.Draw_Rectangle(marker, {}, round, {t = 2, b = 2, l = 2, r = 2}, {255, 255, 255, 255})
	o.Draw_Rectangle(
		{x = marker.x + 1, y = marker.y + 1, w = marker.w - 2, h = marker.h - 2},
		{},
		round,
		{t = 1, b = 1, l = 1, r = 1},
		{0, 0, 0, 220},
	)
}

@(private)
color_picker_draw_slider_triangle :: proc(tip_x, center_y: f32, point_right: bool) {
	tri_w := o.COLOR_PICKER_SLIDER_TRIANGLE_W
	half_h :: f32(6)
	fill := o.RGBA{0, 0, 0, 255}
	rows := int(half_h * 2) + 1

	for row in 0 ..< rows {
		dy := f32(row) - half_h
		span := 1 - abs(dy) / half_h

		if span <= 0 {
			continue
		}

		w := max(f32(1), tri_w * span)
		y := center_y + dy - 0.5
		x := point_right ? tip_x - tri_w : tip_x + (tri_w - w)
		o.Draw_Rectangle({x = x, y = y, w = w, h = 1.25}, fill)
	}
}

@(private)
color_picker_draw_slider :: proc(
	layout_id: o.UI_Id,
	rect: o.Rect,
	hsva: o.HSVA,
	rgba: o.RGBA,
	channel: o.Color_Picker_Channel,
) {
	if o.ui_layout_paint_skip(layout_id) || rect.w <= 0 || rect.h <= 0 {
		return
	}

	o.Draw_Push_Clip(rect)
	samples := o.COLOR_PICKER_SLIDER_SAMPLES

	for row in 0 ..< samples {
		y0 := rect.y + f32(row) * rect.h / f32(samples)
		y1 := rect.y + f32(row + 1) * rect.h / f32(samples)
		y_norm := (f32(row) + 0.5) / f32(samples)
		color := o.color_picker_sample_slider(hsva, rgba, channel, y_norm)
		cell := o.Rect {
			x = rect.x,
			y = y0,
			w = rect.w,
			h = max(f32(1), y1 - y0) + 1,
		}
		o.Draw_Rectangle(cell, color)
	}

	o.Draw_Pop_Clip()

	unit := o.color_picker_channel_unit(hsva, rgba, channel)
	y := rect.y + o.color_picker_y_from_slider_t(unit) * rect.h
	color_picker_draw_slider_triangle(rect.x - 1, y, true)
	color_picker_draw_slider_triangle(rect.x + rect.w + 1, y, false)
}

@(private)
color_picker_draw_alpha :: proc(layout_id: o.UI_Id, rect: o.Rect, rgba: o.RGBA) {
	if o.ui_layout_paint_skip(layout_id) || rect.w <= 0 || rect.h <= 0 {
		return
	}

	checker := o.COLOR_PICKER_CHECKER_SIZE
	cols := int(math_ceil(rect.w / checker))
	rows := int(math_ceil(rect.h / checker))

	for row in 0 ..< rows {
		for col in 0 ..< cols {
			cell := o.Rect {
				x = rect.x + f32(col) * checker,
				y = rect.y + f32(row) * checker,
				w = checker,
				h = checker,
			}
			o.Draw_Rectangle(cell, o.color_picker_checker_color(col, row))
		}
	}

	samples := 64
	cell_w := rect.w / f32(samples)
	opaque := rgba
	opaque.a = 255

	for col in 0 ..< samples {
		t := (f32(col) + 0.5) / f32(samples)
		color := opaque
		color.a = o.color_u8_from01(t)
		cell := o.Rect {
			x = rect.x + f32(col) * cell_w,
			y = rect.y,
			w = cell_w + 0.5,
			h = rect.h,
		}
		o.Draw_Rectangle(cell, color)
	}

	x := rect.x + (f32(rgba.a) / 255) * rect.w
	thumb := o.Rect {
		x = x - 2,
		y = rect.y - 2,
		w = 4,
		h = rect.h + 4,
	}
	o.Draw_Rectangle(thumb, {255, 255, 255, 255}, {}, {t = 1, b = 1, l = 1, r = 1}, {0, 0, 0, 220})
}

@(private)
math_ceil :: proc(v: f32) -> f32 {
	i := f32(int(v))

	if v > i {
		return i + 1
	}

	return i
}

@(private)
color_picker_draw_swatch :: proc(layout_id: o.UI_Id, rect: o.Rect, color: o.RGBA) {
	if o.ui_layout_paint_skip(layout_id) || rect.w <= 0 || rect.h <= 0 {
		return
	}

	o.Draw_Rectangle(rect, color, {}, {t = 1, b = 1, l = 1, r = 1}, {0, 0, 0, 80})
}

@(private)
color_picker_draw_channels :: proc(
	layout_id: o.UI_Id,
	channel: o.Color_Picker_Channel,
) {
	if o.ui_layout_paint_skip(layout_id) {
		return
	}

	hits, ok := color_picker_channel_hits(layout_id)

	if !ok {
		return
	}

	for i in 0 ..< o.LAYOUT_COLOR_PICKER_CHANNEL_COUNT {
		ch := color_picker_comp_channel(i)
		active := ch == channel

		if active {
			o.Draw_Rectangle(hits[i], {0, 0, 0, 40}, {tl = 4, tr = 4, br = 4, bl = 4})
		}
	}
}

@(private)
color_picker_hex_on_change :: proc(event: Text_Input_Event, text: string) {
	_ = event
	ctx := color_picker_ctx_top()

	if !ctx.active || ctx.runtime == nil {
		delete(text)
		return
	}

	ctx.runtime.hex_editing = true
	color_picker_adopt_string(&ctx.runtime.hex, text)

	if parsed, ok := o.hex_parse(ctx.runtime.hex); ok {
		if !ctx.hex_include_alpha {
			parsed.a = ctx.value.a
		}

		ctx.hsva = o.color_picker_hsva_from_rgba(parsed, ctx.hsva)
		color_picker_emit(ctx, parsed, false)
	}
}

@(private)
color_picker_hex_on_blur :: proc(event: Text_Input_Event) {
	_ = event
	ctx := color_picker_ctx_top()

	if !ctx.active || ctx.runtime == nil {
		return
	}

	ctx.runtime.hex_editing = false
	color_picker_sync_runtime_texts(ctx.runtime, ctx.hsva, ctx.value)
}

@(private)
color_picker_type_on_change :: proc(
	color_type: o.Color_Picker_Color_Type,
	index: int,
	text: string,
) {
	ctx := color_picker_ctx_top()

	if !ctx.active || ctx.runtime == nil {
		delete(text)
		return
	}

	slot := int(color_type)

	if slot < 0 || slot >= COLOR_PICKER_TYPE_SLOT_COUNT {
		delete(text)
		return
	}

	drafts := &ctx.runtime.type_drafts[slot]
	drafts.editing[index] = true
	color_picker_adopt_string(&drafts.text[index], text)
	raw, ok := color_picker_parse_type_field(drafts.text[index], color_type, index)

	if !ok {
		return
	}

	ctx.hsva, ctx.value = color_picker_apply_type_field(
		ctx.hsva,
		ctx.value,
		color_type,
		index,
		raw,
	)

	if color_type == .WEB {
		ctx.value = o.rgba_to_web_safe(ctx.value)
		ctx.hsva = o.color_picker_hsva_from_rgba(ctx.value, ctx.hsva)
	}

	color_picker_emit(ctx, ctx.value, false)
}

@(private)
color_picker_type_on_blur :: proc(color_type: o.Color_Picker_Color_Type, index: int) {
	ctx := color_picker_ctx_top()

	if !ctx.active || ctx.runtime == nil {
		return
	}

	slot := int(color_type)

	if slot < 0 || slot >= COLOR_PICKER_TYPE_SLOT_COUNT {
		return
	}

	ctx.runtime.type_drafts[slot].editing[index] = false
	color_picker_sync_runtime_texts(ctx.runtime, ctx.hsva, ctx.value)
}

@(private)
color_picker_web_only_on_change :: proc(checked: Checkbox_Value) {
	ctx := color_picker_ctx_top()

	if !ctx.active {
		return
	}

	next := checked == .TRUE
	ctx.web_only = next

	if ctx.on_web_only_change != nil {
		ctx.on_web_only_change(next)
	}

	if next {
		snapped := o.rgba_to_web_safe(ctx.value)
		ctx.hsva = o.color_picker_hsva_from_rgba(snapped, ctx.hsva)
		color_picker_emit(ctx, snapped, false)
	}
}

@(private)
color_picker_parse_type_input_id :: proc(
	id: string,
) -> (
	color_type: o.Color_Picker_Color_Type,
	index: int,
	ok: bool,
) {
	marker := "/ctype-"

	pos := strings.index(id, marker)

	if pos < 0 {
		return {}, 0, false
	}

	suffix := id[pos + len(marker):]
	parts := strings.split(suffix, "-", context.temp_allocator)

	if len(parts) != 2 {
		return {}, 0, false
	}

	slot: int

	if n, parse_ok := strconv.parse_int(parts[0]); parse_ok {
		slot = n
	} else {
		return {}, 0, false
	}

	field_index: int

	if n, parse_ok := strconv.parse_int(parts[1]); parse_ok {
		field_index = n
	} else {
		return {}, 0, false
	}

	if slot < 0 || slot >= COLOR_PICKER_TYPE_SLOT_COUNT {
		return {}, 0, false
	}

	return o.Color_Picker_Color_Type(slot), field_index, true
}

@(private)
color_picker_type_input_on_change :: proc(event: Text_Input_Event, text: string) {
	color_type, index, ok := color_picker_parse_type_input_id(event.frame_state.config.id)

	if !ok {
		delete(text)
		return
	}

	color_picker_type_on_change(color_type, index, text)
}

@(private)
color_picker_type_input_on_blur :: proc(event: Text_Input_Event) {
	color_type, index, ok := color_picker_parse_type_input_id(event.frame_state.config.id)

	if !ok {
		return
	}

	color_picker_type_on_blur(color_type, index)
}

@(private)
Color_Picker_Surface_State :: o.Widget_Merged_State(o.Widget_Frame_State, o.Resolved_Widget_Config)

@(private)
color_picker_surface_theme :: proc(
	frame_state: ^Color_Picker_Surface_State,
	size_w, size_h: f32,
) -> o.Widget_Config {
	opacity := f32(1)

	if frame_state.is_disabled {
		opacity = 0.5
	}

	return o.Widget_Config {
		kind = .RECT,
		tabbable = set.Tabbable(false),
		width = set.Width(size_w),
		height = set.Height(size_h),
		overflow_x = set.Overflow_X(.HIDDEN),
		overflow_y = set.Overflow_Y(.HIDDEN),
		opacity = set.F32(opacity),
	}
}

@(private)
color_picker_surface :: proc(
	cfg: o.Widget_Config,
	default_w, default_h: f32,
	theme: proc(frame_state: ^Color_Picker_Surface_State) -> o.Widget_Config,
	draw: proc(layout_id: o.UI_Id, rect: o.Rect),
	pointer: proc(
		layout_id: o.UI_Id,
		rect: o.Rect,
		hovered: bool,
		interactive: bool,
		disabled: bool,
	),
) {
	if !color_picker_ctx_ok() {
		return
	}

	picker_ctx := color_picker_ctx_top()
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)
	was_focused := widget_is_focused(key)
	disabled := picker_ctx.disabled || o.cfg_style_bool(cfg.disabled)

	frame_state := Color_Picker_Surface_State {
		is_disabled = disabled,
		is_focused  = was_focused,
	}

	props := struct {
		config: o.Widget_Config,
	} {
		config = cfg,
	}

	handlers := Widget_Lifecycle_Handlers(Color_Picker_Surface_State){}
	event := widget_refresh_merged(props, &frame_state, theme)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config

	if o.ui_pass() == .Layout {
		o.ui_push_scope(layout_id)
		node := o.layout_push_node(layout_id, config)

		if !o.length_is_definite(config.width) || !o.length_is_definite(config.height) {
			o.layout_set_measure_size(node, {default_w, default_h})
		}

		o.ui_push_style(o.style_child_context(config))
		o.ui_pop_style()
		o.layout_pop_node()
		o.ui_pop_scope()

		return
	}

	if o.ui_layout_paint_skip(layout_id) {
		return
	}

	frame_state.is_focused = widget_is_focused(key)
	rect := o.ui_layout_rect(layout_id)

	if rect.w <= 0 || rect.h <= 0 {
		return
	}

	widget_handle_interaction(
		props,
		&frame_state,
		handlers,
		key,
		was_focused,
		config.tabbable,
		layout_id,
		rect,
		config,
	)
	config = frame_state.config

	if widget_style_interaction_fp(&frame_state) != style_fp {
		event = widget_refresh_merged(props, &frame_state, theme)
		config = frame_state.config
	}

	interactive := widget_can_interact(handlers, &frame_state)
	mouse := o.Vec2{o.w_ctx.mouse_x, o.w_ctx.mouse_y}
	hovered := frame_state.is_hovered || color_picker_point_in_rect(mouse, rect)

	if pointer != nil {
		pointer(layout_id, rect, hovered, interactive, disabled)
	}

	if draw != nil {
		draw(layout_id, rect)
	}
}

/*
Renders the color picker root. Compose with `Color_Picker_Field`, `Color_Picker_Slider`,
and other parts inside `child`.
*/
Color_Picker :: proc(props: Color_Picker_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)
	disabled := props.disabled || o.cfg_style_bool(cfg.disabled)
	rt := color_picker_runtime_ensure(key)

	color_picker_sync_runtime_hsva(rt, props.value)

	value := props.value
	previous := props.previous
	hsva := rt != nil ? rt.hsva : o.rgba_to_hsva(value)
	channel := props.channel
	web_only := props.web_only

	frame_state := Color_Picker_State {
		is_disabled = disabled,
		is_focused  = was_focused,
		value       = value,
		previous    = previous,
		hsva        = hsva,
		channel     = channel,
		web_only    = web_only,
	}

	if disabled {
		cfg.disabled = set.Disabled(true)
	}

	resolved_props := props
	resolved_props.config = cfg

	event := color_picker_refresh_merged(resolved_props, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(resolved_props, Color_Picker_State)
	should_auto_focus := widget_should_auto_focus(config, key)
	child := props.child

	pushed := color_picker_ctx_push(
		{
			active = true,
			key = key,
			root_layout_id = layout_id,
			runtime = rt,
			value = value,
			previous = previous,
			hsva = hsva,
			channel = channel,
			web_only = web_only,
			has_web_type = false,
			hex_include_alpha = false,
			disabled = disabled,
			style = props.style,
			on_value_change = props.on_value_change,
			on_value_commit = props.on_value_commit,
			on_channel_change = props.on_channel_change,
			on_web_only_change = props.on_web_only_change,
			on_key_down = props.on_key_down,
			on_key_pressed = props.on_key_pressed,
			on_key_released = props.on_key_released,
		},
	)

	defer {
		if pushed {
			color_picker_ctx_pop()
		}
	}

	props_with_keys := resolved_props
	props_with_keys.on_key_down = color_picker_on_key_down
	props_with_keys.on_key_pressed = color_picker_on_key_pressed
	props_with_keys.on_key_released = color_picker_on_key_released

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = color_picker_refresh_merged(resolved_props, &frame_state)
			config = frame_state.config
			should_auto_focus = widget_should_auto_focus(config, key)
		}

		if skip_layout {
			color_picker_runtime_clear(key)

			return
		}

		can_interact := widget_can_interact(handlers, &frame_state)

		if can_interact && should_auto_focus {
			widget_apply_auto_focus(key, true)
			frame_state.is_focused = true
		}

		widget_register_tab_order(key, config.tabbable, can_interact)

		if child != nil {
			widget_children(
				child,
				layout_id,
				config,
				frame_state,
				key,
				cfg,
				props.on_scroll,
				props.scroll_bar,
				frame_state.is_hovered,
			)
		}

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) {
		return
	}

	frame_state.is_focused = widget_is_focused(key)
	rect := o.ui_layout_rect(layout_id)

	widget_handle_interaction(
		props_with_keys,
		&frame_state,
		handlers,
		key,
		was_focused,
		config.tabbable,
		layout_id,
		rect,
		config,
	)
	widget_handle_scroll_wheel(layout_id, config, frame_state.is_hovered, key, props.on_scroll)
	scroll := o.widget_scroll_get(key)
	config.scroll_x = scroll.x
	config.scroll_y = scroll.y
	frame_state.config = config

	if widget_style_interaction_fp(&frame_state) != style_fp {
		event = color_picker_refresh_merged(resolved_props, &frame_state)
		config = frame_state.config
	}

	interactive := widget_can_interact(handlers, &frame_state)

	if pushed {
		ctx := color_picker_ctx_top()
		frame_state.value = ctx.value
		frame_state.hsva = ctx.hsva
		frame_state.channel = ctx.channel
		frame_state.web_only = ctx.web_only
	}

	if interactive {
		if widget_got_tab_focus(key) && props.on_focus != nil {
			props.on_focus(event)
		}

		if widget_lost_tab_focus(key) && props.on_blur != nil {
			props.on_blur(event)
		}
	}

	if should_auto_focus && !was_focused && props.on_focus != nil && interactive {
		props.on_focus(event)
	}

	background: o.RGBA

	if resolved_background, ok := o.style_background_rgba(config, &frame_state, event); ok {
		background = resolved_background
	}

	border: o.Bd_px

	if resolved_border, ok := o.resolve_border(config.border, &frame_state, event); ok {
		border = resolved_border
	}

	border_color: o.RGBA

	if resolved_border_color, ok := o.style_border_color_rgba(config, &frame_state, event); ok {
		border_color = resolved_border_color
	}

	radius: o.Radius_px

	if resolved_radius, ok := o.resolve_radius(config.radius, &frame_state, event); ok {
		radius = resolved_radius
	}

	o.Draw_Push_Opacity(config.opacity)
	defer o.Draw_Pop_Opacity()

	widget_draw_box_background(layout_id, rect, background, radius)

	if child != nil {
		widget_children(
			child,
			layout_id,
			config,
			frame_state,
			key,
			cfg,
			props.on_scroll,
			props.scroll_bar,
			frame_state.is_hovered,
		)
	}

	widget_draw_box_border(layout_id, rect, radius, border, border_color)

	widget_dispatch_events(props_with_keys, &frame_state, handlers, event, key, was_focused)
}
