package oni_widgets

import o ".."
import set "../set"
import "core:fmt"


@(init)
error_banner_ui_register :: proc "contextless" () {
	o.error_banner_register_ui(error_banner_ui)
}

@(private)
error_banner_entries: []o.Error_Entry

@(private)
error_banner_entry: struct {
	entry: o.Error_Entry,
	index: int,
}

@(private)
error_banner_entry_id :: proc(index: int, suffix: string) -> string {
	return fmt.tprintf("error-banner-{}-{}", index, suffix)
}

@(private)
error_banner_summary_row :: proc(state: Rectangle_State) {
	_ = state

	entry := error_banner_entry.entry
	index := error_banner_entry.index

	Text({
		config = {
			id = error_banner_entry_id(index, "summary"),
			text = entry.summary,
			color = set.Color(.DESTRUCTIVE_FOREGROUND),
			font = set.Font(o.theme.font_body),
			font_size = set.F32(13),
			line_height = set.F32(1.3),
			wrap = set.Wrap(.NEWLINES),
			max_w = set.Max_W(f32(o.state.dpi.logical_w) - 160),
		},
	})

	Button({
		config = {
			id = error_banner_entry_id(index, "details"),
			font = set.Font(o.theme.font_body),
			font_size = set.F32(13),
			color = set.Color(.DESTRUCTIVE_FOREGROUND),
			background = set.Colors(o.RGBA{0, 0, 0, 0}),
			border = set.Border(0),
			padding = set.Padding(o.Pd_pos{x = 4, y = 2}),
			text_decoration = set.Text_decoration(o.Text_Decoration_Lines{.UNDERLINE}),
		},
		child = proc(state: Button_State) {
			_ = state
			label := error_banner_entry.entry.expanded ? "Hide log" : "Show log"
			Text({
				config = {
					id = error_banner_entry_id(error_banner_entry.index, "details-label"),
					text = label,
					color = set.Color(.DESTRUCTIVE_FOREGROUND),
					font_size = set.F32(13),
				},
			})
		},
		on_click = proc(_: Button_Event) {
			o.error_toggle_expanded(error_banner_entry.entry.key)
		},
	})

	Button({
		config = {
			id = error_banner_entry_id(index, "dismiss"),
			font = set.Font(o.theme.font_body),
			font_size = set.F32(13),
			color = set.Color(.DESTRUCTIVE_FOREGROUND),
			background = set.Colors(o.RGBA{0, 0, 0, 0}),
			border = set.Border(0),
			padding = set.Padding(o.Pd_pos{x = 4, y = 2}),
		},
		child = proc(state: Button_State) {
			_ = state
			Text({
				config = {
					id = error_banner_entry_id(error_banner_entry.index, "dismiss-label"),
					text = "Dismiss",
					color = set.Color(.DESTRUCTIVE_FOREGROUND),
					font_size = set.F32(13),
				},
			})
		},
		on_click = proc(_: Button_Event) {
			o.error_dismiss(error_banner_entry.entry.key)
		},
	})
}

@(private)
error_banner_entry_body :: proc(state: Rectangle_State) {
	_ = state

	entry := error_banner_entry.entry
	index := error_banner_entry.index

	Rectangle({
		config = {
			id = error_banner_entry_id(index, "summary-row"),
			direction = set.Direction(.HORIZONTAL),
			gap_x = set.Gap_X(12),
			align = set.Align(.CENTER),
			width = set.Width(.AUTO),
		},
		child = error_banner_summary_row,
	})

	if entry.expanded {
		Text({
			config = {
				id = error_banner_entry_id(index, "details-text"),
				text = entry.log_line,
				color = set.Color(.DESTRUCTIVE_FOREGROUND),
				font = set.Font(o.theme.font_body),
				font_size = set.F32(12),
				line_height = set.F32(1.35),
				wrap = set.Wrap(.NEWLINES),
				max_w = set.Max_W(f32(o.state.dpi.logical_w) - 32),
				opacity = set.F32(0.9),
			},
		})
	}
}

@(private)
error_banner_render_entry :: proc() {
	index := error_banner_entry.index

	Rectangle({
		config = {
			id = error_banner_entry_id(index, "row"),
			direction = set.Direction(.VERTICAL),
			gap_y = set.Gap_Y(4),
			width = set.Width(.AUTO),
		},
		child = error_banner_entry_body,
	})
}

@(private)
error_banner_body :: proc(state: Rectangle_State) {
	_ = state

	for entry, index in error_banner_entries {
		error_banner_entry = {entry, index}
		error_banner_render_entry()
	}
}

@(private)
error_banner_ui :: proc() {
	if o.error_active_count() == 0 {

		return
	}

	error_banner_entries = o.error_entries()

	o.Begin_Overlay()
	defer o.End_Overlay()

	Rectangle({
		config = {
			id = "error-banner",
			position = set.Position(.FIXED),
			x = set.F32(0),
			y = set.F32(0),
			width = set.Width(f32(o.state.dpi.logical_w)),
			direction = set.Direction(.VERTICAL),
			gap_y = set.Gap_Y(8),
			padding = set.Padding(o.Pd_struct{x = 12, y = 10}),
			background = set.Colors(o.Color.DESTRUCTIVE),
			border = set.Border(o.BORDER_SM),
			border_color = set.Border_color(o.Color.DESTRUCTIVE),
		},
		child = error_banner_body,
	})
}
