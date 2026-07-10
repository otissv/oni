package widgets_route

import o "../../../oni"
import set "../../../oni/set"
import w "../../../oni/widgets"

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
