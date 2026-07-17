package oni_set

import oni ".."

/*
Wraps a value in a Cfg with mode set to Value.

Used internally by the public set helpers below.
*/
@(private)
cfg_value :: proc(v: $T) -> oni.Cfg(T) {
	return oni.Cfg(T){mode = .Value, value = v}
}

Align :: proc(value: oni.Text_Align) -> oni.Cfg(oni.Text_Align) {return cfg_value(value)}

Background :: Colors

/*
Sets a bool widget config field to an explicit value or `.INHERIT`.
*/
Bool :: proc(value: oni.Style_Bool) -> oni.Cfg(oni.Style_Bool) {return cfg_value(value)}

/*
Sets a border widget config field to an explicit value or `.INHERIT`.
*/
Border :: proc(value: oni.Border) -> oni.Cfg(oni.Border) {return cfg_value(value)}

Border_color :: Colors

Color :: Colors

/*
Sets a colors widget config field to an explicit value or `.INHERIT`.
*/
Colors :: proc(value: oni.Colors) -> oni.Cfg(oni.Colors) {return cfg_value(value)}

/*
Sets a layout direction widget config field to an explicit value or `.INHERIT`.
*/
Direction :: proc(
	direction: oni.Widget_Direction,
) -> oni.Cfg(oni.Widget_Direction) {return cfg_value(direction)}


Disabled :: Bool


/*
Sets an f32 widget config field to an explicit value or `.INHERIT`.
*/
F32 :: proc(value: oni.Style_F32) -> oni.Cfg(oni.Style_F32) {return cfg_value(value)}

Flex :: F32


/*
Sets a font widget config field to an explicit value or `.INHERIT`.
*/
Font :: proc(font: oni.Style_Font) -> oni.Cfg(oni.Style_Font) {return cfg_value(font)}


Font_size :: F32

/*
Sets a font-style widget config field to an explicit value or `.INHERIT`.
*/
Font_style :: proc(style: oni.Font_Style) -> oni.Cfg(oni.Font_Style) {return cfg_value(style)}

/*
Sets a font-weight widget config field to an explicit value or `.INHERIT`.
*/
Font_weight :: proc(weight: oni.Font_Weight) -> oni.Cfg(oni.Font_Weight) {return cfg_value(weight)}

/*
Sets a horizontal gap widget config field to an explicit value or `.INHERIT`.
*/
Gap_X :: proc(value: oni.Gap_X) -> oni.Cfg(oni.Gap_X) {return cfg_value(value)}

/*
Sets a vertical gap widget config field to an explicit value or `.INHERIT`.
*/
Gap_Y :: proc(value: oni.Gap_Y) -> oni.Cfg(oni.Gap_Y) {return cfg_value(value)}

/*
Sets a height widget config field to an explicit value.
*/
Height :: proc(value: oni.Height) -> oni.Height {return oni.Height(value)}

/*
Sets a justify widget config field to an explicit value or `.INHERIT`.
*/
Justify :: proc(value: oni.Justify) -> oni.Cfg(oni.Justify) {return cfg_value(value)}

Letter_Spacing :: F32

Line_Height :: F32

Max_H :: F32

Max_W :: F32

Min_H :: F32

Min_W :: F32

Order :: F32

Opacity :: F32

overflow :: proc(value: oni.Overflow) -> oni.Cfg(oni.Overflow) {return cfg_value(value)}

/*
Sets a padding widget config field to an explicit value or `.INHERIT`.
*/
Padding :: proc(value: oni.Padding) -> oni.Cfg(oni.Padding) {return cfg_value(value)}

Position :: proc(value: oni.Position) -> oni.Cfg(oni.Position) {return cfg_value(value)}

/*
Sets a radius widget config field to an explicit value or `.INHERIT`.
*/
Radius :: proc(value: oni.Radius) -> oni.Cfg(oni.Radius) {return cfg_value(value)}

/*
Sets a self-alignment justify config field to an explicit value or `.INHERIT`.
*/
Self :: proc(value: oni.Justify) -> oni.Cfg(oni.Justify) {return cfg_value(value)}

/*
Sets a draw-space widget config field to an explicit value or `.INHERIT`.
*/
Space :: proc(space: oni.Style_Space) -> oni.Cfg(oni.Style_Space) {return cfg_value(space)}

Tabbable :: Bool

/*
Sets text-decoration lines (underline, line-through, overline).
*/
Text_decoration :: proc(
	value: oni.Text_Decoration,
) -> oni.Cfg(oni.Text_Decoration) {return cfg_value(value)}

/*
Sets text-decoration-color to an explicit color.
*/
Text_decoration_color :: Colors

/*
Sets text-decoration-style (solid, double, dotted, dashed, wavy).
*/
Text_decoration_style :: proc(
	value: oni.Text_Decoration_Style,
) -> oni.Cfg(oni.Text_Decoration_Style) {return cfg_value(value)}

/*
Sets a text-direction widget config field to an explicit value or `.INHERIT`.
*/
Text_Direction :: proc(
	value: oni.Text_Direction,
) -> oni.Cfg(oni.Text_Direction) {return cfg_value(value)}


/*
Sets a texture-fit style config field to an explicit value or `.INHERIT`.
*/
Texture_Fit :: proc(value: oni.Style_Texture_Fit) -> oni.Cfg(oni.Style_Texture_Fit) {
	return cfg_value(value)
}

/*
Sets a texture position config field from x/y anchor values.
*/
Texture_Pos :: proc(value: oni.Texture_Pos_X_Y) -> oni.Cfg(oni.Style_Texture_Pos) {
	return cfg_value(oni.Style_Texture_Pos(value))
}

/*
Sets a texture position config field from edge-based anchor values.
*/
Texture_Pos_Edges :: proc(value: oni.Texture_Pos) -> oni.Cfg(oni.Style_Texture_Pos) {
	return cfg_value(oni.Style_Texture_Pos(value))
}

Visibility :: proc(value: oni.Visibility) -> oni.Cfg(oni.Visibility) {return cfg_value(value)}

Pointer_Events :: proc(
	value: oni.Pointer_Events,
) -> oni.Cfg(oni.Pointer_Events) {return cfg_value(value)}

Accepts_Text_Input :: proc(value: bool = true) -> bool {return value}

Right :: F32

Bottom :: F32

/*
Sets a width widget config field to an explicit value.
*/
Width :: proc(value: oni.Width) -> oni.Width {return oni.Width(value)}

Wrap :: proc(value: oni.Text_Wrap) -> oni.Cfg(oni.Text_Wrap) {return cfg_value(value)}

Z_Index :: F32
