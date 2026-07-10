package layout_route

import ui "../../../app/ui"
import o "../../../oni"
import set "../../../oni/set"
import w "../../../oni/widgets"

@(private)
direction: o.Direction_Layout = .HORIZONTAL
layout_width: o.Width = .AUTO
layout_height: o.Height = .AUTO
content_align_demo: bool
content_align_x: o.Justify_Align = .MAX_CONTENT
content_align_y: o.Justify_Align = .START


container := proc(state: w.Rectangle_State) {
	if content_align_demo {
		Layout_Content("layout-content")
	} else {
		Layout_1("layout-1", direction)
	}
}

sidebar := proc(state: w.Rectangle_State) {
	ui.Button({
		id = "horizontal",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			direction = .HORIZONTAL
			layout_width = .AUTO
			layout_height = .AUTO
			content_align_demo = false

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
			direction = .HORIZONTAL_REVERSE
			layout_width = .AUTO
			layout_height = .AUTO
			content_align_demo = false
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
			direction = .HORIZONTAL_WRAP
			layout_width = 400
			layout_height = .AUTO
			content_align_demo = false
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
			direction = .HORIZONTAL_WRAP_REVERSE
			layout_width = 400
			layout_height = .AUTO
			content_align_demo = false
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
			direction = .VERTICAL
			layout_width = .AUTO
			layout_height = .AUTO
			content_align_demo = false
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
			direction = .VERTICAL_REVERSE
			layout_width = .AUTO
			layout_height = .AUTO
			content_align_demo = false
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
			direction = .VERTICAL_WRAP
			layout_width = 280
			layout_height = 400
			content_align_demo = false
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
			direction = .VERTICAL_WRAP_REVERSE
			layout_width = 280
			layout_height = 400
			content_align_demo = false
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
			content_align_demo = true
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
			content_align_demo = true
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
			content_align_demo = true
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
			content_align_demo = true
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
