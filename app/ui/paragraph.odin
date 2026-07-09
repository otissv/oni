package ui

import oni "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"


Paragraph_Props :: struct {
	using _: w.Text_Config,
	theme:   ^oni.Theme,
}

Paragraph :: proc(props: Paragraph_Props) {

	paragraph_color :: proc(
		state: oni.Widget_Frame_State,
		_: oni.Widget_Event(oni.Widget_Frame_State),
	) -> oni.Colors {
		if state.is_Pressed do return oni.RGBA{0, 0, 0, 255}
		if state.is_hovered do return oni.RGBA{210, 60, 60, 255}
		return oni.theme.palette[.FOREGROUND]
	}


	w.Text(
		{
			config = {
				id = props.id,
				width = set.Width(480),
				height = set.Height(200),
				text = props.text,
				font = set.Font(props.theme.font_body),
				font_size = set.F32(props.theme.font_body.size_px),
				line_height = set.F32(1.5),
				color = set.Colors(paragraph_color),
				x = props.x,
				y = props.y,
			},
		},
	)
}
