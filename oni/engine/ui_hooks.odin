package engine

UI_Procs :: struct {
	init:        proc(),
	shutdown:    proc(),
	begin_frame: proc(),
	end_frame:   proc(),
}

ui_procs: UI_Procs

register_ui :: proc(procs: UI_Procs) {
	ui_procs = procs
}

ui_init :: proc() {
	if ui_procs.init != nil do ui_procs.init()
}

ui_shutdown :: proc() {
	if ui_procs.shutdown != nil do ui_procs.shutdown()
}

ui_begin_frame :: proc() {
	if ui_procs.begin_frame != nil do ui_procs.begin_frame()
}

ui_end_frame :: proc() {
	if ui_procs.end_frame != nil do ui_procs.end_frame()
}
