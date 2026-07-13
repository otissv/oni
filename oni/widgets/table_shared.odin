package widgets

import o ".."

/*
Draws widget chrome respecting the owning table's gap-driven collapse mode.

Gap 0 collapses borders: cells paint conflict-resolved strips (including the table
border on the outer perimeter). Table/row/group chrome paints fill only.
Descendants that share the table content-box corners inherit matching outer radii so
opaque fills do not square off a rounded table.
*/
table_widget_draw_chrome :: proc(
	layout_id: o.UI_Id,
	kind: o.Widget_Kind,
	rect: o.Rect,
	config: o.Resolved_Widget_Config,
	frame_state: ^$S,
	event: o.Widget_Event(S),
) {
	if o.ui_layout_paint_skip(layout_id) do return
	collapsed := o.table_layout_borders_collapsed_for_widget(layout_id, kind)

	background: o.RGBA
	if resolved_background, background_ok := o.to_rgba(config.background, frame_state, event);
	   background_ok {
		background = resolved_background
	}

	radius: o.Radius_px
	if kind != .TABLE {
		if resolved_radius, ok := o.resolve_radius(config.radius, frame_state, event); ok {
			radius = resolved_radius
		}
		radius = o.table_merge_radius_corners(radius, o.table_descendant_outer_radius(layout_id, rect))
	} else if resolved_radius, ok := o.resolve_radius(config.radius, frame_state, event); ok {
		radius = resolved_radius
	}

	if collapsed {
		#partial switch kind {
		case .TABLE_CELL, .TABLE_HEADING:
			if collapsed_borders := o.layout_collapsed_borders_result(layout_id);
			   collapsed_borders != nil {
				o.table_draw_collapsed_cell(
					rect,
					background,
					collapsed_borders^,
					radius,
					frame_state,
					event,
				)
				return
			}
		case .TABLE, .TABLE_ROW, .TABLE_BODY, .TABLE_HEAD, .TABLE_FOOT:
			if background.a > 0 {
				o.Draw_Rectangle(rect, background, radius)
			}
			return
		}
	}

	border: o.Bd_px
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

	o.Draw_Rectangle(rect, background, radius, border, border_color)
}
