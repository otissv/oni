package layout_route

import ui "../../../app/ui"
import o "../../../oni"
import set "../../../oni/set"
import w "../../../oni/widgets"

@(private)
Layout_Demo :: enum {
	DIRECTION,
	CONTENT_ALIGN,
	ORDER,
	Z_INDEX,
	POSITION,
	VISIBILITY,
	OPACITY,
}

@(private)
demo: Layout_Demo = .DIRECTION
direction: o.Direction_Layout = .HORIZONTAL
layout_width: o.Width = .AUTO
layout_height: o.Height = .AUTO
content_align_x: o.Justify_Align = .MAX_CONTENT
content_align_y: o.Justify_Align = .START


container := proc(state: w.Rectangle_State) {
	switch demo {
	case .DIRECTION:
		Layout_1("layout-1", direction)
	case .CONTENT_ALIGN:
		Layout_Content("layout-content")
	case .ORDER:
		Layout_Order("layout-order")
	case .Z_INDEX:
		Layout_Z_Index("layout-z-index")
	case .POSITION:
		Layout_Position("layout-position")
	case .VISIBILITY:
		Layout_Visibility("layout-visibility")
	case .OPACITY:
		Layout_Opacity("layout-opacity")
	}
}

sidebar := proc(state: w.Rectangle_State) {
	ui.Button({
		id = "horizontal",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			demo = .DIRECTION
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
			demo = .DIRECTION
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
			demo = .DIRECTION
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
			demo = .DIRECTION
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
			demo = .DIRECTION
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
			demo = .DIRECTION
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
			demo = .DIRECTION
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
			demo = .DIRECTION
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
			demo = .CONTENT_ALIGN
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
			demo = .CONTENT_ALIGN
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
			demo = .CONTENT_ALIGN
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
			demo = .CONTENT_ALIGN
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
			demo = .ORDER
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
			demo = .Z_INDEX
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
			demo = .POSITION
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
			demo = .VISIBILITY
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
			demo = .OPACITY
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "layout-opacity-nav", text = "Opacity"}})
		},
	})
}

@(private)
Layout_1 :: proc(id: string, direction: o.Direction_Layout) {
	w.Rectangle({
		config = {
			id = id,
			space = set.Space(.SCREEN),
			direction = set.Direction(direction),
			gap_x = set.Gap_X(u16(8)),
			gap_y = set.Gap_Y(u16(8)),
			width = set.Width(layout_width),
			height = set.Height(layout_height),
			padding = set.Padding(f32(20)),
			justify = set.Justify(o.Justify_Pos{x = .SPACE_AROUND}),
			background = set.Colors(o.theme.palette[.BACKGROUND]),
			radius = set.Radius(10),
			border = set.Border(f32(1)),
			border_color = set.Colors(o.Color.YELLOW_500),
		},
		child = proc(state: w.Rectangle_State) {
			w.Rectangle(
				{
					config = {
						id = "left",
						width = 100,
						height = 100,
						background = set.Colors(o.theme.palette[.DESTRUCTIVE]),
						radius = set.Radius(10),
					},
				},
			)
			w.Rectangle(
				{
					config = {
						id = "center",
						width = 100,
						height = 100,
						background = set.Colors(o.theme.palette[.ACCENT]),
						radius = set.Radius(10),
					},
				},
			)
			w.Rectangle(
				{
					config = {
						id = "right",
						width = 100,
						height = 100,
						background = set.Colors(o.theme.palette[.SUCCESS]),
						radius = set.Radius(10),
					},
				},
			)
			w.Rectangle(
				{
					config = {
						id = "end",
						width = 100,
						height = 100,
						background = set.Colors(o.theme.palette[.INFO]),
						radius = set.Radius(10),
					},
				},
			)
		},
	})
}

@(private)
Layout_Content :: proc(id: string) {
	w.Rectangle({
		config = {
			id = id,
			space = set.Space(.SCREEN),
			direction = set.Direction(direction),
			gap_x = set.Gap_X(u16(8)),
			gap_y = set.Gap_Y(u16(8)),
			width = set.Width(layout_width),
			height = set.Height(layout_height),
			padding = set.Padding(f32(20)),
			justify = set.Justify(o.Justify_Pos{x = content_align_x, y = content_align_y}),
			background = set.Colors(o.theme.palette[.BACKGROUND]),
			radius = set.Radius(10),
			border = set.Border(f32(1)),
			border_color = set.Colors(o.Color.YELLOW_500),
		},
		child = proc(state: w.Rectangle_State) {
			w.Rectangle({
				config = {
					id = "short",
					height = 60,
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.DESTRUCTIVE]),
					radius = set.Radius(8),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "short-label", text = "sm"}})
				},
			})
			w.Rectangle({
				config = {
					id = "medium",
					height = 80,
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.ACCENT]),
					radius = set.Radius(8),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "medium-label", text = "md"}})
				},
			})
			w.Rectangle({
				config = {
					id = "long",
					height = 90,
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.SUCCESS]),
					radius = set.Radius(8),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "long-label", text = "lg"}})
				},
			})
			w.Rectangle({
				config = {
					id = "fixed",
					width = 140,
					height = 100,
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.INFO]),
					radius = set.Radius(8),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "fixed-label", text = "fixed"}})
				},
			})
		},
	})
}

@(private)
Layout_Order :: proc(id: string) {
	// Source order A B C D; flex order rearranges to C B D A.
	w.Rectangle({
		config = {
			id = id,
			space = set.Space(.SCREEN),
			direction = set.Direction(.HORIZONTAL),
			gap_x = set.Gap_X(u16(8)),
			padding = set.Padding(f32(20)),
			background = set.Colors(o.theme.palette[.BACKGROUND]),
			radius = set.Radius(10),
			border = set.Border(f32(1)),
			border_color = set.Colors(o.Color.YELLOW_500),
		},
		child = proc(_: w.Rectangle_State) {
			w.Rectangle({
				config = {
					id = "order-a",
					width = 100,
					height = 100,
					order = set.Order(3),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.DESTRUCTIVE]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "order-a-label", text = "A order=3"}})
				},
			})
			w.Rectangle({
				config = {
					id = "order-b",
					width = 100,
					height = 100,
					order = set.Order(1),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.ACCENT]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "order-b-label", text = "B order=1"}})
				},
			})
			w.Rectangle({
				config = {
					id = "order-c",
					width = 100,
					height = 100,
					order = set.Order(0),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.SUCCESS]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "order-c-label", text = "C order=0"}})
				},
			})
			w.Rectangle({
				config = {
					id = "order-d",
					width = 100,
					height = 100,
					order = set.Order(2),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.INFO]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "order-d-label", text = "D order=2"}})
				},
			})
		},
	})
}

@(private)
Layout_Z_Index :: proc(id: string) {
	w.Rectangle({
		config = {
			id = id,
			space = set.Space(.SCREEN),
			width = set.Width(f32(360)),
			height = set.Height(f32(260)),
			padding = set.Padding(f32(20)),
			background = set.Colors(o.theme.palette[.BACKGROUND]),
			radius = set.Radius(10),
			border = set.Border(f32(1)),
			border_color = set.Colors(o.Color.YELLOW_500),
		},
		child = proc(_: w.Rectangle_State) {
			w.Rectangle({
				config = {
					id = "z-back",
					width = 140,
					height = 140,
					position = set.Position(.ABSOLUTE),
					x = set.F32(40),
					y = set.F32(40),
					z_index = set.Z_Index(-1),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.DESTRUCTIVE]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "z-back-label", text = "z=-1"}})
				},
			})
			w.Rectangle({
				config = {
					id = "z-mid",
					width = 140,
					height = 140,
					position = set.Position(.ABSOLUTE),
					x = set.F32(90),
					y = set.F32(70),
					z_index = set.Z_Index(0),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.ACCENT]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "z-mid-label", text = "z=0"}})
				},
			})
			w.Rectangle({
				config = {
					id = "z-front",
					width = 140,
					height = 140,
					position = set.Position(.ABSOLUTE),
					x = set.F32(140),
					y = set.F32(100),
					z_index = set.Z_Index(2),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.SUCCESS]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "z-front-label", text = "z=2"}})
				},
			})
		},
	})
}

@(private)
Layout_Position :: proc(id: string) {
	w.Rectangle({
		config = {
			id = id,
			space = set.Space(.SCREEN),
			direction = set.Direction(.HORIZONTAL),
			gap_x = set.Gap_X(u16(8)),
			width = set.Width(f32(420)),
			height = set.Height(f32(220)),
			padding = set.Padding(f32(20)),
			background = set.Colors(o.theme.palette[.BACKGROUND]),
			radius = set.Radius(10),
			border = set.Border(f32(1)),
			border_color = set.Colors(o.Color.YELLOW_500),
		},
		child = proc(_: w.Rectangle_State) {
			w.Rectangle({
				config = {
					id = "pos-relative",
					width = 110,
					height = 90,
					position = set.Position(.RELATIVE),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.DESTRUCTIVE]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "pos-relative-label", text = "relative"}})
				},
			})
			w.Rectangle({
				config = {
					id = "pos-flow",
					width = 110,
					height = 90,
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.ACCENT]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "pos-flow-label", text = "in flow"}})
				},
			})
			w.Rectangle({
				config = {
					id = "pos-absolute",
					width = 120,
					height = 80,
					position = set.Position(.ABSOLUTE),
					x = set.F32(160),
					y = set.F32(120),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.SUCCESS]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "pos-absolute-label", text = "absolute"}})
				},
			})
			w.Rectangle({
				config = {
					id = "pos-fixed",
					width = 100,
					height = 60,
					position = set.Position(.FIXED),
					right = set.Right(24),
					bottom = set.Bottom(24),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.INFO]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "pos-fixed-label", text = "fixed"}})
				},
			})
		},
	})
}

@(private)
Layout_Visibility :: proc(id: string) {
	// VISIBLE paints; HIDDEN keeps layout space; NONE is removed from the tree.
	w.Rectangle({
		config = {
			id = id,
			space = set.Space(.SCREEN),
			direction = set.Direction(.HORIZONTAL),
			gap_x = set.Gap_X(u16(8)),
			padding = set.Padding(f32(20)),
			background = set.Colors(o.theme.palette[.BACKGROUND]),
			radius = set.Radius(10),
			border = set.Border(f32(1)),
			border_color = set.Colors(o.Color.YELLOW_500),
		},
		child = proc(_: w.Rectangle_State) {
			w.Rectangle({
				config = {
					id = "vis-visible",
					width = 100,
					height = 100,
					visibility = set.Visibility(.VISIBLE),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.DESTRUCTIVE]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "vis-visible-label", text = "VISIBLE"}})
				},
			})
			w.Rectangle({
				config = {
					id = "vis-hidden",
					width = 100,
					height = 100,
					visibility = set.Visibility(.HIDDEN),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.ACCENT]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "vis-hidden-label", text = "HIDDEN"}})
				},
			})
			w.Rectangle({
				config = {
					id = "vis-none",
					width = 100,
					height = 100,
					visibility = set.Visibility(.NONE),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.SUCCESS]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "vis-none-label", text = "NONE"}})
				},
			})
			w.Rectangle({
				config = {
					id = "vis-after",
					width = 100,
					height = 100,
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.INFO]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "vis-after-label", text = "after"}})
				},
			})
		},
	})
}

@(private)
Layout_Opacity :: proc(id: string) {
	// Local opacities multiply down the tree (CSS group opacity).
	w.Rectangle({
		config = {
			id = id,
			space = set.Space(.SCREEN),
			direction = set.Direction(.HORIZONTAL),
			gap_x = set.Gap_X(u16(8)),
			padding = set.Padding(f32(20)),
			background = set.Colors(o.theme.palette[.BACKGROUND]),
			radius = set.Radius(10),
			border = set.Border(f32(1)),
			border_color = set.Colors(o.Color.YELLOW_500),
			justify = set.Justify(o.Justify_Pos{y = .CENTER}),
		},
		child = proc(_: w.Rectangle_State) {
			w.Rectangle({
				config = {
					id = "op-1",
					width = 100,
					height = 100,
					opacity = set.Opacity(1),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.DESTRUCTIVE]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "op-1-label", text = "1"}})
				},
			})
			w.Rectangle({
				config = {
					id = "op-05",
					width = 100,
					height = 100,
					opacity = set.Opacity(0.5),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.ACCENT]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "op-05-label", text = "0.5"}})
				},
			})
			w.Rectangle({
				config = {
					id = "op-025",
					width = 100,
					height = 100,
					opacity = set.Opacity(0.25),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.SUCCESS]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "op-025-label", text = "0.25"}})
				},
			})
			w.Rectangle({
				config = {
					id = "op-nested",
					width = 120,
					height = 120,
					opacity = set.Opacity(0.5),
					padding = set.Padding(f32(12)),
					background = set.Colors(o.theme.palette[.INFO]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Rectangle({
						config = {
							id = "op-nested-child",
							width = 80,
							height = 80,
							opacity = set.Opacity(0.5),
							padding = set.Padding(f32(6)),
							background = set.Colors(o.theme.palette[.DESTRUCTIVE]),
							radius = set.Radius(6),
							justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
						},
						child = proc(_: w.Rectangle_State) {
							w.Text({config = {id = "op-nested-label", text = "0.5×0.5"}})
						},
					})
				},
			})
		},
	})
}
