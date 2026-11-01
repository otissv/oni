package oni_widgets

import o ".."

Vector_Fit :: enum { Contain, Cover, Fill, None, Scale_Down }
Vector_State :: Rectangle_State
Vector_Event :: Rectangle_Event
Svg_State :: Rectangle_State
Svg_Event :: Rectangle_Event

Vector_Canvas :: struct {
	viewport, rect: o.Rect,
	transform: o.Vector_Transform,
}
Vector_Config :: struct {
	using _: o.Widget_Config,
	viewport: o.Rect,
	fit: Vector_Fit,
	unmount, can_interactive_during_mount: bool,
}
Svg_Config :: struct {
	using _: o.Widget_Config,
	asset: o.Svg_Asset,
	overrides: []o.Svg_Override,
	fit: Vector_Fit,
	unmount, can_interactive_during_mount: bool,
}
Vector_Props :: struct {
	config:                       Vector_Config,
	child:                        proc(frame_state: Vector_State),
	on_mount:                     proc(frame_state: Vector_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Vector_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Vector_Event),
	on_blur:                      proc(event: Vector_Event),
	on_mouse_enter:               proc(event: Vector_Event),
	on_mouse_leave:               proc(event: Vector_Event),
	on_mouse_pressed:             proc(event: Vector_Event),
	on_mouse_down:                proc(event: Vector_Event),
	on_mouse_released:            proc(event: Vector_Event),
	on_mouse_move:                proc(event: Vector_Event),
	on_click:                     proc(event: Vector_Event),
	on_contextmenu:               proc(event: Vector_Event),
	on_key_pressed:               proc(event: Vector_Event),
	on_key_down:                  proc(event: Vector_Event),
	on_key_released:              proc(event: Vector_Event),
	draw: proc(frame_state: Vector_State, canvas: Vector_Canvas),
	on_error: proc(error: o.Vector_Error, diagnostics: []o.Svg_Diagnostic),
}

Svg_Props :: struct {
	config:                       Svg_Config,
	child:                        proc(frame_state: Svg_State),
	on_mount:                     proc(frame_state: Svg_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Svg_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Svg_Event),
	on_blur:                      proc(event: Svg_Event),
	on_mouse_enter:               proc(event: Svg_Event),
	on_mouse_leave:               proc(event: Svg_Event),
	on_mouse_pressed:             proc(event: Svg_Event),
	on_mouse_down:                proc(event: Svg_Event),
	on_mouse_released:            proc(event: Svg_Event),
	on_mouse_move:                proc(event: Svg_Event),
	on_click:                     proc(event: Svg_Event),
	on_contextmenu:               proc(event: Svg_Event),
	on_key_pressed:               proc(event: Svg_Event),
	on_key_down:                  proc(event: Svg_Event),
	on_key_released:              proc(event: Svg_Event),
	on_error: proc(error: o.Vector_Error, diagnostics: []o.Svg_Diagnostic),
}

@(private)
Vector_Widget_Snapshot :: struct {
	viewport: o.Rect,
	fit: Vector_Fit,
	instance: ^o.Svg_Instance,
	error: o.Vector_Error,
	diagnostics: o.Svg_Load_Result,
}
@(private)
Vector_Widget_Content :: struct {
	viewport: o.Rect,
	fit: Vector_Fit,
	asset: o.Svg_Asset,
	overrides: []o.Svg_Override,
	is_svg: bool,
	draw: proc(frame_state: Vector_State, canvas: Vector_Canvas),
	on_error: proc(error: o.Vector_Error, diagnostics: []o.Svg_Diagnostic),
}
@(private)
vector_rectangle_props :: proc(props: $P) -> Rectangle_Props {
	return {config = props.config,
		child = props.child,
		unmount = props.config.unmount,
		can_interactive_during_mount = props.config.can_interactive_during_mount,
		on_mount = props.on_mount,
		on_unmount = props.on_unmount,
		on_scroll = props.on_scroll,
		on_focus = props.on_focus,
		on_blur = props.on_blur,
		on_mouse_enter = props.on_mouse_enter,
		on_mouse_leave = props.on_mouse_leave,
		on_mouse_pressed = props.on_mouse_pressed,
		on_mouse_down = props.on_mouse_down,
		on_mouse_released = props.on_mouse_released,
		on_mouse_move = props.on_mouse_move,
		on_click = props.on_click,
		on_contextmenu = props.on_contextmenu,
		on_key_pressed = props.on_key_pressed,
		on_key_down = props.on_key_down,
		on_key_released = props.on_key_released,
	}
}
@(private)
vector_fit :: proc(fit: Vector_Fit) -> o.Texture_Fit {
	switch fit {
	case .Contain: return .CONTAIN
	case .Cover: return .COVER
	case .Fill: return .FILL
	case .None: return .NONE
	case .Scale_Down: return .SCALE_DOWN
	}
	return .CONTAIN
}
@(private)
vector_viewport_valid :: proc(viewport: o.Rect) -> bool {
	for value in ([]f32{viewport.x, viewport.y, viewport.w, viewport.h}) {
		if !(abs(value) <= 1 << 20) { return false }
	}
	return viewport.w > 0 && viewport.h > 0
}
@(private)
vector_content :: proc(data: rawptr, id: o.UI_Id, frame: rawptr) {
	content := cast(^Vector_Widget_Content)data
	fs := cast(^Rectangle_State)frame
	if o.ui_pass() == .Layout {
		index, found := o.state.ui.layout.id_to_node[id]
		if !found { return }
		node := &o.state.ui.layout.nodes[index]
		allocator := o.layout_frame_allocator()
		snapshot := new(Vector_Widget_Snapshot, allocator)
		if snapshot == nil { node.vector = {active = true, error = .Allocation_Failed}; return }
		snapshot^ = {viewport = content.viewport, fit = content.fit}
		if content.is_svg {
			if content.asset == nil { snapshot.error = .Invalid_Handle } else {
				width, height := o.Svg_Intrinsic_Size(content.asset)
				snapshot.viewport = {0, 0, f32(width), f32(height)}
				instance, result := o.Prepare_Svg_Instance(content.asset, content.overrides, allocator)
				snapshot.instance, snapshot.diagnostics = instance, result
				if !result.ok { snapshot.error = o.Svg_Result_Error(result) }
				if result.ok && width > 0 && height > 0 && !vector_viewport_valid(snapshot.viewport) { snapshot.error = .Invalid_Value }
			}
		} else if !vector_viewport_valid(snapshot.viewport) { snapshot.error = .Invalid_Value }
		if content.fit < .Contain || content.fit > .Scale_Down { snapshot.error = .Invalid_Value }
		o.layout_set_vector(node, snapshot.viewport, vector_fit(snapshot.fit), rawptr(snapshot))
		return
	}
	geometry := o.layout_vector_result(id)
	if geometry == nil { return }
	if geometry.error != .None {
		if content.on_error != nil { content.on_error(geometry.error, nil) }
		return
	}
	if geometry.snapshot == nil { return }
	snapshot := cast(^Vector_Widget_Snapshot)geometry.snapshot
	if snapshot.error != .None {
		if content.on_error != nil { content.on_error(snapshot.error, snapshot.diagnostics.diagnostics[:]) }
		return
	}
	viewport, dst := snapshot.viewport, geometry.dst
	if !vector_viewport_valid(viewport) || dst.w <= 0 || dst.h <= 0 { return }
	if geometry.src.w <= 0 || geometry.src.h <= 0 { return }
	transform := o.Vector_Transform{f64(dst.w / geometry.src.w), 0, 0, f64(dst.h / geometry.src.h), 0, 0}
	// Use the original viewport, including the cropped source offset for COVER.
	transform[4] = f64(dst.x) - f64(geometry.src.x) * transform[0]
	transform[5] = f64(dst.y) - f64(geometry.src.y) * transform[3]
	o.Draw_Push_Clip(geometry.content)
	defer o.Draw_Pop_Clip()
	if snapshot.instance != nil {
		if err := o.Draw_Svg_Instance(snapshot.instance, transform); err != .None && content.on_error != nil { content.on_error(err, nil) }
	} else if content.draw != nil {
		content.draw(fs^, {viewport = viewport, rect = dst, transform = transform})
	}
}

// Config is captured during Layout; drawing reads that immutable frame snapshot.
// Children and input handlers use the shared rectangle lifecycle and event path.
Vector :: proc(props: Vector_Props) {
	content := Vector_Widget_Content{viewport = props.config.viewport, fit = props.config.fit, draw = props.draw, on_error = props.on_error}
	rectangle_with_theme(vector_rectangle_props(props), rect_theme_base, {data = rawptr(&content), invoke = vector_content})
}

Svg :: proc(props: Svg_Props) {
	content := Vector_Widget_Content{asset = props.config.asset, overrides = props.config.overrides, fit = props.config.fit, is_svg = true, on_error = props.on_error}
	rectangle_with_theme(vector_rectangle_props(props), rect_theme_base, {data = rawptr(&content), invoke = vector_content})
}
