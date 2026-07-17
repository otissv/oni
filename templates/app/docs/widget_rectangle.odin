package oni_docs

import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"

Widget_Rectangle :: proc() {
	w.Rectangle(
		{
			config = {
				id = "rectangle1_widget",
				height = set.Height(400),
				width = set.Width(400),
				direction = set.Direction(.VERTICAL),
				justify = set.Justify(o.Justify_Pos{x = .STRETCH, y = .STRETCH}),
				background = set.Background(.SKY_500),
			},
		},
	)
}
