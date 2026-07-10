package globals

import o "../../oni"

image_texture: o.Texture_Handle

frame_dt: f32

Routes :: enum {
	Home,
	About,
	Layout,
	Artboard,
	Widgets,
	Components,
}

Route: Routes = .Widgets
