package oni

import "core:mem"
import "core:strings"

/*
Rich-text override keys aligned with Widget_Config style field names.
*/
Text_Run_Style_Field :: enum {
	align,
	auto_focus,
	background,
	border,
	border_color,
	color,
	direction,
	disabled,
	flex,
	font,
	font_size,
	font_style,
	font_weight,
	gap_x,
	gap_y,
	height,
	justify,
	letter_spacing,
	line_height,
	max_h,
	max_w,
	min_h,
	min_w,
	order,
	overflow_x,
	overflow_y,
	opacity,
	padding,
	pointer_events,
	position,
	radius,
	self,
	space,
	tabbable,
	tab_size,
	text_decoration,
	text_decoration_color,
	text_decoration_style,
	text_direction,
	texture_fit,
	texture_pos,
	visibility,
	width,
	wrap,
	word_spacing,
	x,
	y,
	right,
	bottom,
	z_index,
}

Visibility_Kind :: enum {
	VISIBLE,
	HIDDEN,
	NONE,
}

Pointer_Events_Kind :: enum {
	AUTO,
	NONE,
}

Position_Kind :: enum {
	RELATIVE,
	ABSOLUTE,
	FIXED,
	STICKY,
}

Overflow_Kind :: enum {
	AUTO,
	SCROLL,
	HIDDEN,
}

/*
Parsed tag value for one Widget_Config style field override.
*/
Text_Run_Tag_Value :: union {
	Color,
	f32,
	bool,
	Font_Weights,
	Font_Styles,
	Text_Direction_Kind,
	Text_Decoration_Lines,
	Text_Decoration_Style_Kind,
	Text_Align_Kind,
	Text_Wrap_Kind,
	Visibility_Kind,
	Pointer_Events_Kind,
	Position_Kind,
	Overflow_Kind,
	Direction_Layout,
	Draw_Space,
	Texture_Fit,
	Justify_Pos,
	Length,
	Font_Handle,
	u16,
}

/*
Inline style overrides for one rich-text run.

Only text-applicable fields affect shaping and draw; other fields are parsed
and preserved for tooling such as syntax highlighters.
*/
Text_Run_Style :: struct {
	fields:                bit_set[Text_Run_Style_Field;u64],
	color:                 Color,
	background:            Color,
	border_color:          Color,
	text_decoration_color: Color,
	font_size:             f32,
	letter_spacing:        f32,
	line_height:           f32,
	word_spacing:          f32,
	tab_size:              f32,
	opacity:               f32,
	flex:                  f32,
	max_h:                 f32,
	max_w:                 f32,
	min_h:                 f32,
	min_w:                 f32,
	order:                 f32,
	x:                     f32,
	y:                     f32,
	right:                 f32,
	bottom:                f32,
	z_index:               f32,
	gap_x:                 u16,
	gap_y:                 u16,
	font:                  Font_Handle,
	font_weight:           Font_Weights,
	font_style:            Font_Styles,
	text_direction:        Text_Direction_Kind,
	text_align:            Text_Align_Kind,
	text_wrap:             Text_Wrap_Kind,
	text_decoration:       Text_Decoration_Lines,
	text_decoration_style: Text_Decoration_Style_Kind,
	visibility:            Visibility_Kind,
	overflow_x:            Overflow_Kind,
	overflow_y:            Overflow_Kind,
	pointer_events:        Pointer_Events_Kind,
	position:              Position_Kind,
	direction:             Direction_Layout,
	space:                 Draw_Space,
	texture_fit:           Texture_Fit,
	justify:               Justify_Pos,
	self:                  Justify_Pos,
	width:                 Length,
	height:                Length,
	border:                f32,
	padding:               f32,
	radius:                f32,
	disabled:              bool,
	tabbable:              bool,
	auto_focus:            bool,
}

TEXT_RUN_STYLE_DEFAULT :: Text_Run_Style{}

/*
Layout and draw inputs for one rich-text segment after merging run overrides.
*/
Text_Run_Segment :: struct {
	font:                  Font_Handle,
	font_size:             f32,
	font_weight:           Font_Weight,
	font_style:            Font_Style,
	letter_spacing:        f32,
	word_spacing:          f32,
	line_height:           f32,
	tab_size:              f32,
	text_direction:        Text_Direction_Kind,
	text_decoration:       Text_Decoration_Lines,
	text_decoration_style: Text_Decoration_Style_Kind,
	color:                 Colors,
	text_decoration_color: Colors,
	opacity:               f32,
}

/*
One contiguous styled substring in author order.
*/
Text_Run :: struct {
	text:  string,
	style: Text_Run_Style,
}

/*
Byte range and style for one run in flattened layout text.
*/
Layout_Text_Run :: struct {
	start: int,
	end:   int,
	style: Text_Run_Style,
}

text_run_style_has :: proc(style: Text_Run_Style, field: Text_Run_Style_Field) -> bool {
	return field in style.fields
}

text_run_style_equal :: proc(a, b: Text_Run_Style) -> bool {
	if a.fields != b.fields do return false

	for field in a.fields {
		switch field {
		case .color:
			if a.color != b.color do return false
		case .background:
			if a.background != b.background do return false
		case .border_color:
			if a.border_color != b.border_color do return false
		case .text_decoration_color:
			if a.text_decoration_color != b.text_decoration_color do return false
		case .font_size:
			if a.font_size != b.font_size do return false
		case .letter_spacing:
			if a.letter_spacing != b.letter_spacing do return false
		case .line_height:
			if a.line_height != b.line_height do return false
		case .word_spacing:
			if a.word_spacing != b.word_spacing do return false
		case .tab_size:
			if a.tab_size != b.tab_size do return false
		case .opacity:
			if a.opacity != b.opacity do return false
		case .flex:
			if a.flex != b.flex do return false
		case .max_h:
			if a.max_h != b.max_h do return false
		case .max_w:
			if a.max_w != b.max_w do return false
		case .min_h:
			if a.min_h != b.min_h do return false
		case .min_w:
			if a.min_w != b.min_w do return false
		case .order:
			if a.order != b.order do return false
		case .x:
			if a.x != b.x do return false
		case .y:
			if a.y != b.y do return false
		case .right:
			if a.right != b.right do return false
		case .bottom:
			if a.bottom != b.bottom do return false
		case .z_index:
			if a.z_index != b.z_index do return false
		case .gap_x:
			if a.gap_x != b.gap_x do return false
		case .gap_y:
			if a.gap_y != b.gap_y do return false
		case .font:
			if a.font != b.font do return false
		case .font_weight:
			if a.font_weight != b.font_weight do return false
		case .font_style:
			if a.font_style != b.font_style do return false
		case .text_direction:
			if a.text_direction != b.text_direction do return false
		case .align:
			if a.text_align != b.text_align do return false
		case .wrap:
			if a.text_wrap != b.text_wrap do return false
		case .text_decoration:
			if a.text_decoration != b.text_decoration do return false
		case .text_decoration_style:
			if a.text_decoration_style != b.text_decoration_style do return false
		case .visibility:
			if a.visibility != b.visibility do return false
		case .overflow_x:
			if a.overflow_x != b.overflow_x do return false
		case .overflow_y:
			if a.overflow_y != b.overflow_y do return false
		case .pointer_events:
			if a.pointer_events != b.pointer_events do return false
		case .position:
			if a.position != b.position do return false
		case .direction:
			if a.direction != b.direction do return false
		case .space:
			if a.space != b.space do return false
		case .texture_fit:
			if a.texture_fit != b.texture_fit do return false
		case .justify:
			if a.justify != b.justify do return false
		case .self:
			if a.self != b.self do return false
		case .width:
			if a.width != b.width do return false
		case .height:
			if a.height != b.height do return false
		case .border:
			if a.border != b.border do return false
		case .padding:
			if a.padding != b.padding do return false
		case .radius:
			if a.radius != b.radius do return false
		case .disabled:
			if a.disabled != b.disabled do return false
		case .tabbable:
			if a.tabbable != b.tabbable do return false
		case .auto_focus:
			if a.auto_focus != b.auto_focus do return false
		case .texture_pos:
		}
	}

	return true
}

/*
One parsed open-tag override on the tag stack.
*/
Text_Run_Tag_Entry :: struct {
	field: Text_Run_Style_Field,
	value: Text_Run_Tag_Value,
}

text_run_style_set :: proc(
	style: ^Text_Run_Style,
	field: Text_Run_Style_Field,
	value: Text_Run_Tag_Value,
) {
	style.fields += {field}

	#partial switch field {
	case .color:
		style.color = value.(Color)
	case .background:
		style.background = value.(Color)
	case .border_color:
		style.border_color = value.(Color)
	case .text_decoration_color:
		style.text_decoration_color = value.(Color)
	case .font_size:
		style.font_size = value.(f32)
	case .letter_spacing:
		style.letter_spacing = value.(f32)
	case .line_height:
		style.line_height = value.(f32)
	case .word_spacing:
		style.word_spacing = value.(f32)
	case .tab_size:
		style.tab_size = value.(f32)
	case .opacity:
		style.opacity = value.(f32)
	case .flex:
		style.flex = value.(f32)
	case .max_h:
		style.max_h = value.(f32)
	case .max_w:
		style.max_w = value.(f32)
	case .min_h:
		style.min_h = value.(f32)
	case .min_w:
		style.min_w = value.(f32)
	case .order:
		style.order = value.(f32)
	case .x:
		style.x = value.(f32)
	case .y:
		style.y = value.(f32)
	case .right:
		style.right = value.(f32)
	case .bottom:
		style.bottom = value.(f32)
	case .z_index:
		style.z_index = value.(f32)
	case .border:
		style.border = value.(f32)
	case .padding:
		style.padding = value.(f32)
	case .radius:
		style.radius = value.(f32)
	case .font_weight:
		style.font_weight = value.(Font_Weights)
	case .font_style:
		style.font_style = value.(Font_Styles)
	case .text_direction:
		style.text_direction = value.(Text_Direction_Kind)
	case .align:
		style.text_align = value.(Text_Align_Kind)
	case .wrap:
		style.text_wrap = value.(Text_Wrap_Kind)
	case .text_decoration:
		style.text_decoration = value.(Text_Decoration_Lines)
	case .text_decoration_style:
		style.text_decoration_style = value.(Text_Decoration_Style_Kind)
	case .visibility:
		style.visibility = value.(Visibility_Kind)
	case .overflow_x:
		style.overflow_x = value.(Overflow_Kind)
	case .overflow_y:
		style.overflow_y = value.(Overflow_Kind)
	case .pointer_events:
		style.pointer_events = value.(Pointer_Events_Kind)
	case .position:
		style.position = value.(Position_Kind)
	case .direction:
		style.direction = value.(Direction_Layout)
	case .space:
		style.space = value.(Draw_Space)
	case .texture_fit:
		style.texture_fit = value.(Texture_Fit)
	case .justify:
		style.justify = value.(Justify_Pos)
	case .self:
		style.self = value.(Justify_Pos)
	case .width:
		style.width = value.(Length)
	case .height:
		style.height = value.(Length)
	case .gap_x:
		style.gap_x = value.(u16)
	case .gap_y:
		style.gap_y = value.(u16)
	case .font:
		style.font = value.(Font_Handle)
	case .disabled:
		style.disabled = value.(bool)
	case .tabbable:
		style.tabbable = value.(bool)
	case .auto_focus:
		style.auto_focus = value.(bool)
	}
}

text_run_style_from_stack :: proc(stack: []Text_Run_Tag_Entry) -> Text_Run_Style {
	result := TEXT_RUN_STYLE_DEFAULT

	for entry in stack {
		text_run_style_set(&result, entry.field, entry.value)
	}

	return result
}

/*
Flattens author runs into one plain string and layout byte ranges.
*/
text_runs_to_layout :: proc(
	runs: []Text_Run,
	allocator: mem.Allocator,
) -> (
	plain: string,
	layout_runs: []Layout_Text_Run,
) {
	if len(runs) == 0 do return {}, {}

	b := strings.builder_make(allocator)
	defer strings.builder_destroy(&b)

	lruns := make([dynamic]Layout_Text_Run, 0, len(runs), allocator)

	offset := 0

	for run in runs {
		if len(run.text) == 0 do continue

		start := offset
		strings.write_string(&b, run.text)
		offset += len(run.text)

		append(&lruns, Layout_Text_Run{start = start, end = offset, style = run.style})
	}

	if len(lruns) == 0 do return {}, {}

	return strings.to_string(b), lruns[:]
}

text_run_segment_layout :: proc(
	run_style: Text_Run_Style,
	base: Resolved_Widget_Style,
) -> Text_Run_Segment {
	segment := Text_Run_Segment {
		font                  = base.font,
		font_size             = base.font_size,
		font_weight           = base.font_weight,
		font_style            = base.font_style,
		letter_spacing        = base.letter_spacing,
		word_spacing          = base.word_spacing,
		line_height           = base.line_height,
		tab_size              = base.tab_size,
		text_direction        = text_direction_kind(base.text_direction),
		text_decoration       = text_decoration_lines(base.text_decoration),
		text_decoration_style = text_decoration_style_kind(base.text_decoration_style),
		color                 = base.color,
		text_decoration_color = base.text_decoration_color,
		opacity               = base.opacity,
	}

	if text_run_style_has(run_style, .font_size) {
		segment.font_size = run_style.font_size
	}

	if text_run_style_has(run_style, .font) {
		segment.font = run_style.font

		if run_style.font.size_px > 0 && !text_run_style_has(run_style, .font_size) {
			segment.font_size = run_style.font.size_px
		}
	}

	if text_run_style_has(run_style, .font_weight) {
		segment.font_weight = run_style.font_weight
	}

	if text_run_style_has(run_style, .font_style) {
		segment.font_style = run_style.font_style
	}

	if text_run_style_has(run_style, .letter_spacing) {
		segment.letter_spacing = run_style.letter_spacing
	}

	if text_run_style_has(run_style, .word_spacing) {
		segment.word_spacing = run_style.word_spacing
	}

	if text_run_style_has(run_style, .line_height) {
		segment.line_height = run_style.line_height
	}

	if text_run_style_has(run_style, .tab_size) {
		segment.tab_size = run_style.tab_size
	}

	if text_run_style_has(run_style, .text_direction) {
		segment.text_direction = run_style.text_direction
	}

	if text_run_style_has(run_style, .text_decoration) {
		segment.text_decoration = run_style.text_decoration
	}

	if text_run_style_has(run_style, .text_decoration_style) {
		segment.text_decoration_style = run_style.text_decoration_style
	}

	if text_run_style_has(run_style, .color) {
		segment.color = run_style.color
	}

	if text_run_style_has(run_style, .text_decoration_color) {
		segment.text_decoration_color = run_style.text_decoration_color
	}

	if text_run_style_has(run_style, .opacity) {
		segment.opacity = run_style.opacity
	}

	return segment
}

/*
Resolves concrete font weight and style for shaping one run.
*/
text_run_resolve_font :: proc(
	run_style: Text_Run_Style,
	base_weight: Font_Weight,
	base_style: Font_Style,
) -> (
	weight: Font_Weight,
	style: Font_Style,
) {
	segment := text_run_segment_layout(
		run_style,
		Resolved_Widget_Style{font_weight = base_weight, font_style = base_style},
	)

	return segment.font_weight, segment.font_style
}

/*
Resolves the draw color for one layout run against the widget base color.
*/
text_run_resolve_color :: proc(
	run: Layout_Text_Run,
	base: RGBA,
	base_ok: bool,
) -> (
	rgba: RGBA,
	ok: bool,
) {
	if text_run_style_has(run.style, .color) {
		return css_color_to_rgba(run.style.color), true
	}

	return base, base_ok
}

/*
Resolves decoration lines for one layout run against the widget base decoration.
*/
text_run_resolve_decoration :: proc(
	run: Layout_Text_Run,
	base: Text_Decoration_Lines,
) -> Text_Decoration_Lines {
	if text_run_style_has(run.style, .text_decoration) {
		return run.style.text_decoration
	}

	return base
}

text_run_resolve_decoration_style :: proc(
	run: Layout_Text_Run,
	base: Text_Decoration_Style_Kind,
) -> Text_Decoration_Style_Kind {
	if text_run_style_has(run.style, .text_decoration_style) {
		return run.style.text_decoration_style
	}

	return base
}

text_run_resolve_decoration_color :: proc(
	run: Layout_Text_Run,
	base: RGBA,
	base_ok: bool,
) -> (
	rgba: RGBA,
	ok: bool,
) {
	if text_run_style_has(run.style, .text_decoration_color) {
		return css_color_to_rgba(run.style.text_decoration_color), true
	}

	return base, base_ok
}

text_run_resolve_opacity :: proc(run: Layout_Text_Run, base: f32) -> f32 {
	if text_run_style_has(run.style, .opacity) {
		return run.style.opacity
	}

	return base
}
