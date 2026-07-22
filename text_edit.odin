package oni

import "core:math"
import "core:strings"
import "core:unicode/utf8"

TEXT_EDIT_BLINK_PERIOD :: f32(1.0)
TEXT_EDIT_SCROLL_MARGIN :: f32(4)
TEXT_EDIT_DRAG_SCROLL_EDGE :: f32(24)
TEXT_EDIT_DRAG_SCROLL_MAX_SPEED :: f32(14)

Text_Edit_Content_Bounds :: struct {
	x0, y0, x1, y1: f32,
}

Text_Edit_Scroll_Axes :: struct {
	x, y: bool,
}

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

@(private)
text_edit_hard_line_index :: proc(plain: string, offset: int) -> int {
	clamped := text_edit_clamp_offset(plain, offset)
	line := 0

	for i in 0 ..< clamped {
		if plain[i] == '\n' {
			line += 1
		}
	}

	return line
}

@(private)
text_edit_offset_for_line :: proc(plain: string, line_i: int) -> int {
	current_line := 0

	for i in 0 ..< len(plain) {
		if current_line == line_i {
			return i
		}

		if plain[i] == '\n' {
			current_line += 1
		}
	}

	return len(plain)
}

@(private)
text_edit_paragraph_bounds :: proc(plain: string, offset: int) -> (start, end: int) {
	clamped := text_edit_clamp_offset(plain, offset)
	start = 0

	for i in 0 ..< clamped {
		if plain[i] == '\n' {
			start = i + 1
		}
	}

	end = len(plain)

	for i in start ..< len(plain) {
		if plain[i] == '\n' {
			end = i

			break
		}
	}

	return
}

text_edit_line_at :: proc(geo: ^Text_Edit_Geometry, offset: int) -> int {
	if geo == nil do return 0

	line_count := len(geo.line_origins)
	if line_count == 0 do return 0

	clamped := text_edit_clamp_offset(geo.plain, offset)
	hard_line := text_edit_hard_line_index(geo.plain, clamped)
	para_start, para_end := text_edit_paragraph_bounds(geo.plain, clamped)

	if clamped >= para_start && para_start >= para_end {
		return min(hard_line, line_count - 1)
	}

	if len(geo.glyphs) == 0 {
		return min(hard_line, line_count - 1)
	}

	best := hard_line
	found_glyph := false

	for glyph in geo.glyphs {
		if glyph.cluster < para_start || glyph.cluster >= para_end do continue

		if glyph.cluster <= clamped {
			best = glyph.line_index
			found_glyph = true
		}
	}

	if found_glyph {
		return min(best, line_count - 1)
	}

	return min(hard_line, line_count - 1)
}

text_edit_hit_test :: proc(
	geo: ^Text_Edit_Geometry,
	layout_rect: Rect,
	scroll: Vec2,
	local: Vec2,
) -> int {
	if geo == nil do return 0

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

	best_offset := text_edit_offset_for_line(geo.plain, line_i)
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

	result.x = caret_x - scroll.x
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
					rect = {x0 - scroll.x, line_y, x1 - x0, geo.line_height},
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
	if geo == nil do return {}

	line_count := len(geo.line_origins)
	if line_count == 0 do return {}

	line_i := text_edit_line_at(geo, offset)
	start := len(geo.plain)
	end := 0

	for glyph in geo.glyphs {
		if glyph.line_index != line_i do continue
		start = min(start, glyph.cluster)
		end = max(end, text_edit_cluster_next(geo.plain, glyph.cluster))
	}

	if start > end {
		start = text_edit_offset_for_line(geo.plain, line_i)
		end = start

		for i in start ..< len(geo.plain) {
			if geo.plain[i] == '\n' {
				end = i

				break
			}
		}

		if end == start && start < len(geo.plain) && geo.plain[start] != '\n' {
			end = len(geo.plain)
		}
	}

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

text_edit_clamp_selection :: proc(text: string, sel: Text_Selection) -> Text_Selection {
	return {
		anchor = text_edit_clamp_offset(text, sel.anchor),
		head = text_edit_clamp_offset(text, sel.head),
	}
}

text_edit_within_max_length :: proc(text: string, max_length: int, insert: string) -> bool {
	if max_length <= 0 do return true

	return len(text) + len(insert) <= max_length
}

text_edit_scroll_axes :: proc(overflow_x, overflow_y: Overflow) -> Text_Edit_Scroll_Axes {
	return {
		x = layout_node_scrolls_axis(overflow_x),
		y = layout_node_scrolls_axis(overflow_y),
	}
}

text_edit_caret_content_x :: proc(geo: ^Text_Edit_Geometry, caret: int) -> f32 {
	if geo == nil do return 0

	line_i := text_edit_line_at(geo, caret)

	for glyph in geo.glyphs {
		if glyph.line_index != line_i do continue

		if glyph.cluster < caret {
			continue
		}

		if glyph.cluster == caret {
			return glyph.x0
		}

		break
	}

	last_x: f32

	for glyph in geo.glyphs {
		if glyph.line_index == line_i {
			last_x = glyph.x1
		}
	}

	return last_x
}

text_edit_offset_at_line_x :: proc(geo: ^Text_Edit_Geometry, line_i: int, x: f32) -> int {
	if geo == nil do return 0

	line_count := len(geo.line_origins)
	if line_count == 0 do return 0

	target_line := clamp(line_i, 0, line_count - 1)
	best_offset := text_edit_offset_for_line(geo.plain, target_line)
	best_dist: f32 = max(f32)
	found_glyph := false

	for glyph in geo.glyphs {
		if glyph.line_index != target_line do continue

		found_glyph = true
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

	if !found_glyph {
		return text_edit_offset_for_line(geo.plain, target_line)
	}

	return text_edit_clamp_offset(geo.plain, best_offset)
}

text_edit_merge_content_bounds :: proc(a, b: Text_Edit_Content_Bounds) -> Text_Edit_Content_Bounds {
	if a.x1 < a.x0 do return b
	if b.x1 < b.x0 do return a

	return {
		x0 = min(a.x0, b.x0),
		y0 = min(a.y0, b.y0),
		x1 = max(a.x1, b.x1),
		y1 = max(a.y1, b.y1),
	}
}

text_edit_caret_content_bounds :: proc(geo: ^Text_Edit_Geometry, caret: int) -> Text_Edit_Content_Bounds {
	if geo == nil do return {}

	line_i := text_edit_line_at(geo, caret)
	y0: f32
	y1 := geo.line_height

	if line_i < len(geo.line_origins) {
		y0 = geo.line_origins[line_i].y
		y1 = y0 + geo.line_height
	}

	x := text_edit_caret_content_x(geo, caret)

	return {x0 = x, y0 = y0, x1 = x + 1, y1 = y1}
}

text_edit_selection_content_bounds :: proc(
	geo: ^Text_Edit_Geometry,
	sel: Text_Selection,
) -> Text_Edit_Content_Bounds {
	if geo == nil || !text_edit_selection_active(sel) do return {}

	start, end := text_edit_selection_normalized(sel)
	if start == end do return {}

	bounds: Text_Edit_Content_Bounds
	empty := true
	line_count := len(geo.line_origins)

	for line_i in 0 ..< line_count {
		x0: f32 = -1
		x1: f32 = -1

		for glyph in geo.glyphs {
			if glyph.line_index != line_i do continue

			glyph_start := glyph.cluster
			glyph_end := text_edit_cluster_next(geo.plain, glyph.cluster)

			if glyph_end <= start || glyph_start >= end do continue

			if x0 < 0 do x0 = glyph.x0
			x1 = glyph.x1
		}

		if x0 >= 0 && x1 > x0 {
			origin := geo.line_origins[line_i]
			line_bounds := Text_Edit_Content_Bounds {
				x0 = x0,
				y0 = origin.y,
				x1 = x1,
				y1 = origin.y + geo.line_height,
			}

			if empty {
				bounds = line_bounds
				empty = false
			} else {
				bounds = text_edit_merge_content_bounds(bounds, line_bounds)
			}
		}
	}

	return bounds
}

text_edit_edit_content_bounds :: proc(
	geo: ^Text_Edit_Geometry,
	caret: int,
	sel: Text_Selection,
) -> Text_Edit_Content_Bounds {
	bounds := text_edit_caret_content_bounds(geo, caret)

	if text_edit_selection_active(sel) {
		sel_bounds := text_edit_selection_content_bounds(geo, sel)
		bounds = text_edit_merge_content_bounds(bounds, sel_bounds)
	}

	return bounds
}

text_edit_scroll_to_show_bounds :: proc(
	scroll: ^Vec2,
	viewport, max_scroll: Vec2,
	bounds: Text_Edit_Content_Bounds,
	margin: f32,
	axes: Text_Edit_Scroll_Axes,
) {
	if scroll == nil do return
	if bounds.x1 < bounds.x0 || bounds.y1 < bounds.y0 do return

	if axes.y {
		if bounds.y0 < scroll.y + margin {
			scroll.y = scroll_clamp_axis(bounds.y0 - margin, max_scroll.y)
		}

		if bounds.y1 > scroll.y + viewport.y - margin {
			scroll.y = scroll_clamp_axis(bounds.y1 - viewport.y + margin, max_scroll.y)
		}
	}

	if axes.x {
		if bounds.x0 < scroll.x + margin {
			scroll.x = scroll_clamp_axis(bounds.x0 - margin, max_scroll.x)
		}

		if bounds.x1 > scroll.x + viewport.x - margin {
			scroll.x = scroll_clamp_axis(bounds.x1 - viewport.x + margin, max_scroll.x)
		}
	}
}

text_edit_scroll_to_show_edit :: proc(
	scroll: ^Vec2,
	geo: ^Text_Edit_Geometry,
	caret: int,
	sel: Text_Selection,
	viewport, max_scroll: Vec2,
	overflow_x, overflow_y: Overflow,
) {
	if scroll == nil || geo == nil do return

	bounds := text_edit_edit_content_bounds(geo, caret, sel)
	axes := text_edit_scroll_axes(overflow_x, overflow_y)
	text_edit_scroll_to_show_bounds(
		scroll,
		viewport,
		max_scroll,
		bounds,
		TEXT_EDIT_SCROLL_MARGIN,
		axes,
	)
}

text_edit_drag_scroll_step :: proc(
	layout_id: UI_Id,
	scroll: ^Vec2,
	max_scroll: Vec2,
	overflow_x, overflow_y: Overflow,
) -> bool {
	if scroll == nil || w_ctx == nil do return false

	clip := ui_layout_clip_rect(layout_id)
	if clip.w <= 0 || clip.h <= 0 do return false

	axes := text_edit_scroll_axes(overflow_x, overflow_y)
	if !axes.x && !axes.y do return false

	edge := TEXT_EDIT_DRAG_SCROLL_EDGE
	speed := TEXT_EDIT_DRAG_SCROLL_MAX_SPEED
	mx := w_ctx.mouse_x
	my := w_ctx.mouse_y
	changed := false

	if axes.y && max_scroll.y > 0 {
		if my < clip.y + edge {
			t := clamp((clip.y + edge - my) / edge, 0, 1)
			next := scroll_clamp_axis(scroll.y - t * speed, max_scroll.y)

			if next != scroll.y {
				scroll.y = next
				changed = true
			}
		} else if my > clip.y + clip.h - edge {
			t := clamp((my - (clip.y + clip.h - edge)) / edge, 0, 1)
			next := scroll_clamp_axis(scroll.y + t * speed, max_scroll.y)

			if next != scroll.y {
				scroll.y = next
				changed = true
			}
		}
	}

	if axes.x && max_scroll.x > 0 {
		if mx < clip.x + edge {
			t := clamp((clip.x + edge - mx) / edge, 0, 1)
			next := scroll_clamp_axis(scroll.x - t * speed, max_scroll.x)

			if next != scroll.x {
				scroll.x = next
				changed = true
			}
		} else if mx > clip.x + clip.w - edge {
			t := clamp((mx - (clip.x + clip.w - edge)) / edge, 0, 1)
			next := scroll_clamp_axis(scroll.x + t * speed, max_scroll.x)

			if next != scroll.x {
				scroll.x = next
				changed = true
			}
		}
	}

	return changed
}

text_edit_page_line_count :: proc(geo: ^Text_Edit_Geometry, viewport_h: f32) -> int {
	if geo == nil || geo.line_height <= 0 do return 1

	lines := int(viewport_h / geo.line_height)

	return max(1, lines - 1)
}

text_edit_set_preferred_column :: proc(
	edit: ^Text_Edit_State,
	geo: ^Text_Edit_Geometry,
	caret: int,
) {
	if edit == nil || geo == nil do return

	edit.preferred_column = text_edit_caret_content_x(geo, caret)
	edit.has_preferred_column = true
}

text_edit_preferred_column :: proc(edit: ^Text_Edit_State, geo: ^Text_Edit_Geometry, caret: int) -> f32 {
	if edit != nil && edit.has_preferred_column {
		return edit.preferred_column
	}

	return text_edit_caret_content_x(geo, caret)
}

text_edit_move_to_line :: proc(
	geo: ^Text_Edit_Geometry,
	line_i: int,
	preferred_x: f32,
) -> int {
	if geo == nil do return 0

	line_count := len(geo.line_origins)
	if line_count == 0 do return 0

	target_line := clamp(line_i, 0, line_count - 1)

	return text_edit_offset_at_line_x(geo, target_line, preferred_x)
}

text_edit_handle_key_navigation :: proc(
	text: string,
	caret: int,
	selection: Text_Selection,
	geo: ^Text_Edit_Geometry,
	key: Scancode,
	shift: bool,
	ctrl: bool,
	multiline: bool,
	page_lines: int,
	edit: ^Text_Edit_State,
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

		text_edit_set_preferred_column(edit, geo, new_caret)
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

		text_edit_set_preferred_column(edit, geo, new_caret)
	case .UP:
		if geo == nil || !multiline do break

		handled = true
		line_i := text_edit_line_at(geo, caret)
		preferred_x := text_edit_preferred_column(edit, geo, caret)
		new_caret = text_edit_move_to_line(geo, line_i - 1, preferred_x)

		if shift {
			if !text_edit_selection_active(selection) {
				new_selection = {anchor = caret, head = new_caret}
			} else {
				new_selection.head = new_caret
			}
		} else {
			new_selection = {anchor = new_caret, head = new_caret}
		}

		text_edit_set_preferred_column(edit, geo, new_caret)
	case .DOWN:
		if geo == nil || !multiline do break

		handled = true
		line_i := text_edit_line_at(geo, caret)
		preferred_x := text_edit_preferred_column(edit, geo, caret)
		new_caret = text_edit_move_to_line(geo, line_i + 1, preferred_x)

		if shift {
			if !text_edit_selection_active(selection) {
				new_selection = {anchor = caret, head = new_caret}
			} else {
				new_selection.head = new_caret
			}
		} else {
			new_selection = {anchor = new_caret, head = new_caret}
		}

		text_edit_set_preferred_column(edit, geo, new_caret)
	case .PAGEUP:
		if geo == nil || !multiline do break

		handled = true
		line_i := text_edit_line_at(geo, caret)
		preferred_x := text_edit_preferred_column(edit, geo, caret)
		new_caret = text_edit_move_to_line(geo, line_i - page_lines, preferred_x)

		if shift {
			if !text_edit_selection_active(selection) {
				new_selection = {anchor = caret, head = new_caret}
			} else {
				new_selection.head = new_caret
			}
		} else {
			new_selection = {anchor = new_caret, head = new_caret}
		}

		text_edit_set_preferred_column(edit, geo, new_caret)
	case .PAGEDOWN:
		if geo == nil || !multiline do break

		handled = true
		line_i := text_edit_line_at(geo, caret)
		preferred_x := text_edit_preferred_column(edit, geo, caret)
		new_caret = text_edit_move_to_line(geo, line_i + page_lines, preferred_x)

		if shift {
			if !text_edit_selection_active(selection) {
				new_selection = {anchor = caret, head = new_caret}
			} else {
				new_selection.head = new_caret
			}
		} else {
			new_selection = {anchor = new_caret, head = new_caret}
		}

		text_edit_set_preferred_column(edit, geo, new_caret)
	case .HOME:
		handled = true

		if geo != nil && multiline && !ctrl {
			line := text_edit_line_range_at(geo, caret)
			new_caret = line.anchor
		} else {
			new_caret = 0
		}

		if shift {
			if !text_edit_selection_active(selection) {
				new_selection = {anchor = caret, head = new_caret}
			} else {
				new_selection.head = new_caret
			}
		} else {
			new_selection = {anchor = new_caret, head = new_caret}
		}

		text_edit_set_preferred_column(edit, geo, new_caret)
	case .END:
		handled = true

		if geo != nil && multiline && !ctrl {
			line := text_edit_line_range_at(geo, caret)
			new_caret = line.head
		} else {
			new_caret = len(text)
		}

		if shift {
			if !text_edit_selection_active(selection) {
				new_selection = {anchor = caret, head = new_caret}
			} else {
				new_selection.head = new_caret
			}
		} else {
			new_selection = {anchor = new_caret, head = new_caret}
		}

		text_edit_set_preferred_column(edit, geo, new_caret)
	}

	return new_caret, new_selection, handled
}

text_edit_consume_command :: proc() -> Text_Edit_Command {
	if w_ctx == nil do return .NONE

	cmd := w_ctx.text_edit_command
	w_ctx.text_edit_command = .NONE

	return cmd
}

/*
Takes a pending edit command only when the caller is the focused widget.

Prevents unfocused selectable text widgets from discarding clipboard shortcuts.
*/
text_edit_take_command :: proc(focused: bool) -> Text_Edit_Command {
	if !focused do return .NONE

	return text_edit_consume_command()
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
