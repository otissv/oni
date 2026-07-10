package widgets_route

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
				texture_fit = set.Image_Fit(.COVER),
				texture_pos = set.Image_Pos({x = 50, y = 50}),
			},
		},
	)
}
