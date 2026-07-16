package oni_docs

import ui "../../app/ui"
import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"


@(private)
Sidebar_Layout_options :: enum {
	// Layout
	LAYOUT_HORIZONTAL,
	LAYOUT_VERTICAL,
	LAYOUT_HORIZONTAL_WRAP,
	LAYOUT_VERTICAL_WRAP,
	LAYOUT_HORIZONTAL_REVERSE,
	LAYOUT_VERTICAL_REVERSE,
	LAYOUT_HORIZONTAL_WRAP_REVERSE,
	LAYOUT_VERTICAL_WRAP_REVERSE,
	LAYOUT_MAX_CONTENT_X,
	LAYOUT_MIN_CONTENT_X,
	LAYOUT_MAX_CONTENT_Y,
	LAYOUT_MIN_CONTENT_Y,
	LAYOUT_ORDER,
	LAYOUT_Z_INDEX,
	LAYOUT_POSITION,
	LAYOUT_VISIBILITY,
	LAYOUT_OPACITY,
	LAYOUT_POPOVER,
}

@(private)
active_layout_option: Sidebar_Layout_options = .LAYOUT_HORIZONTAL

direction: o.Direction_Layout = .HORIZONTAL
layout_width: o.Width = .AUTO
layout_height: o.Height = .AUTO
content_align_x: o.Justify_Align = .MAX_CONTENT
content_align_y: o.Justify_Align = .START

layout_container := proc(state: w.Rectangle_State) {
	switch active_layout_option {
	// Layout
	case .LAYOUT_HORIZONTAL:
		Layout_Directions(direction, layout_width, layout_height)
	case .LAYOUT_VERTICAL:
		Layout_Directions(direction, layout_width, layout_height)
	case .LAYOUT_HORIZONTAL_WRAP:
		Layout_Directions(direction, layout_width, layout_height)
	case .LAYOUT_VERTICAL_WRAP:
		Layout_Directions(direction, layout_width, layout_height)
	case .LAYOUT_HORIZONTAL_REVERSE:
		Layout_Directions(direction, layout_width, layout_height)
	case .LAYOUT_VERTICAL_REVERSE:
		Layout_Directions(direction, layout_width, layout_height)
	case .LAYOUT_HORIZONTAL_WRAP_REVERSE:
		Layout_Directions(direction, layout_width, layout_height)
	case .LAYOUT_VERTICAL_WRAP_REVERSE:
		Layout_Content(direction, layout_width, layout_height, content_align_x, content_align_y)
	case .LAYOUT_MAX_CONTENT_X:
		Layout_Content(direction, layout_width, layout_height, content_align_x, content_align_y)
	case .LAYOUT_MIN_CONTENT_X:
		Layout_Content(direction, layout_width, layout_height, content_align_x, content_align_y)
	case .LAYOUT_MAX_CONTENT_Y:
		Layout_Content(direction, layout_width, layout_height, content_align_x, content_align_y)
	case .LAYOUT_MIN_CONTENT_Y:
		Layout_Content(direction, layout_width, layout_height, content_align_x, content_align_y)
	case .LAYOUT_ORDER:
		Layout_Order()
	case .LAYOUT_Z_INDEX:
		Layout_Z_Index()
	case .LAYOUT_POSITION:
		Layout_Position()
	case .LAYOUT_VISIBILITY:
		Layout_Visibility()
	case .LAYOUT_OPACITY:
		Layout_Opacity()
	case .LAYOUT_POPOVER:
		Layout_Popover()
	}
}

layout_sidebar := proc(state: w.Rectangle_State) {
	ui.Button({
		id = "horizontal",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_layout_option = .LAYOUT_HORIZONTAL
			direction = .HORIZONTAL
			layout_width = .AUTO
			layout_height = .AUTO
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "artboard-nav-button", text = "Horizontal"}})
		},
	})

	ui.Button({
		id = "horizontal-reverse",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_layout_option = .LAYOUT_HORIZONTAL_REVERSE
			direction = .HORIZONTAL_REVERSE
			layout_width = .AUTO
			layout_height = .AUTO
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "artboard-nav-button", text = "Horizontal Reverse"}})
		},
	})

	ui.Button({
		id = "horizontal-wrap",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_layout_option = .LAYOUT_HORIZONTAL_WRAP
			direction = .HORIZONTAL_WRAP
			layout_width = 400
			layout_height = .AUTO
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "artboard-nav-button", text = "Horizontal Wrap"}})
		},
	})

	ui.Button({
		id = "horizontal-wrap-reverse",
		variant = .GHOST,
		radius = set.Radius(5),
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		on_click = proc(_: ui.Button_Event) {
			active_layout_option = .LAYOUT_HORIZONTAL_WRAP_REVERSE
			direction = .HORIZONTAL_WRAP_REVERSE
			layout_width = 400
			layout_height = .AUTO
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "artboard-nav-button", text = "Horizontal Wrap Reverse"}})
		},
	})

	ui.Button({
		id = "vertical",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_layout_option = .LAYOUT_VERTICAL
			direction = .VERTICAL
			layout_width = .AUTO
			layout_height = .AUTO
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "artboard-nav-button", text = "Vertical"}})
		},
	})

	ui.Button({
		id = "vertical-reverse",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_layout_option = .LAYOUT_VERTICAL_REVERSE
			direction = .VERTICAL_REVERSE
			layout_width = .AUTO
			layout_height = .AUTO
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "artboard-nav-button", text = "Vertical Reverse"}})
		},
	})

	ui.Button({
		id = "vertical warp",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_layout_option = .LAYOUT_VERTICAL_WRAP
			direction = .VERTICAL_WRAP
			layout_width = 280
			layout_height = 400
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "artboard-nav-button", text = "Vertical Wrap"}})
		},
	})

	ui.Button({
		id = "vertical-wrap-reverse",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_layout_option = .LAYOUT_VERTICAL_WRAP_REVERSE
			direction = .VERTICAL_WRAP_REVERSE
			layout_width = 280
			layout_height = 400
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "artboard-nav-button", text = "Vertical Wrap Reverse"}})
		},
	})

	ui.Button({
		id = "max-content-x",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_layout_option = .LAYOUT_MAX_CONTENT_X
			content_align_x = .MAX_CONTENT
			content_align_y = .START
			direction = .HORIZONTAL
			layout_width = .AUTO
			layout_height = .AUTO
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "artboard-nav-button", text = "Max Content X"}})
		},
	})

	ui.Button({
		id = "min-content-x",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_layout_option = .LAYOUT_MIN_CONTENT_X
			content_align_x = .MIN_CONTENT
			content_align_y = .START
			direction = .HORIZONTAL
			layout_width = .AUTO
			layout_height = .AUTO
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "artboard-nav-button", text = "Min Content X"}})
		},
	})

	ui.Button({
		id = "max-content-y",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_layout_option = .LAYOUT_MAX_CONTENT_Y
			content_align_x = .START
			content_align_y = .MAX_CONTENT
			direction = .VERTICAL
			layout_width = .AUTO
			layout_height = .AUTO
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "artboard-nav-button", text = "Max Content Y"}})
		},
	})

	ui.Button({
		id = "min-content-y",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_layout_option = .LAYOUT_MIN_CONTENT_Y
			content_align_x = .START
			content_align_y = .MIN_CONTENT
			direction = .VERTICAL
			layout_width = .AUTO
			layout_height = .AUTO
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "artboard-nav-button", text = "Min Content Y"}})
		},
	})

	ui.Button({
		id = "order",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_layout_option = .LAYOUT_ORDER
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "layout-order-nav", text = "Order"}})
		},
	})

	ui.Button({
		id = "z-index",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_layout_option = .LAYOUT_Z_INDEX
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "layout-z-index-nav", text = "Z-Index"}})
		},
	})

	ui.Button({
		id = "position",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_layout_option = .LAYOUT_POSITION
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "layout-position-nav", text = "Position"}})
		},
	})

	ui.Button({
		id = "visibility",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_layout_option = .LAYOUT_VISIBILITY
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "layout-visibility-nav", text = "Visibility"}})
		},
	})

	ui.Button({
		id = "opacity",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_layout_option = .LAYOUT_OPACITY
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "layout-opacity-nav", text = "Opacity"}})
		},
	})

	ui.Button({
		id = "popover",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_layout_option = .LAYOUT_POPOVER
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "layout-popover-nav", text = "Popover"}})
		},
	})
}
