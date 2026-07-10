package widgets_route

import o "../../../oni"
import set "../../../oni/set"
import w "../../../oni/widgets"


Widget_Image :: proc() {
	w.Image(
		{
			texture = image_texture,
			config = {
				id           = "bottom-1",
				x            = set.F32(16),
				y            = set.F32(480),
				width        = 464,
				height       = 464,
				background   = set.Colors(o.theme.palette[.INFO]),
				radius       = set.Radius(10),
				border       = set.Border(10),
				border_color = set.Colors(o.Color.YELLOW_500),
				texture_fit  = set.Image_Fit(.NONE),
				texture_pos  = set.Image_Pos({x = 50, y = 50}), // center
			},
		},
	)
}
