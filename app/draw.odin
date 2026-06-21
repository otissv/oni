package app

import oni "../oni"
import w "../oni/widgets"
import "core:fmt"


Heading :: proc() {
	theme := &persistent.app.theme

	w.Text(
		{
			id = "heading",
			width = 480,
			height = 28,
			text = "Artboard text — zoomable",
			font = theme.font_heading,
			color = oni.theme.palette[.Accent],
			font_size = 20,
			line_height = 0,
		},
	)
}

Paragraph :: proc() {
	theme := &persistent.app.theme

	paragraph_color :: proc(
		state: oni.Widget_State,
		widget_event: oni.Widget_Event(oni.Widget_State),
	) -> oni.Colors {
		if state.is_Pressed do return oni.RGBA{0, 0, 0, 255}
		if state.is_hovered do return oni.RGBA{210, 60, 60, 255}
		return oni.theme.palette[.Text]
	}

	w.Text(
		{
			id = "paragraph",
			width = 480,
			height = 200,
			text = "ui_paragraph in artboard space. Scroll to zoom (quantized 0.1 steps). Pan with middle mouse or Alt+drag. Glyphs re-rasterize at the display size so text stays sharp.",
			font = theme.font_body,
			font_size = 20,
			line_height = 1.5,
			color = paragraph_color,
		},
	)
}

Rectangle :: proc() {
	w.Rectangle({
		config = {
			id = "artboard-panel",
			x = 80,
			y = 80,
			width = 520,
			height = 340,
			background = oni.theme.palette[.Surface],
			radius = 10,
			space = .Artboard,
			direction = .Vertical,
			padding = oni.PADDING_MD,
			gap = 12,
			justify = oni.Justify_Pos{x = .Stretch, y = .Start},
		},
		child = proc(state: w.Rectangle_State) {
			Heading()
			Paragraph()
		},
	})
}

Hud :: proc() {
	theme := &persistent.app.theme
	zoom := oni.View_Effective_Zoom()

	hud := fmt.tprintf(
		"Screen HUD  zoom: %.1fx  (scroll / Ctrl+=/- zoom, Ctrl+0 reset, Alt+LMB pan)",
		zoom,
	)
	w.Text(
		{
			id = "hud-zoom",
			x = 16,
			y = 6,
			width = 600,
			height = 24,
			text = hud,
			font = theme.font_body,
			color = oni.theme.palette[.White],
			text_direction = .LTR,
			font_size = 16,
			line_height = 1,
			space = .Screen,
		},
	)
}

Layout_Horizontal :: proc(id: string, x: f32, y: f32) {
	w.Rectangle({
		config = {
			id = id,
			x = x,
			y = y,
			width = 500,
			height = 200,
			space = .Screen,
			direction = .Horizontal,
			gap = 8,
			padding = 20,
			justify = oni.Justify_Pos{x = .Start, y = .Stretch},
			background = oni.theme.palette[.Surface],
			radius = oni.Radius_corners{tl = 10, tr = 10},
			border = 10,
			border_color = .Yellow_500,
		},
		child = proc(state: w.Rectangle_State) {
			w.Rectangle(
				{config = {id = "left", width = 100, background = oni.theme.palette[.Danger]}},
			)
			w.Rectangle(
				{config = {id = "center", flex = 1, background = oni.theme.palette[.Accent]}},
			)
			w.Rectangle(
				{config = {id = "right", width = 100, background = oni.theme.palette[.Success]}},
			)

		},
	})
}

Layout_Vertical :: proc(id: string, x: f32, y: f32) {
	w.Rectangle({
		config = {
			id = id,
			x = x,
			y = y,
			width = 500,
			height = 500,
			space = .Screen,
			direction = .Vertical,
			gap = 8,
			padding = oni.Padding{t = 10, b = 10},
			justify = oni.Justify_Pos{x = .Stretch, y = .Start},
			background = oni.theme.palette[.Surface],
			radius = 10,
			border = 10,
			border_color = .Yellow_500,
		},
		child = proc(state: w.Rectangle_State) {
			w.Rectangle(
				{
					config = {
						id = "top",
						width = 100,
						height = 60,
						background = oni.theme.palette[.Danger],
					},
				},
			)
			w.Rectangle(
				{config = {id = "center", flex = 1, background = oni.theme.palette[.Accent]}},
			)
			w.Rectangle(
				{config = {id = "bottom", height = 60, background = oni.theme.palette[.Success]}},
			)
		},
	})
}
@(private)
app_ui :: proc() {
	oni.Begin_Artboard()
	Rectangle()
	oni.End_Artboard()

	oni.Begin_Screen()
	Hud()
	Layout_Horizontal("layout-demo-1", x = 16, y = 520)
	Layout_Vertical("layout-demo-2", x = 16, y = 750)
	oni.End_Screen()
}

app_draw :: proc() {
	w.BeginFrame()

	app_ui()
	w.EndLayoutPass()

	app_ui()
	w.EndFrame()
}
