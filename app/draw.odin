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
			font = oni.cfg_font_explicit(theme.font_heading),
			color = oni.cfg_colors_explicit(oni.theme.palette[.Accent]),
			font_size = oni.cfg_f32_explicit(20),
			line_height = oni.cfg_f32_explicit(0),
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
			font = oni.cfg_font_explicit(theme.font_body),
			font_size = oni.cfg_f32_explicit(20),
			line_height = oni.cfg_f32_explicit(1.5),
			color = oni.cfg_colors_explicit(paragraph_color),
		},
	)
}

Rectangle :: proc() {
	w.Rectangle({
		config = {
			id = "artboard-panel",
			x = oni.cfg_f32_explicit(80),
			y = oni.cfg_f32_explicit(80),
			width = 520,
			height = 340,
			background = oni.cfg_colors_explicit(oni.theme.palette[.Surface]),
			radius = oni.cfg_radius_explicit(f32(10)),
			space = oni.cfg_space_explicit(.Artboard),
			direction = oni.cfg_direction_explicit(.Vertical),
			padding = oni.cfg_padding_explicit(oni.PADDING_MD),
			gap = oni.cfg_gap_explicit(u16(12)),
			justify = oni.cfg_justify_explicit(oni.Justify_Pos{x = .Stretch, y = .Start}),
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
			x = oni.cfg_f32_explicit(16),
			y = oni.cfg_f32_explicit(6),
			width = 600,
			height = 24,
			text = hud,
			font = oni.cfg_font_explicit(theme.font_body),
			color = oni.cfg_colors_explicit(oni.theme.palette[.White]),
			text_direction = oni.cfg_text_direction_explicit(.LTR),
			font_size = oni.cfg_f32_explicit(16),
			line_height = oni.cfg_f32_explicit(1),
			space = oni.cfg_space_explicit(.Screen),
		},
	)
}

Layout_Horizontal :: proc(id: string, x: f32, y: f32) {
	w.Rectangle({
		config = {
			id = id,
			x = oni.cfg_f32_explicit(x),
			y = oni.cfg_f32_explicit(y),
			width = 500,
			height = 200,
			space = oni.cfg_space_explicit(.Screen),
			direction = oni.cfg_direction_explicit(.Horizontal),
			gap = oni.cfg_gap_explicit(u16(8)),
			padding = oni.cfg_padding_explicit(f32(20)),
			justify = oni.cfg_justify_explicit(oni.Justify_Pos{x = .Start, y = .Stretch}),
			background = oni.cfg_colors_explicit(oni.theme.palette[.Surface]),
			radius = oni.cfg_radius_explicit(oni.Radius_corners{tl = 10, tr = 10}),
			border = oni.cfg_border_explicit(f32(10)),
			border_color = oni.cfg_colors_explicit(oni.Color.Yellow_500),
		},
		child = proc(state: w.Rectangle_State) {
			w.Rectangle(
				{
					config = {
						id = "left",
						width = 100,
						background = oni.cfg_colors_explicit(oni.theme.palette[.Danger]),
					},
				},
			)
			w.Rectangle(
				{
					config = {
						id = "center",
						flex = oni.cfg_f32_explicit(1),
						background = oni.cfg_colors_explicit(oni.theme.palette[.Accent]),
					},
				},
			)
			w.Rectangle(
				{
					config = {
						id = "right",
						width = 100,
						background = oni.cfg_colors_explicit(oni.theme.palette[.Success]),
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
			x = oni.cfg_f32_explicit(x),
			y = oni.cfg_f32_explicit(y),
			width = 500,
			height = 500,
			space = oni.cfg_space_explicit(.Screen),
			direction = oni.cfg_direction_explicit(.Vertical),
			gap = oni.cfg_gap_explicit(u16(8)),
			padding = oni.cfg_padding_explicit(oni.Pd{t = 10, b = 10}),
			justify = oni.cfg_justify_explicit(oni.Justify_Pos{x = .Stretch, y = .Start}),
			background = oni.cfg_colors_explicit(oni.theme.palette[.Surface]),
			radius = oni.cfg_radius_explicit(f32(10)),
			border = oni.cfg_border_explicit(f32(10)),
			border_color = oni.cfg_colors_explicit(oni.Color.Yellow_500),
		},
		child = proc(state: w.Rectangle_State) {
			w.Rectangle(
				{
					config = {
						id = "top",
						width = 100,
						height = 60,
						background = oni.cfg_colors_explicit(oni.theme.palette[.Danger]),
					},
				},
			)
			w.Rectangle(
				{
					config = {
						id = "center",
						flex = oni.cfg_f32_explicit(1),
						background = oni.cfg_colors_explicit(oni.theme.palette[.Accent]),
					},
				},
			)
			w.Rectangle(
				{
					config = {
						id = "bottom",
						height = 60,
						background = oni.cfg_colors_explicit(oni.theme.palette[.Success]),
					},
				},
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
