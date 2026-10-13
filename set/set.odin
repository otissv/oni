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

/*
Sets a text-align widget config field to an explicit value or `.INHERIT`.

Example:
`Align(.CENTER)`
*/
Align :: proc(value: oni.Text_Align) -> oni.Cfg(oni.Text_Align) {return cfg_value(value)}

/*
Sets a background color widget config field to an explicit value or `.INHERIT`.

Example:
`Background(o.Color.PRIMARY)`
*/
Background :: Colors

/*
Sets a bool widget config field to an explicit value or `.INHERIT`.

Example:
`Bool(true)`
*/
Bool :: proc(value: oni.Style_Bool) -> oni.Cfg(oni.Style_Bool) {return cfg_value(value)}

/*
Sets a border widget config field to an explicit value or `.INHERIT`.

Example:
`Border(1)`
*/
Border :: proc(value: oni.Border) -> oni.Cfg(oni.Border) {return cfg_value(value)}

/*
Sets a border-color widget config field to an explicit value or `.INHERIT`.

Example:
`Border_color(o.Color.BORDER)`
*/
Border_color :: Colors

/*
Sets a foreground color widget config field to an explicit value or `.INHERIT`.

Example:
`Color(o.Color.FOREGROUND)`
*/
Color :: Colors

/*
Sets a colors widget config field to an explicit value or `.INHERIT`.

Example:
`Colors(o.Color.MUTED)`
*/
Colors :: proc(value: oni.Colors) -> oni.Cfg(oni.Colors) {return cfg_value(value)}

/*
Sets a layout direction widget config field to an explicit value or `.INHERIT`.

Example:
`Direction(.VERTICAL)`
*/
Direction :: proc(
	direction: oni.Widget_Direction,
) -> oni.Cfg(oni.Widget_Direction) {return cfg_value(direction)}


/*
Sets a disabled widget config field to an explicit value or `.INHERIT`.

Example:
`Disabled(true)`
*/
Disabled :: Bool


/*
Sets an f32 widget config field to an explicit value or `.INHERIT`.

Example:
`F32(13)`
*/
F32 :: proc(value: oni.Style_F32) -> oni.Cfg(oni.Style_F32) {return cfg_value(value)}

/*
Sets a flex grow/shrink widget config field to an explicit value or `.INHERIT`.

Example:
`Flex(1)`
*/
Flex :: F32


/*
Sets a font widget config field to an explicit value or `.INHERIT`.

Example:
`Font(o.theme.font_body)`
*/
Font :: proc(font: oni.Style_Font) -> oni.Cfg(oni.Style_Font) {return cfg_value(font)}


/*
Sets a font-size widget config field to an explicit value or `.INHERIT`.

Example:
`Font_size(16)`
*/
Font_size :: F32

/*
Sets a font-style widget config field to an explicit value or `.INHERIT`.

Example:
`Font_style(.ITALIC)`
*/
Font_style :: proc(style: oni.Font_Style) -> oni.Cfg(oni.Font_Style) {return cfg_value(style)}

/*
Sets a font-weight widget config field to an explicit value or `.INHERIT`.

Example:
`Font_weight(f32(600))`
*/
Font_weight :: proc(weight: oni.Font_Weight) -> oni.Cfg(oni.Font_Weight) {return cfg_value(weight)}

/*
Sets a horizontal gap widget config field to an explicit value or `.INHERIT`.

Unset gap defaults to the theme gap when set, otherwise 0. Pass `.INHERIT` to
take the parent container's gap. Gap applies between immediate children only.

Example:
`Gap_X(u16(12))`
*/
Gap_X :: proc(value: oni.Gap_X) -> oni.Cfg(oni.Gap_X) {return cfg_value(value)}

/*
Sets a vertical gap widget config field to an explicit value or `.INHERIT`.

Unset gap defaults to the theme gap when set, otherwise 0. Pass `.INHERIT` to
take the parent container's gap. Gap applies between immediate children only.

Example:
`Gap_Y(u16(20))`
*/
Gap_Y :: proc(value: oni.Gap_Y) -> oni.Cfg(oni.Gap_Y) {return cfg_value(value)}

/*
Sets a height widget config field to an explicit value.

Unset height is content-sized. Pass `.GROW` to fill free vertical space,
`.AUTO` to fill the parent content area (scrollport viewport), or `.FIT` to
shrink to content clamped to available space.

Example:
`Height(f32(48))`
`Height(.GROW)`
`Height(.AUTO)`
`Height(.FIT)`
*/
Height :: proc(value: oni.Height) -> oni.Height {return oni.Height(value)}

/*
Sets a justify widget config field to an explicit value or `.INHERIT`.

Example:
`Justify(o.Justify_Pos{x = .CENTER, y = .CENTER})`
*/
Justify :: proc(value: oni.Justify) -> oni.Cfg(oni.Justify) {return cfg_value(value)}

/*
Sets a letter-spacing widget config field to an explicit value or `.INHERIT`.

Example:
`Letter_Spacing(0.5)`
*/
Letter_Spacing :: F32

/*
Sets a line-height widget config field to an explicit value or `.INHERIT`.

Example:
`Line_Height(1.5)`
*/
Line_Height :: F32

/*
Sets a max-height widget config field to an explicit value or `.INHERIT`.

Example:
`Max_H(320)`
*/
Max_H :: F32

/*
Sets a max-width widget config field to an explicit value or `.INHERIT`.

Example:
`Max_W(480)`
*/
Max_W :: F32

/*
Sets a min-height widget config field to an explicit value or `.INHERIT`.

Example:
`Min_H(24)`
*/
Min_H :: F32

/*
Sets a min-width widget config field to an explicit value or `.INHERIT`.

Example:
`Min_W(120)`
*/
Min_W :: F32


/*
Sets a layout order widget config field to an explicit value or `.INHERIT`.

Example:
`Order(2)`
*/
Order :: F32

/*
Sets an opacity widget config field to an explicit value or `.INHERIT`.

Example:
`Opacity(0.5)`
*/
Opacity :: F32

/*
Sets an overflow widget config field to an explicit value or `.INHERIT`.

Example:
`overflow(.AUTO)`
*/
overflow :: proc(value: oni.Overflow) -> oni.Cfg(oni.Overflow) {return cfg_value(value)}

/*
Sets an overflow-x widget config field to an explicit value or `.INHERIT`.

Example:
`Overflow_X(.AUTO)`
*/
Overflow_X :: overflow

/*
Sets an overflow-y widget config field to an explicit value or `.INHERIT`.

Example:
`Overflow_Y(.SCROLL)`
*/
Overflow_Y :: overflow

/*
Sets a scroll-x offset value.

Example:
`Scroll_X(0)`
*/
Scroll_X :: proc(value: f32) -> oni.Scroll_Value {return value}

/*
Sets a scroll-y offset value.

Example:
`Scroll_Y(120)`
*/
Scroll_Y :: proc(value: f32) -> oni.Scroll_Value {return value}

/*
Sets a margin widget config field to an explicit value or `.INHERIT`.

Example:
`Margin(o.Mg_struct{b = 16})`
*/
Margin :: proc(value: oni.Margin) -> oni.Cfg(oni.Margin) {return cfg_value(value)}

/*
Sets a padding widget config field to an explicit value or `.INHERIT`.

Example:
`Padding(f32(20))`
*/
Padding :: proc(value: oni.Padding) -> oni.Cfg(oni.Padding) {return cfg_value(value)}

/*
Sets a position widget config field to an explicit value or `.INHERIT`.

Example:
`Position(.ABSOLUTE)`
*/
Position :: proc(value: oni.Position) -> oni.Cfg(oni.Position) {return cfg_value(value)}

/*
Sets a radius widget config field to an explicit value or `.INHERIT`.

Example:
`Radius(8)`
*/
Radius :: proc(value: oni.Radius) -> oni.Cfg(oni.Radius) {return cfg_value(value)}

/*
Sets a self-alignment justify config field to an explicit value or `.INHERIT`.

Example:
`Self(.CENTER)`
*/
Self :: proc(value: oni.Justify) -> oni.Cfg(oni.Justify) {return cfg_value(value)}

/*
Sets a draw-space widget config field to an explicit value or `.INHERIT`.

Example:
`Space(.SCREEN)`
*/
Space :: proc(space: oni.Style_Space) -> oni.Cfg(oni.Style_Space) {return cfg_value(space)}

/*
Sets a tabbable widget config field to an explicit value or `.INHERIT`.

Example:
`Tabbable(false)`
*/
Tabbable :: Bool

/*
Sets text-decoration lines (underline, line-through, overline).

Example:
`Text_decoration({.UNDERLINE})`
*/
Text_decoration :: proc(
	value: oni.Text_Decoration,
) -> oni.Cfg(oni.Text_Decoration) {return cfg_value(value)}

/*
Sets text-decoration-color to an explicit color.

Example:
`Text_decoration_color(o.Color.ACCENT)`
*/
Text_decoration_color :: Colors

/*
Sets text-decoration-style (solid, double, dotted, dashed, wavy).

Example:
`Text_decoration_style(.DOTTED)`
*/
Text_decoration_style :: proc(
	value: oni.Text_Decoration_Style,
) -> oni.Cfg(oni.Text_Decoration_Style) {return cfg_value(value)}

/*
Sets a text-direction widget config field to an explicit value or `.INHERIT`.

Example:
`Text_Direction(.RTL)`
*/
Text_Direction :: proc(
	value: oni.Text_Direction,
) -> oni.Cfg(oni.Text_Direction) {return cfg_value(value)}


/*
Sets a texture-fit style config field to an explicit value or `.INHERIT`.

Example:
`Texture_Fit(.COVER)`
*/
Texture_Fit :: proc(value: oni.Style_Texture_Fit) -> oni.Cfg(oni.Style_Texture_Fit) {
	return cfg_value(value)
}

/*
Sets a texture position config field from x/y anchor values.

Example:
`Texture_Pos(o.Texture_Pos_X_Y{x = 50, y = 50})`
*/
Texture_Pos :: proc(value: oni.Texture_Pos_X_Y) -> oni.Cfg(oni.Style_Texture_Pos) {
	return cfg_value(oni.Style_Texture_Pos(value))
}

/*
Sets a texture position config field from edge-based anchor values.

Example:
`Texture_Pos_Edges(o.Texture_Pos{t = 0, l = 0})`
*/
Texture_Pos_Edges :: proc(value: oni.Texture_Pos) -> oni.Cfg(oni.Style_Texture_Pos) {
	return cfg_value(oni.Style_Texture_Pos(value))
}

/*
Sets a visibility widget config field to an explicit value or `.INHERIT`.

Example:
`Visibility(.HIDDEN)`
*/
Visibility :: proc(value: oni.Visibility) -> oni.Cfg(oni.Visibility) {return cfg_value(value)}

/*
Sets a pointer-events widget config field to an explicit value or `.INHERIT`.

Example:
`Pointer_Events(.NONE)`
*/
Pointer_Events :: proc(
	value: oni.Pointer_Events,
) -> oni.Cfg(oni.Pointer_Events) {return cfg_value(value)}

/*
Marks a widget as accepting text input.

Example:
`Accepts_Text_Input()`
*/
Accepts_Text_Input :: proc(value: bool = true) -> bool {return value}

/*
Marks a widget as text-selectable.

Example:
`Selectable()`
*/
Selectable :: proc(value: bool = true) -> bool {return value}

/*
Sets a right offset widget config field to an explicit value or `.INHERIT`.

Example:
`Right(24)`
*/
Right :: F32

/*
Sets a bottom offset widget config field to an explicit value or `.INHERIT`.

Example:
`Bottom(24)`
*/
Bottom :: F32

/*
Sets a width widget config field to an explicit value.

Unset width resolves to `.GROW`. Pass `.FIT` / `.AUTO` / a fixed size to opt out.

Example:
`Width(f32(320))`
`Width(.FIT)`
*/
Width :: proc(value: oni.Width) -> oni.Width {return oni.Width(value)}

/*
Sets a text-wrap widget config field to an explicit value or `.INHERIT`.

Example:
`Wrap(.BALANCE)`
*/
Wrap :: proc(value: oni.Text_Wrap) -> oni.Cfg(oni.Text_Wrap) {return cfg_value(value)}

/*
Sets a tab-size widget config field to an explicit value or `.INHERIT`.

Example:
`Tab_Size(4)`
*/
Tab_Size :: F32

/*
Sets a word-spacing widget config field to an explicit value or `.INHERIT`.

Example:
`Word_Spacing(2)`
*/
Word_Spacing :: F32

/*
Sets a z-index widget config field to an explicit value or `.INHERIT`.

Example:
`Z_Index(2)`
*/
Z_Index :: F32

/*
Tailwind `grid-cols-{n}`: `repeat(n, minmax(0, 1fr))`.

Example:
`Grid_Cols(3)`
*/
Grid_Cols :: proc(n: int) -> oni.Cfg(oni.Grid_Template_Columns) {
	return cfg_value(oni.Grid_Template_Columns(n))
}

/*
Tailwind `grid-rows-{n}`: `repeat(n, minmax(0, 1fr))`.

Example:
`Grid_Rows(3)`
*/
Grid_Rows :: proc(n: int) -> oni.Cfg(oni.Grid_Template_Rows) {
	return cfg_value(oni.Grid_Template_Rows(n))
}

/*
Raw CSS grid-template-columns track list.

Example:
`Grid_Template_Columns("120px 1fr 1fr")`
*/
Grid_Template_Columns :: proc(list: string) -> oni.Cfg(oni.Grid_Template_Columns) {
	return cfg_value(oni.Grid_Template_Columns(list))
}

/*
Raw CSS grid-template-rows track list.

Example:
`Grid_Template_Rows("auto 1fr auto")`
*/
Grid_Template_Rows :: proc(list: string) -> oni.Cfg(oni.Grid_Template_Rows) {
	return cfg_value(oni.Grid_Template_Rows(list))
}

/*
Tailwind `auto-cols-auto|min|max|fr`.

Example:
`Grid_Auto_Columns(.FR)`
*/
Grid_Auto_Columns :: proc(preset: oni.Grid_Auto_Preset) -> oni.Cfg(oni.Grid_Auto_Track) {
	return cfg_value(oni.Grid_Auto_Track(preset))
}

/*
Tailwind `auto-rows-auto|min|max|fr`.

Example:
`Grid_Auto_Rows(.AUTO)`
*/
Grid_Auto_Rows :: proc(preset: oni.Grid_Auto_Preset) -> oni.Cfg(oni.Grid_Auto_Track) {
	return cfg_value(oni.Grid_Auto_Track(preset))
}

/*
Sets grid-auto-flow.

Example:
`Grid_Auto_Flow(.ROW)`
*/
Grid_Auto_Flow :: proc(flow: oni.Grid_Auto_Flow) -> oni.Cfg(oni.Grid_Auto_Flow) {
	return cfg_value(flow)
}

/*
Sets grid-template-areas.

Example:
`Grid_Template_Areas("\"header header\" \"side main\"")`
*/
Grid_Template_Areas :: proc(areas: string) -> oni.Cfg(string) {return cfg_value(areas)}

/*
Sets grid-column placement.

Example:
`Grid_Column("1 / 4")`
*/
Grid_Column :: proc(value: string) -> oni.Cfg(string) {return cfg_value(value)}

/*
Sets grid-row placement.

Example:
`Grid_Row("2 / 4")`
*/
Grid_Row :: proc(value: string) -> oni.Cfg(string) {return cfg_value(value)}

/*
Sets grid-area by name.

Example:
`Grid_Area("sidebar")`
*/
Grid_Area :: proc(name: string) -> oni.Cfg(string) {return cfg_value(name)}

/*
Sets grid-column-start line.

Example:
`Col_Start(2)`
*/
Col_Start :: proc(line: int) -> oni.Cfg(oni.Grid_Line_Value) {
	return cfg_value(oni.Grid_Line_Value(oni.Grid_Line{line = line}))
}

/*
Sets grid-column-end line.

Example:
`Col_End(4)`
*/
Col_End :: proc(line: int) -> oni.Cfg(oni.Grid_Line_Value) {
	return cfg_value(oni.Grid_Line_Value(oni.Grid_Line{line = line}))
}

/*
Sets grid-column span.

Example:
`Col_Span(2)`
*/
Col_Span :: proc(span: int) -> oni.Cfg(oni.Grid_Line_Value) {
	return cfg_value(oni.Grid_Line_Value(oni.Grid_Line{span = span}))
}

/*
Sets grid-row-start line.

Example:
`Row_Start(2)`
*/
Row_Start :: proc(line: int) -> oni.Cfg(oni.Grid_Line_Value) {
	return cfg_value(oni.Grid_Line_Value(oni.Grid_Line{line = line}))
}

/*
Sets grid-row-end line.

Example:
`Row_End(4)`
*/
Row_End :: proc(line: int) -> oni.Cfg(oni.Grid_Line_Value) {
	return cfg_value(oni.Grid_Line_Value(oni.Grid_Line{line = line}))
}

/*
Sets grid-row span.

Example:
`Row_Span(2)`
*/
Row_Span :: proc(span: int) -> oni.Cfg(oni.Grid_Line_Value) {
	return cfg_value(oni.Grid_Line_Value(oni.Grid_Line{span = span}))
}
