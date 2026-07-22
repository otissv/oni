package oni

import "core:math"
import "core:strings"
import "core:unicode/utf8"

TEXT_EDIT_BLINK_PERIOD :: f32(1.0)

Text_Selection_Rect :: struct {
	rect:       Rect,
	line_index: int,
}

Text_Caret_Geometry :: struct {
	x, y, height: f32,
	line_index:   int,
}

text_edit_selection_start :: proc(sel: Text_Selection) -> int {
	return min(sel.anchor, sel.head)
}

text_edit_selection_end :: proc(sel: Text_Selection) -> int {
	return max(sel.anchor, sel.head)
}

text_edit_selection_active :: proc(sel: Text_Selection) -> bool {
	return sel.anchor != sel.head
}

text_edit_selection_normalized :: proc(sel: Text_Selection) -> (start, end: int) {
	return text_edit_selection_start(sel), text_edit_selection_end(sel)
}

text_edit_cluster_prev :: proc(text: string, offset: int) -> int {
	if offset <= 0 do return 0

	i := offset

	for i > 0 {
		i -= 1

		if (text[i] & 0xC0) != 0x80 do break
	}

	return i
}

text_edit_cluster_next :: proc(text: string, offset: int) -> int {
	if offset >= len(text) do return len(text)

	_, w := utf8.decode_rune_in_string(text[offset:])

	if w == 0 do return len(text)

	return offset + w
}

text_edit_clamp_offset :: proc(text: string, offset: int) -> int {
	return clamp(offset, 0, len(text))
}

text_edit_line_at :: proc(geo: ^Text_Edit_Geometry, offset: int) -> int {
	if geo == nil || len(geo.glyphs) == 0 do return 0

	clamped := text_edit_clamp_offset(geo.plain, offset)
	best := geo.glyphs[0].line_index

	for glyph in geo.glyphs {
		if glyph.cluster <= clamped {
			best = glyph.line_index
		}
	}

	return best
}

text_edit_hit_test :: proc(
	geo: ^Text_Edit_Geometry,
	layout_rect: Rect,
	scroll: Vec2,
	local: Vec2,
) -> int {
	if geo == nil || len(geo.glyphs) == 0 do return 0

	x := layout_rect.x - scroll.x + local.x
	y := layout_rect.y - scroll.y + local.y
	line_count := len(geo.line_origins)
	if line_count == 0 do return 0

	line_i := 0
	for i in 0 ..< line_count {
		origin := geo.line_origins[i]
		line_y := layout_rect.y - scroll.y + origin.y
		if y >= line_y {
			line_i = i
		}
	}

	best_offset := len(geo.plain)
	best_dist: f32 = max(f32)

	for glyph in geo.glyphs {
		if glyph.line_index != line_i do continue

		mid := (glyph.x0 + glyph.x1) * 0.5
		dist := abs(x - mid)

		if dist < best_dist {
			best_dist = dist
			if x <= mid {
				best_offset = glyph.cluster
			} else {
				best_offset = text_edit_cluster_next(geo.plain, glyph.cluster)
			}
		}
	}

	return text_edit_clamp_offset(geo.plain, best_offset)
}

text_edit_caret_geometry :: proc(
	geo: ^Text_Edit_Geometry,
	layout_rect: Rect,
	scroll: Vec2,
	offset: int,
) -> Text_Caret_Geometry {
	result: Text_Caret_Geometry

	if geo == nil do return result

	clamped := text_edit_clamp_offset(geo.plain, offset)
	line_i := text_edit_line_at(geo, clamped)
	result.line_index = line_i

	if line_i < len(geo.line_origins) {
		origin := geo.line_origins[line_i]
		result.y = layout_rect.y - scroll.y + origin.y
	}

	caret_x := layout_rect.x - scroll.x
	height := geo.line_height
	ascent := geo.line_height * 0.8
	descent := geo.line_height * 0.2
	found := false

	for glyph in geo.glyphs {
		if glyph.line_index != line_i do continue

		if glyph.cluster < clamped {
			caret_x = glyph.x1
			ascent = glyph.ascent
			descent = glyph.descent
			found = true
		} else if glyph.cluster == clamped {
			caret_x = glyph.x0
			ascent = glyph.ascent
			descent = glyph.descent
			found = true

			break
		}
	}

	if !found {
		for glyph in geo.glyphs {
			if glyph.line_index == line_i {
				caret_x = glyph.x1
				ascent = glyph.ascent
				descent = glyph.descent
			}
		}
	}

	result.x = caret_x
	result.height = max(ascent + descent, height)

	return result
}

text_edit_selection_rects :: proc(
	geo: ^Text_Edit_Geometry,
	layout_rect: Rect,
	scroll: Vec2,
	sel: Text_Selection,
	allocator := context.temp_allocator,
) -> []Text_Selection_Rect {
	if geo == nil || !text_edit_selection_active(sel) do return nil

	start, end := text_edit_selection_normalized(sel)
	if start == end do return nil

	out := make([dynamic]Text_Selection_Rect, allocator)
	line_count := len(geo.line_origins)

	for line_i in 0 ..< line_count {
		x0: f32 = -1
		x1: f32 = -1
		origin := geo.line_origins[line_i]
		line_y := layout_rect.y - scroll.y + origin.y

		for glyph in geo.glyphs {
			if glyph.line_index != line_i do continue

			glyph_start := glyph.cluster
			glyph_end := text_edit_cluster_next(geo.plain, glyph.cluster)

			if glyph_end <= start || glyph_start >= end do continue

			if x0 < 0 do x0 = glyph.x0
			x1 = glyph.x1
		}

		if x0 >= 0 && x1 > x0 {
			append(
				&out,
				Text_Selection_Rect {
					rect = {x0, line_y, x1 - x0, geo.line_height},
					line_index = line_i,
				},
			)
		}
	}

	return out[:]
}

text_edit_draw_overlay :: proc(
	geo: ^Text_Edit_Geometry,
	layout_rect: Rect,
	scroll: Vec2,
	sel: Text_Selection,
	caret_offset: int,
	selection_color, caret_color: RGBA,
	show_caret, caret_visible: bool,
) {
	if geo == nil do return

	for item in text_edit_selection_rects(geo, layout_rect, scroll, sel) {
		draw_rect(item.rect, selection_color)
	}

	if show_caret && caret_visible {
		caret := text_edit_caret_geometry(geo, layout_rect, scroll, caret_offset)
		caret_rect := Rect{caret.x, caret.y, 1, caret.height}
		draw_rect(caret_rect, caret_color)
	}
}

text_edit_select_all :: proc(text: string) -> Text_Selection {
	return {anchor = 0, head = len(text)}
}

@(private)
unicode_is_word_rune :: proc(r: rune) -> bool {
	if r == '_' do return true

	return (r >= '0' && r <= '9') ||
	       (r >= 'A' && r <= 'Z') ||
	       (r >= 'a' && r <= 'z')
}

text_edit_word_at :: proc(text: string, offset: int) -> Text_Selection {
	clamped := text_edit_clamp_offset(text, offset)
	start := clamped
	end := clamped

	for start > 0 {
		r, w := utf8.decode_last_rune_in_string(text[:start])
		if w == 0 do break
		if !unicode_is_word_rune(r) do break
		start -= w
	}

	for end < len(text) {
		r, w := utf8.decode_rune_in_string(text[end:])
		if w == 0 do break
		if !unicode_is_word_rune(r) do break
		end += w
	}

	return {anchor = start, head = end}
}

text_edit_line_range_at :: proc(geo: ^Text_Edit_Geometry, offset: int) -> Text_Selection {
	if geo == nil || len(geo.glyphs) == 0 do return {}

	line_i := text_edit_line_at(geo, offset)
	start := len(geo.plain)
	end := 0

	for glyph in geo.glyphs {
		if glyph.line_index != line_i do continue
		start = min(start, glyph.cluster)
		end = max(end, text_edit_cluster_next(geo.plain, glyph.cluster))
	}

	if start > end do return {anchor = 0, head = len(geo.plain)}

	return {anchor = start, head = end}
}

text_edit_plain_splice :: proc(
	text: string,
	start, end: int,
	insert: string,
	allocator := context.allocator,
) -> (
	new_text: string,
	new_caret: int,
) {
	start_idx := clamp(start, 0, len(text))
	end_idx := clamp(end, 0, len(text))
	if start_idx > end_idx {
		start_idx, end_idx = end_idx, start_idx
	}

	b := strings.builder_make(allocator)
	strings.write_string(&b, text[:start_idx])
	strings.write_string(&b, insert)
	strings.write_string(&b, text[end_idx:])

	return strings.to_string(b), start_idx + len(insert)
}

text_edit_copy_plain :: proc(text: string, sel: Text_Selection) -> bool {
	start, end := text_edit_selection_normalized(sel)
	if start == end do return false

	return clipboard_set_text(text[start:end])
}

text_edit_undo_stack_init :: proc(stack: ^Text_Undo_Stack) {
	stack.limit = TEXT_UNDO_STACK_LIMIT
}

text_edit_undo_clear :: proc(stack: ^Text_Undo_Stack) {
	if stack.entries != nil {
		for entry in stack.entries {
			delete(entry.text)
		}
		delete(stack.entries)
	}
	stack^ = {}
	text_edit_undo_stack_init(stack)
}

text_edit_undo_push :: proc(
	stack: ^Text_Undo_Stack,
	text: string,
	caret: int,
	selection: Text_Selection,
	frame: u64,
) {
	if stack.limit <= 0 do text_edit_undo_stack_init(stack)

	if stack.pushed_frame == frame && len(stack.entries) > 0 {
		return
	}

	entry := Text_Undo_Entry {
		text      = strings.clone(text),
		caret     = caret,
		selection = selection,
	}
	append(&stack.entries, entry)
	stack.pushed_frame = frame

	for len(stack.entries) > stack.limit {
		old := stack.entries[0]
		delete(old.text)
		ordered_remove(&stack.entries, 0)
	}
}

text_edit_undo_pop :: proc(stack: ^Text_Undo_Stack) -> (entry: Text_Undo_Entry, ok: bool) {
	if len(stack.entries) == 0 do return {}, false

	entry = stack.entries[len(stack.entries) - 1]
	ordered_remove(&stack.entries, len(stack.entries) - 1)
	stack.pushed_frame = 0

	return entry, true
}

text_edit_backspace :: proc(
	text: string,
	caret: int,
	selection: Text_Selection,
	allocator := context.allocator,
) -> (
	new_text: string,
	new_caret: int,
	new_selection: Text_Selection,
	changed: bool,
) {
	if text_edit_selection_active(selection) {
		start, end := text_edit_selection_normalized(selection)
		new_text, new_caret = text_edit_plain_splice(text, start, end, "", allocator)
		new_selection = {anchor = start, head = start}
		changed = true

		return
	}

	if caret <= 0 {
		new_text = text
		new_caret = caret
		new_selection = selection

		return
	}

	prev := text_edit_cluster_prev(text, caret)
	new_text, new_caret = text_edit_plain_splice(text, prev, caret, "", allocator)
	new_selection = {anchor = prev, head = prev}
	changed = true

	return
}

text_edit_delete :: proc(
	text: string,
	caret: int,
	selection: Text_Selection,
	allocator := context.allocator,
) -> (
	new_text: string,
	new_caret: int,
	new_selection: Text_Selection,
	changed: bool,
) {
	if text_edit_selection_active(selection) {
		start, end := text_edit_selection_normalized(selection)
		new_text, new_caret = text_edit_plain_splice(text, start, end, "", allocator)
		new_selection = {anchor = start, head = start}
		changed = true

		return
	}

	if caret >= len(text) {
		new_text = text
		new_caret = caret
		new_selection = selection

		return
	}

	next := text_edit_cluster_next(text, caret)
	new_text, new_caret = text_edit_plain_splice(text, caret, next, "", allocator)
	new_selection = {anchor = caret, head = caret}
	changed = true

	return
}

text_edit_handle_key_navigation :: proc(
	text: string,
	caret: int,
	selection: Text_Selection,
	geo: ^Text_Edit_Geometry,
	key: Scancode,
	shift: bool,
) -> (
	new_caret: int,
	new_selection: Text_Selection,
	handled: bool,
) {
	new_caret = caret
	new_selection = selection

	#partial switch key {
	case .LEFT:
		handled = true
		if shift {
			if !text_edit_selection_active(selection) {
				new_selection = {anchor = caret, head = caret}
			}
			new_caret = text_edit_cluster_prev(text, caret)
			new_selection.head = new_caret
		} else {
			if text_edit_selection_active(selection) {
				new_caret = text_edit_selection_start(selection)
			} else {
				new_caret = text_edit_cluster_prev(text, caret)
			}
			new_selection = {anchor = new_caret, head = new_caret}
		}
	case .RIGHT:
		handled = true
		if shift {
			if !text_edit_selection_active(selection) {
				new_selection = {anchor = caret, head = caret}
			}
			new_caret = text_edit_cluster_next(text, caret)
			new_selection.head = new_caret
		} else {
			if text_edit_selection_active(selection) {
				new_caret = text_edit_selection_end(selection)
			} else {
				new_caret = text_edit_cluster_next(text, caret)
			}
			new_selection = {anchor = new_caret, head = new_caret}
		}
	case .HOME:
		handled = true
		new_caret = 0
		if shift {
			new_selection.head = new_caret
		} else {
			new_selection = {anchor = new_caret, head = new_caret}
		}
	case .END:
		handled = true
		new_caret = len(text)
		if shift {
			new_selection.head = new_caret
		} else {
			new_selection = {anchor = new_caret, head = new_caret}
		}
	}

	_ = geo

	return new_caret, new_selection, handled
}

text_edit_consume_command :: proc() -> Text_Edit_Command {
	if w_ctx == nil do return .NONE

	cmd := w_ctx.text_edit_command
	w_ctx.text_edit_command = .NONE

	return cmd
}

text_edit_set_command :: proc(cmd: Text_Edit_Command) {
	if w_ctx == nil do return

	w_ctx.text_edit_command = cmd
}

text_edit_caret_visible :: proc(blink_phase: f32) -> bool {
	return math.mod(blink_phase, TEXT_EDIT_BLINK_PERIOD) < TEXT_EDIT_BLINK_PERIOD * 0.5
}

text_edit_update_blink :: proc(blink_phase: f32, dt: f32, focused: bool) -> f32 {
	if !focused do return 0

	return blink_phase + dt
}

text_edit_pointer_selection :: proc(
	geo: ^Text_Edit_Geometry,
	layout_rect: Rect,
	scroll: Vec2,
	local: Vec2,
	shift: bool,
	caret: int,
	selection: Text_Selection,
) -> (
	new_caret: int,
	new_selection: Text_Selection,
) {
	offset := text_edit_hit_test(geo, layout_rect, scroll, local)

	if shift {
		if !text_edit_selection_active(selection) {
			return offset, {anchor = caret, head = offset}
		}

		return offset, {anchor = selection.anchor, head = offset}
	}

	return offset, {anchor = offset, head = offset}
}

text_edit_register_click :: proc(
	edit: ^Text_Edit_State,
	local: Vec2,
	now: f64,
	geo: ^Text_Edit_Geometry,
	layout_rect: Rect,
	scroll: Vec2,
	text: string,
) -> (
	caret: int,
	selection: Text_Selection,
) {
	offset := text_edit_hit_test(geo, layout_rect, scroll, local)
	dist := local.x - edit.last_click_pos.x + local.y - edit.last_click_pos.y

	if now - edit.last_click_time < 0.4 && abs(dist) < 4 {
		edit.click_count += 1
	} else {
		edit.click_count = 1
	}

	edit.last_click_time = now
	edit.last_click_pos = local

	switch edit.click_count {
	case 2:
		selection = text_edit_word_at(text, offset)
	case 3:
		selection = text_edit_line_range_at(geo, offset)
	case:
		selection = {anchor = offset, head = offset}
	}

	caret = selection.head

	return caret, selection
}
