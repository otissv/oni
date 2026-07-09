package widgets

import o ".."

/*
Draws widget chrome respecting the owning table's border-collapse mode.
*/
table_widget_draw_chrome :: proc(
	layout_id: o.UI_Id,
	kind: o.Widget_Kind,
	rect: o.Rect,
	config: o.Resolved_Widget_Config,
	frame_state: ^$S,
	event: o.Widget_Event(S),
) {
	collapse := o.table_layout_border_collapse_for_widget(layout_id, kind)

	background: o.RGBA
	if resolved_background, background_ok := o.to_rgba(config.background, frame_state, event);
	   background_ok {
		background = resolved_background
	}

	if collapse == .COLLAPSE {
		#partial switch kind {
		case .TABLE_CELL, .TABLE_HEADING:
			if collapsed, collapsed_ok := o.table_resolve_collapsed_borders(
				layout_id,
				frame_state,
				event,
			); collapsed_ok {
				o.table_draw_collapsed_cell(rect, background, collapsed)
				return
			}
		case .TABLE, .TABLE_ROW, .TABLE_BODY, .TABLE_HEAD, .TABLE_FOOT:
			if background.a > 0 {
				o.Draw_Rectangle(rect, background)
			}
			return
		}
	}

	border: o.Bd
	if resolved_border, border_ok := o.resolve_border(config.border, frame_state, event);
	   border_ok {
		border = resolved_border
	}

	border_color: o.RGBA
	if resolved_border_color, border_color_ok := o.to_rgba(
		config.border_color,
		frame_state,
		event,
	); border_color_ok {
		border_color = resolved_border_color
	}

	radius: o.Radius_corners
	if resolved_radius, ok := o.resolve_radius(config.radius, frame_state, event); ok {
		radius = resolved_radius
	}

	o.Draw_Rectangle(rect, background, radius, border, border_color)
}
