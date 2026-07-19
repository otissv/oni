package oni

import "core:fmt"
import "core:mem"
import "core:strconv"
import "core:strings"

Text_Tag_Diagnostic :: struct {
	message: string,
	offset:  int,
}

Text_Tag_Parse :: struct {
	plain:       string,
	runs:        []Text_Run,
	layout_runs: []Layout_Text_Run,
	diagnostics: []Text_Tag_Diagnostic,
}

@(private)
text_tag_color_from_name :: proc(name: string) -> (Color, bool) {
	switch strings.to_lower(name, context.temp_allocator) {
	case "foreground":
		return .FOREGROUND, true
	case "background":
		return .BACKGROUND, true
	case "muted":
		return .MUTED, true
	case "muted_foreground":
		return .MUTED_FOREGROUND, true
	case "accent":
		return .ACCENT, true
	case "accent_foreground":
		return .ACCENT_FOREGROUND, true
	case "primary":
		return .PRIMARY, true
	case "primary_foreground":
		return .PRIMARY_FOREGROUND, true
	case "secondary":
		return .SECONDARY, true
	case "secondary_foreground":
		return .SECONDARY_FOREGROUND, true
	case "destructive":
		return .DESTRUCTIVE, true
	case "destructive_foreground":
		return .DESTRUCTIVE_FOREGROUND, true
	case "success":
		return .SUCCESS, true
	case "success_foreground":
		return .SUCCESS_FOREGROUND, true
	case "warning":
		return .WARNING, true
	case "warning_foreground":
		return .WARNING_FOREGROUND, true
	case "info":
		return .INFO, true
	case "info_foreground":
		return .INFO_FOREGROUND, true
	case "border":
		return .BORDER, true
	case "card":
		return .CARD, true
	case "card_foreground":
		return .CARD_FOREGROUND, true
	}

	return .INVALID, false
}

@(private)
text_tag_field_from_name :: proc(name: string) -> (Text_Run_Style_Field, bool) {
	switch strings.to_lower(name, context.temp_allocator) {
	case "c", "color":
		return .color, true
	case "b", "font_weight":
		return .font_weight, true
	case "i", "font_style":
		return .font_style, true
	case "u", "text_decoration":
		return .text_decoration, true
	case "align":
		return .align, true
	case "auto_focus":
		return .auto_focus, true
	case "background":
		return .background, true
	case "border":
		return .border, true
	case "border_color":
		return .border_color, true
	case "direction":
		return .direction, true
	case "disabled":
		return .disabled, true
	case "flex":
		return .flex, true
	case "font":
		return .font, true
	case "font_size":
		return .font_size, true
	case "gap_x":
		return .gap_x, true
	case "gap_y":
		return .gap_y, true
	case "height":
		return .height, true
	case "justify":
		return .justify, true
	case "letter_spacing":
		return .letter_spacing, true
	case "line_height":
		return .line_height, true
	case "max_h":
		return .max_h, true
	case "max_w":
		return .max_w, true
	case "min_h":
		return .min_h, true
	case "min_w":
		return .min_w, true
	case "order":
		return .order, true
	case "overflow_x":
		return .overflow_x, true
	case "overflow_y":
		return .overflow_y, true
	case "opacity":
		return .opacity, true
	case "padding":
		return .padding, true
	case "pointer_events":
		return .pointer_events, true
	case "position":
		return .position, true
	case "radius":
		return .radius, true
	case "self":
		return .self, true
	case "space":
		return .space, true
	case "tabbable":
		return .tabbable, true
	case "tab_size":
		return .tab_size, true
	case "text_decoration_color":
		return .text_decoration_color, true
	case "text_decoration_style":
		return .text_decoration_style, true
	case "text_direction":
		return .text_direction, true
	case "texture_fit":
		return .texture_fit, true
	case "texture_pos":
		return .texture_pos, true
	case "visibility":
		return .visibility, true
	case "width":
		return .width, true
	case "wrap":
		return .wrap, true
	case "word_spacing":
		return .word_spacing, true
	case "x":
		return .x, true
	case "y":
		return .y, true
	case "right":
		return .right, true
	case "bottom":
		return .bottom, true
	case "z_index":
		return .z_index, true
	}

	return Text_Run_Style_Field(0), false
}

@(private)
text_tag_parse_bool :: proc(value: string) -> (bool, bool) {
	switch strings.to_lower(value, context.temp_allocator) {
	case "", "true", "1", "yes", "on":
		return true, true
	case "false", "0", "no", "off":
		return false, true
	}

	return false, false
}

@(private)
text_tag_parse_f32 :: proc(value: string) -> (f32, bool) {
	return strconv.parse_f32(value)
}

@(private)
text_tag_parse_u16 :: proc(value: string) -> (u16, bool) {
	parsed, ok := strconv.parse_u64(value)

	if !ok || parsed > u64(max(u16)) do return 0, false

	return u16(parsed), true
}

@(private)
text_tag_parse_length :: proc(value: string) -> (Length, bool) {
	if strings.has_suffix(value, "%") {
		num, ok := strconv.parse_f32(value[:len(value) - 1])

		if !ok do return {}, false

		return Length{kind = .PERCENT, value = num}, true
	}

	num, ok := text_tag_parse_f32(value)

	if !ok do return {}, false

	return Length{kind = .FIXED, value = num}, true
}

@(private)
text_tag_parse_font :: proc(value: string) -> (Font_Handle, bool) {
	if len(value) == 0 do return {}, false

	sep := strings.index_byte(value, ':')

	if sep < 0 {
		sep = strings.index_byte(value, '/')
	}

	if sep >= 0 {
		family_name := strings.trim_space(value[:sep])
		size_text := strings.trim_space(value[sep + 1:])
		size, size_ok := text_tag_parse_f32(size_text)

		if !size_ok || size <= 0 do return {}, false

		family, family_ok := font_family_by_name(family_name)

		if !family_ok do return {}, false

		return font_with_size(family, size), true
	}

	family, ok := font_family_by_name(strings.trim_space(value))

	if !ok do return {}, false

	return family, true
}

@(private)
text_tag_parse_font_weight :: proc(value: string) -> (Font_Weights, bool) {
	switch strings.to_lower(value, context.temp_allocator) {
	case "", "bold", "b":
		return .Bold, true
	case "normal", "regular":
		return .Normal, true
	case "thin":
		return .Thin, true
	case "light":
		return .Light, true
	case "medium":
		return .Medium, true
	case "semibold", "semi_bold":
		return .Semi_Bold, true
	case "extrabold", "extra_bold":
		return .Extra_Bold, true
	case "heavy":
		return .Heavy, true
	}

	return .Normal, false
}

@(private)
text_tag_parse_font_style :: proc(value: string) -> (Font_Styles, bool) {
	switch strings.to_lower(value, context.temp_allocator) {
	case "", "italic", "i":
		return .ITALIC, true
	case "normal":
		return .NORMAL, true
	}

	return .NORMAL, false
}

@(private)
text_tag_parse_text_direction :: proc(value: string) -> (Text_Direction_Kind, bool) {
	switch strings.to_lower(value, context.temp_allocator) {
	case "ltr", "left":
		return .LTR, true
	case "rtl", "right":
		return .RTL, true
	}

	return .LTR, false
}

@(private)
text_tag_parse_text_align :: proc(value: string) -> (Text_Align_Kind, bool) {
	switch strings.to_lower(value, context.temp_allocator) {
	case "left":
		return .LEFT, true
	case "center", "centre":
		return .CENTER, true
	case "right":
		return .RIGHT, true
	}

	return .LEFT, false
}

@(private)
text_tag_parse_text_wrap :: proc(value: string) -> (Text_Wrap_Kind, bool) {
	switch strings.to_lower(value, context.temp_allocator) {
	case "none":
		return .NONE, true
	case "newlines":
		return .NEWLINES, true
	case "balance":
		return .BALANCE, true
	case "preserve":
		return .PRESERVE, true
	}

	return .NONE, false
}

@(private)
text_tag_parse_decoration_line :: proc(token: string) -> (Text_Decoration_Line, bool) {
	switch strings.to_lower(token, context.temp_allocator) {
	case "underline", "u":
		return .UNDERLINE, true
	case "line-through", "line_through", "through":
		return .LINE_THROUGH, true
	case "overline":
		return .OVERLINE, true
	}

	return .UNDERLINE, false
}

@(private)
text_tag_parse_text_decoration :: proc(value: string) -> (Text_Decoration_Lines, bool) {
	if len(value) == 0 do return {.UNDERLINE}, true

	lines: Text_Decoration_Lines
	remaining := value

	for {
		comma := strings.index_byte(remaining, ',')

		token := remaining if comma < 0 else remaining[:comma]
		line, ok := text_tag_parse_decoration_line(strings.trim_space(token))

		if !ok do return {}, false

		lines += {line}

		if comma < 0 do break

		remaining = remaining[comma + 1:]
	}

	if lines == {} do return {}, false

	return lines, true
}

@(private)
text_tag_parse_text_decoration_style :: proc(value: string) -> (Text_Decoration_Style_Kind, bool) {
	switch strings.to_lower(value, context.temp_allocator) {
	case "solid":
		return .SOLID, true
	case "double":
		return .DOUBLE, true
	case "dotted":
		return .DOTTED, true
	case "dashed":
		return .DASHED, true
	case "wavy":
		return .WAVY, true
	}

	return .SOLID, false
}

@(private)
text_tag_parse_visibility :: proc(value: string) -> (Visibility_Kind, bool) {
	switch strings.to_lower(value, context.temp_allocator) {
	case "visible":
		return .VISIBLE, true
	case "hidden":
		return .HIDDEN, true
	case "none":
		return .NONE, true
	}

	return .VISIBLE, false
}

@(private)
text_tag_parse_overflow :: proc(value: string) -> (Overflow_Kind, bool) {
	switch strings.to_lower(value, context.temp_allocator) {
	case "auto":
		return .AUTO, true
	case "scroll":
		return .SCROLL, true
	case "hidden":
		return .HIDDEN, true
	}

	return .AUTO, false
}

@(private)
text_tag_parse_pointer_events :: proc(value: string) -> (Pointer_Events_Kind, bool) {
	switch strings.to_lower(value, context.temp_allocator) {
	case "auto":
		return .AUTO, true
	case "none":
		return .NONE, true
	}

	return .AUTO, false
}

@(private)
text_tag_parse_position :: proc(value: string) -> (Position_Kind, bool) {
	switch strings.to_lower(value, context.temp_allocator) {
	case "relative":
		return .RELATIVE, true
	case "absolute":
		return .ABSOLUTE, true
	case "fixed":
		return .FIXED, true
	case "sticky":
		return .STICKY, true
	}

	return .RELATIVE, false
}

@(private)
text_tag_parse_direction :: proc(value: string) -> (Direction_Layout, bool) {
	switch strings.to_lower(value, context.temp_allocator) {
	case "horizontal", "row":
		return .HORIZONTAL, true
	case "vertical", "column":
		return .VERTICAL, true
	case "horizontal_wrap":
		return .HORIZONTAL_WRAP, true
	case "vertical_wrap":
		return .VERTICAL_WRAP, true
	}

	return .HORIZONTAL, false
}

@(private)
text_tag_parse_space :: proc(value: string) -> (Draw_Space, bool) {
	switch strings.to_lower(value, context.temp_allocator) {
	case "screen":
		return .SCREEN, true
	case "artboard":
		return .ARTBOARD, true
	case "popover":
		return .POPOVER, true
	}

	return .SCREEN, false
}

@(private)
text_tag_parse_texture_fit :: proc(value: string) -> (Texture_Fit, bool) {
	switch strings.to_lower(value, context.temp_allocator) {
	case "fill":
		return .FILL, true
	case "contain":
		return .CONTAIN, true
	case "cover":
		return .COVER, true
	case "scale_down", "scale-down":
		return .SCALE_DOWN, true
	case "none":
		return .NONE, true
	}

	return .FILL, false
}

@(private)
text_tag_parse_spacing_preset :: proc(value: string) -> (f32, bool) {
	switch strings.to_lower(value, context.temp_allocator) {
	case "sm":
		return PADDING_SM, true
	case "md":
		return PADDING_MD, true
	case "lg":
		return PADDING_LG, true
	case "xl":
		return PADDING_XL, true
	}

	return text_tag_parse_f32(value)
}

@(private)
text_tag_parse_justify_axis :: proc(token: string) -> (Justify_Align, bool) {
	switch strings.to_lower(token, context.temp_allocator) {
	case "", "start":
		return .START, true
	case "center", "centre":
		return .CENTER, true
	case "end":
		return .END, true
	case "stretch":
		return .STRETCH, true
	}

	return .START, false
}

@(private)
text_tag_parse_justify_pos :: proc(value: string) -> (Justify_Pos, bool) {
	parts := strings.split(value, "-", context.temp_allocator)

	if len(parts) == 0 do return {}, false

	x, x_ok := text_tag_parse_justify_axis(parts[0])

	if !x_ok do return {}, false

	y := x

	if len(parts) > 1 {
		y, x_ok = text_tag_parse_justify_axis(parts[1])

		if !x_ok do return {}, false
	}

	return {x = x, y = y}, true
}

@(private)
text_tag_parse_value :: proc(
	field: Text_Run_Style_Field,
	value: string,
) -> (
	parsed: Text_Run_Tag_Value,
	ok: bool,
) {
	#partial switch field {
	case .color, .background, .border_color, .text_decoration_color:
		color, color_ok := text_tag_color_from_name(value)

		if !color_ok do return parsed, false

		return color, true
	case .font_weight:
		weight, weight_ok := text_tag_parse_font_weight(value)

		return weight, weight_ok
	case .font:
		font, font_ok := text_tag_parse_font(value)

		return font, font_ok
	case .font_style:
		style, style_ok := text_tag_parse_font_style(value)

		return style, style_ok
	case .text_direction:
		direction, direction_ok := text_tag_parse_text_direction(value)

		return direction, direction_ok
	case .align:
		align, align_ok := text_tag_parse_text_align(value)

		return align, align_ok
	case .wrap:
		wrap, wrap_ok := text_tag_parse_text_wrap(value)

		return wrap, wrap_ok
	case .text_decoration:
		lines, lines_ok := text_tag_parse_text_decoration(value)

		return lines, lines_ok
	case .text_decoration_style:
		style, style_ok := text_tag_parse_text_decoration_style(value)

		return style, style_ok
	case .visibility:
		visibility, visibility_ok := text_tag_parse_visibility(value)

		return visibility, visibility_ok
	case .overflow_x, .overflow_y:
		overflow, overflow_ok := text_tag_parse_overflow(value)

		return overflow, overflow_ok
	case .pointer_events:
		events, events_ok := text_tag_parse_pointer_events(value)

		return events, events_ok
	case .position:
		position, position_ok := text_tag_parse_position(value)

		return position, position_ok
	case .direction:
		direction, direction_ok := text_tag_parse_direction(value)

		return direction, direction_ok
	case .space:
		space, space_ok := text_tag_parse_space(value)

		return space, space_ok
	case .texture_fit:
		fit, fit_ok := text_tag_parse_texture_fit(value)

		return fit, fit_ok
	case .justify, .self:
		justify, justify_ok := text_tag_parse_justify_pos(value)

		return justify, justify_ok
	case .width, .height:
		length, length_ok := text_tag_parse_length(value)

		return length, length_ok
	case .gap_x, .gap_y:
		gap, gap_ok := text_tag_parse_u16(value)

		return gap, gap_ok
	case .disabled, .tabbable, .auto_focus:
		flag, flag_ok := text_tag_parse_bool(value)

		return flag, flag_ok
	case .border, .padding, .radius, .font_size, .letter_spacing, .line_height, .word_spacing, .tab_size, .opacity, .flex, .max_h, .max_w, .min_h, .min_w, .order, .x, .y, .right, .bottom, .z_index:
		num, num_ok := text_tag_parse_spacing_preset(value)

		return num, num_ok
	case .texture_pos:
		return parsed, false
	}

	return parsed, false
}

@(private)
text_runs_push :: proc(
	runs: ^[dynamic]Text_Run,
	text: string,
	style: Text_Run_Style,
	allocator: mem.Allocator,
) {
	if len(text) == 0 do return

	if len(runs) > 0 && text_run_style_equal(runs[len(runs) - 1].style, style) {
		prev := &runs[len(runs) - 1]
		b := strings.builder_make(allocator)
		defer strings.builder_destroy(&b)
		strings.write_string(&b, prev.text)
		strings.write_string(&b, text)
		prev.text = strings.to_string(b)

		return
	}

	append(runs, Text_Run{text = strings.clone(text, allocator), style = style})
}

@(private)
text_tags_push_diagnostic :: proc(
	diagnostics: ^[dynamic]Text_Tag_Diagnostic,
	message: string,
	offset: int,
	allocator: mem.Allocator,
) {
	append(
		diagnostics,
		Text_Tag_Diagnostic{message = strings.clone(message, allocator), offset = offset},
	)
}

@(private)
text_tags_open :: proc(
	stack: ^[dynamic]Text_Run_Tag_Entry,
	body: string,
	offset: int,
) -> bool {
	field: Text_Run_Style_Field
	field_ok: bool

	if strings.has_prefix(body, "c:") {
		value, value_ok := text_tag_parse_value(.color, body[2:])

		if !value_ok do return false

		append(
			stack,
			Text_Run_Tag_Entry{field = .color, value = value, tag = body, offset = offset},
		)

		return true
	}

	colon := strings.index_byte(body, ':')

	if colon >= 0 {
		name := body[:colon]
		value_text := body[colon + 1:]
		field, field_ok = text_tag_field_from_name(name)

		if !field_ok do return false

		value, value_ok := text_tag_parse_value(field, value_text)

		if !value_ok do return false

		append(
			stack,
			Text_Run_Tag_Entry{field = field, value = value, tag = body, offset = offset},
		)

		return true
	}

	field, field_ok = text_tag_field_from_name(body)

	if !field_ok do return false

	value, value_ok := text_tag_parse_value(field, "")

	if !value_ok do return false

	append(stack, Text_Run_Tag_Entry{field = field, value = value, tag = body, offset = offset})

	return true
}

@(private)
text_tag_entry_close_name :: proc(entry: Text_Run_Tag_Entry) -> string {
	colon := strings.index_byte(entry.tag, ':')

	if colon >= 0 do return entry.tag[:colon]

	return entry.tag
}

/*
Parses rich-text tags in `source` into flattened plain text and styled runs.

Open tags use Widget_Config field names: `{field:value}...{/field}`.
Shorthand tags: `{c:name}`, `{b}`, `{i}`, `{u}`.
Close tags must match the most recently opened tag (strict XML-like nesting).
Escape a literal `{` with `\{`.

Only text-applicable fields affect layout and draw; other parsed fields are
retained for tooling such as syntax highlighters.
*/
text_tags_parse :: proc(source: string, allocator: mem.Allocator) -> Text_Tag_Parse {
	if len(source) == 0 do return {}

	runs := make([dynamic]Text_Run, allocator)
	stack := make([dynamic]Text_Run_Tag_Entry, context.temp_allocator)
	defer delete(stack)
	diagnostics := make([dynamic]Text_Tag_Diagnostic, allocator)

	literal := strings.builder_make(context.temp_allocator)
	defer strings.builder_destroy(&literal)

	flush_literal :: proc(
		literal: ^strings.Builder,
		runs: ^[dynamic]Text_Run,
		stack: []Text_Run_Tag_Entry,
		allocator: mem.Allocator,
	) {
		if strings.builder_len(literal^) == 0 do return

		text_runs_push(runs, strings.to_string(literal^), text_run_style_from_stack(stack), allocator)
		strings.builder_reset(literal)
	}

	i := 0

	for i < len(source) {
		if source[i] == '\\' && i + 1 < len(source) && source[i + 1] == '{' {
			strings.write_byte(&literal, '{')
			i += 2

			continue
		}

		if source[i] != '{' {
			strings.write_byte(&literal, source[i])
			i += 1

			continue
		}

		close := i + 1

		for close < len(source) && source[close] != '}' {
			close += 1
		}

		if close >= len(source) {
			text_tags_push_diagnostic(
				&diagnostics,
				fmt.tprintf("unterminated tag starting at offset %d", i),
				i,
				allocator,
			)
			strings.write_byte(&literal, '{')
			i += 1

			continue
		}

		body := source[i + 1:close]
		accepted := false

		flush_literal(&literal, &runs, stack[:], allocator)

		if len(body) > 0 && body[0] == '/' {
			close_body := body[1:]
			close_field, close_name_ok := text_tag_field_from_name(close_body)

			if !close_name_ok {
				text_tags_push_diagnostic(
					&diagnostics,
					fmt.tprintf("unknown close tag {%s}", body),
					i,
					allocator,
				)
			} else if len(stack) == 0 {
				text_tags_push_diagnostic(
					&diagnostics,
					fmt.tprintf("close tag {%s} without matching open tag", body),
					i,
					allocator,
				)
			} else if stack[len(stack) - 1].field != close_field {
				expected := text_tag_entry_close_name(stack[len(stack) - 1])
				text_tags_push_diagnostic(
					&diagnostics,
					fmt.tprintf(
						"mis-nested close tag {%s}; expected {/%s}",
						body,
						expected,
					),
					i,
					allocator,
				)
			} else {
				pop(&stack)
				accepted = true
			}
		} else if text_tags_open(&stack, body, i) {
			accepted = true
		} else {
			text_tags_push_diagnostic(
				&diagnostics,
				fmt.tprintf("unknown or invalid tag {%s}", body),
				i,
				allocator,
			)
		}

		if !accepted {
			tag_text := source[i:close + 1]
			text_runs_push(&runs, tag_text, text_run_style_from_stack(stack[:]), allocator)
		}

		i = close + 1
	}

	flush_literal(&literal, &runs, stack[:], allocator)

	for entry in stack {
		text_tags_push_diagnostic(
			&diagnostics,
			fmt.tprintf("unclosed {%s} tag opened at offset %d", entry.tag, entry.offset),
			entry.offset,
			allocator,
		)
	}

	plain, layout_runs := text_runs_to_layout(runs[:], allocator)

	return {
		plain = plain,
		runs = runs[:],
		layout_runs = layout_runs,
		diagnostics = diagnostics[:],
	}
}
