package app

import oni "../oni"
import set "../oni/set"
import wg "../oni/widgets"
import ui "./ui"


direction: oni.Direction_Layout = .HORIZONTAL


layout_route :: proc() {
	wg.Rectangle({
		config = {
			id = "home_rect",
			x = set.F32(0),
			y = set.F32(60),
			direction = set.Direction(.VERTICAL),
		},
		child = proc(state: wg.Rectangle_State) {
			wg.Rectangle({
				config = {id = "layouts", x = set.F32(0), y = set.F32(0)},
				child = proc(state: wg.Rectangle_State) {
					wg.Rectangle({
						config = {id = "horizontal", x = set.F32(0), y = set.F32(0)},
						child = proc(state: wg.Rectangle_State) {
							ui.Button({
								id = "horizontal-button",
								child = proc(_: ui.Button_state) {
									wg.Text(
										{id = "artboard-nav-button", text = "Horizontal Reverse"},
									)
								},
								on_click = proc(_: ui.Button_Event) {
									direction = .HORIZONTAL_REVERSE
								},
							})
						},
					})
				},
			})

			Layout_1("layout-1", 0, 0, direction)
		},
	})
}

// Layout_Horizontal :: proc(id: string, x: f32, y: f32) {
// 	wg.Rectangle({
// 		config = {
// 			id = id,
// 			x = set.F32(x),
// 			y = set.F32(y),
// 			space = set.Space(.SCREEN),
// 			direction = set.Direction(.HORIZONTAL),
// 			gap = set.Gap(u16(8)),
// 			padding = set.Padding(f32(20)),
// 			justify = set.Justify(oni.Justify_Pos{x = .SPACE_AROUND}),
// 			background = set.Colors(oni.theme.palette[.BACKGROUND]),
// 			radius = set.Radius(oni.Radius_corners{tl = 10, tr = 10}),
// 			border = set.Border(f32(10)),
// 			border_color = set.Colors(oni.Color.YELLOW_500),
// 		},
// 		child = proc(state: wg.Rectangle_State) {
// 			wg.Rectangle(
// 				{
// 					config = {
// 						id = "left",
// 						width = 100,
// 						height = 30,
// 						background = set.Colors(oni.theme.palette[.DESTRUCTIVE]),
// 					},
// 				},
// 			)
// 			wg.Rectangle({
// 				config = {
// 					id = "center",
// 					background = set.Colors(oni.theme.palette[.ACCENT]),
// 					height = 100,
// 				},
// 				child = proc(state: wg.Rectangle_State) {
// 					ui.Label(
// 						{
// 							id = "label",
// 							theme = &persistent.app.theme,
// 							text = "label",
// 							size = .Large,
// 						},
// 					)
// 				},
// 			})
// 			wg.Rectangle(
// 				{
// 					config = {
// 						id = "right",
// 						width = 100,
// 						height = 100,
// 						background = set.Colors(oni.theme.palette[.SUCCESS]),
// 					},
// 				},
// 			)
// 			wg.Rectangle(
// 				{
// 					config = {
// 						id = "end",
// 						width = 100,
// 						height = 100,
// 						background = set.Colors(oni.theme.palette[.INFO]),
// 					},
// 				},
// 			)
// 		},
// 	})
// }

Layout_1 :: proc(id: string, x: f32, y: f32, direction: oni.Direction_Layout) {
	wg.Rectangle({
		config = {
			id = id,
			x = set.F32(x),
			y = set.F32(y),
			width = 500,
			height = 500,
			space = set.Space(.SCREEN),
			direction = set.Direction(direction),
			gap = set.Gap(u16(8)),
			padding = set.Padding(oni.Pd{t = 10, b = 10}),
			justify = set.Justify(oni.Justify_Pos{x = .STRETCH, y = .SPACE_BETWEEN}),
			background = set.Colors(oni.theme.palette[.BACKGROUND]),
			radius = set.Radius(10),
			border = set.Border(10),
			border_color = set.Colors(oni.Color.YELLOW_500),
		},
		child = proc(state: wg.Rectangle_State) {
			wg.Rectangle(
				{
					config = {
						id = "top-1",
						width = 100,
						height = 100,
						background = set.Colors(oni.theme.palette[.DESTRUCTIVE]),
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
					},
				},
			)
			wg.Rectangle(
				{
					config = {
						id = "bottom",
						width = 100,
						height = 100,
						background = set.Colors(oni.theme.palette[.SUCCESS]),
					},
				},
			)
			wg.Rectangle(
				{
					config = {
						id = "bottom-1",
						width = 100,
						height = 100,
						background = set.Colors(oni.theme.palette[.INFO]),
					},
				},
			)
		},
	})
}
