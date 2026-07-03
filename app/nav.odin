package app

import ui "../app/ui"
import set "../oni/set"
import wg "../oni/widgets"

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

			ui.Button({
				id = "nav-artboard-button",
				variant = .OUTLINE,
				child = proc(_: ui.Button_state) {
					wg.Text({id = "artboard-nav-button", text = "Artboard"})
				},
				on_click = proc(_: ui.Button_Event) {
					Route = .Artboard
				},
				active = .Artboard == Route,
			})

			ui.Button({
				id = "nav-layout-button",
				variant = .OUTLINE,
				child = proc(_: ui.Button_state) {
					wg.Text({id = "layout-nav-button", text = "Layout"})
				},
				on_click = proc(_: ui.Button_Event) {
					Route = .Layout
				},
				active = .Layout == Route,
			})
		},
	})
}
