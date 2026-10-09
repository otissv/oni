package oni

import "core:strconv"
import "core:strings"
import "core:unicode"
/*
Maximum explicit grid template tracks per axis (template columns/rows).
*/
GRID_MAX_TRACKS :: 64

/*
Maximum named areas in one grid-template-areas declaration.
*/
GRID_MAX_AREAS :: 64

/*
Maximum rows/columns in an implicit grid (auto-placement expansion).
*/
GRID_MAX_IMPLICIT_TRACKS :: 256

/*
CSS grid-auto-flow values.
*/
Grid_Auto_Flow :: enum {
	ROW,
	COLUMN,
	ROW_DENSE,
	COLUMN_DENSE,
}

/*
Bound inside minmax() for a grid track.
*/
Grid_Track_Bound_Kind :: enum {
	AUTO,
	PX,
	FR,
}

Grid_Track_Bound :: struct {
	kind:  Grid_Track_Bound_Kind,
	value: f32,
}

/*
One grid track size (auto, px, fr, or minmax).
*/
Grid_Track_Size_Kind :: enum {
	AUTO,
	PX,
	FR,
	MINMAX,
}

Grid_Track_Size :: struct {
	kind: Grid_Track_Size_Kind,
	px:   f32,
	fr:   f32,
	min:  Grid_Track_Bound,
	max:  Grid_Track_Bound,
}

/*
Author/resolved explicit track list for template-columns or template-rows.
*/
Grid_Template_Tracks :: struct {
	count:  int,
	tracks: [GRID_MAX_TRACKS]Grid_Track_Size,
}

/*
Resolved grid line (CSS 1-based). Zero means auto / unset.
*/
Grid_Line :: struct {
	line: int,
	span: int,
}

/*
Rectangle in grid line coordinates (start inclusive, end exclusive).
*/
Grid_Area_Lines :: struct {
	col_start: int,
	col_end:   int,
	row_start: int,
	row_end:   int,
}

/*
Returns whether a template track list was authored (non-empty).
*/
grid_template_tracks_is_set :: proc(tracks: Grid_Template_Tracks) -> bool {
	return tracks.count > 0
}

/*
Default auto track size (auto).
*/
grid_track_size_auto :: proc() -> Grid_Track_Size {
	return Grid_Track_Size{kind = .AUTO}
}

/*
Builds a fixed pixel track size.
*/
grid_track_size_px :: proc(px: f32) -> Grid_Track_Size {
	return Grid_Track_Size{kind = .PX, px = px}
}

/*
Builds a fractional (fr) track size.
*/
grid_track_size_fr :: proc(fr: f32) -> Grid_Track_Size {
	return Grid_Track_Size{kind = .FR, fr = fr}
}

/*
Builds a minmax() track size.
*/
grid_track_size_minmax :: proc(min, max: Grid_Track_Bound) -> Grid_Track_Size {
	return Grid_Track_Size{kind = .MINMAX, min = min, max = max}
}

grid_track_bound_auto :: proc() -> Grid_Track_Bound {
	return Grid_Track_Bound{kind = .AUTO}
}

grid_track_bound_px :: proc(px: f32) -> Grid_Track_Bound {
	return Grid_Track_Bound{kind = .PX, value = px}
}

grid_track_bound_fr :: proc(fr: f32) -> Grid_Track_Bound {
	return Grid_Track_Bound{kind = .FR, value = fr}
}

@(private)
grid_track_size_is_fr :: proc(track: Grid_Track_Size) -> (fr: f32, ok: bool) {
	#partial switch track.kind {
	case .FR:
		return max(track.fr, 0), true
	case .MINMAX:
		if track.max.kind == .FR {
			return max(track.max.value, 0), true
		}
	}
	return 0, false
}

@(private)
grid_track_min_floor :: proc(track: Grid_Track_Size, content_min: f32) -> f32 {
	switch track.kind {
	case .AUTO:
		return max(0, content_min)
	case .PX:
		return max(0, track.px)
	case .FR:
		return max(0, content_min)
	case .MINMAX:
		min_v: f32
		switch track.min.kind {
		case .AUTO:
			min_v = max(0, content_min)
		case .PX:
			min_v = max(0, track.min.value)
		case .FR:
			min_v = max(0, content_min)
		}
		return min_v
	}
	return 0
}

@(private)
grid_track_max_cap :: proc(track: Grid_Track_Size) -> (cap: f32, has_cap: bool) {
	switch track.kind {
	case .PX:
		return track.px, true
	case .MINMAX:
		switch track.max.kind {
		case .PX:
			return max(0, track.max.value), true
		case .AUTO, .FR:
			return 0, false
		}
	case .AUTO, .FR:
		return 0, false
	}
	return 0, false
}

/*
Distributes `available` space across resolved base track sizes, honoring fr and minmax caps.
*/
grid_distribute_tracks :: proc(
	tracks: []Grid_Track_Size,
	gap: f32,
	available: f32,
	content_mins: []f32,
	out_sizes: []f32,
) {
	n := len(tracks)
	if n == 0 do return
	assert(len(content_mins) >= n)
	assert(len(out_sizes) >= n)

	fr_sum: f32
	for i in 0 ..< n {
		base := grid_track_min_floor(tracks[i], content_mins[i])
		out_sizes[i] = base
		if fr, ok := grid_track_size_is_fr(tracks[i]); ok {
			fr_sum += fr
		}
	}

	gaps := n > 1 ? gap * f32(n - 1) : 0
	fixed := gaps
	for i in 0 ..< n {
		if _, is_fr := grid_track_size_is_fr(tracks[i]); !is_fr {
			fixed += out_sizes[i]
		}
	}

	remaining := available > 0 ? max(0, available - fixed) : 0
	if fr_sum > 0 && remaining > 0 {
		for i in 0 ..< n {
			fr, ok := grid_track_size_is_fr(tracks[i])
			if !ok do continue
			out_sizes[i] += remaining * (fr / fr_sum)
		}
	}

	for i in 0 ..< n {
		if cap, has_cap := grid_track_max_cap(tracks[i]); has_cap {
			out_sizes[i] = min(out_sizes[i], cap)
		}
		out_sizes[i] = max(0, out_sizes[i])
	}
}

@(private)
grid_skip_ws :: proc(s: string, i: int) -> int {
	for k in i ..< len(s) {
		c := s[k]
		if c == ' ' || c == '\t' || c == '\n' || c == '\r' do continue
		return k
	}
	return len(s)
}

@(private)
grid_read_ident :: proc(s: string, i: int) -> (ident: string, next: int, ok: bool) {
	start := grid_skip_ws(s, i)
	if start >= len(s) do return "", start, false
	end := start
	for end < len(s) {
		c := s[end]
		if unicode.is_space(rune(c)) || c == '(' || c == ')' do break
		end += 1
	}
	if end == start do return "", start, false
	return s[start:end], end, true
}

@(private)
grid_read_number :: proc(s: string, i: int) -> (value: f32, next: int, ok: bool) {
	start := grid_skip_ws(s, i)
	if start >= len(s) do return 0, start, false
	end := start
	for end < len(s) {
		c := s[end]
		if c == ' ' || c == '\t' || c == 'p' || c == 'x' || c == 'f' || c == 'r' do break
		if (c < '0' || c > '9') && c != '.' do break
		end += 1
	}
	num := s[start:end]
	if len(num) == 0 do return 0, start, false
	v, parsed := strconv.parse_f32(num)
	if !parsed do return 0, start, false
	next = end
	if strings.has_prefix(s[end:], "px") {
		next = end + 2
	}
	return v, next, true
}

@(private)
grid_parse_track_bound :: proc(s: string, i: int) -> (bound: Grid_Track_Bound, next: int, ok: bool) {
	pos := grid_skip_ws(s, i)
	ident, after_ident, ident_ok := grid_read_ident(s, pos)
	if !ident_ok do return {}, pos, false
	lower := strings.to_lower(ident, context.temp_allocator)
	switch lower {
	case "auto":
		return grid_track_bound_auto(), after_ident, true
	case "fr":
		v, n, num_ok := grid_read_number(s, after_ident)
		if !num_ok do return {}, pos, false
		return grid_track_bound_fr(v), n, true
	}
	if strings.has_suffix(lower, "fr") && len(lower) > 2 {
		num_str := ident[:len(ident) - 2]
		fv, parsed := strconv.parse_f32(num_str)
		if parsed {
			return grid_track_bound_fr(fv), after_ident, true
		}
	}
	v, n, num_ok := grid_read_number(s, pos)
	if num_ok {
		return grid_track_bound_px(v), n, true
	}
	return {}, pos, false
}

/*
Parses one track size token (e.g. 100px, 1fr, auto, minmax(0, 1fr)).
*/
grid_parse_track_size :: proc(s: string, i: int) -> (track: Grid_Track_Size, next: int, ok: bool) {
	pos := grid_skip_ws(s, i)
	ident, after_ident, ident_ok := grid_read_ident(s, pos)
	if !ident_ok do return {}, pos, false

	lower := strings.to_lower(ident, context.temp_allocator)
	switch lower {
	case "auto":
		return grid_track_size_auto(), after_ident, true
	case "fr":
		v, n, num_ok := grid_read_number(s, after_ident)
		if !num_ok do return {}, pos, false
		return grid_track_size_fr(v), n, true
	case "minmax":
		if after_ident >= len(s) || s[after_ident] != '(' do return {}, pos, false
		inner := after_ident + 1
		min_b, after_min, min_ok := grid_parse_track_bound(s, inner)
		if !min_ok do return {}, pos, false
		if after_min >= len(s) || s[after_min] != ',' do return {}, pos, false
		max_b, after_max, max_ok := grid_parse_track_bound(s, after_min + 1)
		if !max_ok do return {}, pos, false
		if after_max >= len(s) || s[after_max] != ')' do return {}, pos, false
		return grid_track_size_minmax(min_b, max_b), after_max + 1, true
	}

	if strings.has_suffix(lower, "fr") {
		num_str := ident[:len(ident) - 2]
		fv, parsed := strconv.parse_f32(num_str)
		if parsed {
			return grid_track_size_fr(fv), after_ident, true
		}
	}

	v, n, num_ok := grid_read_number(s, pos)
	if num_ok {
		return grid_track_size_px(v), n, true
	}

	return {}, pos, false
}

/*
Parses a CSS grid-template-columns/rows list into explicit tracks.
*/
grid_parse_template_tracks :: proc(
	list: string,
	allocator := context.temp_allocator,
) -> (
	tracks: Grid_Template_Tracks,
	ok: bool,
) {
	if len(list) == 0 do return {}, false

	pos := 0
	for tracks.count < GRID_MAX_TRACKS {
		pos = grid_skip_ws(list, pos)
		if pos >= len(list) do break

		track, next, track_ok := grid_parse_track_size(list, pos)
		if !track_ok do return {}, false

		tracks.tracks[tracks.count] = track
		tracks.count += 1
		pos = grid_skip_ws(list, next)
		if pos >= len(list) do break
	}

	return tracks, tracks.count > 0
}

@(private)
grid_parse_line_token :: proc(token: string) -> (line: int, span: int, ok: bool) {
	t := strings.trim_space(token)
	if len(t) == 0 do return 0, 0, false

	lower := strings.to_lower(t, context.temp_allocator)
	if strings.has_prefix(lower, "span") {
		rest := strings.trim_space(lower[4:])
		v, parsed := strconv.parse_int(rest)
		if !parsed || v <= 0 do return 0, 0, false
		return 0, v, true
	}

	v, parsed := strconv.parse_int(t)
	if !parsed || v <= 0 do return 0, 0, false
	return v, 0, true
}

/*
Parses grid-column or grid-row shorthand (e.g. "1 / 3", "span 2", "2").
*/
grid_parse_line_shorthand :: proc(value: string) -> (start, end: Grid_Line, ok: bool) {
	t := strings.trim_space(value)
	if len(t) == 0 do return {}, {}, false

	parts := strings.split(t, "/", context.temp_allocator)
	if len(parts) == 1 {
		line, span, line_ok := grid_parse_line_token(parts[0])
		if !line_ok do return {}, {}, false
		if span > 0 {
			return Grid_Line{span = span}, {}, true
		}
		return Grid_Line{line = line}, {}, true
	}

	if len(parts) != 2 do return {}, {}, false

	s_line, s_span, s_ok := grid_parse_line_token(parts[0])
	e_line, e_span, e_ok := grid_parse_line_token(parts[1])
	if !s_ok && !e_ok do return {}, {}, false

	start = Grid_Line{line = s_line, span = s_span}
	end = Grid_Line{line = e_line, span = e_span}
	return start, end, true
}

/*
Parses grid-template-areas into a map of area name to line rectangle.

`rows` receives one string per template row (whitespace-separated cell names).
*/
grid_parse_template_areas :: proc(
	areas: string,
	allocator := context.temp_allocator,
) -> (
	cols: int,
	rows: int,
	names: map[string]Grid_Area_Lines,
	ok: bool,
) {
	names = make(map[string]Grid_Area_Lines, allocator)
	lines := strings.split_lines(areas, allocator)
	grid_rows: [dynamic]string
	defer delete(grid_rows)

	for line in lines {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 do continue
		append(&grid_rows, trimmed)
	}

	rows = len(grid_rows)
	if rows == 0 do return 0, 0, names, false

	cols = 0
	for row_text in grid_rows {
		cells := strings.fields(row_text, allocator)
		cols = max(cols, len(cells))
	}
	if cols == 0 do return 0, 0, names, false

	for row_i in 0 ..< len(grid_rows) {
		row_text := grid_rows[row_i]
		cells := strings.fields(row_text, allocator)
		for col_i in 0 ..< len(cells) {
			name := strings.trim_space(cells[col_i])
			if len(name) == 0 || name == "." do continue

			entry, found := names[name]
			if !found {
				entry = Grid_Area_Lines {
					col_start = col_i + 1,
					col_end   = col_i + 2,
					row_start = row_i + 1,
					row_end   = row_i + 2,
				}
			} else {
				entry.col_start = min(entry.col_start, col_i + 1)
				entry.row_start = min(entry.row_start, row_i + 1)
				entry.col_end = max(entry.col_end, col_i + 2)
				entry.row_end = max(entry.row_end, row_i + 2)
			}
			names[strings.clone(name, allocator)] = entry
		}
	}

	return cols, rows, names, len(names) > 0
}

/*
Merges resolved grid line fields into start/end line numbers (1-based, end exclusive).
*/
grid_resolve_placement_lines :: proc(
	col_start, col_end: Grid_Line,
	row_start, row_end: Grid_Line,
	area: Grid_Area_Lines,
	area_set: bool,
) -> (
	c0, c1, r0, r1: int,
	ok: bool,
) {
	if area_set {
		return area.col_start, area.col_end, area.row_start, area.row_end, true
	}

	c0 = col_start.line
	c1 = col_end.line
	r0 = row_start.line
	r1 = row_end.line

	if col_start.span > 0 {
		if c0 <= 0 do return 0, 0, 0, 0, false
		c1 = c0 + col_start.span
	} else if col_end.span > 0 {
		if c0 <= 0 do return 0, 0, 0, 0, false
		c1 = c0 + col_end.span
	}

	if row_start.span > 0 {
		if r0 <= 0 do return 0, 0, 0, 0, false
		r1 = r0 + row_start.span
	} else if row_end.span > 0 {
		if r0 <= 0 do return 0, 0, 0, 0, false
		r1 = r0 + row_end.span
	}

	if c0 > 0 && c1 <= 0 do c1 = c0 + 1
	if r0 > 0 && r1 <= 0 do r1 = r0 + 1

	if c0 > 0 && c1 > 0 && c1 <= c0 do return 0, 0, 0, 0, false
	if r0 > 0 && r1 > 0 && r1 <= r0 do return 0, 0, 0, 0, false

	return c0, c1, r0, r1, true
}

/*
Tailwind `auto-cols-*` presets (maps to grid-auto-columns).
*/
Grid_Auto_Preset :: enum {
	AUTO,
	MIN,
	MAX,
	FR,
}

/*
Author grid-template-columns (`grid-cols-{n}`, raw track list, or explicit tracks).
*/
Grid_Template_Columns :: union {
	Inherit,
	struct{},
	int,
	string,
	Grid_Template_Tracks,
	proc(
		frame_state: Widget_Frame_State,
		event: Widget_Event(Widget_Frame_State),
	) -> Grid_Template_Columns,
}

/*
Author grid-template-rows (`grid-rows-{n}`, raw track list, or explicit tracks).
*/
Grid_Template_Rows :: union {
	Inherit,
	struct{},
	int,
	string,
	Grid_Template_Tracks,
	proc(
		frame_state: Widget_Frame_State,
		event: Widget_Event(Widget_Frame_State),
	) -> Grid_Template_Rows,
}

/*
Author grid-auto-columns / grid-auto-rows (Tailwind preset, track size, or CSS token).
*/
Grid_Auto_Track :: union {
	Inherit,
	struct{},
	Grid_Auto_Preset,
	Grid_Track_Size,
	string,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Grid_Auto_Track,
}

/*
Author grid-column/row line, span, or shorthand token.
*/
Grid_Line_Value :: union {
	Inherit,
	struct{},
	int,
	string,
	Grid_Line,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Grid_Line_Value,
}

/*
Tailwind `grid-cols-{n}`: `repeat(n, minmax(0, 1fr))`.
*/
grid_template_columns_count :: proc(n: int) -> Grid_Template_Tracks {
	tracks: Grid_Template_Tracks
	if n <= 0 do return tracks
	count := min(n, GRID_MAX_TRACKS)
	for i in 0 ..< count {
		tracks.tracks[i] = grid_track_size_minmax(grid_track_bound_px(0), grid_track_bound_fr(1))
	}
	tracks.count = count
	return tracks
}

/*
Tailwind `grid-rows-{n}`: `repeat(n, minmax(0, 1fr))`.
*/
grid_template_rows_count :: proc(n: int) -> Grid_Template_Tracks {
	return grid_template_columns_count(n)
}

/*
Maps Tailwind auto-cols/rows presets to a track size.
*/
grid_auto_track_from_preset :: proc(preset: Grid_Auto_Preset) -> Grid_Track_Size {
	switch preset {
	case .AUTO:
		return grid_track_size_auto()
	case .MIN:
		return grid_track_size_minmax(grid_track_bound_auto(), grid_track_bound_px(0))
	case .MAX:
		return grid_track_size_minmax(grid_track_bound_auto(), grid_track_bound_px(1e9))
	case .FR:
		return grid_track_size_fr(1)
	}
	return grid_track_size_auto()
}

/*
Coerces an author template-columns value to explicit tracks.
*/
grid_resolve_template_columns :: proc(value: Grid_Template_Columns) -> Grid_Template_Tracks {
	switch v in value {
	case Inherit, struct{}:
		return {}
	case int:
		return grid_template_columns_count(v)
	case string:
		if tracks, ok := grid_parse_template_tracks(v); ok do return tracks
		return {}
	case Grid_Template_Tracks:
		return v
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Grid_Template_Columns:
		panic("grid_resolve_template_columns: unresolved proc")
	}
	return {}
}

/*
Coerces an author template-rows value to explicit tracks.
*/
grid_resolve_template_rows :: proc(value: Grid_Template_Rows) -> Grid_Template_Tracks {
	switch v in value {
	case Inherit, struct{}:
		return {}
	case int:
		return grid_template_rows_count(v)
	case string:
		if tracks, ok := grid_parse_template_tracks(v); ok do return tracks
		return {}
	case Grid_Template_Tracks:
		return v
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Grid_Template_Rows:
		panic("grid_resolve_template_rows: unresolved proc")
	}
	return {}
}

/*
Coerces an author auto-track value to a concrete track size.
*/
grid_resolve_auto_track :: proc(value: Grid_Auto_Track) -> Grid_Track_Size {
	switch v in value {
	case Inherit, struct{}:
		return grid_track_size_auto()
	case Grid_Auto_Preset:
		return grid_auto_track_from_preset(v)
	case Grid_Track_Size:
		return v
	case string:
		if track, _, ok := grid_parse_track_size(v, 0); ok do return track
		return grid_track_size_auto()
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Grid_Auto_Track:
		panic("grid_resolve_auto_track: unresolved proc")
	}
	return grid_track_size_auto()
}

/*
Coerces an author line value to Grid_Line (int → 1-based line number).
*/
grid_resolve_line_value :: proc(value: Grid_Line_Value) -> Grid_Line {
	switch v in value {
	case Inherit, struct{}:
		return {}
	case int:
		if v <= 0 do return {}
		return Grid_Line{line = v}
	case string:
		line, span, ok := grid_parse_line_token(v)
		if !ok do return {}
		if span > 0 do return Grid_Line{span = span}
		return Grid_Line{line = line}
	case Grid_Line:
		return v
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Grid_Line_Value:
		panic("grid_resolve_line_value: unresolved proc")
	}
	return {}
}

/*
Merges grid-column/row shorthands into start/end line fields on a resolved style.
*/
grid_apply_line_shorthands :: proc(style: ^Resolved_Widget_Style) {
	if style.grid_column != "" {
		start, end, ok := grid_parse_line_shorthand(style.grid_column)
		if ok {
			if start.line > 0 || start.span > 0 do style.grid_column_start = start
			if end.line > 0 || end.span > 0 do style.grid_column_end = end
		}
	}
	if style.grid_row != "" {
		start, end, ok := grid_parse_line_shorthand(style.grid_row)
		if ok {
			if start.line > 0 || start.span > 0 do style.grid_row_start = start
			if end.line > 0 || end.span > 0 do style.grid_row_end = end
		}
	}
}

/*
Resolved placement for one grid item (1-based lines, end exclusive).
*/
Grid_Item_Placement :: struct {
	c0, c1, r0, r1: int,
	explicit:       bool,
}

/*
Resolves grid item lines from resolved style and optional named-area map.
*/
grid_item_placement :: proc(
	style: Resolved_Widget_Style,
	areas: map[string]Grid_Area_Lines,
) -> (
	placement: Grid_Item_Placement,
	ok: bool,
) {
	area_set := false
	area: Grid_Area_Lines
	if style.grid_area != "" {
		if entry, found := areas[style.grid_area]; found {
			area = entry
			area_set = true
		}
	}

	c0, c1, r0, r1, lines_ok := grid_resolve_placement_lines(
		style.grid_column_start,
		style.grid_column_end,
		style.grid_row_start,
		style.grid_row_end,
		area,
		area_set,
	)
	if !lines_ok do return {}, false

	explicit :=
		c0 > 0 || c1 > 0 || r0 > 0 || r1 > 0 || area_set ||
		style.grid_column != "" ||
		style.grid_row != ""

	return Grid_Item_Placement{c0, c1, r0, r1, explicit}, true
}
