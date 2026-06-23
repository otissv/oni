package ui

import oni "../../oni"
import set "../../oni/set"
import wg "../../oni/widgets"


Heading_Variant :: enum {
	H1,
	H2,
	H3,
	H4,
	H5,
	H6,
}


Heading_Props :: struct {
	id:      string,
	text:    string,
	variant: Heading_Variant,
	theme:   ^oni.Theme,
}

Heading :: proc(props: Heading_Props) {
	font_size: oni.Cfg(f32)

	switch props.variant {
	case .H1:
		font_size = set.F32(32)
	case .H2:
		font_size = set.F32(28)
	case .H3:
		font_size = set.F32(24)
	case .H4:
		font_size = set.F32(20)
	case .H5:
		font_size = set.F32(18)
	case .H6:
		font_size = set.F32(16)
	}

	wg.Text(
		{
			id = props.id,
			width = set.Width(480),
			height = set.Height(28),
			text = props.text,
			font = set.Font(props.theme.font_heading),
			color = set.Colors(oni.theme.palette[.Foreground]),
			font_size = font_size,
			line_height = set.F32(0),
		},
	)
}
