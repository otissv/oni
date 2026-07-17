package oni_docs

import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"

Layout_Z_Index :: proc() {
	w.Rectangle({
		config = {
			id = "layout_z_index",
			space = set.Space(.SCREEN),
			width = set.Width(f32(360)),
			height = set.Height(f32(260)),
			padding = set.Padding(f32(20)),
			background = set.Colors(o.theme.palette[.BACKGROUND]),
			radius = set.Radius(10),
			border = set.Border(f32(1)),
			border_color = set.Colors(o.Color.YELLOW_500),
		},
		child = proc(_: w.Rectangle_State) {
			w.Rectangle({
				config = {
					id = "z-back",
					width = 140,
					height = 140,
					position = set.Position(.ABSOLUTE),
					x = set.F32(40),
					y = set.F32(40),
					z_index = set.Z_Index(-1),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.DESTRUCTIVE]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "z-back-label", text = "z=-1"}})
				},
			})
			w.Rectangle({
				config = {
					id = "z-mid",
					width = 140,
					height = 140,
					position = set.Position(.ABSOLUTE),
					x = set.F32(90),
					y = set.F32(70),
					z_index = set.Z_Index(0),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.ACCENT]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "z-mid-label", text = "z=0"}})
				},
			})
			w.Rectangle({
				config = {
					id = "z-front",
					width = 140,
					height = 140,
					position = set.Position(.ABSOLUTE),
					x = set.F32(140),
					y = set.F32(100),
					z_index = set.Z_Index(2),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.SUCCESS]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "z-front-label", text = "z=2"}})
				},
			})
		},
	})
}
