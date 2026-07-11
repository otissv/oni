package widgets_route

import o "../../../oni"
import set "../../../oni/set"
import w "../../../oni/widgets"
import g "../../globlas"


Widget_Image :: proc() {
	w.Image(
		{
			texture = g.image_texture,
			config = {
				id = "image1_widget",
				width = 464,
				height = 464,
				background = set.Colors(o.Color.INFO),
				texture_fit = set.Texture_Fit(.CONTAIN),
				texture_pos = set.Texture_Pos({x = 50, y = 50}),
			},
		},
	)
}
