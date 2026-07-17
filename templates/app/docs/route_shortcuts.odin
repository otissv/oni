package oni_docs

import ui "../../app/ui"
import g "../../app/globlas"
import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"

@(private)
shortcuts_route_child :: proc(_: w.Rectangle_State) {
	ui.Heading({id = "shortcuts_title", text = "Shortcuts", variant = .H2, theme = o.theme})

	w.Shortcuts_Table({
		config = {id = "shortcuts_settings"},
		session = &g.app.shortcuts_table,
		bindings_path = g.app.shortcuts_path,
	})
}

shortcuts_route :: proc() {
	w.Rectangle({
		config = {
			id = "shortcuts_route",
			direction = set.Direction(.VERTICAL),
			gap_y = set.Gap_Y(12),
			justify = set.Justify(o.Justify_Pos{x = .STRETCH, y = .START}),
		},
		child = shortcuts_route_child,
	})
}
