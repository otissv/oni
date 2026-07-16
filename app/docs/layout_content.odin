package oni_docs

import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"

Layout_Content :: proc(
	direction: o.Direction_Layout,
	layout_width: o.Width,
	layout_height: o.Height,
	content_align_x: o.Justify_Align,
	content_align_y: o.Justify_Align,
) {
	w.Rectangle({
		config = {
			id = "layout_content",
			space = set.Space(.SCREEN),
			direction = set.Direction(direction),
			gap_x = set.Gap_X(u16(8)),
			gap_y = set.Gap_Y(u16(8)),
			width = set.Width(layout_width),
			height = set.Height(layout_height),
			padding = set.Padding(f32(20)),
			justify = set.Justify(o.Justify_Pos{x = content_align_x, y = content_align_y}),
			background = set.Colors(o.theme.palette[.BACKGROUND]),
			radius = set.Radius(10),
			border = set.Border(f32(1)),
			border_color = set.Colors(o.Color.YELLOW_500),
		},
		child = proc(state: w.Rectangle_State) {
			w.Rectangle({
				config = {
					id = "short",
					height = 60,
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.DESTRUCTIVE]),
					radius = set.Radius(8),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "short-label", text = "sm"}})
				},
			})
			w.Rectangle({
				config = {
					id = "medium",
					height = 80,
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.ACCENT]),
					radius = set.Radius(8),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "medium-label", text = "md"}})
				},
			})
			w.Rectangle({
				config = {
					id = "long",
					height = 90,
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.SUCCESS]),
					radius = set.Radius(8),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "long-label", text = "lg"}})
				},
			})
			w.Rectangle({
				config = {
					id = "fixed",
					width = 140,
					height = 100,
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.INFO]),
					radius = set.Radius(8),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "fixed-label", text = "fixed"}})
				},
			})
		},
	})
}
