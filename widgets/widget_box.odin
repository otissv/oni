package oni_widgets

import o ".."

/*
Paints the background layer of a widget's CSS-style box.

The background occupies the rounded border box. Content is painted after this
layer, followed by widget_draw_box_border so descendants cannot cover chrome.
*/
@(private)
widget_draw_box_background :: proc(
	layout_id: o.UI_Id,
	rect: o.Rect,
	background: o.RGBA,
	radius: o.Radius_px,
) {
	if o.ui_layout_paint_skip(layout_id) do return

	o.Draw_Rectangle(rect, background, radius)
}

/*
Paints the border layer of a widget's CSS-style box above its content.
*/
@(private)
widget_draw_box_border :: proc(
	layout_id: o.UI_Id,
	rect: o.Rect,
	radius: o.Radius_px,
	border: o.Bd_px,
	border_color: o.RGBA,
) {
	if o.ui_layout_paint_skip(layout_id) do return

	o.Draw_Rectangle(rect, {}, radius, border, border_color)
}
