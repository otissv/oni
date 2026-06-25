package ui

import oni "../../oni"
import set "../../oni/set"
import wg "../../oni/widgets"


Paragraph_Props :: struct {
	id:    string,
	text:  string,
	theme: ^oni.Theme,
}

Paragraph :: proc(props: Paragraph_Props) {

	paragraph_color :: proc(
		state: oni.Widget_State,
		_: oni.Widget_Event(oni.Widget_State),
	) -> oni.Colors {
		if state.is_Pressed do return oni.RGBA{0, 0, 0, 255}
		if state.is_hovered do return oni.RGBA{210, 60, 60, 255}
		return oni.theme.palette[.FOREGROUND]
	}

	wg.Text(
		{
			id = props.id,
			width = set.Width(480),
			height = set.Height(200),
			text = props.text,
			font = set.Font(props.theme.font_body),
			font_size = set.F32(20),
			line_height = set.F32(1.5),
			color = set.Colors(paragraph_color),
		},
	)
}
