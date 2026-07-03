package app

import oni "../oni"
import set "../oni/set"
import wg "../oni/widgets"
import ui "./ui"

artboard_route :: proc() {
	wg.Rectangle({
		config = {
			id = "screen_rect",
			x = set.F32(0),
			y = set.F32(60),
			background = set.Colors(oni.theme.palette[.BACKGROUND]),
		},
		child = proc(state: wg.Rectangle_State) {
			oni.Begin_Artboard()
			Panel()
			oni.End_Artboard()
		},
	})
}


Panel :: proc() {
	wg.Rectangle({
		config = {
			id = "artboard-panel",
			x = panel_state.x,
			y = set.F32(80),
			width = 520,
			height = 340,
			background = panel_state.background,
			radius = set.Radius(f32(10)),
			space = set.Space(.ARTBOARD),
			direction = set.Direction(.VERTICAL),
			padding = set.Padding(oni.PADDING_MD),
			gap = set.Gap(u16(12)),
			justify = set.Justify(oni.Justify_Pos{x = .STRETCH, y = .START}),
			border = set.Border(10),
			border_color = set.Colors(oni.theme.palette[.FOREGROUND]),
		},
		child = proc(state: wg.Rectangle_State) {
			ui.Heading({id = "heading", text = "Artboard heading", theme = &persistent.app.theme})

			ui.Paragraph(
				{
					id = "paragraph",
					text = "ui_paragraph in artboard space. Scroll to zoom (quantized 0.1 steps). Pan with middle mouse or Alt+drag. Glyphs re-rasterize at the display size so text stays sharp.",
					theme = &persistent.app.theme,
				},
			)

			ui.Button({
				id = "button",
				radius = set.Radius(20),
				child = proc(_: ui.Button_state) {
					wg.Text(
						{
							id = "button",
							width = .AUTO,
							height = set.Height(28),
							text = "Click me",
							font = set.Font(oni.theme.font_heading),
							color = set.Colors(oni.theme.palette[.FOREGROUND]),
							font_size = set.F32(20),
							line_height = set.F32(0),
						},
					)
				},
			})
		},
	})
}
