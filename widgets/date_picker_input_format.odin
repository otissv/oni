package oni_widgets

import "core:fmt"
import "core:strconv"
import "core:strings"

@(private)
Date_Picker_Input_Field :: enum u8 {
	Year,
	Month,
	Day,
}

/*
Parsed date input format: field order + separator.
*/
@(private)
Date_Picker_Input_Format :: struct {
	ok:      bool,
	pattern: string,
	order:   [3]Date_Picker_Input_Field,
	sep:     u8,
}

@(private)
DATE_PICKER_INPUT_DEFAULT_FORMAT :: "YYYY-MM-DD"

@(private)
date_picker_input_field_width :: proc(field: Date_Picker_Input_Field) -> int {
	switch field {
	case .Year:
		return 4
	case .Month, .Day:
		return 2
	}

	return 0
}

@(private)
date_picker_input_token_field :: proc(token: string) -> (Date_Picker_Input_Field, bool) {
	switch token {
	case "YYYY", "yyyy":
		return .Year, true
	case "MM", "mm":
		return .Month, true
	case "DD", "dd":
		return .Day, true
	}

	return {}, false
}

@(private)
date_picker_input_canonical_token :: proc(field: Date_Picker_Input_Field) -> string {
	switch field {
	case .Year:
		return "YYYY"
	case .Month:
		return "MM"
	case .Day:
		return "DD"
	}

	return ""
}

/*
Parses author format strings such as `YYYY-MM-DD` or `DD/MM/YYYY`.

Accepts case-insensitive `YYYY`/`MM`/`DD` tokens separated by a single `-` or `/`.
*/
@(private)
date_picker_input_parse_format :: proc(format: string) -> Date_Picker_Input_Format {
	trimmed := strings.trim_space(format)

	if trimmed == "" {
		return {}
	}

	tokens: [3]string
	seps: [2]u8
	token_count := 0
	sep_count := 0
	i := 0

	for i < len(trimmed) {
		if trimmed[i] == '-' || trimmed[i] == '/' {
			if token_count == 0 || sep_count >= 2 {
				return {}
			}

			seps[sep_count] = trimmed[i]
			sep_count += 1
			i += 1

			continue
		}

		start := i

		for i < len(trimmed) && trimmed[i] != '-' && trimmed[i] != '/' {
			i += 1
		}

		if token_count >= 3 {
			return {}
		}

		tokens[token_count] = trimmed[start:i]
		token_count += 1
	}

	if token_count != 3 || sep_count != 2 {
		return {}
	}

	if seps[0] != seps[1] {
		return {}
	}

	seen: [3]bool
	order: [3]Date_Picker_Input_Field

	for ti in 0 ..< 3 {
		field, field_ok := date_picker_input_token_field(tokens[ti])

		if !field_ok {
			return {}
		}

		idx := int(field)

		if seen[idx] {
			return {}
		}

		seen[idx] = true
		order[ti] = field
	}

	if !seen[0] || !seen[1] || !seen[2] {
		return {}
	}

	pattern := fmt.tprintf(
		"%s%c%s%c%s",
		date_picker_input_canonical_token(order[0]),
		seps[0],
		date_picker_input_canonical_token(order[1]),
		seps[0],
		date_picker_input_canonical_token(order[2]),
	)

	return Date_Picker_Input_Format{ok = true, pattern = pattern, order = order, sep = seps[0]}
}

/*
Resolves an author format string, defaulting invalid/empty to `YYYY-MM-DD`.
*/
@(private)
date_picker_input_resolve_format :: proc(format: string) -> Date_Picker_Input_Format {
	parsed := date_picker_input_parse_format(format)

	if parsed.ok {
		return parsed
	}

	return date_picker_input_parse_format(DATE_PICKER_INPUT_DEFAULT_FORMAT)
}

@(private)
date_picker_input_extract_digits :: proc(
	text: string,
	allocator := context.temp_allocator,
) -> string {
	b := strings.builder_make(allocator)

	for r in text {
		if r >= '0' && r <= '9' {
			strings.write_rune(&b, r)
		}
	}

	return strings.to_string(b)
}

/*
Keeps digits and rebuilds the formatted mask for `format`.

Non-digits are dropped; separators are normalized to the format separator.
*/
@(private)
date_picker_input_sanitize_text :: proc(text: string, format: Date_Picker_Input_Format) -> string {
	if !format.ok {
		return ""
	}

	digits := date_picker_input_extract_digits(text)

	if digits == "" {
		return ""
	}

	b := strings.builder_make(context.temp_allocator)
	offset := 0

	for fi in 0 ..< 3 {
		width := date_picker_input_field_width(format.order[fi])
		remaining := len(digits) - offset

		if remaining <= 0 {
			break
		}

		take := width

		if take > remaining {
			take = remaining
		}

		if fi > 0 {
			strings.write_byte(&b, format.sep)
		}

		strings.write_string(&b, digits[offset:offset + take])
		offset += take
	}

	return strings.to_string(b)
}

/*
Formats a civil date with the resolved input format.
*/
@(private)
date_picker_input_format_date :: proc(
	date: Calendar_Date,
	format: Date_Picker_Input_Format,
	allocator := context.temp_allocator,
) -> string {
	if !format.ok || !Calendar_Date_Valid(date) {
		return ""
	}

	parts: [3]string

	for fi in 0 ..< 3 {
		switch format.order[fi] {
		case .Year:
			parts[fi] = fmt.tprintf("%04d", date.year)
		case .Month:
			parts[fi] = fmt.tprintf("%02d", int(date.month))
		case .Day:
			parts[fi] = fmt.tprintf("%02d", int(date.day))
		}
	}

	return fmt.aprintf(
		"%s%c%s%c%s",
		parts[0],
		format.sep,
		parts[1],
		format.sep,
		parts[2],
		allocator = allocator,
	)
}

@(private)
date_picker_input_parse_field_int :: proc(
	text: string,
	field: Date_Picker_Input_Field,
) -> (
	int,
	bool,
) {
	width := date_picker_input_field_width(field)

	if len(text) != width {
		return 0, false
	}

	for ch in text {
		if ch < '0' || ch > '9' {
			return 0, false
		}
	}

	value, ok := strconv.parse_int(text)

	return value, ok
}

@(private)
date_picker_input_sep_string :: proc(sep: u8) -> string {
	switch sep {
	case '-':
		return "-"
	case '/':
		return "/"
	}

	return fmt.tprintf("%c", sep)
}

/*
Parses a complete date string for `format`. Partial/invalid values return ok=false.
*/
@(private)
date_picker_input_parse_date :: proc(
	text: string,
	format: Date_Picker_Input_Format,
) -> (
	date: Calendar_Date,
	ok: bool,
) {
	if !format.ok {
		return {}, false
	}

	trimmed := strings.trim_space(text)

	if trimmed == "" {
		return {}, false
	}

	sanitized := date_picker_input_sanitize_text(trimmed, format)

	if sanitized == "" {
		return {}, false
	}

	sep := date_picker_input_sep_string(format.sep)
	parts := strings.split(sanitized, sep, context.temp_allocator)

	if len(parts) != 3 {
		return {}, false
	}

	year: int
	month: int
	day: int
	have_y: bool
	have_m: bool
	have_d: bool

	for fi in 0 ..< 3 {
		value, value_ok := date_picker_input_parse_field_int(parts[fi], format.order[fi])

		if !value_ok {
			return {}, false
		}

		switch format.order[fi] {
		case .Year:
			year = value
			have_y = true
		case .Month:
			month = value
			have_m = true
		case .Day:
			day = value
			have_d = true
		}
	}

	if !have_y || !have_m || !have_d {
		return {}, false
	}

	date = {
		year  = i64(year),
		month = i8(month),
		day   = i8(day),
	}

	if !Calendar_Date_Valid(date) {
		return {}, false
	}

	return date, true
}

/*
Stores the author format string on the picker runtime (heap-owned).
*/
@(private)
date_picker_input_sync_runtime_format :: proc(picker_key: string, format: string) {
	rt := date_picker_runtime_ensure(picker_key)

	if rt == nil {
		return
	}

	resolved := strings.trim_space(format)

	if resolved == "" {
		resolved = DATE_PICKER_INPUT_DEFAULT_FORMAT
	}

	date_picker_runtime_set_string(&rt.input_format, resolved)
}

@(private)
date_picker_input_runtime_format :: proc(picker_key: string) -> Date_Picker_Input_Format {
	format := DATE_PICKER_INPUT_DEFAULT_FORMAT

	if picker_key != "" {
		if rt := date_picker_runtime_ensure(picker_key); rt != nil && rt.input_format != "" {
			format = rt.input_format
		}
	}

	return date_picker_input_resolve_format(format)
}
