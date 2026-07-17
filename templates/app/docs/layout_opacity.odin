package oni_docs

import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"


Layout_Opacity :: proc() {
	// Local opacities multiply down the tree (CSS group opacity).
	w.Rectangle({
		config = {
			id = "layout_opacity",
			space = set.Space(.SCREEN),
			direction = set.Direction(.HORIZONTAL),
			gap_x = set.Gap_X(u16(8)),
			padding = set.Padding(f32(20)),
			background = set.Colors(o.theme.palette[.BACKGROUND]),
			radius = set.Radius(10),
			border = set.Border(f32(1)),
			border_color = set.Colors(o.Color.YELLOW_500),
			justify = set.Justify(o.Justify_Pos{y = .CENTER}),
		},
		child = proc(_: w.Rectangle_State) {
			w.Rectangle({
				config = {
					id = "op-1",
					width = 100,
					height = 100,
					opacity = set.Opacity(1),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.DESTRUCTIVE]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "op-1-label", text = "1"}})
				},
			})
			w.Rectangle({
				config = {
					id = "op-05",
					width = 100,
					height = 100,
					opacity = set.Opacity(0.5),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.ACCENT]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "op-05-label", text = "0.5"}})
				},
			})
			w.Rectangle({
				config = {
					id = "op-025",
					width = 100,
					height = 100,
					opacity = set.Opacity(0.25),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.SUCCESS]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "op-025-label", text = "0.25"}})
				},
			})
			w.Rectangle({
				config = {
					id = "op-nested",
					width = 120,
					height = 120,
					opacity = set.Opacity(0.5),
					padding = set.Padding(f32(12)),
					background = set.Colors(o.theme.palette[.INFO]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Rectangle({
						config = {
							id = "op-nested-child",
							width = 80,
							height = 80,
							opacity = set.Opacity(0.5),
							padding = set.Padding(f32(6)),
							background = set.Colors(o.theme.palette[.DESTRUCTIVE]),
							radius = set.Radius(6),
							justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
						},
						child = proc(_: w.Rectangle_State) {
							w.Text({config = {id = "op-nested-label", text = "0.5×0.5"}})
						},
					})
				},
			})
		},
	})
}
