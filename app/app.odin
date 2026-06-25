package app

import oni "../oni"
import set "../oni/set"
import wg "../oni/widgets"
import ui "./ui"
import "core:fmt"


PANEL_STATE_INITIALIZED: bool
ONI_IMAGE_PATH :: "assets/oni-2.avif"

@(private)
panel_state: Panel_State
Panel_State :: struct {
	background: oni.Cfg(oni.Colors),
	x:          oni.Cfg(f32),
}

@(private)
image_texture: oni.Texture_Handle


@(private)
init_state :: proc() {
	if PANEL_STATE_INITIALIZED do return
	PANEL_STATE_INITIALIZED = true

	panel := Panel_State {
		background = set.Colors(oni.theme.palette[.Background]),
		x          = set.F32(80),
	}
	panel_state = panel

	tex, ok := oni.Load_Texture(ONI_IMAGE_PATH)
	if ok do image_texture = tex
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
			space = set.Space(.Artboard),
			direction = set.Direction(.Vertical),
			padding = set.Padding(oni.PADDING_MD),
			gap = set.Gap(u16(12)),
			justify = set.Justify(oni.Justify_Pos{x = .Stretch, y = .Start}),
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
							width = .Auto,
							height = set.Height(28),
							text = "Click me",
							font = set.Font(oni.theme.font_heading),
							color = set.Colors(oni.theme.palette[.Foreground]),
							font_size = set.F32(20),
							line_height = set.F32(0),
						},
					)
				},
			})
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
	wg.Text(
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
	wg.Rectangle({
		config = {
			id = id,
			x = set.F32(x),
			y = set.F32(y),
			space = set.Space(.Screen),
			direction = set.Direction(.Horizontal),
			gap = set.Gap(u16(8)),
			padding = set.Padding(f32(20)),
			justify = set.Justify(oni.Justify_Pos{x = .Space_around}),
			background = set.Colors(oni.theme.palette[.Background]),
			radius = set.Radius(oni.Radius_corners{tl = 10, tr = 10}),
			border = set.Border(f32(10)),
			border_color = set.Colors(oni.Color.Yellow_500),
		},
		child = proc(state: wg.Rectangle_State) {
			wg.Rectangle(
				{
					config = {
						id = "left",
						width = 100,
						height = 30,
						background = set.Colors(oni.theme.palette[.Destructive]),
					},
				},
			)
			wg.Rectangle({
				config = {
					id = "center",
					background = set.Colors(oni.theme.palette[.Accent]),
					height = 100,
				},
				child = proc(state: wg.Rectangle_State) {
					ui.Label(
						{
							id = "label",
							theme = &persistent.app.theme,
							text = "label",
							size = .Large,
						},
					)
				},
			})
			wg.Rectangle(
				{
					config = {
						id = "right",
						width = 100,
						height = 100,
						background = set.Colors(oni.theme.palette[.Success]),
					},
				},
			)
			wg.Rectangle(
				{
					config = {
						id = "end",
						width = 100,
						height = 100,
						background = set.Colors(oni.theme.palette[.Info]),
					},
				},
			)
		},
	})
}

Layout_Vertical :: proc(id: string, x: f32, y: f32) {
	wg.Rectangle({
		config = {
			id = id,
			x = set.F32(x),
			y = set.F32(y),
			width = 400,
			height = 400,
			space = set.Space(.Screen),
			direction = set.Direction(.Vertical_Wrap),
			gap = set.Gap(u16(8)),
			padding = set.Padding(oni.Pd{t = 10, b = 10}),
			justify = set.Justify(oni.Justify_Pos{x = .Stretch, y = .Space_between}),
			background = set.Colors(oni.theme.palette[.Background]),
			radius = set.Radius(10),
			border = set.Border(10),
			border_color = set.Colors(oni.Color.Yellow_500),
		},
		child = proc(state: wg.Rectangle_State) {
			wg.Rectangle(
				{
					config = {
						id = "top-1",
						width = 100,
						height = 100,
						background = set.Colors(oni.theme.palette[.Destructive]),
					},
				},
			)
			wg.Rectangle(
				{
					config = {
						id = "center",
						width = 100,
						height = 100,
						background = set.Colors(oni.theme.palette[.Accent]),
					},
				},
			)
			wg.Rectangle(
				{
					config = {
						id = "bottom",
						width = 100,
						height = 100,
						background = set.Colors(oni.theme.palette[.Success]),
					},
				},
			)
			wg.Rectangle(
				{
					config = {
						id = "bottom-1",
						width = 100,
						height = 100,
						background = set.Colors(oni.theme.palette[.Info]),
					},
				},
			)
		},
	})
}


@(private)
view :: proc() {
	init_state()

	oni.Begin_Artboard()
	Panel()


	wg.Image(
		{
			texture = image_texture,
			config = {
				id           = "bottom-1",
				x            = set.F32(16),
				y            = set.F32(480),
				width        = 464,
				height       = 464,
				background   = set.Colors(oni.theme.palette[.Info]),
				radius       = set.Radius(10),
				border       = set.Border(10),
				border_color = set.Colors(oni.Color.Yellow_500),
				texture_fit  = set.Image_Fit(.NONE),
				texture_pos  = set.Image_Pos({x = 50, y = 50}), // center
			},
		},
	)


	oni.End_Artboard()

	oni.Begin_Screen()
	Hud()

	// Layout_Horizontal("layout-demo-1", x = 16, y = 480)
	// Layout_Vertical("layout-demo-2", x = 16, y = 850)


	oni.End_Screen()
}

app_draw :: proc() {
	oni.Render(view)
}
