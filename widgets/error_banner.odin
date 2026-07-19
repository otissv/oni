package oni_widgets

import o ".."
import set "../set"
import "core:fmt"


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
	level_label := entry.level == .ERROR ? "ERROR" : "WARN"

	Text({
		config = {
			id = error_banner_entry_id(index, "summary"),
			text = fmt.tprintf("[%s] %s", level_label, entry.message),
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
				text = o.error_format_log_line(entry),
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
error_banner_estimate_height :: proc(entries: []o.Error_Entry) -> f32 {
	if len(entries) == 0 do return 0

	height := f32(20)

	for entry in entries {
		height += 28

		if entry.expanded {
			height += 20
		}

		height += 8
	}

	return height
}

@(private)
error_banner_body :: proc(state: Rectangle_State) {
	_ = state

	entries := o.error_active_entries(context.temp_allocator)

	for entry, index in entries {
		error_banner_entry = {entry, index}
		error_banner_render_entry()
	}
}

/*
Renders active engine/app errors in a fixed banner at the top of the window.

Call near the start of the screen UI tree. Height is exposed via o.Error_Banner_Height().
*/
Error_Banner :: proc() {
	if o.error_active_count() == 0 {
		o.error_set_banner_height(0)

		return
	}

	entries := o.error_active_entries(context.temp_allocator)
	o.error_set_banner_height(error_banner_estimate_height(entries))

	Rectangle({
		config = {
			id = "error-banner",
			space = set.Space(.POPOVER),
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
			z_index = set.Z_Index(f32(100000)),
		},
		child = error_banner_body,
	})

	if o.ui_pass() == .Draw {
		layout_id := o.ui_id("error-banner")
		layout_rect := o.ui_layout_rect(layout_id)
		o.error_set_banner_height(layout_rect.h)
	}
}
