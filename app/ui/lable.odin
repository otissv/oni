package ui

import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"


Label_Size :: enum {
	Default,
	Small,
	Large,
	Icon,
}


Label_Props :: struct {
	using _: w.Text_Config,
	size:    Label_Size,
	theme:   ^o.Theme,
}

Label :: proc(props: Label_Props) {
	font_size: o.Cfg(o.Style_F32)

	switch props.size {
	case .Default:
		font_size = set.F32(16)
	case .Small:
		font_size = set.F32(14)
	case .Large:
		font_size = set.F32(24)
	case .Icon:
		font_size = set.F32(14)
	}
	config := props
	config.font_size = font_size

	w.Text({config = config})
}
