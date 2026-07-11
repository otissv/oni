package widgets_route

import ui "../../../app/ui"
import o "../../../oni"
import set "../../../oni/set"
import w "../../../oni/widgets"


@(private)
Sidebar_Widgets_options :: enum {
	BUTTON,
	IMAGE,
	RECTANGLE,
	TEXT,
	TABLE,
}

@(private)
active_widget_option: Sidebar_Widgets_options = .TABLE

container := proc(state: w.Rectangle_State) {
	switch active_widget_option {
	case .RECTANGLE:
		Widget_Rectangle()
	case .TABLE:
		Widget_Table()
	case .IMAGE:
		Widget_Image()
	case .BUTTON:
		Widget_Button()
	case .TEXT:
		WidgetText()
	}
}

sidebar := proc(state: w.Rectangle_State) {
	ui.Button({
		id = "widget_sidebar_button_rect",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_widget_option = .RECTANGLE
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "widget_sidebar_button_rect_text", text = "Rectangle"}})
		},
	})

	ui.Button({
		id = "widget_sidebar_button_button",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_widget_option = .BUTTON
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "widget_sidebar_button_button_text", text = "Button"}})
		},
	})


	ui.Button({
		id = "widget_sidebar_button_image",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_widget_option = .IMAGE

		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "widget_sidebar_button_image_text", text = "Image"}})
		},
	})

	ui.Button({
		id = "widget_sidebar_button_table",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_widget_option = .TABLE

		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "widget_sidebar_button_table_text", text = "Table"}})
		},
	})

	ui.Button({
		id = "widget_sidebar_button_text",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_widget_option = .TEXT
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "widget_sidebar_button_text_text", text = "Text"}})
		},
	})

}
