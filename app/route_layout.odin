package app

import oni "../oni"
import set "../oni/set"
import wg "../oni/widgets"
import ui "./ui"


direction: oni.Direction_Layout = .HORIZONTAL
layout_width: oni.Width = .AUTO
layout_height: oni.Height = .AUTO

layout_route :: proc() {
	wg.Rectangle({
		config = {id = "home_rect", x = set.F32(0), y = set.F32(60), padding = set.Padding(4)},
		child = proc(state: wg.Rectangle_State) {
			Layout_sideBar()

			wg.Rectangle({
				config = {id = "container"},
				child = proc(state: wg.Rectangle_State) {
					Layout_1("layout-1", direction)
				},
			})

		},
	})
}

Layout_sideBar :: proc() {
	wg.Rectangle({
		config = {
			id = "horizontal",
			x = set.F32(0),
			y = set.F32(0),
			direction = set.Direction(.VERTICAL),
			justify = set.Justify(oni.Justify_Pos{x = .STRETCH, y = .STRETCH}),
			gap = set.Gap(0),
		},
		child = proc(state: wg.Rectangle_State) {
			ui.Button({
				id = "horizontal",
				variant = .GHOST,
				justify = set.Justify(oni.Justify_Pos{x = .START, y = .START}),
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					direction = .HORIZONTAL
					layout_width = .AUTO
					layout_height = .AUTO

				},
				child = proc(_: ui.Button_state) {
					wg.Text({id = "artboard-nav-button", text = "Horizontal"})
				},
			})

			ui.Button({
				id = "horizontal-reverse",
				variant = .GHOST,
				justify = set.Justify(oni.Justify_Pos{x = .START, y = .START}),
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					direction = .HORIZONTAL_REVERSE
					layout_width = .AUTO
					layout_height = .AUTO
				},
				child = proc(_: ui.Button_state) {
					wg.Text({id = "artboard-nav-button", text = "Horizontal Reverse"})
				},
			})

			ui.Button({
				id = "horizontal-wrap",
				variant = .GHOST,
				justify = set.Justify(oni.Justify_Pos{x = .START, y = .START}),
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					direction = .HORIZONTAL_WRAP
					layout_width = 400
					layout_height = .AUTO
				},
				child = proc(_: ui.Button_state) {
					wg.Text({id = "artboard-nav-button", text = "Horizontal Wrap"})
				},
			})

			ui.Button({
				id = "horizontal-wrap-reverse",
				variant = .GHOST,
				radius = set.Radius(5),
				justify = set.Justify(oni.Justify_Pos{x = .START, y = .START}),
				on_click = proc(_: ui.Button_Event) {
					direction = .HORIZONTAL_WRAP_REVERSE
					layout_width = 400
					layout_height = .AUTO
				},
				child = proc(_: ui.Button_state) {
					wg.Text({id = "artboard-nav-button", text = "Horizontal Wrap Reverse"})
				},
			})

			ui.Button({
				id = "vertical",
				variant = .GHOST,
				justify = set.Justify(oni.Justify_Pos{x = .START, y = .START}),
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					direction = .VERTICAL
					layout_width = .AUTO
					layout_height = .AUTO
				},
				child = proc(_: ui.Button_state) {
					wg.Text({id = "artboard-nav-button", text = "Vertical"})
				},
			})

			ui.Button({
				id = "vertical-reverse",
				variant = .GHOST,
				justify = set.Justify(oni.Justify_Pos{x = .START, y = .START}),
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					direction = .VERTICAL_REVERSE
					layout_width = .AUTO
					layout_height = .AUTO
				},
				child = proc(_: ui.Button_state) {
					wg.Text({id = "artboard-nav-button", text = "Vertical Reverse"})
				},
			})

			ui.Button({
				id = "vertical warp",
				variant = .GHOST,
				justify = set.Justify(oni.Justify_Pos{x = .START, y = .START}),
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					direction = .VERTICAL_WRAP
					layout_width = 280
					layout_height = 400
				},
				child = proc(_: ui.Button_state) {
					wg.Text({id = "artboard-nav-button", text = "Vertical Wrap"})
				},
			})

			ui.Button({
				id = "vertical-wrap-reverse",
				variant = .GHOST,
				justify = set.Justify(oni.Justify_Pos{x = .START, y = .START}),
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					direction = .VERTICAL_WRAP_REVERSE
					layout_width = 280
					layout_height = 400
				},
				child = proc(_: ui.Button_state) {
					wg.Text({id = "artboard-nav-button", text = "Vertical Wrap Reverse"})
				},
			})
		},
	})
}

Layout_1 :: proc(id: string, direction: oni.Direction_Layout) {
	wg.Rectangle({
		config = {
			id = id,
			space = set.Space(.SCREEN),
			direction = set.Direction(direction),
			gap = set.Gap(u16(8)),
			width = set.Width(layout_width),
			height = set.Height(layout_height),
			padding = set.Padding(f32(20)),
			justify = set.Justify(oni.Justify_Pos{x = .SPACE_AROUND}),
			background = set.Colors(oni.theme.palette[.BACKGROUND]),
			radius = set.Radius(10),
			border = set.Border(f32(1)),
			border_color = set.Colors(oni.Color.YELLOW_500),
		},
		child = proc(state: wg.Rectangle_State) {
			wg.Rectangle(
				{
					config = {
						id = "left",
						width = 100,
						height = 100,
						background = set.Colors(oni.theme.palette[.DESTRUCTIVE]),
						radius = set.Radius(10),
					},
				},
			)
			wg.Rectangle(
				{
					config = {
						id = "center",
						width = 100,
						height = 100,
						background = set.Colors(oni.theme.palette[.ACCENT]),
						radius = set.Radius(10),
					},
				},
			)
			wg.Rectangle(
				{
					config = {
						id = "right",
						width = 100,
						height = 100,
						background = set.Colors(oni.theme.palette[.SUCCESS]),
						radius = set.Radius(10),
					},
				},
			)
			wg.Rectangle(
				{
					config = {
						id = "end",
						width = 100,
						height = 100,
						background = set.Colors(oni.theme.palette[.INFO]),
						radius = set.Radius(10),
					},
				},
			)
		},
	})
}
