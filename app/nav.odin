package app

import ui "../app/ui"
import set "../oni/set"
import w "../oni/widgets"

Nav :: proc() {
	w.Rectangle({
		config = {id = "nav", x = set.F32(16), y = set.F32(16)},
		child = proc(state: w.Rectangle_State) {
			ui.Button({
				id = "nav-home-button",
				variant = .OUTLINE,
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					Route = .Home
				},
				child = proc(_: ui.Button_state) {
					w.Text({config = {id = "home-nav-button", text = "Home"}})
				},
			})

			ui.Button({
				id = "nav-about-button",
				variant = .OUTLINE,
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					Route = .About
				},
				child = proc(_: ui.Button_state) {
					w.Text({config = {id = "about-nav-button", text = "About"}})
				},
			})

			ui.Button({
				id = "nav-artboard-button",
				variant = .OUTLINE,
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					Route = .Artboard
				},
				child = proc(_: ui.Button_state) {
					w.Text({config = {id = "artboard-nav-button", text = "Artboard"}})
				},
			})

			ui.Button({
				id = "nav-layout-button",
				variant = .OUTLINE,
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					Route = .Layout
				},
				child = proc(_: ui.Button_state) {
					w.Text({config = {id = "layout-nav-button", text = "Layout"}})
				},
			})

			ui.Button({
				id = "nav-widgets-button",
				variant = .OUTLINE,
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					Route = .Widgets
				},
				child = proc(_: ui.Button_state) {
					w.Text({config = {id = "widgets-nav-button", text = "Widgets"}})
				},
			})

			ui.Button({
				id = "nav-Components-button",
				variant = .OUTLINE,
				radius = set.Radius(5),
				on_click = proc(_: ui.Button_Event) {
					Route = .Components
				},
				child = proc(_: ui.Button_state) {
					w.Text({config = {id = "Components-nav-button", text = "Components"}})
				},
			})
		},
	})
}
