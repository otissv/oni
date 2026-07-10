package routes

import o "../../oni"
import c "../components"
import g "../globlas"
import layouts "./layouts"
import widgets "./widgets"


routes_init :: proc() {
	tex, ok := o.Load_Texture("assets/oni-2.avif")
	if ok do g.image_texture = tex
}

widgets_route :: proc() {
	c.View("widget_view", widgets.sidebar, widgets.container)
}


layout_route :: proc() {
	c.View("layout_view", layouts.sidebar, layouts.container)
}
