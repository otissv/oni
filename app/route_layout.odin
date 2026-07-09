package app

import o "../oni"
import set "../oni/set"
import w "../oni/widgets"
import ui "./ui"

@(private)
direction: o.Direction_Layout = .HORIZONTAL
layout_width: o.Width = .AUTO
layout_height: o.Height = .AUTO

layout_route :: proc() {
	w.Rectangle({
		config = {id = "home_rect", padding = set.Padding(4), width = set.Width(200)},
		child = proc(state: w.Rectangle_State) {
			Layout_sidebar()

			w.Rectangle({
				config = {id = "container"},
				child = proc(state: w.Rectangle_State) {
					Layout_1("layout-1", direction)
				},
			})
		},
	})
}

@(private)
Layout_sidebar :: proc() {
	w.Rectangle({
		config = {
			id = "horizontal",
			x = set.F32(0),
			y = set.F32(0),
			width = set.Width(300),
			border = set.Border(o.Bd{r = 1}),
			border_color = set.Border_color(.GRAY_500),
			direction = set.Direction(.VERTICAL),
			justify = set.Justify(o.Justify_Pos{x = .STRETCH, y = .STRETCH}),
			gap = set.Gap(0),
		},
		child = proc(state: w.Rectangle_State) {
			ui.Button({
				id = "horizontal",
				variant = .GHOST,
				justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
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
					direction = .HORIZONTAL_WRAP_REVERSE
					layout_width = 400
					layout_height = .AUTO
				},
				child = proc(_: ui.Button_state) {
					w.Text(
						{config = {id = "artboard-nav-button", text = "Horizontal Wrap Reverse"}},
					)
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
				},
				child = proc(_: ui.Button_state) {
					w.Text({config = {id = "artboard-nav-button", text = "Vertical Wrap Reverse"}})
				},
			})
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
			gap = set.Gap(u16(8)),
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
