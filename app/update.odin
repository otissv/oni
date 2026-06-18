package app

import oni "../oni"

ZOOM_WHEEL_STEP :: oni.VIEW_ZOOM_STEP

app_tick :: proc(dt: f32) {
	_ = dt

	if persistent.engine.input.mouse_wheel_y == 0 do return

	mouse := oni.Input_Mouse_Screen()
	factor := ZOOM_WHEEL_STEP
	if persistent.engine.input.mouse_wheel_y < 0 {
		factor = 1 / ZOOM_WHEEL_STEP
	}
	oni.View_Zoom_By_Screen(mouse, factor)
}
