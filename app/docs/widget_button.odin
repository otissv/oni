package oni_docs

import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"

Widget_Button :: proc() {
	w.Button({
		config = {
			id = "button1_widget",
			padding = set.Padding(o.Pd_pos{x = 12, y = 6}),
			border = set.Border(1),
		},
		child = proc(_: w.Button_State) {
			w.Text({config = {id = "button1_widget_text1", text = "Button"}})
		},
	})
}
