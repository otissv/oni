package app

import ui "../app/ui"
import o "../oni"
import "../oni/set"
import w "../oni/widgets"

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

widgets_route :: proc() {
	w.Rectangle({
		config = {id = "home_rect", padding = set.Padding(4), gap = set.Gap(o.theme.gap)},
		child = proc(state: w.Rectangle_State) {
			Widget_sidebar()

			w.Rectangle({
				config = {id = "container"},
				child = proc(state: w.Rectangle_State) {
					#partial switch active_widget_option {
					case .RECTANGLE:
						Widget_Rectangle()
					case .TABLE:
						Widget_Table()

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
		},
		child = proc(state: w.Rectangle_State) {
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
		},
	})
}

Widget_Rectangle :: proc() {
	w.Rectangle(
		{
			config = {
				id = "rectalgel_widget",
				height = set.Height(400),
				width = set.Width(400),
				direction = set.Direction(.VERTICAL),
				justify = set.Justify(o.Justify_Pos{x = .STRETCH, y = .STRETCH}),
				gap = set.Gap(0),
				background = set.Background(.SKY_500),
			},
		},
	)
}

Widget_Table :: proc() {
	w.Table({
		config = {
			id = "table1",
			direction = set.Direction(.VERTICAL),
			justify = set.Justify(o.Justify_Pos{x = .STRETCH, y = .STRETCH}),
		},
		child = proc(_: w.Table_State) {
			w.Table_Head({
				config = {id = "table1_head"},
				child = proc(_: w.Table_Head_State) {
					w.Table_Row({
						config = {id = "table1_head_r1"},
						child = proc(_: w.Table_Row_State) {
							w.Table_Heading({
								config = {id = "table1_r1_heading1"},
								child = proc(_: w.Table_Heading_State) {
									w.Text(
										{
											config = {
												id = "table1_r1_heading_text",
												text = "Player Name",
											},
										},
									)
								},
							})

							w.Table_Heading({
								config = {id = "table1_heading2"},
								child = proc(_: w.Table_Heading_State) {
									w.Text(
										{config = {id = "table1_r1_heading_text", text = "Score"}},
									)
								},
							})
						},
					})
				},
			})

			w.Table_Body({
				config = {id = "table1_body"},
				child = proc(_: w.Table_Body_State) {
					w.Table_Row({
						config = {id = "table1_r1"},
						child = proc(_: w.Table_Row_State) {
							w.Table_Cell({
								config = {id = "tabel1_r1_c1"},
								child = proc(_: w.Table_Cell_State) {
									w.Text(
										{
											config = {
												id = "tabel1_r1_c1_text",
												text = "Player 1 \nhey heyhey",
											},
										},
									)
								},
							})

							w.Table_Cell({
								config = {id = "tabel1_r1_c2"},
								child = proc(_: w.Table_Cell_State) {
									w.Text({config = {id = "tabel1_r1_c2_text", text = "1"}})
								},
							})
						},
					})

					w.Table_Row({
						config = {id = "table1_r2"},
						child = proc(_: w.Table_Row_State) {
							w.Table_Cell({
								config = {id = "tabel1_r2_c1"},
								child = proc(_: w.Table_Cell_State) {
									w.Text(
										{config = {id = "tabel1_r2_c1_text", text = "Player 1"}},
									)
								},
							})

							w.Table_Cell({
								config = {id = "tabel1_r2_c2"},
								child = proc(_: w.Table_Cell_State) {
									w.Text({config = {id = "tabel1_r2_c2_text", text = "2"}})
								},
							})
						},
					})
				},
			})
		},
	})
}
