package oni_docs

import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"


PRESERVE_DEMO_TEXT :: "Two  spaces stay wide.\n\tTabbed line\n\t\tNested tab\nThis line is intentionally long and should scroll horizontally inside the block below.\nCRLF line\r\nNext line after CRLF\n"


Widget_Preserve :: proc() {
	w.Rectangle({
		config = {
			id = "preserve-demo",
			direction = set.Direction(.VERTICAL),
			gap_y = set.Gap_Y(u16(8)),
			width = set.Width(480),
		},
		child = proc(_: w.Rectangle_State) {
			w.Text({
				config = {
					id = "preserve-demo-caption",
					text = "Tabs, spaces, newlines, and CRLF are preserved. Scroll when content overflows.",
				},
			})
			w.Rectangle({
				config = {
					id = "preserve-demo-port",
					width = set.Width(480),
					height = set.Height(240),
					padding = set.Padding(12),
					background = set.Colors(o.Color.MUTED),
					radius = set.Radius(8),
					overflow_x = set.Overflow_X(.AUTO),
					overflow_y = set.Overflow_Y(.AUTO),
				},
				child = proc(_: w.Rectangle_State) {
					w.Preserve({
						config = {
							id = "preserve-demo-text",
							text = PRESERVE_DEMO_TEXT,
							font = set.Font(o.theme.font_body),
							font_size = set.F32(14),
							tab_size = set.Tab_Size(4),
						},
					})
				},
			})
		},
	})
}
