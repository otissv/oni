package oni

import col "../colors"

Color :: col.Color
RGBA :: col.RGBA
Hex :: col.Hex
HSLA :: col.HSLA
HWBA :: col.HWBA
LCHA :: col.LCHA
OKLCHA :: col.OKLCHA
Palette :: col.Palette

palette := col.palette

css_color_to_rgba :: col.css_color_to_rgba
to_rgba_color :: col.to_rgba_color
rgba_to_f32 :: col.rgba_to_f32

Colors :: union {
	Color,
	RGBA,
	Hex,
	HSLA,
	HWBA,
	LCHA,
	OKLCHA,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Colors,
}

/*
Returns true when a Colors union value is a dynamic callback proc.
*/
colors_is_proc :: proc(c: Colors) -> bool {
	#partial switch _ in c {
	case proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Colors:
		return true
	}
	return false
}

/*
Resolves any Colors value (including callbacks) to RGBA using widget context.

Handles Color.INHERIT by walking the current style stack for a parent color.
*/
to_rgba :: proc(c: Colors, state: ^$S, event: Widget_Event(S)) -> (rgba: RGBA, ok: bool) {
	#partial switch v in c {
	case Color:
		if v == .INVALID do return {}, false
		if v == .INHERIT {
			parent := ui_style_current()
			#partial switch c in parent.color {
			case RGBA:
				return c, true
			case Color:
				if c == .INVALID do return {}, false
				return css_color_to_rgba(c), true
			}
			return {}, false
		}
		return to_rgba_color(v), true
	case RGBA:
		return to_rgba_color(v), true
	case Hex:
		return to_rgba_color(v), true
	case HSLA:
		return to_rgba_color(v), true
	case HWBA:
		return to_rgba_color(v), true
	case LCHA:
		return to_rgba_color(v), true
	case OKLCHA:
		return to_rgba_color(v), true
	case proc(
		     frame_state: Widget_Frame_State,
		     widget_event: Widget_Event(Widget_Frame_State),
	     ) -> Colors:
		ui_state := (^Widget_Frame_State)(cast(rawptr)state)^
		ui_event := Widget_Event(Widget_Frame_State) {
			frame_state = ui_state,
		}
		return to_rgba(v(ui_state, ui_event), state, event)
	}
	return {}, false
}

/*
Converts any static Colors variant to normalized [4]f32.

Callback proc variants are not supported; returns zero for .Invalid.
*/
color_to_f32 :: proc(c: Colors) -> [4]f32 {
	rgba: RGBA

	#partial switch v in c {
	case Color:
		if v == .INVALID do return {}
		rgba = to_rgba_color(v)
	case RGBA:
		rgba = to_rgba_color(v)
	case Hex:
		rgba = to_rgba_color(v)
	case HSLA:
		rgba = to_rgba_color(v)
	case HWBA:
		rgba = to_rgba_color(v)
	case LCHA:
		rgba = to_rgba_color(v)
	case OKLCHA:
		rgba = to_rgba_color(v)
	}

	return rgba_to_f32(rgba)
}
