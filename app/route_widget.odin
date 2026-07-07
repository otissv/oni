package app

import ui "../app/ui"
import o "../oni"
import "../oni/set"
import w "../oni/widgets"

@(private)
Sidebar_Widgets_options :: enum {
	Button,
	Image,
	Rectangle,
	Text,
}

@(private)
active_widget_option: Sidebar_Widgets_options = .Rectangle

widgets_route :: proc() {
	w.Rectangle({
		config = {id = "home_rect", padding = set.Padding(4)},
		child = proc(state: w.Rectangle_State) {
			Widget_sidebar()

			w.Rectangle({
				config = {id = "container"},
				child = proc(state: w.Rectangle_State) {

					#partial switch active_widget_option {
					case .Rectangle:
						Widget_Rectangle()
					}
				},
			})

		},
	})
}

@(private)
Widget_sidebar :: proc() {
	w.Rectangle({
		config = {
			id = "widget_sidebar",
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
				id = "widget_sidebar_button_rect",
				variant = .GHOST,
				justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					active_widget_option = .Rectangle
				},
				child = proc(_: ui.Button_state) {
					w.Text({id = "widget_sidebar_button_rect_text", text = "Rectangle"})
				},
			})
		},
	})
}


Widget_Rectangle :: proc() {
	w.Rectangle(
		{
			config = {
				id = "horizontal",
				height = set.Height(400),
				width = set.Width(400),
				direction = set.Direction(.VERTICAL),
				justify = set.Justify(o.Justify_Pos{x = .STRETCH, y = .STRETCH}),
				gap = set.Gap(0),
				background = set.Colors(.SKY_500),
			},
		},
	)
}
