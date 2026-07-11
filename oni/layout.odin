package oni


/*
Author text and optional wrap-width hint for leaf text measurement.
*/
Layout_Measure :: struct {
	text:  string,
	max_w: f32,
}

/*
One layout-owned glyph paint quad in absolute logical coordinates.
*/
Layout_Glyph_Paint :: struct {
	glyph_id: u32,
	dst:      Rect,
}

/*
One layout-owned decoration stroke segment in absolute logical coordinates.
*/
Layout_Decoration_Stroke :: struct {
	a, b:      Vec2,
	thickness: f32,
}

/*
Layout-owned shaped text: wrap, line boxes, glyph quads, and decoration strokes.
*/
Layout_Text :: struct {
	lines:               []Shaped_Line,
	line_origins:        []Vec2,
	glyphs:              []Layout_Glyph_Paint,
	decoration_strokes:  []Layout_Decoration_Stroke,
	font:                Font_Face_Handle,
	layout_scale:        f32,
	wrap_w:              f32,
	line_height:         f32,
	size:                Vec2,
}

/*
Author image inputs captured during the layout pass for fit finalization.
*/
Layout_Image_Input :: struct {
	src:    Rect,
	dst:    Rect,
	fit:    Texture_Fit,
	pos:    Resolved_Texture_Pos,
	active: bool,
}

/*
Layout-owned image paint geometry after object-fit and content insets.
*/
Layout_Image :: struct {
	content: Rect,
	src:     Rect,
	dst:     Rect,
	active:  bool,
}

/*
Layout-owned collapsed table border winners and paint strip rects (t,b,l,r).
*/
Layout_Collapsed_Borders :: struct {
	borders: Table_Cell_Borders,
	strips:  [4]Rect,
	active:  bool,
}

/*
One node in the flex layout tree with resolved style, geometry, and children.
*/
Layout_Node :: struct {
	ui_id:             UI_Id,
	kind:              Widget_Kind,
	config:            Resolved_Widget_Style,
	padding:           Pd,
	border:            Bd,
	desired:           Vec2,
	rect:              Rect,
	parent:            int,
	child_indices:     [dynamic]int,
	measure:           Layout_Measure,
	text:              Layout_Text,
	image_input:       Layout_Image_Input,
	image:             Layout_Image,
	collapsed_borders: Layout_Collapsed_Borders,
}

/*
Column widths and row heights computed for a table with TABLE_CELL alignment.
*/
Layout_Table_Tracks :: struct {
	rows:           [dynamic]int,
	col_widths:     [dynamic]f32,
	row_heights:    [dynamic]f32,
	border_collapse: Border_Collapse,
	cell_positions: map[int]Table_Grid_Pos,
}

/*
Per-frame flex layout tree, stacks, and UI_Id to node index map.
*/
Layout_State :: struct {
	nodes:                 [dynamic]Layout_Node,
	node_stack:            [dynamic]int,
	bounds_stack:          [dynamic]Rect,
	space_markers:         [dynamic]int,
	id_to_node:            map[UI_Id]int,
	table_tracks:          map[int]Layout_Table_Tracks,
	table_border_collapse: map[UI_Id]Border_Collapse,
}

@(private)
layout_release_node_children :: proc(layout: ^Layout_State) {
	for &node in layout.nodes {
		delete(node.child_indices)
		layout_text_release(&node)
	}
}

/*
Clears all layout nodes, stacks, and id-to-node mappings.

Called at the start of each UI frame.
*/
layout_reset :: proc() {
	for _, tracks in state.ui.layout.table_tracks {
		delete(tracks.rows)
		delete(tracks.col_widths)
		delete(tracks.row_heights)
		delete(tracks.cell_positions)
	}
	clear(&state.ui.layout.table_tracks)
	clear(&state.ui.layout.table_border_collapse)
	layout_release_node_children(&state.ui.layout)
	clear(&state.ui.layout.nodes)
	clear(&state.ui.layout.node_stack)
	clear(&state.ui.layout.bounds_stack)
	clear(&state.ui.layout.space_markers)
	clear(&state.ui.layout.id_to_node)
}

/*
Releases all heap-owned layout storage.

Call during UI shutdown after the final layout_reset.
*/
layout_shutdown :: proc() {
	delete(state.ui.layout.nodes)
	state.ui.layout.nodes = nil
	delete(state.ui.layout.node_stack)
	state.ui.layout.node_stack = nil
	delete(state.ui.layout.bounds_stack)
	state.ui.layout.bounds_stack = nil
	delete(state.ui.layout.space_markers)
	state.ui.layout.space_markers = nil
}

/*
Returns the flex direction from a resolved widget style.
*/
layout_config_direction :: proc(config: Resolved_Widget_Style) -> Direction_Layout {
	return config.direction
}

/*
Derived axis, wrap, and reverse flags for a Direction_Layout value.
*/
Layout_Direction_Info :: struct {
	is_horizontal:    bool,
	is_wrap:          bool,
	is_main_reverse:  bool,
	is_cross_reverse: bool,
}

/*
Derives axis, wrap, and reverse flags from a layout direction enum.
*/
layout_direction_info :: proc(direction: Direction_Layout) -> Layout_Direction_Info {
	switch direction {
	case .HORIZONTAL:
		return {is_horizontal = true}
	case .VERTICAL:
		return {}
	case .HORIZONTAL_WRAP:
		return {is_horizontal = true, is_wrap = true}
	case .VERTICAL_WRAP:
		return {is_wrap = true}
	case .HORIZONTAL_REVERSE:
		return {is_horizontal = true, is_main_reverse = true}
	case .VERTICAL_REVERSE:
		return {is_main_reverse = true}
	case .HORIZONTAL_WRAP_REVERSE:
		return {
			is_horizontal = true,
			is_wrap = true,
			is_main_reverse = true,
			is_cross_reverse = true,
		}
	case .VERTICAL_WRAP_REVERSE:
		return {is_wrap = true, is_main_reverse = true, is_cross_reverse = true}
	}
	unreachable()
}

/*
Returns whether a layout direction flows horizontally.
*/
layout_direction_is_horizontal :: proc(direction: Direction_Layout) -> bool {
	return layout_direction_info(direction).is_horizontal
}

/*
Returns whether a layout direction enables line wrapping.
*/
layout_direction_is_wrap :: proc(direction: Direction_Layout) -> bool {
	return layout_direction_info(direction).is_wrap
}

/*
Mirrors a position within available space for reverse flow axes.
*/
layout_mirror_in_available :: proc(pos, size, available: f32) -> f32 {
	return available - pos - size
}

/*
One wrapped line segment within a flex container during layout.
*/
Layout_Wrap_Line :: struct {
	start:     int,
	count:     int,
	main_sum:  f32,
	cross_max: f32,
}

/*
Computes the main-axis wrap limit from node config and insets.
*/
layout_wrap_main_limit_from_config :: proc(node: ^Layout_Node, is_horizontal: bool) -> f32 {
	main_len := is_horizontal ? node.config.width : node.config.height
	main_max := is_horizontal ? node.config.max_w : node.config.max_h
	main := length_resolve(main_len, 0)
	if main <= 0 && main_max > 0 do main = main_max

	if main <= 0 do return 0

	inset: f32
	if is_horizontal {
		inset = node.padding.l + node.padding.r + node.border.l + node.border.r
	} else {
		inset = node.padding.t + node.padding.b + node.border.t + node.border.b
	}
	return max(0, main - inset)
}

/*
Returns a child's size along the main axis for wrap layout.
*/
layout_wrap_child_main :: proc(size: Vec2, is_horizontal: bool) -> f32 {
	return is_horizontal ? size.x : size.y
}

/*
Returns a child's size along the cross axis for wrap layout.
*/
layout_wrap_child_cross :: proc(size: Vec2, is_horizontal: bool) -> f32 {
	return is_horizontal ? size.y : size.x
}

/*
Groups children into wrap lines given a main-axis size limit.
*/
layout_wrap_build_lines :: proc(
	sizes: []Vec2,
	is_horizontal: bool,
	gap: f32,
	main_limit: f32,
) -> [dynamic]Layout_Wrap_Line {
	lines: [dynamic]Layout_Wrap_Line
	if len(sizes) == 0 do return lines

	current: Layout_Wrap_Line

	for size, i in sizes {
		main := layout_wrap_child_main(size, is_horizontal)
		cross := layout_wrap_child_cross(size, is_horizontal)

		if current.count > 0 && main_limit > 0 {
			needed := current.main_sum + gap + main
			if needed > main_limit {
				append(&lines, current)
				current = {}
			}
		}

		if current.count == 0 do current.start = i
		if current.count > 0 do current.main_sum += gap
		current.main_sum += main
		current.cross_max = max(current.cross_max, cross)
		current.count += 1
	}

	if current.count > 0 do append(&lines, current)
	return lines
}

/*
Measures a wrap container's natural size from child desired sizes.
*/
layout_wrap_measure :: proc(node: ^Layout_Node, is_horizontal: bool, gap_main, gap_cross: f32) -> Vec2 {
	sizes: [dynamic]Vec2
	defer delete(sizes)
	resize(&sizes, len(node.child_indices))

	for child_index, i in node.child_indices {
		child := &state.ui.layout.nodes[child_index]
		sizes[i] = child.desired
	}

	main_limit := layout_wrap_main_limit_from_config(node, is_horizontal)
	lines := layout_wrap_build_lines(sizes[:], is_horizontal, gap_main, main_limit)
	defer delete(lines)

	main_natural: f32
	cross_sum: f32
	for line, i in lines {
		main_natural = max(main_natural, line.main_sum)
		cross_sum += line.cross_max
		if i + 1 < len(lines) do cross_sum += gap_cross
	}

	inset_w := node.padding.l + node.padding.r + node.border.l + node.border.r
	inset_h := node.padding.t + node.padding.b + node.border.t + node.border.b

	width := length_resolve(node.config.width, 0)
	height := length_resolve(node.config.height, 0)

	if is_horizontal {
		if width <= 0 do width = (main_limit > 0 ? main_limit : main_natural) + inset_w
		if height <= 0 do height = cross_sum + inset_h
	} else {
		if height <= 0 do height = (main_limit > 0 ? main_limit : main_natural) + inset_h
		if width <= 0 do width = cross_sum + inset_w
	}

	return {
		layout_clamp_axis(width, node.config.min_w, node.config.max_w),
		layout_clamp_axis(height, node.config.min_h, node.config.max_h),
	}
}

/*
Returns the main-axis inter-child gap from a resolved widget style.
*/
layout_config_gap_main :: proc(config: Resolved_Widget_Style, is_horizontal: bool) -> f32 {
	if is_horizontal do return f32(config.gap_x)
	return f32(config.gap_y)
}

/*
Returns the cross-axis inter-child gap from a resolved widget style.
*/
layout_config_gap_cross :: proc(config: Resolved_Widget_Style, is_horizontal: bool) -> f32 {
	if is_horizontal do return f32(config.gap_y)
	return f32(config.gap_x)
}

/*
Returns the justify alignment from a resolved widget style.
*/
layout_config_justify :: proc(config: Resolved_Widget_Style) -> Justify_Pos {
	return config.justify
}

/*
Merges parent justify with child self-alignment overrides per axis.
*/
layout_merge_justify :: proc(parent, self: Justify_Pos) -> Justify_Pos {
	result := parent
	if _, x_ok := resolve_justify_x(self.x); x_ok do result.x = self.x
	if _, y_ok := resolve_justify_y(self.y); y_ok do result.y = self.y
	return result
}
/*
Clamps a size to optional min and max constraints when they are positive.
*/
layout_clamp_axis :: proc(value, min_v, max_v: f32) -> f32 {
	result := value
	if min_v > 0 do result = max(result, min_v)
	if max_v > 0 do result = min(result, max_v)
	return result
}

/*
Shrinks an outer rect inward by padding to the content box.
*/
layout_content_rect :: proc(outer: Rect, padding: Pd) -> Rect {
	return {
		x = outer.x + padding.l,
		y = outer.y + padding.t,
		w = max(0, outer.w - padding.l - padding.r),
		h = max(0, outer.h - padding.t - padding.b),
	}
}

/*
Shrinks an outer rect inward by border and padding to the inner box.
*/
layout_inner_rect :: proc(outer: Rect, border: Bd, padding: Pd) -> Rect {
	return layout_content_rect(
		outer,
		{
			t = border.t + padding.t,
			b = border.b + padding.b,
			l = border.l + padding.l,
			r = border.r + padding.r,
		},
	)
}

/*
Returns whether a layout node carries author text to shape.
*/
layout_node_has_text :: proc(node: ^Layout_Node) -> bool {
	return node != nil && len(node.measure.text) > 0
}

/*
Frees shaped lines, origins, glyph quads, and decoration strokes owned by a layout node.
*/
layout_text_release :: proc(node: ^Layout_Node) {
	if node == nil do return
	if len(node.text.lines) > 0 {
		font_destroy_shaped_lines(node.text.lines)
	}
	delete(node.text.line_origins)
	delete(node.text.glyphs)
	delete(node.text.decoration_strokes)
	node.text = {}
}

/*
Resolves the wrap width layout owns for text.

Priority: author max_w, fixed width, then the available layout width.
*/
layout_text_resolve_wrap_w :: proc(node: ^Layout_Node, available_w: f32) -> f32 {
	if node.measure.max_w > 0 do return node.measure.max_w
	if node.config.width.kind == .FIXED && node.config.width.value > 0 {
		return node.config.width.value
	}
	if node.config.max_w > 0 do return node.config.max_w
	return available_w
}

/*
Shapes text into the node and records measured size.

Destroys any previous shaped lines. Line origins are filled by layout_text_position_lines.
*/
layout_text_build :: proc(node: ^Layout_Node, wrap_w: f32) {
	layout_text_release(node)
	if !layout_node_has_text(node) do return

	config := node.config
	resolved_font, layout_scale, ok := font_resolve(
		config.font,
		config.font_size,
		config.space,
		config.font_weight,
		config.font_style,
	)
	if !ok do return

	face := font_face_from_handle(resolved_font)
	if face == nil do return

	shape_max_w := wrap_w > 0 ? wrap_w / layout_scale : wrap_w
	letter_spacing := config.letter_spacing / layout_scale
	wrap := text_wrap_kind(config.wrap)
	direction := text_direction_kind(config.text_direction)
	lines := font_shape_line_build(
		face,
		node.measure.text,
		shape_max_w,
		letter_spacing,
		wrap,
		direction,
	)
	if len(lines) == 0 do return

	line_height := config.font_size * config.line_height
	size := font_measure_lines(face, lines, line_height, layout_scale)

	node.text = {
		lines               = lines,
		line_origins        = nil,
		glyphs              = nil,
		decoration_strokes  = nil,
		font                = resolved_font,
		layout_scale        = layout_scale,
		wrap_w              = wrap_w,
		line_height         = line_height,
		size                = size,
	}
}

/*
Computes per-line draw origins relative to node.rect using text-align.
*/
layout_text_position_lines :: proc(node: ^Layout_Node) {
	if len(node.text.lines) == 0 do return

	delete(node.text.line_origins)
	origins := make([]Vec2, len(node.text.lines))

	face := font_face_from_handle(node.text.font)
	lh := font_text_line_height(face, node.text.line_height, node.text.layout_scale)
	align := text_align_kind(node.config.align)
	box_w := node.rect.w

	y: f32
	for line, i in node.text.lines {
		line_w := line.width * node.text.layout_scale
		x: f32
		switch align {
		case .LEFT:
			x = 0
		case .CENTER:
			x = (box_w - line_w) * 0.5
		case .RIGHT:
			x = box_w - line_w
		}
		origins[i] = {x, y}
		y += lh
	}

	node.text.line_origins = origins
}

/*
Builds absolute glyph paint quads from shaped lines and line origins.
*/
layout_text_position_glyphs :: proc(node: ^Layout_Node) {
	delete(node.text.glyphs)
	node.text.glyphs = nil

	if len(node.text.lines) == 0 || len(node.text.line_origins) == 0 do return

	face := font_face_from_handle(node.text.font)
	if face == nil do return

	face_id := node.text.font.id
	scale := node.text.layout_scale
	glyphs: [dynamic]Layout_Glyph_Paint

	for line, i in node.text.lines {
		if len(line.glyphs) == 0 do continue
		if !font_ensure_glyphs(face, face_id, line.glyphs) do continue

		origin := node.text.line_origins[i]
		pos := Vec2{node.rect.x + origin.x, node.rect.y + origin.y}
		baseline_y := snap_logical(pos.y + face.ascent * scale)
		pen_x := pos.x
		if line.direction == .RTL {
			pen_x = pos.x + line.width * scale
		}

		for glyph in line.glyphs {
			key := Font_Glyph_Key {
				face_id  = face_id,
				glyph_id = glyph.glyph_id,
			}
			entry, ok := state.fonts.glyph_cache[key]
			if !ok do continue

			glyph_x: f32
			if line.direction == .RTL {
				pen_x -= glyph.x_advance * scale
				glyph_x = pen_x + glyph.x_offset * scale
			} else {
				glyph_x = pen_x + glyph.x_offset * scale
				pen_x += glyph.x_advance * scale
			}

			glyph_y := baseline_y + glyph.y_offset * scale - entry.bearing_y * scale
			append(
				&glyphs,
				Layout_Glyph_Paint {
					glyph_id = glyph.glyph_id,
					dst = {
						x = snap_logical(glyph_x + entry.bearing_x * scale),
						y = snap_logical(glyph_y),
						w = entry.region.w * scale,
						h = entry.region.h * scale,
					},
				},
			)
		}
	}

	if len(glyphs) == 0 {
		delete(glyphs)
		return
	}
	node.text.glyphs = glyphs[:]
}

/*
Expands one decoration stroke style into layout-owned line segments.
*/
layout_text_append_decoration_stroke :: proc(
	strokes: ^[dynamic]Layout_Decoration_Stroke,
	x0, x1, y, thickness: f32,
	style: Text_Decoration_Style_Kind,
) {
	switch style {
	case .SOLID:
		append(strokes, Layout_Decoration_Stroke{{x0, y}, {x1, y}, thickness})
	case .DOUBLE:
		gap := thickness * 1.5
		append(strokes, Layout_Decoration_Stroke{{x0, y - gap * 0.5}, {x1, y - gap * 0.5}, thickness})
		append(strokes, Layout_Decoration_Stroke{{x0, y + gap * 0.5}, {x1, y + gap * 0.5}, thickness})
	case .DOTTED:
		dot := max(thickness, 1)
		gap := dot
		x := x0
		for x < x1 {
			end := min(x + dot, x1)
			append(strokes, Layout_Decoration_Stroke{{x, y}, {end, y}, thickness})
			x += dot + gap
		}
	case .DASHED:
		dash := thickness * 3
		gap := thickness * 2
		x := x0
		for x < x1 {
			end := min(x + dash, x1)
			append(strokes, Layout_Decoration_Stroke{{x, y}, {end, y}, thickness})
			x += dash + gap
		}
	case .WAVY:
		amp := thickness
		period := max(thickness * 2.5, 4)
		x := x0
		prev := Vec2{x0, y}
		up := true
		for x < x1 {
			next_x := min(x + period * 0.5, x1)
			next_y := y + (up ? -amp : amp)
			next := Vec2{next_x, next_y}
			append(strokes, Layout_Decoration_Stroke{prev, next, thickness})
			prev = next
			x = next_x
			up = !up
		}
	}
}

/*
Builds absolute decoration stroke segments from text style and line origins.
*/
layout_text_position_decorations :: proc(node: ^Layout_Node) {
	delete(node.text.decoration_strokes)
	node.text.decoration_strokes = nil

	if len(node.text.lines) == 0 || len(node.text.line_origins) == 0 do return

	lines := text_decoration_lines(node.config.text_decoration)
	if lines == {} do return

	style := text_decoration_style_kind(node.config.text_decoration_style)
	face := font_face_from_handle(node.text.font)
	if face == nil do return

	scale := node.text.layout_scale
	strokes: [dynamic]Layout_Decoration_Stroke

	for line, i in node.text.lines {
		width := line.width * scale
		if width <= 0 do continue

		origin := node.text.line_origins[i]
		pos := Vec2{node.rect.x + origin.x, node.rect.y + origin.y}
		baseline_y := pos.y + face.ascent * scale
		thickness := max(face.underline_thickness * scale, 1)
		x0 := pos.x
		x1 := pos.x + width

		if .UNDERLINE in lines {
			y := baseline_y - face.underline_position * scale
			layout_text_append_decoration_stroke(&strokes, x0, x1, y, thickness, style)
		}
		if .LINE_THROUGH in lines {
			y := baseline_y - (face.ascent * 0.35) * scale
			layout_text_append_decoration_stroke(&strokes, x0, x1, y, thickness, style)
		}
		if .OVERLINE in lines {
			y := pos.y + thickness * 0.5
			layout_text_append_decoration_stroke(&strokes, x0, x1, y, thickness, style)
		}
	}

	if len(strokes) == 0 {
		delete(strokes)
		return
	}
	node.text.decoration_strokes = strokes[:]
}

/*
Builds or refreshes layout-owned text for the node's allocated rect.

Uses the allocated width as wrap width when the author did not set one.
Updates auto height from the shaped result and precomputes paint geometry.
*/
layout_finalize_text_node :: proc(node: ^Layout_Node) {
	if !layout_node_has_text(node) do return

	wrap_w := layout_text_resolve_wrap_w(node, node.rect.w)
	if len(node.text.lines) == 0 || node.text.wrap_w != wrap_w {
		layout_text_build(node, wrap_w)
	}

	if !length_is_definite(node.config.height) && node.text.size.y > 0 {
		node.rect.h = layout_clamp_axis(node.text.size.y, node.config.min_h, node.config.max_h)
	}

	layout_text_position_lines(node)
	layout_text_position_glyphs(node)
	layout_text_position_decorations(node)
}

/*
Attaches author image source/fit inputs for layout-owned object-fit finalization.
*/
layout_set_image :: proc(
	node: ^Layout_Node,
	src, dst: Rect,
	fit: Texture_Fit,
	pos: Resolved_Texture_Pos,
) {
	node.image_input = {src = src, dst = dst, fit = fit, pos = pos, active = true}
	node.image = {}
}

/*
Computes content/src/dst paint rects for an image node after its layout rect is set.
*/
layout_finalize_image_node :: proc(node: ^Layout_Node) {
	node.image = {}
	if !node.image_input.active do return

	content := layout_inner_rect(node.rect, node.border, node.padding)
	container := content

	props_dst := node.image_input.dst
	if props_dst.w > 0 || props_dst.h > 0 {
		container = props_dst
		if container.w == 0 do container.w = content.w
		if container.h == 0 do container.h = content.h
		if container.x == 0 && container.y == 0 {
			container.x = content.x
			container.y = content.y
		}
	}

	src := node.image_input.src
	dst := container
	src, dst = texture_fit_rects(src, container, node.image_input.fit, node.image_input.pos)

	node.image = {
		content = content,
		src     = src,
		dst     = dst,
		active  = true,
	}
}

/*
Finalizes all layout-owned paint geometry for a node after its rect is assigned.
*/
layout_finalize_node :: proc(node: ^Layout_Node) {
	layout_finalize_text_node(node)
	layout_finalize_image_node(node)
}

/*
Returns layout-owned text for a UI id after the layout pass.
*/
layout_text_result :: proc(id: UI_Id) -> ^Layout_Text {
	if node_index, ok := state.ui.layout.id_to_node[id]; ok {
		node := &state.ui.layout.nodes[node_index]
		if len(node.text.lines) > 0 do return &node.text
	}
	return nil
}

/*
Returns layout-owned image paint geometry for a UI id after the layout pass.
*/
layout_image_result :: proc(id: UI_Id) -> ^Layout_Image {
	if node_index, ok := state.ui.layout.id_to_node[id]; ok {
		node := &state.ui.layout.nodes[node_index]
		if node.image.active do return &node.image
	}
	return nil
}

/*
Returns layout-owned collapsed border geometry for a UI id after the layout pass.
*/
layout_collapsed_borders_result :: proc(id: UI_Id) -> ^Layout_Collapsed_Borders {
	if node_index, ok := state.ui.layout.id_to_node[id]; ok {
		node := &state.ui.layout.nodes[node_index]
		if node.collapsed_borders.active do return &node.collapsed_borders
	}
	return nil
}

/*
Measures a leaf node's size from text or explicit dimensions.
*/
layout_measure_leaf :: proc(node: ^Layout_Node) -> Vec2 {
	config := node.config
	size: Vec2

	if layout_node_has_text(node) {
		available_w := ui_style_current().content_w
		wrap_w := layout_text_resolve_wrap_w(node, available_w)
		layout_text_build(node, wrap_w)
		size = node.text.size
	} else {
		width := length_resolve(node.config.width, 0)
		height := length_resolve(node.config.height, 0)
		if width <= 0 do width = node.desired.x
		if height <= 0 do height = node.desired.y
		if width <= 0 do width = config.min_w
		if height <= 0 do height = config.min_h
		size = {
			layout_clamp_axis(width, config.min_w, config.max_w),
			layout_clamp_axis(height, config.min_h, config.max_h),
		}
	}

	if length_is_definite(node.config.width) {
		if width := length_resolve(node.config.width, 0); width > 0 {
			size.x = layout_clamp_axis(width, config.min_w, config.max_w)
		}
	}
	if length_is_definite(node.config.height) {
		if height := length_resolve(node.config.height, 0); height > 0 {
			size.y = layout_clamp_axis(height, config.min_h, config.max_h)
		}
	}

	return size
}

/*
Measures a node's desired size from children or leaf content.
*/
layout_measure :: proc(node: ^Layout_Node) -> Vec2 {
	padding := node.padding
	border := node.border
	direction := layout_config_direction(node.config)
	info := layout_direction_info(direction)
	gap_main := layout_config_gap_main(node.config, info.is_horizontal)
	gap_cross := layout_config_gap_cross(node.config, info.is_horizontal)

	if len(node.child_indices) > 0 {

		if info.is_wrap {
			return layout_wrap_measure(node, info.is_horizontal, gap_main, gap_cross)
		}

		child_sizes: [dynamic]Vec2
		child_nodes: [dynamic]^Layout_Node
		defer delete(child_sizes)
		defer delete(child_nodes)

		for child_index in node.child_indices {
			child := &state.ui.layout.nodes[child_index]
			append(&child_nodes, child)
			append(&child_sizes, child.desired)
		}

		justify := layout_config_justify(node.config)
		layout_apply_content_align_sizes(justify, child_nodes[:], child_sizes[:])

		main_sum: f32
		cross_max: f32
		for child, i in child_nodes {
			child_main := info.is_horizontal ? child.config.width : child.config.height
			if child.config.flex > 0 && !length_is_definite(child_main) do continue

			if info.is_horizontal {
				main_sum += child_sizes[i].x
				cross_max = max(cross_max, child_sizes[i].y)
			} else {
				main_sum += child_sizes[i].y
				cross_max = max(cross_max, child_sizes[i].x)
			}
		}

		if len(node.child_indices) > 1 {
			main_sum += gap_main * f32(len(node.child_indices) - 1)
		}

		inset_w := padding.l + padding.r + border.l + border.r
		inset_h := padding.t + padding.b + border.t + border.b

		if info.is_horizontal {
			width := length_resolve(node.config.width, 0)
			height := length_resolve(node.config.height, 0)
			if width <= 0 do width = main_sum + inset_w
			if height <= 0 do height = cross_max + inset_h
			return {
				layout_clamp_axis(width, node.config.min_w, node.config.max_w),
				layout_clamp_axis(height, node.config.min_h, node.config.max_h),
			}
		} else {
			width := length_resolve(node.config.width, 0)
			height := length_resolve(node.config.height, 0)
			if width <= 0 do width = cross_max + inset_w
			if height <= 0 do height = main_sum + inset_h
			return {
				layout_clamp_axis(width, node.config.min_w, node.config.max_w),
				layout_clamp_axis(height, node.config.min_h, node.config.max_h),
			}
		}
	}

	return layout_measure_leaf(node)
}

/*
Creates a layout node, links it to the parent, and pushes it on the stack.
*/
layout_push_node :: proc(ui_id: UI_Id, config: Resolved_Widget_Config) -> ^Layout_Node {
	parent_index := -1
	if len(state.ui.layout.node_stack) > 0 {
		parent_index = state.ui.layout.node_stack[len(state.ui.layout.node_stack) - 1]
	}

	padding, _ := resolve_padding_value(config.padding)
	border, _ := resolve_border_value(config.border)

	node := Layout_Node {
		ui_id   = ui_id,
		kind    = config.kind,
		config  = config.style,
		padding = padding,
		border  = border,
		parent  = parent_index,
	}
	append(&state.ui.layout.nodes, node)
	node_index := len(state.ui.layout.nodes) - 1

	if layout_node_is_table_cell(config.kind) {
		table_index := layout_find_table_ancestor_in(&state.ui.layout, node_index)
		if table_index >= 0 {
			table := &state.ui.layout.nodes[table_index]
			if mode, ok := state.ui.layout.table_border_collapse[table.ui_id]; ok &&
			   mode == .COLLAPSE {
				node.border = {}
			}
		}
	}

	if parent_index >= 0 {
		append(&state.ui.layout.nodes[parent_index].child_indices, node_index)
	}

	append(&state.ui.layout.node_stack, node_index)
	state.ui.layout.id_to_node[ui_id] = node_index
	return &state.ui.layout.nodes[node_index]
}

/*
Attaches author text and optional max-width hint for layout-owned shaping.
*/
layout_set_measure_text :: proc(node: ^Layout_Node, text: string, max_w: f32) {
	node.measure.text = text
	node.measure.max_w = max_w
}

/*
Sets an explicit desired size on a layout node.
*/
layout_set_measure_size :: proc(node: ^Layout_Node, size: Vec2) {
	node.desired = size
}

/*
Pops the current node from the stack and stores its measured size.
*/
layout_pop_node :: proc() {
	if len(state.ui.layout.node_stack) == 0 do return

	node_index := state.ui.layout.node_stack[len(state.ui.layout.node_stack) - 1]
	ordered_remove(&state.ui.layout.node_stack, len(state.ui.layout.node_stack) - 1)

	node := &state.ui.layout.nodes[node_index]
	node.desired = layout_measure(node)
}

/*
Resolves final width and height for a node within bounds.
*/
layout_resolve_node_size :: proc(node: ^Layout_Node, bounds: Rect) -> Vec2 {
	desired := node.desired

	width := length_resolve(node.config.width, bounds.w)
	height := length_resolve(node.config.height, bounds.h)
	if width <= 0 do width = desired.x
	if height <= 0 do height = desired.y

	if width <= 0 && bounds.w > 0 do width = bounds.w
	if height <= 0 && bounds.h > 0 do height = bounds.h

	return {
		layout_clamp_axis(width, node.config.min_w, node.config.max_w),
		layout_clamp_axis(height, node.config.min_h, node.config.max_h),
	}
}

/*
Overwrites size axes that have definite length constraints.
*/
layout_apply_definite_size :: proc(node: ^Layout_Node, bounds: Rect, size: ^Vec2) {
	resolved := layout_resolve_node_size(node, bounds)
	if length_is_definite(node.config.width) do size.x = resolved.x
	if length_is_definite(node.config.height) do size.y = resolved.y
}

/*
Computes a child's main-axis size including flex distribution.
*/
layout_child_main_size :: proc(
	child: ^Layout_Node,
	is_horizontal: bool,
	flex_unit: f32,
	parent_main: f32,
) -> f32 {
	main_len := is_horizontal ? child.config.width : child.config.height
	main_fixed := length_resolve(main_len, parent_main)
	if main_fixed > 0 do return main_fixed

	if child.config.flex > 0 && flex_unit > 0 {
		desired_main := is_horizontal ? child.desired.x : child.desired.y
		return max(desired_main, flex_unit * child.config.flex)
	}

	return is_horizontal ? child.desired.x : child.desired.y
}

/*
Returns whether a child participates in main-axis flow layout.
*/
layout_child_in_main_flow :: proc(child: ^Layout_Node, is_horizontal: bool) -> bool {
	self := child.config.self
	if is_horizontal {
		_, ok := resolve_justify_x(self.x)
		return !ok
	}
	_, ok := resolve_justify_y(self.y)
	return !ok
}

/*
Computes a child's cross-axis size including stretch alignment.
*/
layout_child_cross_size :: proc(
	child: ^Layout_Node,
	is_horizontal: bool,
	cross_available: f32,
	justify: Justify_Pos,
) -> f32 {
	cross_len := is_horizontal ? child.config.height : child.config.width
	cross_fixed := length_resolve(cross_len, cross_available)
	if cross_fixed > 0 do return cross_fixed

	self := child.config.self
	cross_stretch := child.config.flex > 0
	if is_horizontal {
		if _, y_ok := resolve_justify_y(self.y); y_ok {
			cross_stretch ||= justify_axis_is_stretch_y(self.y)
		} else {
			cross_stretch ||= justify_axis_is_stretch_y(justify.y)
		}
	} else {
		if _, x_ok := resolve_justify_x(self.x); x_ok {
			cross_stretch ||= justify_axis_is_stretch_x(self.x)
		} else {
			cross_stretch ||= justify_axis_is_stretch_x(justify.x)
		}
	}

	if cross_stretch && cross_available > 0 {
		return cross_available
	}

	return is_horizontal ? child.desired.y : child.desired.x
}

/*
Returns the layout node index for a node pointer in a layout tree.
*/
layout_node_index_in :: proc(layout: ^Layout_State, node: ^Layout_Node) -> int {
	for &n, i in layout.nodes {
		if &n == node do return i
	}
	return -1
}

/*
Returns the layout node index for a node pointer in the current layout tree.
*/
layout_node_index :: proc(node: ^Layout_Node) -> int {
	return layout_node_index_in(&state.ui.layout, node)
}

/*
Walks ancestors to find the nearest TABLE layout node index.
*/
layout_find_table_ancestor_in :: proc(layout: ^Layout_State, node_index: int) -> int {
	parent := node_index
	for parent >= 0 {
		node := &layout.nodes[parent]
		if node.kind == .TABLE do return parent
		parent = node.parent
	}
	return -1
}

/*
Walks ancestors to find the nearest TABLE layout node index.
*/
layout_find_table_ancestor :: proc(node_index: int) -> int {
	return layout_find_table_ancestor_in(&state.ui.layout, node_index)
}

/*
Returns whether a widget kind represents a table data cell.
*/
layout_node_is_table_cell :: proc(kind: Widget_Kind) -> bool {
	return kind == .TABLE_CELL || kind == .TABLE_HEADING
}

/*
Returns whether a justify position uses TABLE_CELL on the x axis.
*/
layout_justify_uses_TABLE_CELL_x :: proc(justify: Justify_Pos) -> bool {
	align, ok := justify_align_from_x(justify.x)
	return ok && align == .TABLE_CELL
}

/*
Returns whether a justify position uses TABLE_CELL on the y axis.
*/
layout_justify_uses_TABLE_CELL_y :: proc(justify: Justify_Pos) -> bool {
	align, ok := justify_align_from_y(justify.y)
	return ok && align == .TABLE_CELL
}

/*
Returns a cell's intrinsic size along one axis for table track sizing.
*/
layout_table_cell_intrinsic_axis :: proc(cell: ^Layout_Node, horizontal: bool) -> f32 {
	if horizontal {
		if length_is_definite(cell.config.width) {
			return length_resolve(cell.config.width, 0)
		}
		return cell.desired.x
	}
	if length_is_definite(cell.config.height) {
		return length_resolve(cell.config.height, 0)
	}
	return cell.desired.y
}

/*
Collects TABLE_ROW node indices under a table in document order.
*/
layout_table_collect_rows_in :: proc(layout: ^Layout_State, table_index: int) -> [dynamic]int {
	rows: [dynamic]int
	stack: [dynamic]int
	defer delete(stack)

	table := &layout.nodes[table_index]
	for i := len(table.child_indices) - 1; i >= 0; i -= 1 {
		append(&stack, table.child_indices[i])
	}

	for len(stack) > 0 {
		idx := stack[len(stack) - 1]
		ordered_remove(&stack, len(stack) - 1)
		node := &layout.nodes[idx]

		if node.kind == .TABLE_ROW {
			append(&rows, idx)
		}

		for i := len(node.child_indices) - 1; i >= 0; i -= 1 {
			append(&stack, node.child_indices[i])
		}
	}

	return rows
}

/*
Finds a row's index inside prepared table track data.
*/
layout_table_row_track_index :: proc(tracks: ^Layout_Table_Tracks, row_index: int) -> (int, bool) {
	for row_node_index, track_i in tracks.rows {
		if row_node_index == row_index do return track_i, true
	}
	return 0, false
}

/*
Computes shared column widths and row heights for a table with TABLE_CELL rows.
*/
layout_table_prepare_in :: proc(layout: ^Layout_State, table_index: int) {
	table := &layout.nodes[table_index]
	if table.kind != .TABLE do return

	rows := layout_table_collect_rows_in(layout, table_index)
	if len(rows) == 0 {
		delete(rows)
		return
	}

	uses_x := false
	uses_y := false
	for row_index in rows {
		row := &layout.nodes[row_index]
		uses_x ||= layout_justify_uses_TABLE_CELL_x(row.config.justify)
		uses_y ||= layout_justify_uses_TABLE_CELL_y(row.config.justify)
	}
	if !uses_x && !uses_y {
		delete(rows)
		return
	}

	col_count := 0
	for row_index in rows {
		row := &layout.nodes[row_index]
		col_count = max(col_count, len(row.child_indices))
	}

	col_widths: [dynamic]f32
	row_heights: [dynamic]f32
	resize(&col_widths, col_count)
	resize(&row_heights, len(rows))

	if uses_x {
		for col in 0 ..< col_count {
			max_w: f32
			for row_index in rows {
				row := &layout.nodes[row_index]
				if col >= len(row.child_indices) do continue
				child := &layout.nodes[row.child_indices[col]]
				if !layout_node_is_table_cell(child.kind) do continue
				max_w = max(max_w, layout_table_cell_intrinsic_axis(child, true))
			}
			col_widths[col] = max_w
		}
	}

	if uses_y {
		for row_node_index, track_i in rows {
			row := &layout.nodes[row_node_index]
			if !layout_justify_uses_TABLE_CELL_y(row.config.justify) do continue

			max_h: f32
			for child_idx in row.child_indices {
				child := &layout.nodes[child_idx]
				if !layout_node_is_table_cell(child.kind) do continue
				max_h = max(max_h, layout_table_cell_intrinsic_axis(child, false))
			}
			row_heights[track_i] = max_h
		}
	}

	if existing, ok := &layout.table_tracks[table_index]; ok {
		delete(existing.rows)
		delete(existing.col_widths)
		delete(existing.row_heights)
		delete(existing.cell_positions)
	}

	border_collapse := layout.table_border_collapse[table.ui_id]
	if border_collapse == {} do border_collapse = .SEPERATE

	layout.table_tracks[table_index] = Layout_Table_Tracks {
		rows            = rows,
		col_widths      = col_widths,
		row_heights     = row_heights,
		border_collapse = border_collapse,
		cell_positions  = make(map[int]Table_Grid_Pos),
	}
}

/*
Computes shared column widths and row heights for a table with TABLE_CELL rows.
*/
layout_table_prepare :: proc(table_index: int) {
	layout_table_prepare_in(&state.ui.layout, table_index)
}

/*
Applies prepared table track sizes to a cell when its row uses TABLE_CELL.
*/
layout_table_apply_cell_size :: proc(
	row: ^Layout_Node,
	tracks: ^Layout_Table_Tracks,
	row_track_index: int,
	col_index: int,
	child: ^Layout_Node,
	content: Rect,
) -> Vec2 {
	size := child.desired
	use_x := layout_justify_uses_TABLE_CELL_x(row.config.justify)
	use_y := layout_justify_uses_TABLE_CELL_y(row.config.justify)

	if use_x && col_index < len(tracks.col_widths) && !length_is_definite(child.config.width) {
		size.x = tracks.col_widths[col_index]
	}
	if use_y && !length_is_definite(child.config.height) {
		size.y = tracks.row_heights[row_track_index]
	}

	layout_apply_definite_size(child, content, &size)
	return size
}

/*
Registers a table's border-collapse mode for the current layout pass.
*/
layout_table_register_border_collapse :: proc(ui_id: UI_Id, mode: Border_Collapse) {
	state.ui.layout.table_border_collapse[ui_id] = mode
}

/*
Builds the table cell grid after rows and cells have been positioned.

Also resolves collapsed border winners and paint strip rects for each cell.
*/
layout_table_finalize_in :: proc(layout: ^Layout_State, table_index: int) {
	table := &layout.nodes[table_index]
	if table.kind != .TABLE do return

	tracks, tracks_ok := layout.table_tracks[table_index]
	if !tracks_ok do return

	for track_i in 0 ..< len(tracks.rows) {
		row_node_index := tracks.rows[track_i]
		row := &layout.nodes[row_node_index]
		col := 0
		for child_index in row.child_indices {
			child := &layout.nodes[child_index]
			if !layout_node_is_table_cell(child.kind) do continue
			tracks.cell_positions[child_index] = Table_Grid_Pos {
				row = track_i,
				col = col,
			}
			col += 1
		}
	}

	if tracks.border_collapse == .COLLAPSE {
		for row_node_index in tracks.rows {
			row := &layout.nodes[row_node_index]
			for child_index in row.child_indices {
				child := &layout.nodes[child_index]
				if !layout_node_is_table_cell(child.kind) do continue
				child.border = {}
			}
		}

		for row_node_index in tracks.rows {
			row := &layout.nodes[row_node_index]
			for child_index in row.child_indices {
				child := &layout.nodes[child_index]
				if !layout_node_is_table_cell(child.kind) do continue
				child.collapsed_borders = table_layout_resolve_collapsed_borders(
					layout,
					&tracks,
					child_index,
				)
			}
		}
	}

	layout.table_tracks[table_index] = tracks
}

layout_table_finalize :: proc(table_index: int) {
	layout_table_finalize_in(&state.ui.layout, table_index)
}

/*
Extracts the main-axis justify align from a justify position.
*/
layout_main_justify_align :: proc(
	justify: Justify_Pos,
	is_horizontal: bool,
) -> (
	Justify_Align,
	bool,
) {
	if is_horizontal {
		return justify_align_from_x(justify.x)
	}
	return justify_align_from_y(justify.y)
}

/*
Extracts the cross-axis justify align from a justify position.
*/
layout_cross_justify_align :: proc(
	justify: Justify_Pos,
	is_horizontal: bool,
) -> (
	Justify_Align,
	bool,
) {
	if is_horizontal {
		return justify_align_from_y(justify.y)
	}
	return justify_align_from_x(justify.x)
}

/*
Computes leading inset for space-distribution justify modes.
*/
layout_space_leading :: proc(align: Justify_Align, free: f32, count: int) -> f32 {
	if count <= 0 do return 0

	#partial switch align {
	case .SPACE_BETWEEN:
		return 0
	case .SPACE_AROUND:
		return free / (2 * f32(count))
	case .SPACE_EVENLY:
		return free / f32(count + 1)
	}
	return 0
}

/*
Computes gap between items for space-distribution justify modes.
*/
/*
Returns the target size for a content-align mode from sibling extrema.
*/
layout_content_align_target :: proc(align: Justify_Align, max_v, min_v: f32) -> (f32, bool) {
	#partial switch align {
	case .MAX_CONTENT:
		return max_v, true
	case .MIN_CONTENT:
		return min_v, true
	}
	return 0, false
}

/*
Computes max and min values from a list of sibling axis sizes.
*/
layout_sibling_axis_extrema :: proc(sizes: []f32) -> (max_v, min_v: f32, ok: bool) {
	if len(sizes) == 0 do return 0, 0, false

	max_v = sizes[0]
	min_v = sizes[0]
	for size in sizes[1:] {
		max_v = max(max_v, size)
		min_v = min(min_v, size)
	}
	return max_v, min_v, true
}

/*
Applies a content-align mode to one axis size using sibling extrema.
*/
layout_apply_content_align_axis :: proc(align: Justify_Align, current, max_v, min_v: f32) -> f32 {
	if target, ok := layout_content_align_target(align, max_v, min_v); ok {
		return target
	}
	return current
}

/*
Equalizes one axis of child sizes to sibling max/min when parent justify requests it.

Children with definite width or height keep their provided size but still
participate in sibling extrema.
*/
layout_apply_content_align_sizes_indices :: proc(
	justify: Justify_Pos,
	children: []^Layout_Node,
	child_sizes: []Vec2,
	indices: []int,
) {
	if len(indices) == 0 do return

	if align, ok := justify_align_from_x(justify.x); ok && justify_align_is_content(align) {
		sizes: [dynamic]f32
		defer delete(sizes)
		for idx in indices {
			append(&sizes, child_sizes[idx].x)
		}

		max_v, min_v, extrema_ok := layout_sibling_axis_extrema(sizes[:])
		if extrema_ok {
			for idx in indices {
				child := children[idx]
				if length_is_definite(child.config.width) do continue
				child_sizes[idx].x = layout_apply_content_align_axis(
					align,
					child_sizes[idx].x,
					max_v,
					min_v,
				)
			}
		}
	}

	if align, ok := justify_align_from_y(justify.y); ok && justify_align_is_content(align) {
		sizes: [dynamic]f32
		defer delete(sizes)
		for idx in indices {
			append(&sizes, child_sizes[idx].y)
		}

		max_v, min_v, extrema_ok := layout_sibling_axis_extrema(sizes[:])
		if extrema_ok {
			for idx in indices {
				child := children[idx]
				if length_is_definite(child.config.height) do continue
				child_sizes[idx].y = layout_apply_content_align_axis(
					align,
					child_sizes[idx].y,
					max_v,
					min_v,
				)
			}
		}
	}
}

/*
Equalizes child sizes for all children in a container.
*/
layout_apply_content_align_sizes :: proc(
	justify: Justify_Pos,
	children: []^Layout_Node,
	child_sizes: []Vec2,
) {
	indices: [dynamic]int
	defer delete(indices)
	resize(&indices, len(children))
	for i in 0 ..< len(children) {
		indices[i] = i
	}
	layout_apply_content_align_sizes_indices(justify, children, child_sizes, indices[:])
}

layout_space_between_items :: proc(align: Justify_Align, free: f32, count: int) -> f32 {
	if count <= 1 do return 0

	#partial switch align {
	case .SPACE_BETWEEN:
		return free / f32(count - 1)
	case .SPACE_AROUND:
		return free / f32(count)
	case .SPACE_EVENLY:
		return free / f32(count + 1)
	}
	return 0
}

/*
Computes main-axis positions for space-distribution alignment.
*/
layout_space_positions :: proc(
	align: Justify_Align,
	available: f32,
	sizes: []f32,
	gap: f32,
) -> [dynamic]f32 {
	positions: [dynamic]f32
	count := len(sizes)
	if count == 0 do return positions

	total: f32
	for size in sizes do total += size
	if count > 1 do total += gap * f32(count - 1)

	free := max(0, available - total)
	leading := layout_space_leading(align, free, count)
	between := layout_space_between_items(align, free, count)

	cursor := leading
	for i in 0 ..< count {
		append(&positions, cursor)
		if i + 1 < count {
			cursor += sizes[i] + gap + between
		}
	}

	return positions
}

/*
Positions one child rect and recursively lays out its descendants.
*/
layout_position_child_rect :: proc(
	child: ^Layout_Node,
	content: Rect,
	size: Vec2,
	main_pos: f32,
	cross_pos: f32,
	is_horizontal: bool,
	justify: Justify_Pos,
	in_flow_main: bool,
	in_flow_cross: bool,
) {
	child_justify := layout_merge_justify(justify, child.config.self)
	self := child.config.self
	_, self_x_ok := resolve_justify_x(self.x)
	_, self_y_ok := resolve_justify_y(self.y)

	x, y: f32
	if self_x_ok {
		x = content.x + justify_align_position_offset_x(content.w, size.x, self.x)
	} else if is_horizontal {
		if in_flow_main {
			x = content.x + main_pos
		} else {
			x = content.x + justify_align_position_offset_x(content.w, size.x, child_justify.x)
		}
	} else if in_flow_cross {
		x = content.x + cross_pos
	} else {
		x = content.x + justify_align_position_offset_x(content.w, size.x, child_justify.x)
	}

	if self_y_ok {
		y = content.y + justify_align_position_offset_y(content.h, size.y, self.y)
	} else if is_horizontal {
		if in_flow_cross {
			y = content.y + cross_pos
		} else {
			y = content.y + justify_align_position_offset_y(content.h, size.y, child_justify.y)
		}
	} else if in_flow_main {
		y = content.y + main_pos
	} else {
		y = content.y + justify_align_position_offset_y(content.h, size.y, child_justify.y)
	}

	x += child.config.x
	y += child.config.y

	child.rect = {
		x = x,
		y = y,
		w = size.x,
		h = size.y,
	}
	layout_finalize_node(child)

	if len(child.child_indices) > 0 {
		layout_position_children(child, layout_inner_rect(child.rect, child.border, child.padding))
	}
}

/*
Positions children in a wrap flex container.
*/
layout_position_children_wrap :: proc(
	node: ^Layout_Node,
	content: Rect,
	info: Layout_Direction_Info,
) {
	is_horizontal := info.is_horizontal
	gap_main := layout_config_gap_main(node.config, is_horizontal)
	gap_cross := layout_config_gap_cross(node.config, is_horizontal)
	justify := layout_config_justify(node.config)

	main_available := is_horizontal ? content.w : content.h
	cross_available := is_horizontal ? content.h : content.w
	main_limit := main_available

	child_sizes: [dynamic]Vec2
	defer delete(child_sizes)
	resize(&child_sizes, len(node.child_indices))

	for child_index, i in node.child_indices {
		child := &state.ui.layout.nodes[child_index]
		child_justify := layout_merge_justify(justify, child.config.self)
		main := layout_child_main_size(child, is_horizontal, 0, main_available)
		cross := layout_child_cross_size(child, is_horizontal, 0, child_justify)
		child_sizes[i] = is_horizontal ? Vec2{main, cross} : Vec2{cross, main}
		layout_apply_definite_size(child, content, &child_sizes[i])
	}

	lines := layout_wrap_build_lines(child_sizes[:], is_horizontal, gap_main, main_limit)
	defer delete(lines)

	line_cross_sizes: [dynamic]f32
	defer delete(line_cross_sizes)
	resize(&line_cross_sizes, len(lines))

	for line, line_index in lines {
		line_main_available := main_limit > 0 ? main_limit : line.main_sum

		flex_total: f32
		fixed_total: f32
		for i in 0 ..< line.count {
			child := &state.ui.layout.nodes[node.child_indices[line.start + i]]
			child_main := is_horizontal ? child.config.width : child.config.height
			if child.config.flex > 0 && !length_is_definite(child_main) {
				flex_total += child.config.flex
			} else {
				fixed_total += layout_wrap_child_main(child_sizes[line.start + i], is_horizontal)
			}
		}
		if line.count > 1 do fixed_total += gap_main * f32(line.count - 1)

		remaining := max(0, line_main_available - fixed_total)
		flex_unit := flex_total > 0 ? remaining / flex_total : 0

		line_cross_natural: f32
		for i in 0 ..< line.count {
			child_index := node.child_indices[line.start + i]
			child := &state.ui.layout.nodes[child_index]
			child_justify := layout_merge_justify(justify, child.config.self)
			main := layout_child_main_size(child, is_horizontal, flex_unit, line_main_available)
			cross := layout_child_cross_size(child, is_horizontal, 0, child_justify)
			size := is_horizontal ? Vec2{main, cross} : Vec2{cross, main}
			layout_apply_definite_size(child, content, &size)
			line_cross_natural = max(
				line_cross_natural,
				layout_wrap_child_cross(size, is_horizontal),
			)
		}

		for i in 0 ..< line.count {
			size_index := line.start + i
			child_index := node.child_indices[size_index]
			child := &state.ui.layout.nodes[child_index]
			child_justify := layout_merge_justify(justify, child.config.self)
			main := layout_child_main_size(child, is_horizontal, flex_unit, line_main_available)
			cross := layout_child_cross_size(
				child,
				is_horizontal,
				line_cross_natural,
				child_justify,
			)
			child_sizes[size_index] = is_horizontal ? Vec2{main, cross} : Vec2{cross, main}
			layout_apply_definite_size(child, content, &child_sizes[size_index])
		}

		line_indices: [dynamic]int
		defer delete(line_indices)
		line_children: [dynamic]^Layout_Node
		defer delete(line_children)
		for i in 0 ..< line.count {
			size_index := line.start + i
			append(&line_indices, size_index)
			append(&line_children, &state.ui.layout.nodes[node.child_indices[size_index]])
		}
		layout_apply_content_align_sizes_indices(
			justify,
			line_children[:],
			child_sizes[:],
			line_indices[:],
		)

		line_cross := line_cross_natural
		for idx in line_indices {
			line_cross = max(line_cross, layout_wrap_child_cross(child_sizes[idx], is_horizontal))
		}
		line_cross_sizes[line_index] = line_cross
	}

	total_cross: f32
	for line_cross, i in line_cross_sizes {
		total_cross += line_cross
		if i + 1 < len(line_cross_sizes) do total_cross += gap_cross
	}

	cross_align, cross_align_ok := layout_cross_justify_align(justify, is_horizontal)
	cross_start: f32
	if cross_align_ok {
		cross_start = justify_align_position_offset(cross_available, total_cross, cross_align)
	}

	main_align, main_align_ok := layout_main_justify_align(justify, is_horizontal)
	main_space := main_align_ok && justify_align_is_space(main_align)

	line_cross_cursor := cross_start
	for line, line_index in lines {
		line_main_available := main_limit > 0 ? main_limit : line.main_sum
		line_cross := line_cross_sizes[line_index]

		in_flow: [dynamic]int
		defer delete(in_flow)
		for i in 0 ..< line.count {
			child := &state.ui.layout.nodes[node.child_indices[line.start + i]]
			if layout_child_in_main_flow(child, is_horizontal) {
				append(&in_flow, line.start + i)
			}
		}

		main_positions: [dynamic]f32
		defer delete(main_positions)
		if main_space && len(in_flow) > 0 {
			main_sizes: [dynamic]f32
			defer delete(main_sizes)
			for idx in in_flow {
				append(&main_sizes, layout_wrap_child_main(child_sizes[idx], is_horizontal))
			}
			main_positions = layout_space_positions(
				main_align,
				line_main_available,
				main_sizes[:],
				gap_main,
			)
		}

		main_start: f32
		if !main_space {
			total_main: f32
			for idx in in_flow {
				total_main += layout_wrap_child_main(child_sizes[idx], is_horizontal)
			}
			if len(in_flow) > 1 do total_main += gap_main * f32(len(in_flow) - 1)
			if main_align_ok {
				main_start = justify_align_position_offset(
					line_main_available,
					total_main,
					main_align,
				)
			}
		}

		main_cursor := main_start
		flow_index := 0
		for i in 0 ..< line.count {
			size_index := line.start + i
			child_index := node.child_indices[size_index]
			child := &state.ui.layout.nodes[child_index]
			size := child_sizes[size_index]
			main := layout_wrap_child_main(size, is_horizontal)
			in_flow_child := layout_child_in_main_flow(child, is_horizontal)

			main_pos: f32
			if in_flow_child && main_space {
				main_pos = main_positions[flow_index]
			} else if in_flow_child {
				main_pos = main_cursor
			}
			if info.is_main_reverse && in_flow_child {
				main_pos = layout_mirror_in_available(main_pos, main, line_main_available)
			}

			cross_pos := line_cross_cursor
			if info.is_cross_reverse {
				cross_pos = layout_mirror_in_available(
					line_cross_cursor,
					line_cross,
					cross_available,
				)
			}
			child_justify := layout_merge_justify(justify, child.config.self)
			self := child.config.self
			_, self_x_ok := resolve_justify_x(self.x)
			_, self_y_ok := resolve_justify_y(self.y)
			in_flow_cross := is_horizontal ? !self_y_ok : !self_x_ok

			if is_horizontal {
				if in_flow_cross {
					cross_pos += justify_align_position_offset_y(
						line_cross,
						size.y,
						child_justify.y,
					)
				}
			} else if in_flow_cross {
				cross_pos += justify_align_position_offset_x(line_cross, size.x, child_justify.x)
			}

			layout_position_child_rect(
				child,
				content,
				size,
				main_pos,
				cross_pos,
				is_horizontal,
				justify,
				in_flow_child,
				in_flow_cross,
			)

			if in_flow_child {
				if !main_space {
					main_cursor += main
					if i + 1 < line.count {
						next_child := &state.ui.layout.nodes[node.child_indices[line.start + i + 1]]
						if layout_child_in_main_flow(next_child, is_horizontal) {
							main_cursor += gap_main
						}
					}
				}
				flow_index += 1
			}
		}

		line_cross_cursor += line_cross
		if line_index + 1 < len(lines) do line_cross_cursor += gap_cross
	}
}

/*
Expands a wrap parent's cross size to fit wrapped children.
*/
layout_wrap_apply_auto_cross_size :: proc(node: ^Layout_Node, is_horizontal: bool) {
	cross_len := is_horizontal ? node.config.height : node.config.width
	if length_is_definite(cross_len) do return

	far_edge := node.rect.y if is_horizontal else node.rect.x
	for child_index in node.child_indices {
		child := &state.ui.layout.nodes[child_index]
		if is_horizontal {
			far_edge = max(far_edge, child.rect.y + child.rect.h)
		} else {
			far_edge = max(far_edge, child.rect.x + child.rect.w)
		}
	}

	if is_horizontal {
		inset_b := node.padding.b + node.border.b
		node.rect.h = max(node.rect.h, far_edge - node.rect.y + inset_b)
	} else {
		inset_r := node.padding.r + node.border.r
		node.rect.w = max(node.rect.w, far_edge - node.rect.x + inset_r)
	}
}

/*
Positions children in a non-wrap flex container.
*/
layout_position_children :: proc(node: ^Layout_Node, content: Rect) {
	if len(node.child_indices) == 0 do return

	if node.kind == .TABLE {
		layout_table_prepare(layout_node_index(node))
	}

	direction := layout_config_direction(node.config)
	info := layout_direction_info(direction)
	if info.is_wrap {
		layout_position_children_wrap(node, content, info)
		return
	}

	is_horizontal := info.is_horizontal
	gap_main := layout_config_gap_main(node.config, is_horizontal)
	justify := layout_config_justify(node.config)

	main_available := is_horizontal ? content.w : content.h
	cross_available := is_horizontal ? content.h : content.w

	flex_total: f32
	fixed_total: f32

	child_sizes: [dynamic]Vec2
	defer delete(child_sizes)
	resize(&child_sizes, len(node.child_indices))

	for child_index in node.child_indices {
		child := &state.ui.layout.nodes[child_index]
		child_main := is_horizontal ? child.config.width : child.config.height

		if child.config.flex > 0 && !length_is_definite(child_main) {
			flex_total += child.config.flex
		} else {
			main := layout_child_main_size(child, is_horizontal, 0, main_available)
			fixed_total += main
		}
	}

	if len(node.child_indices) > 1 {
		fixed_total += gap_main * f32(len(node.child_indices) - 1)
	}

	remaining := max(0, main_available - fixed_total)
	flex_unit := flex_total > 0 ? remaining / flex_total : 0

	table_index := -1
	row_track_index := -1
	tracks: ^Layout_Table_Tracks = nil
	if node.kind == .TABLE_ROW {
		node_index := layout_node_index(node)
		table_index = layout_find_table_ancestor(node_index)
		if table_index >= 0 {
			if track_data, ok := &state.ui.layout.table_tracks[table_index]; ok {
				tracks = track_data
				row_track_index, _ = layout_table_row_track_index(tracks, node_index)
			}
		}
	}

	for child_index, i in node.child_indices {
		child := &state.ui.layout.nodes[child_index]
		if tracks != nil && row_track_index >= 0 && layout_node_is_table_cell(child.kind) {
			child_sizes[i] = layout_table_apply_cell_size(
				node,
				tracks,
				row_track_index,
				i,
				child,
				content,
			)
			continue
		}

		child_justify := layout_merge_justify(justify, child.config.self)
		main := layout_child_main_size(child, is_horizontal, flex_unit, main_available)
		cross := layout_child_cross_size(child, is_horizontal, cross_available, child_justify)
		child_sizes[i] = is_horizontal ? Vec2{main, cross} : Vec2{cross, main}
		layout_apply_definite_size(child, content, &child_sizes[i])
	}

	child_nodes: [dynamic]^Layout_Node
	defer delete(child_nodes)
	resize(&child_nodes, len(node.child_indices))
	for child_index, i in node.child_indices {
		child_nodes[i] = &state.ui.layout.nodes[child_index]
	}
	layout_apply_content_align_sizes(justify, child_nodes[:], child_sizes[:])

	in_flow: [dynamic]int
	defer delete(in_flow)
	for child_index, i in node.child_indices {
		child := &state.ui.layout.nodes[child_index]
		if layout_child_in_main_flow(child, is_horizontal) {
			append(&in_flow, i)
		}
	}

	main_align, main_align_ok := layout_main_justify_align(justify, is_horizontal)
	main_space := main_align_ok && justify_align_is_space(main_align)

	cross_align, cross_align_ok := layout_cross_justify_align(justify, is_horizontal)
	cross_space := cross_align_ok && justify_align_is_space(cross_align)

	main_positions: [dynamic]f32
	defer delete(main_positions)
	if main_space && len(in_flow) > 0 {
		main_sizes: [dynamic]f32
		defer delete(main_sizes)
		for idx in in_flow {
			size := child_sizes[idx]
			append(&main_sizes, is_horizontal ? size.x : size.y)
		}
		main_positions = layout_space_positions(main_align, main_available, main_sizes[:], gap_main)
	}

	cross_positions: [dynamic]f32
	defer delete(cross_positions)
	if cross_space && len(in_flow) > 0 {
		cross_sizes: [dynamic]f32
		defer delete(cross_sizes)
		for idx in in_flow {
			size := child_sizes[idx]
			append(&cross_sizes, is_horizontal ? size.y : size.x)
		}
		cross_positions = layout_space_positions(cross_align, cross_available, cross_sizes[:], 0)
	}

	main_start: f32
	if !main_space {
		total_main: f32
		if len(in_flow) > 0 {
			for idx in in_flow {
				size := child_sizes[idx]
				total_main += is_horizontal ? size.x : size.y
			}
			if len(in_flow) > 1 {
				total_main += gap_main * f32(len(in_flow) - 1)
			}
		}

		if main_align_ok {
			main_start = justify_align_position_offset(main_available, total_main, main_align)
		}
	}

	main_cursor := main_start
	flow_index := 0
	for child_index, i in node.child_indices {
		child := &state.ui.layout.nodes[child_index]
		child_justify := layout_merge_justify(justify, child.config.self)
		size := child_sizes[i]

		main := is_horizontal ? size.x : size.y
		in_flow_child := layout_child_in_main_flow(child, is_horizontal)

		main_pos: f32
		if in_flow_child && main_space {
			main_pos = main_positions[flow_index]
		} else if in_flow_child {
			main_pos = main_cursor
		}
		if info.is_main_reverse && in_flow_child {
			main_pos = layout_mirror_in_available(main_pos, main, main_available)
		}

		x, y: f32
		self := child.config.self
		_, self_x_ok := resolve_justify_x(self.x)
		_, self_y_ok := resolve_justify_y(self.y)

		if self_x_ok {
			x = content.x + justify_align_position_offset_x(content.w, size.x, self.x)
		} else if is_horizontal {
			if in_flow_child {
				x = content.x + main_pos
			} else {
				x = content.x + justify_align_position_offset_x(content.w, size.x, child_justify.x)
			}
		} else if cross_space && in_flow_child {
			x = content.x + cross_positions[flow_index]
		} else {
			x = content.x + justify_align_position_offset_x(content.w, size.x, child_justify.x)
		}

		if self_y_ok {
			y = content.y + justify_align_position_offset_y(content.h, size.y, self.y)
		} else if is_horizontal {
			if cross_space && in_flow_child {
				y = content.y + cross_positions[flow_index]
			} else {
				y = content.y + justify_align_position_offset_y(content.h, size.y, child_justify.y)
			}
		} else if in_flow_child {
			y = content.y + main_pos
		} else {
			y = content.y + justify_align_position_offset_y(content.h, size.y, child_justify.y)
		}

		x += child.config.x
		y += child.config.y

		child.rect = {
			x = x,
			y = y,
			w = size.x,
			h = size.y,
		}
		layout_finalize_node(child)

		if len(child.child_indices) > 0 {
			layout_position_children(
				child,
				layout_inner_rect(child.rect, child.border, child.padding),
			)
		}

		if in_flow_child {
			if !main_space {
				main_cursor += main
				next_in_flow := false
				for j in i + 1 ..< len(node.child_indices) {
					next_child := &state.ui.layout.nodes[node.child_indices[j]]
					if layout_child_in_main_flow(next_child, is_horizontal) {
						next_in_flow = true
						break
					}
				}
				if next_in_flow do main_cursor += gap_main
			}
			flow_index += 1
		}
	}

	if node.kind == .TABLE {
		layout_table_finalize(layout_node_index(node))
	}
}

/*
Assigns a node's rect and recursively positions its children.
*/
layout_solve_node :: proc(node: ^Layout_Node, bounds: Rect) {
	size := layout_resolve_node_size(node, bounds)

	x := bounds.x
	y := bounds.y
	if node.config.x != 0 do x += node.config.x
	if node.config.y != 0 do y += node.config.y

	node.rect = {
		x = x,
		y = y,
		w = size.x,
		h = size.y,
	}
	layout_finalize_node(node)

	if len(node.child_indices) > 0 {
		layout_position_children(node, layout_inner_rect(node.rect, node.border, node.padding))
		if layout_direction_is_wrap(node.config.direction) {
			layout_wrap_apply_auto_cross_size(
				node,
				layout_direction_info(node.config.direction).is_horizontal,
			)
		}
	}
}

/*
Solves layout for a root node within the given bounds.
*/
layout_solve :: proc(root: ^Layout_Node, bounds: Rect) {
	layout_solve_node(root, bounds)
}

/*
Returns layout bounds for screen or artboard draw space.
*/
layout_space_bounds :: proc(space: Draw_Space) -> Rect {
	logical_w := f32(state.dpi.logical_w)
	logical_h := f32(state.dpi.logical_h)

	if space == .ARTBOARD {
		zoom := view_effective_zoom()
		if zoom <= 0 do zoom = 1
		return {0, 0, logical_w / zoom, logical_h / zoom}
	}

	return {0, 0, logical_w, logical_h}
}

/*
Pushes layout bounds and records the node index for a new space.
*/
layout_begin_space :: proc(space: Draw_Space) {
	append(&state.ui.layout.bounds_stack, layout_space_bounds(space))
	append(&state.ui.layout.space_markers, len(state.ui.layout.nodes))
}

/*
Solves all root nodes created since the matching layout_begin_space.
*/
layout_end_space :: proc() {
	if len(state.ui.layout.bounds_stack) == 0 do return

	bounds := state.ui.layout.bounds_stack[len(state.ui.layout.bounds_stack) - 1]
	marker := state.ui.layout.space_markers[len(state.ui.layout.space_markers) - 1]

	ordered_remove(&state.ui.layout.bounds_stack, len(state.ui.layout.bounds_stack) - 1)
	ordered_remove(&state.ui.layout.space_markers, len(state.ui.layout.space_markers) - 1)

	for node_index in marker ..< len(state.ui.layout.nodes) {
		node := &state.ui.layout.nodes[node_index]
		if node.parent >= 0 do continue
		layout_solve(node, bounds)
	}
}
