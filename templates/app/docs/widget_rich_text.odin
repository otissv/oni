package oni_docs

import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"


Widget_Rich_Text :: proc() {
	w.Rectangle({
		config = {
			id = "rich-text-demo",
			direction = set.Direction(.VERTICAL),
			gap_y = set.Gap_Y(u16(12)),
			width = set.Width(520),
		},
		child = proc(_: w.Rectangle_State) {
			w.Text(
				{
					config = {
						id = "rich-text-demo-caption",
						text = "RichText supports inline tags for every Widget_Config style field name (e.g. {font:Inter:24}heading size{/font}, {font_size:20}size{/font_size}, {opacity:0.6}fade{/opacity}). Shorthand: {c:accent}color{/c}, {b}bold{/b}, {i}italic{/i}, {u}underline{/u}. Escape: \\{literal}",
					},
				},
			)

			w.RichText(
				{
					config = {
						id = "rich-text-demo-body",
						width = set.Width(520),
						text = "{c:foreground}Plain{/c} {c:accent}accent{/c} {c:destructive}destructive{/c} {c:muted}muted{/c}\n{b}Bold{/b} {i}italic{/i} {u}underlined{/u}\n{font_size:20}Large{/font_size} {opacity:0.55}Faded{/opacity} {text_decoration_style:dotted}{u}dotted underline{/u}{/text_decoration_style}\nBrace escape: \\{literal}",
						font = set.Font(o.theme.font_body),
						font_size = set.F32(16),
						line_height = set.F32(1.6),
						wrap = set.Wrap(.BALANCE),
					},
				},
			)
		},
	})
}
