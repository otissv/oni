package engine

Theme_Color_Role :: enum {
	Bg,
	Surface,
	Border,
	Text,
	Text_Muted,
	Accent,
	Accent_Hover,
	Accent_Pressed,
	Danger,
	Success,
}

theme_color :: proc(t: ^Theme, role: Theme_Color_Role) -> Color {
	switch role {
	case .Bg:
		return t.bg
	case .Surface:
		return t.surface
	case .Border:
		return t.border
	case .Text:
		return t.text
	case .Text_Muted:
		return t.text_muted
	case .Accent:
		return t.accent
	case .Accent_Hover:
		return t.accent_hover
	case .Accent_Pressed:
		return t.accent_pressed
	case .Danger:
		return t.danger
	case .Success:
		return t.success
	}
	return {}
}
