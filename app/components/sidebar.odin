package components

import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"

Sidebar :: proc(id: string, children: proc(state: w.Rectangle_State)) {
	w.Rectangle(
		{
			config = {
				id = id,
				x = set.F32(0),
				y = set.F32(0),
				width = set.Width(300),
				border = set.Border(o.Bd{r = 1}),
				border_color = set.Border_color(.GRAY_500),
				direction = set.Direction(.VERTICAL),
				justify = set.Justify(o.Justify_Pos{x = .STRETCH, y = .STRETCH}),
				padding = set.Padding(o.Pd_struct{r = 5}),
			},
			child = children,
		},
	)
}
