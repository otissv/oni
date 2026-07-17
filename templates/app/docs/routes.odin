package oni_docs

import o "../../oni"
import c "../components"
import g "../globlas"


routes_init :: proc() {
	tex, ok := o.Load_Texture("assets/oni-2.avif")
	if ok do g.app.image_texture = tex
}

widgets_route :: proc() {
	c.View("widget_view", widget_sidebar, widget_container)
}


layout_route :: proc() {
	c.View("layout_view", layout_sidebar, layout_container)
}
