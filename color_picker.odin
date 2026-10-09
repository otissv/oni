package oni

COLOR_PICKER_DEFAULT_FIELD_SIZE :: f32(200)
COLOR_PICKER_DEFAULT_SLIDER_WIDTH :: f32(20)
COLOR_PICKER_DEFAULT_ALPHA_HEIGHT :: f32(16)
COLOR_PICKER_FIELD_SAMPLES :: 48
COLOR_PICKER_SLIDER_SAMPLES :: 128
COLOR_PICKER_THUMB_SIZE :: f32(12)
COLOR_PICKER_CHECKER_SIZE :: f32(6)
// Side-triangle thumb width; gutters beside the spectrum keep thumbs clear of neighbors.
COLOR_PICKER_SLIDER_TRIANGLE_W :: f32(8)
COLOR_PICKER_SLIDER_GUTTER :: f32(16)

/*
Which component drives the vertical spectrum slider.
*/
Color_Picker_Channel :: enum {
	H,
	S,
	V,
	R,
	G,
	B,
}

/*
Numeric input groups exposed by `Color_Picker_Type` rows.
*/
Color_Picker_Color_Type :: enum {
	RGB,
	HSB,
	HSL,
	LAB,
	CMYK,
	WEB,
}

/*
Active drag target within a color picker.
*/
Color_Picker_Drag_Region :: enum {
	NONE,
	FIELD,
	SLIDER,
	ALPHA,
}

/*
Pointer-drag latch for a color picker layout id.
*/
Color_Picker_Drag :: struct {
	active: bool,
	region: Color_Picker_Drag_Region,
}

/*
Returns existing color-picker drag state for a layout id, or nil.
*/
color_picker_drag_get :: proc(id: UI_Id) -> ^Color_Picker_Drag {
	if state == nil || state.ui.color_picker_drags == nil {
		return nil
	}

	if _, ok := state.ui.color_picker_drags[id]; !ok {
		return nil
	}

	return &state.ui.color_picker_drags[id]
}

/*
Returns or creates color-picker drag state for a layout id.
*/
color_picker_drag_entry :: proc(id: UI_Id) -> ^Color_Picker_Drag {
	if state == nil {
		return nil
	}

	if state.ui.color_picker_drags == nil {
		state.ui.color_picker_drags = make(map[UI_Id]Color_Picker_Drag)
	}

	if _, ok := state.ui.color_picker_drags[id]; !ok {
		state.ui.color_picker_drags[id] = {}
	}

	return &state.ui.color_picker_drags[id]
}

/*
Clears an active color-picker drag while retaining the map entry.
*/
color_picker_drag_end :: proc(id: UI_Id) {
	drag := color_picker_drag_entry(id)

	if drag == nil {
		return
	}

	drag.active = false
	drag.region = .NONE
}

/*
Removes color-picker drag state for a layout id.
*/
color_picker_drag_clear :: proc(id: UI_Id) {
	if state == nil || state.ui.color_picker_drags == nil {
		return
	}

	delete_key(&state.ui.color_picker_drags, id)
}

@(private)
color_picker_shutdown :: proc() {
	if state == nil {
		return
	}

	if state.ui.color_picker_drags != nil {
		delete(state.ui.color_picker_drags)
		state.ui.color_picker_drags = nil
	}
}

/*
Normalized pointer position inside `rect` with x/y in [0, 1].

Y increases downward in layout space. Returns false when the rect has no area.
*/
color_picker_norm_in_rect :: proc(pointer: Vec2, rect: Rect) -> (x, y: f32, ok: bool) {
	if rect.w <= 0 || rect.h <= 0 {
		return 0, 0, false
	}

	x = clamp((pointer.x - rect.x) / rect.w, 0, 1)
	y = clamp((pointer.y - rect.y) / rect.h, 0, 1)

	return x, y, true
}

/*
Maps a vertical slider normalized y (0=top, 1=bottom) to a unit channel value
with maximum at the top and minimum at the bottom.
*/
color_picker_slider_t_from_y :: proc(y_norm: f32) -> f32 {
	return clamp(1 - y_norm, 0, 1)
}

/*
Maps a unit channel value to vertical slider y (0=top, 1=bottom).
*/
color_picker_y_from_slider_t :: proc(t: f32) -> f32 {
	return clamp(1 - t, 0, 1)
}

/*
Reads the active slider channel as a unit value in [0, 1] (hue scaled by 1/360).
*/
color_picker_channel_unit :: proc(hsva: HSVA, rgba: RGBA, channel: Color_Picker_Channel) -> f32 {
	switch channel {
	case .H:
		return color_hue_wrap(hsva.h) / 360
	case .S:
		return color_clamp01(hsva.s)
	case .V:
		return color_clamp01(hsva.v)
	case .R:
		return f32(rgba.r) / 255
	case .G:
		return f32(rgba.g) / 255
	case .B:
		return f32(rgba.b) / 255
	}

	return 0
}

/*
Writes the active slider channel from a unit value in [0, 1].
*/
color_picker_apply_channel_unit :: proc(
	hsva: HSVA,
	rgba: RGBA,
	channel: Color_Picker_Channel,
	unit: f32,
) -> (
	HSVA,
	RGBA,
) {
	u := color_clamp01(unit)
	out_hsva := hsva
	out_rgba := rgba

	switch channel {
	case .H:
		out_hsva.h = u * 360
		out_rgba = hsva_to_rgba(out_hsva)
	case .S:
		out_hsva.s = u
		out_rgba = hsva_to_rgba(out_hsva)
	case .V:
		out_hsva.v = u
		out_rgba = hsva_to_rgba(out_hsva)
	case .R:
		out_rgba.r = color_u8_from01(u)
		out_hsva = color_picker_hsva_from_rgba(out_rgba, hsva)
	case .G:
		out_rgba.g = color_u8_from01(u)
		out_hsva = color_picker_hsva_from_rgba(out_rgba, hsva)
	case .B:
		out_rgba.b = color_u8_from01(u)
		out_hsva = color_picker_hsva_from_rgba(out_rgba, hsva)
	}

	return out_hsva, out_rgba
}

/*
Converts RGBA to HSVA while preserving prior hue when the result is achromatic.
*/
color_picker_hsva_from_rgba :: proc(rgba: RGBA, prior: HSVA) -> HSVA {
	hsva := rgba_to_hsva(rgba)

	if hsva.s <= 1e-6 {
		hsva.h = prior.h
	}

	return hsva
}

/*
Applies a color-field pointer (normalized x/y, y downward) for the active channel.
*/
color_picker_apply_field :: proc(
	hsva: HSVA,
	rgba: RGBA,
	channel: Color_Picker_Channel,
	x_norm, y_norm: f32,
) -> (
	HSVA,
	RGBA,
) {
	x := color_clamp01(x_norm)
	y_up := color_clamp01(1 - y_norm)
	out_hsva := hsva
	out_rgba := rgba

	switch channel {
	case .H:
		out_hsva.s = x
		out_hsva.v = y_up
		out_rgba = hsva_to_rgba(out_hsva)
	case .S:
		out_hsva.h = x * 360
		out_hsva.v = y_up
		out_rgba = hsva_to_rgba(out_hsva)
	case .V:
		out_hsva.h = x * 360
		out_hsva.s = y_up
		out_rgba = hsva_to_rgba(out_hsva)
	case .R:
		out_rgba.g = color_u8_from01(x)
		out_rgba.b = color_u8_from01(y_up)
		out_hsva = color_picker_hsva_from_rgba(out_rgba, hsva)
	case .G:
		out_rgba.r = color_u8_from01(x)
		out_rgba.b = color_u8_from01(y_up)
		out_hsva = color_picker_hsva_from_rgba(out_rgba, hsva)
	case .B:
		out_rgba.r = color_u8_from01(x)
		out_rgba.g = color_u8_from01(y_up)
		out_hsva = color_picker_hsva_from_rgba(out_rgba, hsva)
	}

	return out_hsva, out_rgba
}

/*
Returns the normalized field marker position (x in [0,1], y downward in [0,1]).
*/
color_picker_field_marker :: proc(
	hsva: HSVA,
	rgba: RGBA,
	channel: Color_Picker_Channel,
) -> (
	x, y: f32,
) {
	switch channel {
	case .H:
		return color_clamp01(hsva.s), color_clamp01(1 - hsva.v)
	case .S:
		return color_clamp01(hsva.h / 360), color_clamp01(1 - hsva.v)
	case .V:
		return color_clamp01(hsva.h / 360), color_clamp01(1 - hsva.s)
	case .R:
		return f32(rgba.g) / 255, 1 - f32(rgba.b) / 255
	case .G:
		return f32(rgba.r) / 255, 1 - f32(rgba.b) / 255
	case .B:
		return f32(rgba.r) / 255, 1 - f32(rgba.g) / 255
	}

	return 0, 0
}

/*
Samples the color displayed at a field cell for painting.
*/
color_picker_sample_field :: proc(
	hsva: HSVA,
	rgba: RGBA,
	channel: Color_Picker_Channel,
	x_norm, y_norm: f32,
) -> RGBA {
	_, sample := color_picker_apply_field(hsva, rgba, channel, x_norm, y_norm)
	sample.a = 255

	return sample
}

/*
Samples the color displayed at a slider stop for painting.
*/
color_picker_sample_slider :: proc(
	hsva: HSVA,
	rgba: RGBA,
	channel: Color_Picker_Channel,
	y_norm: f32,
) -> RGBA {
	unit := color_picker_slider_t_from_y(y_norm)
	_, sample := color_picker_apply_channel_unit(hsva, rgba, channel, unit)
	sample.a = 255

	return sample
}

/*
Applies alpha from a normalized horizontal position (0=left transparent).
*/
color_picker_apply_alpha :: proc(hsva: HSVA, rgba: RGBA, x_norm: f32) -> (HSVA, RGBA) {
	a := color_clamp01(x_norm)
	out_hsva := hsva
	out_rgba := rgba
	out_hsva.a = a
	out_rgba.a = color_u8_from01(a)

	return out_hsva, out_rgba
}

/*
Keyboard nudge for the focused color field / slider / alpha.

`step` is a unit fraction (e.g. 1/255 or 1/100). Returns false when the key is
not handled.
*/
color_picker_nudge :: proc(
	hsva: HSVA,
	rgba: RGBA,
	channel: Color_Picker_Channel,
	region: Color_Picker_Drag_Region,
	key: Scancode,
	step: f32,
) -> (
	HSVA,
	RGBA,
	bool,
) {
	dx: f32 = 0
	dy: f32 = 0

	#partial switch key {
	case .LEFT:
		dx = -step
	case .RIGHT:
		dx = step
	case .UP:
		dy = -step
	case .DOWN:
		dy = step
	case .HOME:
		dx = -1
		dy = -1
	case .END:
		dx = 1
		dy = 1
	case:
		return hsva, rgba, false
	}

	switch region {
	case .FIELD:
		mx, my := color_picker_field_marker(hsva, rgba, channel)

		if key == .HOME {
			mx, my = 0, 0
		} else if key == .END {
			mx, my = 1, 1
		} else {
			mx = color_clamp01(mx + dx)
			my = color_clamp01(my + dy)
		}

		out_h, out_r := color_picker_apply_field(hsva, rgba, channel, mx, my)

		return out_h, out_r, true
	case .SLIDER, .NONE:
		unit := color_picker_channel_unit(hsva, rgba, channel)

		if key == .HOME {
			unit = 1
		} else if key == .END {
			unit = 0
		} else if key == .UP || key == .RIGHT {
			unit = color_clamp01(unit + step)
		} else if key == .DOWN || key == .LEFT {
			unit = color_clamp01(unit - step)
		} else {
			return hsva, rgba, false
		}

		out_h, out_r := color_picker_apply_channel_unit(hsva, rgba, channel, unit)

		return out_h, out_r, true
	case .ALPHA:
		a := color_clamp01(hsva.a)

		if key == .HOME {
			a = 0
		} else if key == .END {
			a = 1
		} else if key == .LEFT || key == .DOWN {
			a = color_clamp01(a - step)
		} else if key == .RIGHT || key == .UP {
			a = color_clamp01(a + step)
		} else {
			return hsva, rgba, false
		}

		out_h, out_r := color_picker_apply_alpha(hsva, rgba, a)

		return out_h, out_r, true
	}

	return hsva, rgba, false
}

/*
Checkerboard tile color for alpha previews.
*/
color_picker_checker_color :: proc(col, row: int) -> RGBA {
	if (col + row) % 2 == 0 {
		return RGBA{220, 220, 220, 255}
	}

	return RGBA{170, 170, 170, 255}
}

/*
Linearly blends two opaque colors by `t` in [0, 1] (used for alpha ramp overlays).
*/
color_picker_lerp_rgb :: proc(a, b: RGBA, t: f32) -> RGBA {
	u := color_clamp01(t)

	return RGBA {
		color_u8_from01((1 - u) * f32(a.r) / 255 + u * f32(b.r) / 255),
		color_u8_from01((1 - u) * f32(a.g) / 255 + u * f32(b.g) / 255),
		color_u8_from01((1 - u) * f32(a.b) / 255 + u * f32(b.b) / 255),
		255,
	}
}

/*
Snaps a component edit string value into range for H (0-360), S/V (0-100), or RGB (0-255).
*/
color_picker_parse_component :: proc(
	text: string,
	channel: Color_Picker_Channel,
) -> (
	f32,
	bool,
) {
	n, ok := color_picker_parse_f32(text)

	if !ok {
		return 0, false
	}

	switch channel {
	case .H:
		return color_hue_wrap(n), true
	case .S, .V:
		return color_clamp01(n / 100), true
	case .R, .G, .B:
		return color_clamp01(n / 255), true
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
