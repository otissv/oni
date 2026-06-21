package set

import oni ".."

@(private)
cfg_value :: proc(v: $T) -> oni.Cfg(T) {
	return oni.Cfg(T){mode = .Value, value = v}
}

@(private)
cfg_inherit :: proc($T: typeid) -> oni.Cfg(T) {
	return oni.Cfg(T){mode = .Inherit}
}

Colors :: proc(value: oni.Colors) -> oni.Cfg(oni.Colors) {return cfg_value(value)}
Padding :: proc(value: oni.Padding) -> oni.Cfg(oni.Padding) {return cfg_value(value)}
Radius :: proc(value: oni.Radius) -> oni.Cfg(oni.Radius) {return cfg_value(value)}
Border :: proc(value: oni.Border) -> oni.Cfg(oni.Border) {return cfg_value(value)}
Gap :: proc(value: oni.Gap) -> oni.Cfg(oni.Gap) {return cfg_value(value)}
Justify :: proc(value: oni.Justify) -> oni.Cfg(oni.Justify) {return cfg_value(value)}
Direction :: proc(direction: oni.Direction_Layout) -> oni.Cfg(oni.Widget_Direction) {
	return cfg_value(oni.Widget_Direction(direction))
}
Space :: proc(space: oni.Draw_Space) -> oni.Cfg(oni.Draw_Space) {return cfg_value(space)}
Inherit_Space :: proc() -> oni.Cfg(oni.Draw_Space) {return cfg_inherit(oni.Draw_Space)}
Text_Direction :: proc(value: oni.Text_Direction) -> oni.Cfg(oni.Text_Direction) {
	return cfg_value(value)
}
F32 :: proc(value: f32) -> oni.Cfg(f32) {return cfg_value(value)}
Font :: proc(font: oni.Font_Handle) -> oni.Cfg(oni.Font_Handle) {return cfg_value(font)}
Bool :: proc(value: bool) -> oni.Cfg(bool) {return cfg_value(value)}
Inherit :: proc($T: typeid) -> oni.Cfg(T) {return cfg_inherit(T)}
