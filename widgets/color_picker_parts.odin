package oni_widgets

import o ".."
import set "../set"
import "core:fmt"

/*
Which swatch `Color_Picker_Swatch` paints.
*/
Color_Picker_Swatch_Role :: enum {
	CURRENT,
	PREVIOUS,
}

Color_Picker_Field_Config :: o.Widget_Config
Color_Picker_Slider_Config :: o.Widget_Config
Color_Picker_Alpha_Config :: o.Widget_Config
Color_Picker_Swatch_Config :: o.Widget_Config
Color_Picker_Channels_Config :: o.Widget_Config
Color_Picker_Hex_Config :: o.Widget_Config
Color_Picker_Type_Config :: o.Widget_Config
Color_Picker_Web_Only_Config :: o.Widget_Config

Color_Picker_Field_Props :: struct {
	config: Color_Picker_Field_Config,
}

Color_Picker_Slider_Props :: struct {
	config: Color_Picker_Slider_Config,
}

Color_Picker_Alpha_Props :: struct {
	config: Color_Picker_Alpha_Config,
}

Color_Picker_Swatch_Props :: struct {
	config: Color_Picker_Swatch_Config,
	role:   Color_Picker_Swatch_Role,
}

Color_Picker_Channels_Props :: struct {
	config: Color_Picker_Channels_Config,
}

/*
Hex input for the enclosing `Color_Picker`.

`include_alpha` controls whether parsed hex may replace the alpha channel.
*/
Color_Picker_Hex_Props :: struct {
	config:        Color_Picker_Hex_Config,
	include_alpha: bool,
}

/*
One numeric row (RGB, HSB, HSL, LAB, CMYK, or WEB) for the enclosing picker.
*/
Color_Picker_Type_Props :: struct {
	config:     Color_Picker_Type_Config,
	color_type: o.Color_Picker_Color_Type,
}

Color_Picker_Web_Only_Props :: struct {
	config: Color_Picker_Web_Only_Config,
}

@(private)
color_picker_field_theme :: proc(frame_state: ^Color_Picker_Surface_State) -> o.Widget_Config {
	ctx := color_picker_ctx_top()
	size := color_picker_style_f32(ctx.style.field_size, o.COLOR_PICKER_DEFAULT_FIELD_SIZE)

	return color_picker_surface_theme(frame_state, size, size)
}

@(private)
color_picker_slider_theme :: proc(frame_state: ^Color_Picker_Surface_State) -> o.Widget_Config {
	ctx := color_picker_ctx_top()
	w := color_picker_style_f32(ctx.style.slider_width, o.COLOR_PICKER_DEFAULT_SLIDER_WIDTH)
	h := color_picker_style_f32(ctx.style.field_size, o.COLOR_PICKER_DEFAULT_FIELD_SIZE)

	return color_picker_surface_theme(frame_state, w, h)
}

@(private)
color_picker_alpha_theme :: proc(frame_state: ^Color_Picker_Surface_State) -> o.Widget_Config {
	ctx := color_picker_ctx_top()
	h := color_picker_style_f32(ctx.style.alpha_height, o.COLOR_PICKER_DEFAULT_ALPHA_HEIGHT)

	return color_picker_surface_theme(frame_state, f32(220), max(h, f32(10)))
}

@(private)
color_picker_swatch_theme :: proc(frame_state: ^Color_Picker_Surface_State) -> o.Widget_Config {
	ctx := color_picker_ctx_top()
	h := color_picker_style_f32(ctx.style.swatch_height, f32(28))

	return color_picker_surface_theme(frame_state, COLOR_PICKER_SWATCH_W, h)
}

@(private)
color_picker_channels_theme :: proc(frame_state: ^Color_Picker_Surface_State) -> o.Widget_Config {
	h := COLOR_PICKER_CHANNEL_ROW_H * 6

	return color_picker_surface_theme(frame_state, f32(120), h)
}

@(private)
color_picker_field_draw :: proc(layout_id: o.UI_Id, rect: o.Rect) {
	ctx := color_picker_ctx_top()

	if !ctx.active {
		return
	}

	color_picker_draw_field(layout_id, rect, ctx.hsva, ctx.value, ctx.channel)
}

@(private)
color_picker_field_pointer :: proc(
	layout_id: o.UI_Id,
	rect: o.Rect,
	hovered: bool,
	interactive: bool,
	disabled: bool,
) {
	color_picker_part_drag(layout_id, .FIELD, rect, hovered, interactive, disabled)
}

@(private)
color_picker_slider_draw :: proc(layout_id: o.UI_Id, rect: o.Rect) {
	ctx := color_picker_ctx_top()

	if !ctx.active {
		return
	}

	color_picker_draw_slider(layout_id, rect, ctx.hsva, ctx.value, ctx.channel)
}

@(private)
color_picker_slider_pointer :: proc(
	layout_id: o.UI_Id,
	rect: o.Rect,
	hovered: bool,
	interactive: bool,
	disabled: bool,
) {
	color_picker_part_drag(layout_id, .SLIDER, rect, hovered, interactive, disabled)
}

@(private)
color_picker_alpha_draw :: proc(layout_id: o.UI_Id, rect: o.Rect) {
	ctx := color_picker_ctx_top()

	if !ctx.active {
		return
	}

	color_picker_draw_alpha(layout_id, rect, ctx.value)
}

@(private)
color_picker_alpha_pointer :: proc(
	layout_id: o.UI_Id,
	rect: o.Rect,
	hovered: bool,
	interactive: bool,
	disabled: bool,
) {
	color_picker_part_drag(layout_id, .ALPHA, rect, hovered, interactive, disabled)
}

@(private)
color_picker_swatch_role: Color_Picker_Swatch_Role

@(private)
color_picker_swatch_draw_active :: proc(layout_id: o.UI_Id, rect: o.Rect) {
	ctx := color_picker_ctx_top()

	if !ctx.active {
		return
	}

	color := ctx.value

	if color_picker_swatch_role == .PREVIOUS {
		color = ctx.previous
	}

	color_picker_draw_swatch(layout_id, rect, color)
}

@(private)
color_picker_swatch_pointer_active :: proc(
	layout_id: o.UI_Id,
	rect: o.Rect,
	hovered: bool,
	interactive: bool,
	disabled: bool,
) {
	if color_picker_swatch_role != .PREVIOUS || !interactive || disabled {
		return
	}

	ctx := color_picker_ctx_top()

	if !ctx.active {
		return
	}

	mouse := o.Vec2{o.w_ctx.mouse_x, o.w_ctx.mouse_y}

	if o.w_ctx.left_mouse.pressed && hovered && color_picker_point_in_rect(mouse, rect) {
		restored := ctx.previous
		ctx.hsva = o.color_picker_hsva_from_rgba(restored, ctx.hsva)
		color_picker_emit(ctx, restored, true)
		o.Stop_Propagation()
	}
}

@(private)
color_picker_channels_draw :: proc(layout_id: o.UI_Id, rect: o.Rect) {
	ctx := color_picker_ctx_top()

	if !ctx.active {
		return
	}

	color_picker_draw_channels(layout_id, rect, ctx.channel)
	hits := color_picker_channel_hit_rects(rect)

	for i in 0 ..< 6 {
		ch := color_picker_comp_channel(i)
		active := ch == ctx.channel
		label := color_picker_channel_label(ch)
		Text(
			{
				config = {
					id = fmt.tprintf("%s/ch-%d", ctx.key, i),
					text = label,
					position = set.Position(.ABSOLUTE),
					x = set.F32(hits[i].x + 4),
					y = set.F32(hits[i].y + 3),
					width = set.Width(max(f32(0), hits[i].w - 6)),
					height = set.Height(hits[i].h),
					font_size = set.F32(12),
					color = set.Colors(active ? o.Color.FOREGROUND : o.Color.MUTED_FOREGROUND),
					tabbable = set.Tabbable(false),
				},
			},
		)
	}
}

@(private)
color_picker_channels_pointer :: proc(
	layout_id: o.UI_Id,
	rect: o.Rect,
	hovered: bool,
	interactive: bool,
	disabled: bool,
) {
	if !interactive || disabled {
		return
	}

	ctx := color_picker_ctx_top()

	if !ctx.active {
		return
	}

	mouse := o.Vec2{o.w_ctx.mouse_x, o.w_ctx.mouse_y}

	hits := color_picker_channel_hit_rects(rect)

	for i in 0 ..< 6 {
		if o.w_ctx.left_mouse.pressed && color_picker_point_in_rect(mouse, hits[i]) {
			color_picker_set_channel(ctx, color_picker_comp_channel(i))
			o.Stop_Propagation()

			return
		}
	}
}

/*
Two-dimensional saturation/value (or channel) field for the active picker channel.
*/
Color_Picker_Field :: proc(props: Color_Picker_Field_Props) {
	if !color_picker_ctx_ok() {
		return
	}

	ctx := color_picker_ctx_top()
	size := color_picker_style_f32(ctx.style.field_size, o.COLOR_PICKER_DEFAULT_FIELD_SIZE)
	cfg := props.config

	if _, is_auto := cfg.width.(struct{}); is_auto {
		cfg.width = set.Width(size)
	}

	if _, is_auto := cfg.height.(struct{}); is_auto {
		cfg.height = set.Height(size)
	}

	color_picker_surface(
		cfg,
		size,
		size,
		color_picker_field_theme,
		color_picker_field_draw,
		color_picker_field_pointer,
	)
}

/*
Vertical channel slider for the active picker channel.
*/
Color_Picker_Slider :: proc(props: Color_Picker_Slider_Props) {
	color_picker_surface(
		props.config,
		o.COLOR_PICKER_DEFAULT_SLIDER_WIDTH,
		o.COLOR_PICKER_DEFAULT_FIELD_SIZE,
		color_picker_slider_theme,
		color_picker_slider_draw,
		color_picker_slider_pointer,
	)
}

/*
Horizontal alpha strip.
*/
Color_Picker_Alpha :: proc(props: Color_Picker_Alpha_Props) {
	color_picker_surface(
		props.config,
		f32(220),
		o.COLOR_PICKER_DEFAULT_ALPHA_HEIGHT,
		color_picker_alpha_theme,
		color_picker_alpha_draw,
		color_picker_alpha_pointer,
	)
}

/*
Current or previous color swatch. Clicking the previous swatch restores that color.
*/
Color_Picker_Swatch :: proc(props: Color_Picker_Swatch_Props) {
	color_picker_swatch_role = props.role

	color_picker_surface(
		props.config,
		COLOR_PICKER_SWATCH_W,
		f32(28),
		color_picker_swatch_theme,
		color_picker_swatch_draw_active,
		color_picker_swatch_pointer_active,
	)
}

/*
H / S / V / R / G / B channel selector rows.
*/
@(private)
color_picker_channels_overlay :: proc(rs: Rectangle_State) {
	if o.ui_pass() != .Draw {
		return
	}

	layout_id := o.ui_id(rs.config.id)
	rect := o.ui_layout_rect(layout_id)
	ctx := color_picker_ctx_top()

	if !ctx.active || rect.w <= 0 || rect.h <= 0 {
		return
	}

	color_picker_channels_draw(layout_id, rect)
}

@(private)
color_picker_channels_on_pressed :: proc(event: Rectangle_Event) {
	ctx := color_picker_ctx_top()

	if !ctx.active || ctx.disabled || event.frame_state.is_disabled {
		return
	}

	layout_id := o.ui_id(event.frame_state.config.id)
	rect := o.ui_layout_rect(layout_id)
	mouse := o.Vec2{o.w_ctx.mouse_x, o.w_ctx.mouse_y}
	hits := color_picker_channel_hit_rects(rect)

	for i in 0 ..< 6 {
		if color_picker_point_in_rect(mouse, hits[i]) {
			color_picker_set_channel(ctx, color_picker_comp_channel(i))
			o.Stop_Propagation()

			return
		}
	}
}

Color_Picker_Channels :: proc(props: Color_Picker_Channels_Props) {
	if !color_picker_ctx_ok() {
		return
	}

	cfg := props.config

	if _, is_auto := cfg.width.(struct{}); is_auto {
		cfg.width = set.Width(f32(120))
	}

	if _, is_auto := cfg.height.(struct{}); is_auto {
		cfg.height = set.Height(COLOR_PICKER_CHANNEL_ROW_H * 6)
	}

	Rectangle(
		{
			config = cfg,
			child = color_picker_channels_overlay,
			on_mouse_pressed = color_picker_channels_on_pressed,
		},
	)
}

/*
Hex text field bound to the picker value.
*/
Color_Picker_Hex :: proc(props: Color_Picker_Hex_Props) {
	ctx := color_picker_ctx_top()

	if !ctx.active || ctx.runtime == nil {
		return
	}

	ctx.hex_include_alpha = props.include_alpha
	color_picker_hex_row_props = props
	color_picker_hex_row_text = ctx.runtime.hex

	if color_picker_hex_row_text == "" {
		color_picker_hex_row_text = o.hex_format(
			ctx.value,
			props.include_alpha,
			context.temp_allocator,
		)
	}

	Rectangle(
		{
			config = {
				id = props.config.id,
				direction = set.Direction(.HORIZONTAL),
				gap_x = set.Gap_X(u16(6)),
				align = set.Align(.CENTER),
				width = props.config.width,
				height = set.Height(COLOR_PICKER_HEX_ROW_H),
			},
			child = color_picker_hex_row_child,
		},
	)
}

@(private)
color_picker_hex_row_props: Color_Picker_Hex_Props

@(private)
color_picker_hex_row_text: string

@(private)
color_picker_hex_row_child :: proc(_: Rectangle_State) {
	props := color_picker_hex_row_props
	Text(
		{
			config = {
				id = fmt.tprintf("%s/hash", props.config.id),
				text = "#",
				font_size = set.F32(13),
				tabbable = set.Tabbable(false),
			},
		},
	)
	Text_Input(
		{
			config = {
				id = fmt.tprintf("%s/input", props.config.id),
				text = color_picker_hex_row_text,
				placeholder = props.include_alpha ? "rrggbbaa" : "rrggbb",
				max_length = props.include_alpha ? 9 : 7,
				width = set.Width(f32(110)),
				height = set.Height(COLOR_PICKER_HEX_ROW_H),
				tabbable = set.Tabbable(true),
			},
			on_change = color_picker_hex_on_change,
			on_blur = color_picker_hex_on_blur,
		},
	)
}

/*
Numeric inputs for one color model (for example `.RGB` or `.HSB`).
*/
Color_Picker_Type :: proc(props: Color_Picker_Type_Props) {
	ctx := color_picker_ctx_top()

	if !ctx.active || ctx.runtime == nil {
		return
	}

	slot := int(props.color_type)

	if slot < 0 || slot >= COLOR_PICKER_TYPE_SLOT_COUNT {
		return
	}

	ctx.runtime.type_active[slot] = true

	if props.color_type == .WEB {
		ctx.has_web_type = true
	}

	color_picker_type_row_props = props
	row_w := color_picker_type_row_width(props.color_type)

	Rectangle(
		{
			config = {
				id = props.config.id,
				direction = set.Direction(.HORIZONTAL),
				gap_x = set.Gap_X(u16(COLOR_PICKER_TYPE_FIELD_GAP)),
				width = set.Width(row_w),
				height = set.Height(COLOR_PICKER_INPUT_ROW_H),
			},
			child = color_picker_type_row_child,
		},
	)
}

@(private)
color_picker_type_row_props: Color_Picker_Type_Props

@(private)
color_picker_type_field_index: int

@(private)
color_picker_type_field_cell_child :: proc(_: Rectangle_State) {
	props := color_picker_type_row_props
	i := color_picker_type_field_index
	ctx := color_picker_ctx_top()
	slot := int(props.color_type)
	label := color_picker_type_field_label(props.color_type, i)
	text := ctx.runtime.type_drafts[slot].text[i]

	if text == "" {
		text = color_picker_format_type_field(ctx.hsva, ctx.value, props.color_type, i)
	}

	Text(
		{
			config = {
				id = fmt.tprintf("%s/l-%d", props.config.id, i),
				text = label,
				width = set.Width(COLOR_PICKER_TYPE_LABEL_W),
				font_size = set.F32(12),
				tabbable = set.Tabbable(false),
			},
		},
	)
	Text_Input(
		{
			config = {
				id         = fmt.tprintf("%s/ctype-%d-%d", props.config.id, slot, i),
				text       = text,
				max_length = 8,
				width      = set.Width(COLOR_PICKER_TYPE_INPUT_W),
				// height = set.Height(COLOR_PICKER_HEX_ROW_H),
				tabbable   = set.Tabbable(true),
			},
			on_change = color_picker_type_input_on_change,
			on_blur = color_picker_type_input_on_blur,
		},
	)
}

@(private)
color_picker_type_row_child :: proc(_: Rectangle_State) {
	props := color_picker_type_row_props
	count := color_picker_type_field_count(props.color_type)

	for i in 0 ..< count {
		color_picker_type_field_index = i

		Rectangle(
			{
				config = {
					id = fmt.tprintf("%s/cell-%d", props.config.id, i),
					direction = set.Direction(.HORIZONTAL),
					gap_x = set.Gap_X(u16(COLOR_PICKER_TYPE_FIELD_GAP)),
					height = set.Height(COLOR_PICKER_INPUT_ROW_H),
					justify = set.Justify(o.Justify_Pos{x = .START, y = .CENTER}),
				},
				child = color_picker_type_field_cell_child,
			},
		)
	}
}

/*
When a `.WEB` type row is present, snaps chosen colors to web-safe values.
*/
Color_Picker_Web_Only :: proc(props: Color_Picker_Web_Only_Props) {
	ctx := color_picker_ctx_top()

	if !ctx.active ||
	   ctx.runtime == nil ||
	   !ctx.runtime.type_active[int(o.Color_Picker_Color_Type.WEB)] {
		return
	}

	color_picker_web_only_props = props

	Rectangle(
		{
			config = {
				id = fmt.tprintf("%s-row", props.config.id),
				direction = set.Direction(.HORIZONTAL),
				gap_x = set.Gap_X(u16(8)),
				align = set.Align(.CENTER),
				height = set.Height(COLOR_PICKER_INPUT_ROW_H),
				justify = set.Justify(o.Justify_Pos{x = .START, y = .CENTER}),
			},
			child = color_picker_web_only_child,
		},
	)
}

@(private)
color_picker_web_only_props: Color_Picker_Web_Only_Props

@(private)
color_picker_web_only_child :: proc(_: Rectangle_State) {
	props := color_picker_web_only_props
	ctx := color_picker_ctx_top()
	check_id := props.config.id
	Checkbox(
		{
			config = {id = check_id, tabbable = set.Tabbable(true)},
			checked = ctx.web_only ? .TRUE : .FALSE,
			on_checked_change = color_picker_web_only_on_change,
		},
	)
	Text(
		{
			config = {
				for_id = check_id,
				id = fmt.tprintf("%s-label", check_id),
				text = "Only Web Colors",
				font_size = set.F32(13),
				tabbable = set.Tabbable(false),
			},
		},
	)
}

@(private)
color_picker_layout: struct {
	prefix:            string,
	hex_include_alpha: bool,
}

@(private)
color_picker_side_child :: proc(_: Rectangle_State) {
	p := color_picker_layout.prefix

	Color_Picker_Swatch({config = {id = fmt.tprintf("%s-swatch-new", p)}, role = .CURRENT})
	Color_Picker_Swatch({config = {id = fmt.tprintf("%s-swatch-prev", p)}, role = .PREVIOUS})
	Color_Picker_Channels({config = {id = fmt.tprintf("%s-channels", p)}})
}

@(private)
color_picker_top_child :: proc(_: Rectangle_State) {
	p := color_picker_layout.prefix

	Color_Picker_Field({config = {id = fmt.tprintf("%s-field", p)}})
	Color_Picker_Slider({config = {id = fmt.tprintf("%s-slider", p)}})
	Rectangle(
		{
			config = {
				id = fmt.tprintf("%s-side", p),
				direction = set.Direction(.VERTICAL),
				gap_y = set.Gap_Y(u16(8)),
			},
			child = color_picker_side_child,
		},
	)
}

/*
Default full color picker layout: 2D field, vertical spectrum slider, new/previous swatches,
H/S/V/R/G/B channel list, alpha strip, hex, RGB/HSB/HSL/LAB/CMYK/WEB numeric rows,
and the web-only toggle (when `.WEB` is included).

`id_prefix` is used for stable part ids (`{prefix}-field`, `{prefix}-slider`, …).
Call only inside an active `Color_Picker` child.
*/
Color_Picker_Default :: proc(id_prefix: string, hex_include_alpha: bool = true) {
	if !color_picker_ctx_ok() {
		return
	}

	color_picker_layout = {id_prefix, hex_include_alpha}
	gutter := u16(int(o.COLOR_PICKER_SLIDER_GUTTER))
	p := id_prefix

	Rectangle(
		{
			config = {
				id = fmt.tprintf("%s-top", p),
				direction = set.Direction(.HORIZONTAL),
				gap_x = set.Gap_X(gutter),
			},
			child = color_picker_top_child,
		},
	)


	Color_Picker_Alpha({config = {id = fmt.tprintf("%s-alpha", p)}})
	Color_Picker_Web_Only({config = {id = fmt.tprintf("%s-web-only", p)}})


	Color_Picker_Hex({config = {id = fmt.tprintf("%s-hex", p)}, include_alpha = hex_include_alpha})
	Color_Picker_Type({config = {id = fmt.tprintf("%s-rgb", p)}, color_type = .RGB})
	Color_Picker_Type({config = {id = fmt.tprintf("%s-hsb", p)}, color_type = .HSB})
	Color_Picker_Type({config = {id = fmt.tprintf("%s-hsl", p)}, color_type = .HSL})
	Color_Picker_Type({config = {id = fmt.tprintf("%s-lab", p)}, color_type = .LAB})
	Color_Picker_Type({config = {id = fmt.tprintf("%s-cmyk", p)}, color_type = .CMYK})
	Color_Picker_Type({config = {id = fmt.tprintf("%s-web", p)}, color_type = .WEB})
}
