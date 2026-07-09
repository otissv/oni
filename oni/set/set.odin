package set

import oni ".."

/*
Wraps a value in a Cfg with mode set to Value.

Used internally by the public set helpers below.
*/
@(private)
cfg_value :: proc(v: $T) -> oni.Cfg(T) {
	return oni.Cfg(T){mode = .Value, value = v}
}

/*
Wraps a type in a Cfg with mode set to Inherit.

Used internally when a style field should defer to the parent context.
*/
@(private)
cfg_inherit :: proc($T: typeid) -> oni.Cfg(T) {
	return oni.Cfg(T){mode = .Inherit}
}

Align :: proc(value: oni.Text_Align) -> oni.Cfg(oni.Text_Align) {return cfg_value(value)}

Background :: Colors

/*
Sets a bool widget config field to an explicit value.
*/
Bool :: proc(value: bool) -> oni.Cfg(bool) {return cfg_value(value)}

/*
Sets a border widget config field to an explicit value.
*/
Border :: proc(value: oni.Border) -> oni.Cfg(oni.Border) {return cfg_value(value)}

Border_color :: Colors

Color :: Colors

/*
Sets a colors widget config field to an explicit value.
*/
Colors :: proc(value: oni.Colors) -> oni.Cfg(oni.Colors) {return cfg_value(value)}

/*
Sets a layout direction widget config field to an explicit value.
*/
Direction :: proc(
	direction: oni.Direction_Layout,
) -> oni.Cfg(oni.Widget_Direction) {return cfg_value(oni.Widget_Direction(direction))}


Disabled :: Bool


/*
Sets an f32 widget config field to an explicit value.
*/
F32 :: proc(value: f32) -> oni.Cfg(f32) {return cfg_value(value)}

Flex :: F32


/*
Sets a font widget config field to an explicit value.
*/
Font :: proc(font: oni.Font_Handle) -> oni.Cfg(oni.Font_Handle) {return cfg_value(font)}


Font_size :: F32

/*
Sets a horizontal gap widget config field to an explicit value.
*/
Gap_X :: proc(value: oni.Gap_X) -> oni.Cfg(oni.Gap_X) {return cfg_value(value)}

/*
Sets a vertical gap widget config field to an explicit value.
*/
Gap_Y :: proc(value: oni.Gap_Y) -> oni.Cfg(oni.Gap_Y) {return cfg_value(value)}

/*
Sets a height widget config field to an explicit value.
*/
Height :: proc(value: oni.Height) -> oni.Height {return oni.Height(value)}

/*
Marks a widget config field to inherit from the parent context.
*/
Inherit :: proc($T: typeid) -> oni.Cfg(T) {return cfg_inherit(T)}

/*
Marks a draw-space config field to inherit from the parent context.
*/
Inherit_Space :: proc() -> oni.Cfg(oni.Draw_Space) {return cfg_inherit(oni.Draw_Space)}

/*
Sets a justify widget config field to an explicit value.
*/
Justify :: proc(value: oni.Justify) -> oni.Cfg(oni.Justify) {return cfg_value(value)}

Letter_Spacig :: F32

Letter_Height :: F32

Max_H :: F32

Max_W :: F32

Min_H :: F32

Min_W :: F32

overflow :: proc(value: oni.Overflow) -> oni.Cfg(oni.Overflow) {return cfg_value(value)}

/*
Sets a padding widget config field to an explicit value.
*/
Padding :: proc(value: oni.Padding) -> oni.Cfg(oni.Padding) {return cfg_value(value)}

Position :: proc(value: oni.Position) -> oni.Cfg(oni.Position) {return cfg_value(value)}

/*
Sets a radius widget config field to an explicit value.
*/
Radius :: proc(value: oni.Radius) -> oni.Cfg(oni.Radius) {return cfg_value(value)}

/*
Sets a self-alignment justify config field to an explicit value.
*/
Self :: proc(value: oni.Justify) -> oni.Cfg(oni.Justify) {return cfg_value(value)}

/*
Sets a draw-space widget config field to an explicit value.
*/
Space :: proc(space: oni.Draw_Space) -> oni.Cfg(oni.Draw_Space) {return cfg_value(space)}

Tabbable :: F32

/*
Sets a text-direction widget config field to an explicit value.
*/
Text_Direction :: proc(
	value: oni.Text_Direction,
) -> oni.Cfg(oni.Text_Direction) {return cfg_value(value)}


/*
Sets a texture-fit style config field to an explicit value.
*/
Image_Fit :: proc(value: oni.Image_Fit) -> oni.Cfg(oni.Style_Image_Fit) {
	return cfg_value(oni.Style_Image_Fit(value))
}

/*
Sets a texture position config field from x/y anchor values.
*/
Image_Pos :: proc(value: oni.Image_Pos_X_Y) -> oni.Cfg(oni.Style_Image_Pos) {
	return cfg_value(oni.Style_Image_Pos(value))
}

/*
Sets a texture position config field from edge-based anchor values.
*/
Image_Pos_Edges :: proc(value: oni.Image_Pos) -> oni.Cfg(oni.Style_Image_Pos) {
	return cfg_value(oni.Style_Image_Pos(value))
}

Visibility :: proc(value: oni.Visibility) -> oni.Cfg(oni.Visibility) {return cfg_value(value)}

/*
Sets a width widget config field to an explicit value.
*/
Width :: proc(value: oni.Width) -> oni.Width {return oni.Width(value)}

Wrap :: proc(value: oni.Text_Warp) -> oni.Cfg(oni.Text_Warp) {return cfg_value(value)}

Border_Collapse :: proc(value: oni.Border_Collapse) -> oni.Cfg(oni.Border_Collapse) {
	return cfg_value(value)
}
