package oni_docs

import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"

Layout_Directions :: proc(
	direction: o.Direction_Layout,
	layout_width: o.Width,
	layout_height: o.Height,
) {
	w.Rectangle({
		config = {
			id = "Layout_Directions",
			space = set.Space(.SCREEN),
			direction = set.Direction(direction),
			gap_x = set.Gap_X(u16(8)),
			gap_y = set.Gap_Y(u16(8)),
			width = set.Width(layout_width),
			height = set.Height(layout_height),
			padding = set.Padding(f32(20)),
			justify = set.Justify(o.Justify_Pos{x = .SPACE_AROUND}),
			background = set.Colors(o.theme.palette[.BACKGROUND]),
			radius = set.Radius(10),
			border = set.Border(f32(1)),
			border_color = set.Colors(o.Color.YELLOW_500),
		},
		child = proc(state: w.Rectangle_State) {
			w.Rectangle(
				{
					config = {
						id = "left",
						width = 100,
						height = 100,
						background = set.Colors(o.theme.palette[.DESTRUCTIVE]),
						radius = set.Radius(10),
					},
				},
			)
			w.Rectangle(
				{
					config = {
						id = "center",
						width = 100,
						height = 100,
						background = set.Colors(o.theme.palette[.ACCENT]),
						radius = set.Radius(10),
					},
				},
			)
			w.Rectangle(
				{
					config = {
						id = "right",
						width = 100,
						height = 100,
						background = set.Colors(o.theme.palette[.SUCCESS]),
						radius = set.Radius(10),
					},
				},
			)
			w.Rectangle(
				{
					config = {
						id = "end",
						width = 100,
						height = 100,
						background = set.Colors(o.theme.palette[.INFO]),
						radius = set.Radius(10),
					},
				},
			)
		},
	})
}
