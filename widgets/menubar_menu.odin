package oni_widgets

import o ".."
import set "../set"

Menubar_Menu_Config :: struct {
	value: string,
	disabled: o.Cfg(o.Style_Bool),
}

Menubar_Menu_State :: struct {
	value: string,
	open, disabled: bool,
}

Menubar_Menu_Props :: struct {
	config: Menubar_Menu_Config,
	child: proc(state: Menubar_Menu_State),
}

// Menu is a structural scope; Trigger and Content provide its layout nodes.
Menubar_Menu :: proc(props: Menubar_Menu_Props) {
	ctx := menubar_ctx
	if ctx == nil || props.config.value == "" do return
	saved_value, saved_group := ctx.menu_value, ctx.menu_group
	saved_disabled, saved_trigger := ctx.menu_disabled, ctx.trigger
	ctx.menu_value = props.config.value
	ctx.menu_group = o.ui_id(props.config.value)
	ctx.menu_disabled = ctx.disabled || o.cfg_style_bool(props.config.disabled)
	ctx.trigger = 0
	defer {
		ctx.menu_value, ctx.menu_group = saved_value, saved_group
		ctx.menu_disabled, ctx.trigger = saved_disabled, saved_trigger
	}

	if props.child != nil {
		props.child({value = props.config.value, open = ctx.value == props.config.value, disabled = ctx.menu_disabled})
	}
}

Menubar_Sub_Config :: struct {
	id: string,
	disabled: o.Cfg(o.Style_Bool),
}
Menubar_Sub_State :: struct { open, disabled: bool }
Menubar_Sub_Props :: struct {
	config: Menubar_Sub_Config,
	child: proc(state: Menubar_Sub_State),
}

Menubar_Sub :: proc(props: Menubar_Sub_Props) {
	ctx := menubar_ctx
	if ctx == nil || ctx.group == ctx.root || ctx.level >= len(ctx.runtime.path) do return
	key := o.element_key(props.config.id)
	id := o.ui_id(key)
	saved_group, saved_trigger := ctx.menu_group, ctx.trigger
	saved_disabled := ctx.menu_disabled
	ctx.menu_group = id
	ctx.trigger = 0
	ctx.menu_disabled = saved_disabled || o.cfg_style_bool(props.config.disabled)
	defer {
		ctx.menu_group, ctx.trigger = saved_group, saved_trigger
		ctx.menu_disabled = saved_disabled
	}
	open := ctx.runtime.depth > ctx.level && ctx.runtime.path[ctx.level] == id

	if props.child != nil do props.child({open = open, disabled = ctx.menu_disabled})
}

Menubar_Content_Config :: struct {
	using _: o.Widget_Config,
	anchor_align: Popover_Align,
	anchor_gap: f32,
	viewport_margin: f32,
}

Menubar_Content_State :: Popover_Content_State
Menubar_Content_Event :: Popover_Content_Event
Menubar_Content_Props :: struct {
	config: Menubar_Content_Config,
	child: proc(state: Menubar_Content_State),
}
Menubar_Sub_Content_Config :: Menubar_Content_Config
Menubar_Sub_Content_State :: Menubar_Content_State
Menubar_Sub_Content_Props :: Menubar_Content_Props

Menubar_Content :: proc(props: Menubar_Content_Props) {
	menubar_content(props, false)
}

Menubar_Sub_Content :: proc(props: Menubar_Sub_Content_Props) {
	menubar_content(props, true)
}

@(private)
menubar_content :: proc(props: Menubar_Content_Props, sub: bool) {
	ctx := menubar_ctx
	if ctx == nil || ctx.menu_disabled || ctx.trigger == 0 do return
	open := ctx.value == ctx.menu_value

	if sub {
		open = open && ctx.runtime.depth > ctx.level && ctx.runtime.path[ctx.level] == ctx.menu_group
	}

	// Use the Layout snapshot throughout Draw, even when input requests a change.
	if o.ui_pass() == .Draw {
		_, open = o.state.ui.layout.id_to_node[o.ui_id(props.config.id != "" ? props.config.id : menubar_content_id(ctx.menu_group))]
	}

	if !open do return
	cfg := o.Widget_Config {
		kind = sub ? .MENUBAR_SUB_CONTENT : .MENUBAR_CONTENT,
		id = props.config.id != "" ? props.config.id : menubar_content_id(ctx.menu_group),
		space = set.Space(.POPOVER), position = set.Position(.ABSOLUTE),
		width = set.Width(.FIT), height = set.Height(.FIT),
		min_w = set.Min_W(f32(192)), direction = set.Direction(.VERTICAL),
		padding = set.Padding(f32(4)), gap_y = set.Gap_Y(u16(2)),
		background = set.Background(o.Color.BACKGROUND),
		border = set.Border(1), border_color = set.Border_color(o.Color.BORDER),
		radius = set.Radius(f32(6)), z_index = set.Z_Index(f32(50 + ctx.level)),
		overflow_y = set.Overflow_Y(.SCROLL), tabbable = set.Tabbable(false),
		overflow_x = set.Overflow_X(.HIDDEN),
	}
	cfg = o.merge_widget_config(cfg, props.config)
	if cfg.id == "" do cfg.id = menubar_content_id(ctx.menu_group)
	cfg.space = set.Space(.POPOVER)
	cfg.position = set.Position(.ABSOLUTE)
	content_id := o.ui_id(cfg.id)
	anchor := ctx.trigger
	group := ctx.group
	panel_key := ctx.panel_key
	level := ctx.level
	ctx.group = ctx.menu_group
	ctx.panel_key = cfg.id
	if sub do ctx.level += 1
	defer {
		ctx.group = group
		ctx.panel_key = panel_key
		ctx.level = level
	}

	if o.ui_pass() == .Draw {
		rect := o.ui_layout_rect(content_id)
		if o.pointer_hits(content_id, rect, .POPOVER) do ctx.pointer_inside = true
	}

	if o.ui_pass() == .Layout {
		align := props.config.anchor_align
		if ctx.rtl && align == .START do align = .END
		gap := props.config.anchor_gap
		if gap == 0 do gap = 4
		margin := props.config.viewport_margin
		if margin <= 0 do margin = 8
		side := o.Layout_Popup_Side.BOTTOM
		if sub do side = ctx.rtl ? .LEFT : .RIGHT
		o.layout_anchor_popup(anchor, content_id, gap, margin, false, align, side)
	}

	popover_panel({config = cfg, child = props.child})
}

