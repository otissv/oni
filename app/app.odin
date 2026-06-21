package app

import oni "../oni"
import set "../oni/set"
import w "../oni/widgets"
import "core:fmt"


Heading :: proc() {
	theme := &persistent.app.theme

	w.Text(
		{
			id = "heading",
			width = set.Width(480),
			height = set.Height(28),
			text = "Artboard text — zoomable",
			font = set.Font(theme.font_heading),
			color = set.Colors(oni.theme.palette[.Accent]),
			font_size = set.F32(20),
			line_height = set.F32(0),
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
			width = set.Width(480),
			height = set.Height(200),
			text = "ui_paragraph in artboard space. Scroll to zoom (quantized 0.1 steps). Pan with middle mouse or Alt+drag. Glyphs re-rasterize at the display size so text stays sharp.",
			font = set.Font(theme.font_body),
			font_size = set.F32(20),
			line_height = set.F32(1.5),
			color = set.Colors(paragraph_color),
		},
	)
}

Rectangle :: proc() {
	w.Rectangle({
		config = {
			id = "artboard-panel",
			x = set.F32(80),
			y = set.F32(80),
			width = 520,
			height = 340,
			background = set.Colors(oni.theme.palette[.Surface]),
			radius = set.Radius(f32(10)),
			space = set.Space(.Artboard),
			direction = set.Direction(.Vertical),
			padding = set.Padding(oni.PADDING_MD),
			gap = set.Gap(u16(12)),
			justify = set.Justify(oni.Justify_Pos{x = .Stretch, y = .Start}),
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
			x = set.F32(16),
			y = set.F32(6),
			width = set.Width(600),
			height = set.Height(24),
			text = hud,
			font = set.Font(theme.font_body),
			color = set.Colors(oni.theme.palette[.White]),
			text_direction = set.Text_Direction(.LTR),
			font_size = set.F32(16),
			line_height = set.F32(1),
			space = set.Space(.Screen),
		},
	)
}

Layout_Horizontal :: proc(id: string, x: f32, y: f32) {
	w.Rectangle({
		config = {
			id = id,
			x = set.F32(x),
			y = set.F32(y),
			width = 500,
			height = 200,
			space = set.Space(.Screen),
			direction = set.Direction(.Horizontal),
			gap = set.Gap(u16(8)),
			padding = set.Padding(f32(20)),
			justify = set.Justify(oni.Justify_Pos{x = .Start, y = .Stretch}),
			background = set.Colors(oni.theme.palette[.Surface]),
			radius = set.Radius(oni.Radius_corners{tl = 10, tr = 10}),
			border = set.Border(f32(10)),
			border_color = set.Colors(oni.Color.Yellow_500),
		},
		child = proc(state: w.Rectangle_State) {
			w.Rectangle(
				{
					config = {
						id = "left",
						width = 100,
						background = set.Colors(oni.theme.palette[.Danger]),
					},
				},
			)
			w.Rectangle(
				{
					config = {
						id = "center",
						flex = set.F32(1),
						background = set.Colors(oni.theme.palette[.Accent]),
					},
				},
			)
			w.Rectangle(
				{
					config = {
						id = "right",
						width = 100,
						background = set.Colors(oni.theme.palette[.Success]),
					},
				},
			)

		},
	})
}

Layout_Vertical :: proc(id: string, x: f32, y: f32) {
	w.Rectangle({
		config = {
			id = id,
			x = set.F32(x),
			y = set.F32(y),
			width = 500,
			height = 500,
			space = set.Space(.Screen),
			direction = set.Direction(.Vertical),
			gap = set.Gap(u16(8)),
			padding = set.Padding(oni.Pd{t = 10, b = 10}),
			justify = set.Justify(oni.Justify_Pos{x = .Stretch, y = .Start}),
			background = set.Colors(oni.theme.palette[.Surface]),
			radius = set.Radius(f32(10)),
			border = set.Border(f32(10)),
			border_color = set.Colors(oni.Color.Yellow_500),
		},
		child = proc(state: w.Rectangle_State) {
			w.Rectangle(
				{
					config = {
						id = "top",
						width = 100,
						height = 60,
						background = set.Colors(oni.theme.palette[.Danger]),
					},
				},
			)
			w.Rectangle(
				{
					config = {
						id = "center",
						flex = set.F32(1),
						background = set.Colors(oni.theme.palette[.Accent]),
					},
				},
			)
			w.Rectangle(
				{
					config = {
						id = "bottom",
						height = 60,
						background = set.Colors(oni.theme.palette[.Success]),
					},
				},
			)
		},
	})
}

@(private)
view :: proc() {
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
	oni.Render(view)
}
