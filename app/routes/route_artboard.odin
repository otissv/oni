package routes

import ui "../../app/ui"
import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"

artboard_route :: proc() {
	w.Rectangle({
		config = {id = "screen_rect", background = set.Colors(o.theme.palette[.BACKGROUND])},
		child = proc(state: w.Rectangle_State) {
			o.Begin_Artboard()
			Panel()
			o.End_Artboard()
		},
	})
}


Panel :: proc() {
	w.Rectangle({
		config = {
			id = "artboard-panel",
			width = 520,
			height = 340,
			background = set.Colors(o.theme.palette[.SECONDARY]),
			radius = set.Radius(f32(10)),
			space = set.Space(.ARTBOARD),
			direction = set.Direction(.VERTICAL),
			padding = set.Padding(o.PADDING_MD),
			gap_x = set.Gap_X(u16(12)),
			gap_y = set.Gap_Y(u16(12)),
			justify = set.Justify(o.Justify_Pos{x = .STRETCH, y = .START}),
			border = set.Border(10),
			border_color = set.Colors(o.theme.palette[.FOREGROUND]),
		},
		child = proc(state: w.Rectangle_State) {
			ui.Heading({id = "heading", text = "Artboard heading", theme = o.theme})

			ui.Paragraph(
				{
					id = "paragraph",
					text = "ui_paragraph in artboard space. Scroll to zoom (quantized 0.1 steps). Pan with middle mouse or Alt+drag. Glyphs re-rasterize at the display size so text stays sharp.",
					theme = o.theme,
				},
			)

			ui.Button({
				id = "button",
				radius = set.Radius(20),
				child = proc(_: ui.Button_state) {
					w.Text(
						{
							config = {
								id = "button",
								width = .AUTO,
								height = set.Height(28),
								text = "Click me",
								font = set.Font(o.theme.font_heading),
								color = set.Colors(o.theme.palette[.FOREGROUND]),
								font_size = set.F32(20),
								line_height = set.F32(0),
							},
						},
					)
				},
			})
		},
	})
}
