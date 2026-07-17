package oni_docs

import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"


Layout_Position :: proc() {
	w.Rectangle({
		config = {
			id = "layout_position",
			space = set.Space(.SCREEN),
			direction = set.Direction(.HORIZONTAL),
			gap_x = set.Gap_X(u16(8)),
			width = set.Width(f32(420)),
			height = set.Height(f32(220)),
			padding = set.Padding(f32(20)),
			background = set.Colors(o.theme.palette[.BACKGROUND]),
			radius = set.Radius(10),
			border = set.Border(f32(1)),
			border_color = set.Colors(o.Color.YELLOW_500),
		},
		child = proc(_: w.Rectangle_State) {
			w.Rectangle({
				config = {
					id = "pos-relative",
					width = 110,
					height = 90,
					position = set.Position(.RELATIVE),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.DESTRUCTIVE]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "pos-relative-label", text = "relative"}})
				},
			})
			w.Rectangle({
				config = {
					id = "pos-flow",
					width = 110,
					height = 90,
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.ACCENT]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "pos-flow-label", text = "in flow"}})
				},
			})
			w.Rectangle({
				config = {
					id = "pos-absolute",
					width = 120,
					height = 80,
					position = set.Position(.ABSOLUTE),
					x = set.F32(160),
					y = set.F32(120),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.SUCCESS]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "pos-absolute-label", text = "absolute"}})
				},
			})
			w.Rectangle({
				config = {
					id = "pos-fixed",
					width = 100,
					height = 60,
					position = set.Position(.FIXED),
					right = set.Right(24),
					bottom = set.Bottom(24),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.INFO]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "pos-fixed-label", text = "fixed"}})
				},
			})
		},
	})
}
