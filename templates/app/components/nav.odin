package components

import set "../../oni/set"
import w "../../oni/widgets"
import g "../globlas"
import ui "../ui"


Nav :: proc() {
	w.Rectangle({
		config = {id = "nav", x = set.F32(16), y = set.F32(16), gap_x = set.Gap_X(10)},
		child = proc(state: w.Rectangle_State) {
			ui.Button({
				id = "nav-home-button",
				variant = .GHOST,
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					g.app.Route = .Home
				},
				child = proc(_: ui.Button_state) {
					w.Text({config = {id = "home-nav-button", text = "Home"}})
				},
			})

			ui.Button({
				id = "nav-about-button",
				variant = .GHOST,
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					g.app.Route = .About
				},
				child = proc(_: ui.Button_state) {
					w.Text({config = {id = "about-nav-button", text = "About"}})
				},
			})

			ui.Button({
				id = "nav-artboard-button",
				variant = .GHOST,
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					g.app.Route = .Artboard
				},
				child = proc(_: ui.Button_state) {
					w.Text({config = {id = "artboard-nav-button", text = "Artboard"}})
				},
			})

			ui.Button({
				id = "nav-layout-button",
				variant = .GHOST,
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					g.app.Route = .Layout
				},
				child = proc(_: ui.Button_state) {
					w.Text({config = {id = "layout-nav-button", text = "Layout"}})
				},
			})

			ui.Button({
				id = "nav-widgets-button",
				variant = .GHOST,
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					g.app.Route = .Widgets
				},
				child = proc(_: ui.Button_state) {
					w.Text({config = {id = "widgets-nav-button", text = "Widgets"}})
				},
			})

			ui.Button({
				id = "nav-Components-button",
				variant = .GHOST,
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					g.app.Route = .Components
				},
				child = proc(_: ui.Button_state) {
					w.Text({config = {id = "Components-nav-button", text = "Components"}})
				},
			})

			ui.Button({
				id = "nav-shortcuts-button",
				variant = .GHOST,
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					g.app.Route = .Shortcuts
				},
				child = proc(_: ui.Button_state) {
					w.Text({config = {id = "shortcuts-nav-button", text = "Shortcuts"}})
				},
			})
		},
	})
}
