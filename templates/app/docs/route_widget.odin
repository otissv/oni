package oni_docs

import ui "../../app/ui"
import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"


@(private)
Sidebar_Widgets_options :: enum {
	WIDGET_BUTTON,
	WIDGET_IMAGE,
	WIDGET_PRESERVE,
	WIDGET_RECTANGLE,
	WIDGET_RICH_TEXT,
	WIDGET_TEXT,
	WIDGET_TABLE,
}

@(private)
active_widget_option: Sidebar_Widgets_options = .WIDGET_TABLE


widget_container := proc(state: w.Rectangle_State) {
	switch active_widget_option {
	// Widgets
	case .WIDGET_RECTANGLE:
		Widget_Rectangle()
	case .WIDGET_TABLE:
		Widget_Table()
	case .WIDGET_IMAGE:
		Widget_Image()
	case .WIDGET_BUTTON:
		Widget_Button()
	case .WIDGET_PRESERVE:
		Widget_Preserve()
	case .WIDGET_RICH_TEXT:
		Widget_Rich_Text()
	case .WIDGET_TEXT:
		WidgetText()
	}
}

widget_sidebar := proc(state: w.Rectangle_State) {
	ui.Button({
		id = "widget_sidebar_button_rect",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_widget_option = .WIDGET_RECTANGLE
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
			active_widget_option = .WIDGET_BUTTON
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
			active_widget_option = .WIDGET_IMAGE

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
			active_widget_option = .WIDGET_TABLE

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
			active_widget_option = .WIDGET_TEXT
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "widget_sidebar_button_text_text", text = "Text"}})
		},
	})

	ui.Button({
		id = "widget_sidebar_button_rich_text",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_widget_option = .WIDGET_RICH_TEXT
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "widget_sidebar_button_rich_text_text", text = "RichText"}})
		},
	})

	ui.Button({
		id = "widget_sidebar_button_preserve",
		variant = .GHOST,
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			active_widget_option = .WIDGET_PRESERVE
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "widget_sidebar_button_preserve_text", text = "Preserve"}})
		},
	})

}
