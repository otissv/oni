package app

import ui "../app/ui"
import oni "../oni"
import set "../oni/set"
import wg "../oni/widgets"
import "core:fmt"

Nav :: proc() {
	wg.Rectangle({
		config = {id = "nav", x = set.F32(16), y = set.F32(16)},
		child = proc(state: wg.Rectangle_State) {
			ui.Button({
				id = "nav-home-button",
				variant = .OUTLINE,
				child = proc(_: ui.Button_state) {
					wg.Text({id = "home-nav-button", text = "Home"})
				},
				on_click = proc(_: ui.Button_Event) {
					Route = .Home
					oni.Log_Debug("Home")
				},
				active = .Home == Route,
			})
			ui.Button({
				id = "nav-about-button",
				variant = .OUTLINE,
				child = proc(_: ui.Button_state) {
					wg.Text({id = "about-nav-button", text = "About"})
				},
				on_click = proc(_: ui.Button_Event) {
					Route = .About
				},
				active = .About == Route,
			})
			wg.Text({id = "route-fade-elapsed-text", text = route_fade_elapsed_text()})
			wg.Text({id = "opacity-text", text = fmt.tprintf("Opacity: %.2f", about_fade.opacity)})
		},
	})
}
