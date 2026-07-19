package oni_widgets

import o ".."
import set "../set"


/*
Preserve widget configuration extending Text_Config for preformatted text.
*/
Preserve_Config :: struct {
	using _: Text_Config,
}

/*
Preserve widget props: same shape as Text with preserve-oriented defaults applied.
*/
Preserve_Props :: Text_Props

/*
Applies preserve defaults to unset text layout fields on a config copy.
*/
@(private)
preserve_apply_defaults :: proc(config: Text_Config) -> Text_Config {
	result := config

	if result.wrap.mode == .UNSET {
		result.wrap = set.Wrap(.PRESERVE)
	}

	if result.align.mode == .UNSET {
		result.align = set.Align(.LEFT)
	}

	if result.line_height.mode == .UNSET {
		result.line_height = set.F32(1.35)
	}

	return result
}

/*
Lays out and draws preformatted text with preserved whitespace and hard line breaks.
*/
Preserve :: proc(props: Preserve_Props) -> o.Vec2 {
	p := Text_Props(props)
	p.config = preserve_apply_defaults(p.config)

	return Text(p)
}
