package routes

import o "../../oni"
import c "../components"
import layouts "./layouts"
import widgets "./widgets"

image_texture: o.Texture_Handle

routes_init :: proc() {
	tex, ok := o.Load_Texture("assets/o-2.avif")
	if ok do image_texture = tex
}


widgets_route :: proc() {
	c.View("widget_view", widgets.sidebar, widgets.container)
}


layout_route :: proc() {
	c.View("layout_view", layouts.sidebar, layouts.container)
}
