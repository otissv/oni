package oni_docs

import set "../../oni/set"
import w "../../oni/widgets"


WidgetText :: proc() {
	w.Text(
		{
			config = {
				id = "text1_widget",
				width = set.Width(400),
				text = "Consequuntur fugit veritatis ea aliquid officiis nesciunt enim. Minima vitae culpa occaecati optio. Sed consequuntur laboriosam inventore sapiente laboriosam non. Vero laborum alias modi quos. Nobis vero nobis occaecati dolore culpa deleniti. Ipsum ea qui eaque est.",
			},
		},
	)
}
