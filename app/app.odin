package app

import oni "../oni"
import set "../oni/set"
import wg "../oni/widgets"
import tengu "../tengu"
import ui "./ui"
import "core:fmt"


// ONI_IMAGE_PATH :: "assets/oni-2.avif"
// LIFECYCLE_PANEL_ID :: "lifecycle-demo-panel"
// LIFECYCLE_UNMOUNT_DURATION :: tengu.Seconds(0.3)


// @(private)
// panel_state: Panel_State
// Panel_State :: struct {
// 	background: oni.Cfg(oni.Colors),
// 	x:          oni.Cfg(f32),
// }

// @(private)
// lifecycle_demo_state: Lifecycle_Demo_State
// Lifecycle_Demo_State :: struct {
// 	show:                bool,
// 	opacity:             f32,
// 	mount_spring:        tengu.Spring_State(f32),
// 	mount_spring_ready:  bool,
// 	unmount_tween:       tengu.Tween_State(f32),
// 	unmount_tween_ready: bool,
// }

// @(private)
// image_texture: oni.Texture_Handle


// @(init)
// register_init :: proc "contextless" () {
// 	init = run_init
// }

// @(private)
// run_init :: proc() {
// 	panel := Panel_State {
// 		background = set.Colors(oni.theme.palette[.SECONDARY]),
// 		x          = set.F32(80),
// 	}
// 	panel_state = panel

// 	lifecycle_demo_state = Lifecycle_Demo_State {
// 		show    = true,
// 		opacity = 1,
// 	}

// 	tex, ok := oni.Load_Texture(ONI_IMAGE_PATH)
// 	if ok do image_texture = tex
// }


// Panel :: proc() {
// 	wg.Rectangle({
// 		config = {
// 			id = "artboard-panel",
// 			x = panel_state.x,
// 			y = set.F32(80),
// 			width = 520,
// 			height = 340,
// 			background = panel_state.background,
// 			radius = set.Radius(f32(10)),
// 			space = set.Space(.ARTBOARD),
// 			direction = set.Direction(.VERTICAL),
// 			padding = set.Padding(oni.PADDING_MD),
// 			gap = set.Gap(u16(12)),
// 			justify = set.Justify(oni.Justify_Pos{x = .STRETCH, y = .START}),
// 		},
// 		child = proc(state: wg.Rectangle_State) {
// 			ui.Heading({id = "heading", text = "Artboard heading", theme = &persistent.app.theme})

// 			ui.Paragraph(
// 				{
// 					id = "paragraph",
// 					text = "ui_paragraph in artboard space. Scroll to zoom (quantized 0.1 steps). Pan with middle mouse or Alt+drag. Glyphs re-rasterize at the display size so text stays sharp.",
// 					theme = &persistent.app.theme,
// 				},
// 			)

// 			ui.Button({
// 				id = "button",
// 				radius = set.Radius(20),
// 				child = proc(_: ui.Button_state) {
// 					wg.Text(
// 						{
// 							id = "button",
// 							width = .AUTO,
// 							height = set.Height(28),
// 							text = "Click me",
// 							font = set.Font(oni.theme.font_heading),
// 							color = set.Colors(oni.theme.palette[.FOREGROUND]),
// 							font_size = set.F32(20),
// 							line_height = set.F32(0),
// 						},
// 					)
// 				},
// 			})
// 		},
// 	})
// }

// Hud :: proc() {
// 	theme := &persistent.app.theme
// 	zoom := oni.View_Effective_Zoom()

// 	hud := fmt.tprintf(
// 		"Screen HUD  zoom: %.1fx  (scroll / Ctrl+=/- zoom, Ctrl+0 reset, Alt+LMB pan)",
// 		zoom,
// 	)
// 	wg.Text(
// 		{
// 			id = "hud-zoom",
// 			x = set.F32(16),
// 			y = set.F32(6),
// 			width = set.Width(600),
// 			height = set.Height(24),
// 			text = hud,
// 			font = set.Font(theme.font_body),
// 			color = set.Colors(oni.theme.palette[.WHITE]),
// 			text_direction = set.Text_Direction(.LTR),
// 			font_size = set.F32(16),
// 			line_height = set.F32(1),
// 			space = set.Space(.SCREEN),
// 		},
// 	)
// }

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

// Layout_Vertical :: proc(id: string, x: f32, y: f32) {
// 	wg.Rectangle({
// 		config = {
// 			id = id,
// 			x = set.F32(x),
// 			y = set.F32(y),
// 			width = 400,
// 			height = 400,
// 			space = set.Space(.SCREEN),
// 			direction = set.Direction(.VERTICAL_WRAP),
// 			gap = set.Gap(u16(8)),
// 			padding = set.Padding(oni.Pd{t = 10, b = 10}),
// 			justify = set.Justify(oni.Justify_Pos{x = .STRETCH, y = .SPACE_BETWEEN}),
// 			background = set.Colors(oni.theme.palette[.BACKGROUND]),
// 			radius = set.Radius(10),
// 			border = set.Border(10),
// 			border_color = set.Colors(oni.Color.YELLOW_500),
// 		},
// 		child = proc(state: wg.Rectangle_State) {
// 			wg.Rectangle(
// 				{
// 					config = {
// 						id = "top-1",
// 						width = 100,
// 						height = 100,
// 						background = set.Colors(oni.theme.palette[.DESTRUCTIVE]),
// 					},
// 				},
// 			)
// 			wg.Rectangle(
// 				{
// 					config = {
// 						id = "center",
// 						width = 100,
// 						height = 100,
// 						background = set.Colors(oni.theme.palette[.ACCENT]),
// 					},
// 				},
// 			)
// 			wg.Rectangle(
// 				{
// 					config = {
// 						id = "bottom",
// 						width = 100,
// 						height = 100,
// 						background = set.Colors(oni.theme.palette[.SUCCESS]),
// 					},
// 				},
// 			)
// 			wg.Rectangle(
// 				{
// 					config = {
// 						id = "bottom-1",
// 						width = 100,
// 						height = 100,
// 						background = set.Colors(oni.theme.palette[.INFO]),
// 					},
// 				},
// 			)
// 		},
// 	})
// }


// @(private)
// lifecycle_demo_background :: proc(
// 	_: oni.Widget_Frame_State,
// 	_: oni.Widget_Event(oni.Widget_Frame_State),
// ) -> oni.Colors {
// 	base := oni.theme.palette[.ACCENT]
// 	alpha := u8(min(max(lifecycle_demo_state.opacity, 0), 1) * 255)
// 	return oni.RGBA{base.r, base.g, base.b, alpha}
// }

// @(private)
// lifecycle_demo_on_mount :: proc(_: wg.Rectangle_State) -> oni.Mount {
// 	dt := f32(oni.Frame_Time())

// 	if !lifecycle_demo_state.mount_spring_ready {
// 		tengu.spring_init(
// 			tengu.Spring_Init_Params(f32) {
// 				state = &lifecycle_demo_state.mount_spring,
// 				config = tengu.spring_default_config(f32(1)),
// 				start_value = lifecycle_demo_state.opacity,
// 			},
// 		)
// 		lifecycle_demo_state.mount_spring_ready = true
// 	}

// 	result := tengu.spring_step(
// 		tengu.Motion_Step_Params(f32) {
// 			state = &lifecycle_demo_state.mount_spring,
// 			dt = dt,
// 			anim = tengu.F32_Animatable(),
// 			completion = tengu.DEFAULT_COMPLETION_POLICY,
// 			time = tengu.DEFAULT_TIME_POLICY,
// 		},
// 	)
// 	lifecycle_demo_state.opacity = result.value
// 	return result.done ? .COMPLETED : .RUNNING
// }

// @(private)
// lifecycle_demo_on_unmount :: proc(_: wg.Rectangle_State) -> oni.Mount {
// 	dt := f32(oni.Frame_Time())

// 	if !lifecycle_demo_state.unmount_tween_ready {
// 		tengu.tween_init(
// 			&lifecycle_demo_state.unmount_tween,
// 			tengu.Tween_Config(f32) {
// 				start = lifecycle_demo_state.opacity,
// 				target = 0,
// 				duration = LIFECYCLE_UNMOUNT_DURATION,
// 				easing = tengu.Ease.OUT_CUBIC,
// 			},
// 		)
// 		lifecycle_demo_state.unmount_tween_ready = true
// 	}

// 	result := tengu.tween_step(
// 		tengu.Step_Params(f32) {
// 			state = &lifecycle_demo_state.unmount_tween,
// 			dt = dt,
// 			anim = tengu.F32_Animatable(),
// 			completion = tengu.DEFAULT_COMPLETION_POLICY,
// 		},
// 	)
// 	lifecycle_demo_state.opacity = result.value
// 	return result.done ? .COMPLETED : .RUNNING
// }


// @(private)
// lifecycle_demo_panel_child :: proc(_: wg.Rectangle_State) {
// 	wg.Text(
// 		{
// 			id = "lifecycle-demo-title",
// 			text = "Mount / unmount demo",
// 			font = set.Font(oni.theme.font_heading),
// 			color = set.Colors(oni.theme.palette[.FOREGROUND]),
// 			font_size = set.F32(18),
// 		},
// 	)
// 	wg.Text(
// 		{
// 			id = "lifecycle-demo-body",
// 			text = "Springs in on mount, tweens out on unmount. Use the toggle above to hide.",
// 			font = set.Font(oni.theme.font_body),
// 			color = set.Colors(oni.theme.palette[.MUTED]),
// 			font_size = set.F32(14),
// 			line_height = set.F32(1.3),
// 		},
// 	)
// }


// @(private)
// Lifecycle_Demo :: proc() {
// 	panel_config := wg.Rectangle_Config {
// 		id           = LIFECYCLE_PANEL_ID,
// 		x            = set.F32(900),
// 		y            = set.F32(120),
// 		width        = 320,
// 		height       = 180,
// 		background   = set.Colors(lifecycle_demo_background),
// 		radius       = set.Radius(10),
// 		border       = set.Border(2),
// 		border_color = set.Colors(oni.theme.palette[.FOREGROUND]),
// 		space        = set.Space(.SCREEN),
// 		direction    = set.Direction(.VERTICAL),
// 		padding      = set.Padding(oni.PADDING_MD),
// 		gap          = set.Gap(u16(8)),
// 		justify      = set.Justify(oni.Justify_Pos{x = .STRETCH, y = .START}),
// 	}

// 	ui.Button({
// 		id = "lifecycle-toggle",
// 		variant = .OUTLINE,
// 		x = set.F32(900),
// 		y = set.F32(80),
// 		space = set.Space(.SCREEN),
// 		child = proc(_: ui.Button_state) {
// 			label := lifecycle_demo_state.show ? "Hide panel" : "Show panel"
// 			wg.Text(
// 				{
// 					id = "lifecycle-toggle-label",
// 					text = label,
// 					font = set.Font(oni.theme.font_body),
// 					color = set.Colors(oni.theme.palette[.FOREGROUND]),
// 					font_size = set.F32(14),
// 				},
// 			)
// 		},
// 		on_click = proc(_: ui.Button_Event) {
// 			if lifecycle_demo_state.show {
// 				lifecycle_demo_state.show = false
// 				lifecycle_demo_state.unmount_tween_ready = false
// 			} else {
// 				lifecycle_demo_state.opacity = 0
// 				lifecycle_demo_state.show = true
// 				lifecycle_demo_state.mount_spring_ready = false
// 			}
// 		},
// 	})

// 	if lifecycle_demo_state.show {
// 		wg.Rectangle(
// 			{
// 				config = panel_config,
// 				on_mount = lifecycle_demo_on_mount,
// 				child = lifecycle_demo_panel_child,
// 			},
// 		)
// 	} else {
// 		wg.Rectangle(
// 			{
// 				config = panel_config,
// 				unmount = true,
// 				on_unmount = lifecycle_demo_on_unmount,
// 				child = lifecycle_demo_panel_child,
// 			},
// 		)
// 	}
// }


// @(private)
// panel_view :: proc() {
// 	oni.Begin_Artboard()
// 	Panel()


// 	wg.Image(
// 		{
// 			texture = image_texture,
// 			config = {
// 				id           = "bottom-1",
// 				x            = set.F32(16),
// 				y            = set.F32(480),
// 				width        = 464,
// 				height       = 464,
// 				background   = set.Colors(oni.theme.palette[.INFO]),
// 				radius       = set.Radius(10),
// 				border       = set.Border(10),
// 				border_color = set.Colors(oni.Color.YELLOW_500),
// 				texture_fit  = set.Image_Fit(.NONE),
// 				texture_pos  = set.Image_Pos({x = 50, y = 50}), // center
// 			},
// 		},
// 	)


// 	oni.End_Artboard()

// 	oni.Begin_Screen()
// 	Hud()
// 	Lifecycle_Demo()

// 	// Layout_Horizontal("layout-demo-1", x = 16, y = 480)
// 	// Layout_Vertical("layout-demo-2", x = 16, y = 850)


// 	oni.End_Screen()
// }


Routes :: enum {
	Home,
	About,
}

Route: Routes = .Home

@(private)
frame_dt: f32

@(private)
Route_Fade :: struct {
	opacity: f32,
	tween:   tengu.Tween_State(f32),
}

@(private)
home_fade: Route_Fade
@(private)
about_fade: Route_Fade

@(private)
route_fade_step :: proc(fade: ^Route_Fade, mounting: oni.Mount) -> oni.Mount {
	if mounting == .UNSET {
		tengu.tween_init(
			&fade.tween,
			tengu.Tween_Config(f32) {
				start = 0,
				target = 1,
				duration = tengu.Seconds(60),
				easing = tengu.Ease.LINEAR,
				repeat_count = 1,
			},
		)
		fade.opacity = 0
	}

	result := tengu.tween_step(
		tengu.Step_Params(f32) {
			state = &fade.tween,
			dt = frame_dt,
			anim = tengu.F32_Animatable(),
			completion = tengu.DEFAULT_COMPLETION_POLICY,
		},
	)
	fade.opacity = result.value
	return result.done ? .COMPLETED : .RUNNING
}

@(private)
active_route_fade :: proc() -> ^Route_Fade {
	switch Route {
	case .Home:
		return &home_fade
	case .About:
		return &about_fade
	}
	return &home_fade
}

@(private)
route_fade_elapsed_text :: proc() -> string {
	fade := active_route_fade()
	if tengu.tween_is_finished(fade.tween) do return ""
	return fmt.tprintf("%.2f s", fade.tween.elapsed)
}

@(private)
route_fade_color :: proc(base: oni.RGBA, opacity: f32) -> oni.Colors {
	alpha := u8(min(max(opacity, 0), 1) * 255)
	return oni.RGBA{base.r, base.g, base.b, alpha}
}

@(private)
home_background :: proc(
	_: oni.Widget_Frame_State,
	_: oni.Widget_Event(oni.Widget_Frame_State),
) -> oni.Colors {
	return route_fade_color(oni.theme.palette[.RED_500], home_fade.opacity)
}

@(private)
about_background :: proc(
	_: oni.Widget_Frame_State,
	_: oni.Widget_Event(oni.Widget_Frame_State),
) -> oni.Colors {
	return route_fade_color(oni.theme.palette[.BLUE_500], about_fade.opacity)
}

home_route :: proc() {
	wg.Rectangle({
		config = {
			id = "home_rect",
			x = set.F32(0),
			y = set.F32(60),
			background = set.Colors(home_background),
		},
		on_mount = proc(frame_state: wg.Rectangle_State) -> oni.Mount {
			return route_fade_step(&home_fade, frame_state.mounting)
		},
	})
}

about_route :: proc() {
	wg.Rectangle({
		config = {
			id = "about_rect",
			x = set.F32(0),
			y = set.F32(60),
			background = set.Colors(about_background),
		},
		on_mount = proc(frame_state: wg.Rectangle_State) -> oni.Mount {
			return route_fade_step(&about_fade, frame_state.mounting)
		},
	})
}


Nav :: proc() {
	wg.Rectangle({
		config = {id = "nav", x = set.F32(16), y = set.F32(16)},
		child = proc(state: wg.Rectangle_State) {
			ui.Button({
				id = "nav-home-button",
				variant = .OUTLINE,
				child = proc(_: ui.Button_state) {
					wg.Text({id = "home-nav-button", text = "Home"})
				},
				on_click = proc(_: ui.Button_Event) {
					Route = .Home
					oni.Log_Debug("Home")
				},
			})
			ui.Button({
				id = "nav-animate-button",
				variant = .OUTLINE,
				child = proc(_: ui.Button_state) {
					wg.Text({id = "animate-nav-button", text = "Animate"})
				},
				on_click = proc(_: ui.Button_Event) {
					Route = .About
				},
			})
			wg.Text({id = "route-fade-elapsed-text", text = route_fade_elapsed_text()})
			wg.Text({id = "opacity-text", text = fmt.tprintf("Opacity: %.2f", about_fade.opacity)})
		},
	})
}

draw_ui :: proc() {
	oni.Begin_Screen()

	Nav()

	ui.Paragraph(
		{
			id = "opacity-text",
			text = "HELLO",
			x = set.F32(480),
			y = set.F32(480),
			theme = &persistent.app.theme,
		},
	)

	switch Route {
	case .Home:
		home_route()
	case .About:
		about_route()
	case:
		home_route()
	}

	oni.End_Screen()
}

app_draw :: proc() {
	oni.Render(draw_ui)
}
