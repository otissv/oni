package oni_docs

import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"

Layout_Scrollview :: proc() {
	// overflow_y = SCROLL turns a fixed-size rectangle into a scrollport:
	// content taller than the viewport clips, wheel/drag scrolls, bars paint.
	w.Rectangle({
		config = {
			id = "layout_scrollview",
			space = set.Space(.SCREEN),
			direction = set.Direction(.VERTICAL),
			gap_y = set.Gap_Y(u16(12)),
			width = set.Width(f32(320)),
			padding = set.Padding(f32(20)),
			background = set.Colors(o.theme.palette[.BACKGROUND]),
			radius = set.Radius(10),
			border = set.Border(f32(1)),
			border_color = set.Colors(o.Color.YELLOW_500),
		},
		child = proc(_: w.Rectangle_State) {
			w.Text({
				config = {
					id = "layout-scrollview-title",
					text = "Wheel or drag the scrollbar to scroll.",
				},
			})
			w.Rectangle({
				config = {
					id = "scroll-port",
					direction = set.Direction(.VERTICAL),
					gap_y = set.Gap_Y(u16(8)),
					width = set.Width(f32(280)),
					height = set.Height(f32(200)),
					padding = set.Padding(f32(8)),
					overflow_y = set.Overflow_Y(.SCROLL),
					background = set.Colors(o.Color.MUTED),
					radius = set.Radius(8),
				},
				child = proc(_: w.Rectangle_State) {
					w.Rectangle({
						config = {
							id = "scroll-row-1",
							width = set.Width(.AUTO),
							height = set.Height(f32(48)),
							padding = set.Padding(f32(8)),
							background = set.Colors(o.theme.palette[.DESTRUCTIVE]),
							radius = set.Radius(8),
							justify = set.Justify(o.Justify_Pos{x = .START, y = .CENTER}),
						},
						child = proc(_: w.Rectangle_State) {
							w.Text({config = {id = "scroll-row-1-label", text = "Row 1"}})
						},
					})
					w.Rectangle({
						config = {
							id = "scroll-row-2",
							width = set.Width(.AUTO),
							height = set.Height(f32(48)),
							padding = set.Padding(f32(8)),
							background = set.Colors(o.theme.palette[.ACCENT]),
							radius = set.Radius(8),
							justify = set.Justify(o.Justify_Pos{x = .START, y = .CENTER}),
						},
						child = proc(_: w.Rectangle_State) {
							w.Text({config = {id = "scroll-row-2-label", text = "Row 2"}})
						},
					})
					w.Rectangle({
						config = {
							id = "scroll-row-3",
							width = set.Width(.AUTO),
							height = set.Height(f32(48)),
							padding = set.Padding(f32(8)),
							background = set.Colors(o.theme.palette[.SUCCESS]),
							radius = set.Radius(8),
							justify = set.Justify(o.Justify_Pos{x = .START, y = .CENTER}),
						},
						child = proc(_: w.Rectangle_State) {
							w.Text({config = {id = "scroll-row-3-label", text = "Row 3"}})
						},
					})
					w.Rectangle({
						config = {
							id = "scroll-row-4",
							width = set.Width(.AUTO),
							height = set.Height(f32(48)),
							padding = set.Padding(f32(8)),
							background = set.Colors(o.theme.palette[.INFO]),
							radius = set.Radius(8),
							justify = set.Justify(o.Justify_Pos{x = .START, y = .CENTER}),
						},
						child = proc(_: w.Rectangle_State) {
							w.Text({config = {id = "scroll-row-4-label", text = "Row 4"}})
						},
					})
					w.Rectangle({
						config = {
							id = "scroll-row-5",
							width = set.Width(.AUTO),
							height = set.Height(f32(48)),
							padding = set.Padding(f32(8)),
							background = set.Colors(o.theme.palette[.DESTRUCTIVE]),
							radius = set.Radius(8),
							justify = set.Justify(o.Justify_Pos{x = .START, y = .CENTER}),
						},
						child = proc(_: w.Rectangle_State) {
							w.Text({config = {id = "scroll-row-5-label", text = "Row 5"}})
						},
					})
					w.Rectangle({
						config = {
							id = "scroll-row-6",
							width = set.Width(.AUTO),
							height = set.Height(f32(48)),
							padding = set.Padding(f32(8)),
							background = set.Colors(o.theme.palette[.ACCENT]),
							radius = set.Radius(8),
							justify = set.Justify(o.Justify_Pos{x = .START, y = .CENTER}),
						},
						child = proc(_: w.Rectangle_State) {
							w.Text({config = {id = "scroll-row-6-label", text = "Row 6"}})
						},
					})
					w.Rectangle({
						config = {
							id = "scroll-row-7",
							width = set.Width(.AUTO),
							height = set.Height(f32(48)),
							padding = set.Padding(f32(8)),
							background = set.Colors(o.theme.palette[.SUCCESS]),
							radius = set.Radius(8),
							justify = set.Justify(o.Justify_Pos{x = .START, y = .CENTER}),
						},
						child = proc(_: w.Rectangle_State) {
							w.Text({config = {id = "scroll-row-7-label", text = "Row 7"}})
						},
					})
					w.Rectangle({
						config = {
							id = "scroll-row-8",
							width = set.Width(.AUTO),
							height = set.Height(f32(48)),
							padding = set.Padding(f32(8)),
							background = set.Colors(o.theme.palette[.INFO]),
							radius = set.Radius(8),
							justify = set.Justify(o.Justify_Pos{x = .START, y = .CENTER}),
						},
						child = proc(_: w.Rectangle_State) {
							w.Text({config = {id = "scroll-row-8-label", text = "Row 8"}})
						},
					})
				},
			})
		},
	})
}
