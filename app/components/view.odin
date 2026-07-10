package components

import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"
import "core:fmt"

@(private)
view_children: struct {
	sidebar:   proc(state: w.Rectangle_State),
	container: proc(state: w.Rectangle_State),
}

@(private)
view_child :: proc(state: w.Rectangle_State) {
	sidebar_id := fmt.tprintf("{}_sidebar", state.config.id)

	Sidebar(sidebar_id, view_children.sidebar)
	w.Rectangle(
		{
			config = {id = "container", padding = set.Padding(o.Pd_struct{l = 20})},
			child = view_children.container,
		},
	)
}

View :: proc(
	id: string,
	sidebar: proc(state: w.Rectangle_State),
	container: proc(state: w.Rectangle_State),
) {
	view_children = {sidebar, container}

	w.Rectangle({config = {id = id, padding = set.Padding(4)}, child = view_child})
}
