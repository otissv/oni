package oni_docs

import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"

Layout_Order :: proc() {
	// Source order A B C D; flex order rearranges to C B D A.
	w.Rectangle({
		config = {
			id = "layout_order",
			space = set.Space(.SCREEN),
			direction = set.Direction(.HORIZONTAL),
			gap_x = set.Gap_X(u16(8)),
			padding = set.Padding(f32(20)),
			background = set.Colors(o.theme.palette[.BACKGROUND]),
			radius = set.Radius(10),
			border = set.Border(f32(1)),
			border_color = set.Colors(o.Color.YELLOW_500),
		},
		child = proc(_: w.Rectangle_State) {
			w.Rectangle({
				config = {
					id = "order-a",
					width = 100,
					height = 100,
					order = set.Order(3),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.DESTRUCTIVE]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "order-a-label", text = "A order=3"}})
				},
			})
			w.Rectangle({
				config = {
					id = "order-b",
					width = 100,
					height = 100,
					order = set.Order(1),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.ACCENT]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "order-b-label", text = "B order=1"}})
				},
			})
			w.Rectangle({
				config = {
					id = "order-c",
					width = 100,
					height = 100,
					order = set.Order(0),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.SUCCESS]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "order-c-label", text = "C order=0"}})
				},
			})
			w.Rectangle({
				config = {
					id = "order-d",
					width = 100,
					height = 100,
					order = set.Order(2),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.INFO]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "order-d-label", text = "D order=2"}})
				},
			})
		},
	})
}
