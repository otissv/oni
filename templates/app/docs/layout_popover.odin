package oni_docs

import ui "../../app/ui"
import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"

@(private)
layout_popover_open := true

Layout_Popover :: proc() {
	w.Rectangle({
		config = {
			id = "layout_popover",
			space = set.Space(.SCREEN),
			direction = set.Direction(.VERTICAL),
			gap_y = set.Gap_Y(u16(12)),
			width = set.Width(f32(420)),
			height = set.Height(f32(280)),
			padding = set.Padding(f32(20)),
			background = set.Colors(o.theme.palette[.BACKGROUND]),
			radius = set.Radius(10),
		},
		child = proc(_: w.Rectangle_State) {
			w.Text(
				{
					config = {
						id = "layout-popover-title",
						text = "Popover paints and hits above screen content.",
					},
				},
			)
			ui.Button({
				id = "layout-popover-toggle",
				variant = .DEFAULT,
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					layout_popover_open = !layout_popover_open
				},
				child = proc(_: ui.Button_state) {
					label := layout_popover_open ? "Hide popover" : "Show popover"
					w.Text({config = {id = "layout-popover-toggle-label", text = label}})
				},
			})
			w.Rectangle({
				config = {
					id = "layout-popover-underlay",
					width = set.Width(f32(200)),
					height = set.Height(f32(120)),
					padding = set.Padding(f32(8)),
					background = set.Colors(o.theme.palette[.ACCENT]),
					radius = set.Radius(8),
					justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
				},
				child = proc(_: w.Rectangle_State) {
					w.Text({config = {id = "layout-popover-underlay-label", text = "underlay"}})
				},
			})

			if layout_popover_open {
				w.Popover({
					config = {
						id = "layout-popover-panel",
						position = set.Position(.ABSOLUTE),
						x = set.F32(140),
						y = set.F32(90),
						width = set.Width(f32(220)),
						height = set.Height(f32(140)),
						direction = set.Direction(.VERTICAL),
						gap_y = set.Gap_Y(u16(8)),
						padding = set.Padding(f32(12)),
						background = set.Colors(o.theme.palette[.BACKGROUND]),
						radius = set.Radius(10),
						border = set.Border(f32(1)),
						border_color = set.Colors(o.Color.SKY_500),
						justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
					},
					child = proc(_: w.Popover_State) {
						w.Text(
							{config = {id = "layout-popover-panel-title", text = "Popover panel"}},
						)
						w.Text(
							{
								config = {
									id = "layout-popover-panel-body",
									text = "Always space=.POPOVER",
								},
							},
						)
					},
				})
			}
		},
	})
}
