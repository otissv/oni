package oni_docs

import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"


Layout_Visibility :: proc() {
	// VISIBLE paints; HIDDEN keeps layout space; NONE is removed from the tree.
	w.Rectangle({
		config = {
			id = "layout_visibility",
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
					id = "vis-visible",
					width = 100,
					height = 100,
					visibility = set.Visibility(.VISIBLE),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.DESTRUCTIVE]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "vis-visible-label", text = "VISIBLE"}})
				},
			})
			w.Rectangle({
				config = {
					id = "vis-hidden",
					width = 100,
					height = 100,
					visibility = set.Visibility(.HIDDEN),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.ACCENT]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "vis-hidden-label", text = "HIDDEN"}})
				},
			})
			w.Rectangle({
				config = {
					id = "vis-none",
					width = 100,
					height = 100,
					visibility = set.Visibility(.NONE),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.SUCCESS]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "vis-none-label", text = "NONE"}})
				},
			})
			w.Rectangle({
				config = {
					id = "vis-after",
					width = 100,
					height = 100,
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.INFO]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "vis-after-label", text = "after"}})
				},
			})
		},
	})
}
