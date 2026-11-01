package oni_vector

import "core:fmt"
import "core:strings"

@(private)
svg_supported_element :: proc(name: string) -> bool {
	switch name {
	case "svg", "g", "defs", "symbol", "use", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "linearGradient", "radialGradient", "stop", "clipPath", "mask", "style", "metadata", "title", "desc": return true
	}
	return false
}
@(private)
svg_attribute_names :: proc(element: string) -> string {
	switch element {
	case "svg": return " x y width height viewBox preserveAspectRatio version baseProfile "
	case "symbol": return " viewBox preserveAspectRatio width height "
	case "use": return " x y width height href "
	case "path": return " d pathLength "
	case "rect": return " x y width height rx ry pathLength "
	case "circle": return " cx cy r pathLength "
	case "ellipse": return " cx cy rx ry pathLength "
	case "line": return " x1 y1 x2 y2 pathLength "
	case "polyline", "polygon": return " points pathLength "
	case "linearGradient": return " x1 y1 x2 y2 gradientUnits gradientTransform spreadMethod href "
	case "radialGradient": return " cx cy r fx fy fr gradientUnits gradientTransform spreadMethod href "
	case "stop": return " offset "
	case "clipPath": return " clipPathUnits "
	case "mask": return " x y width height maskUnits maskContentUnits "
	case "style": return " type "
	}
	return " "
}
@(private)
svg_validate_property :: proc(name, value: string, node: ^Xml_Node, ctx: ^Svg_Build_Ctx) -> bool {
	if _, wide := svg_css_wide(value); wide { return true }
	style := Default_Computed_Style()
	if !svg_merge_property(&style, name, value, {300, 150}) {
		svg_push(ctx.result, .Invalid_Value, fmt.tprintf("invalid %s value %q", name, value), node.line, node.column, node.name, name)
		return false
	}
	expected := ""
	switch name {
	case "clip-path": expected = "clipPath"
	case "mask": expected = "mask"
	case "fill", "stroke": expected = "gradient"
	}
	if expected != "" && value != "none" {
		if id, ref := svg_parse_url_reference(value); ref { return svg_reference(ctx, node, id, expected, name) }
	}
	return true
}
@(private)
svg_validate_tree :: proc(node: ^Xml_Node, ctx: ^Svg_Build_Ctx, inherited: Computed_Style) -> bool {
	if node.in_metadata { return true }
	if node.kind == .Text { return true }
	if ctx.arena.failed { return false }
	if node.namespace != SVG_NS || !svg_supported_element(node.name) {
		svg_push(ctx.result, .Unsupported_Feature, "unsupported element or namespace", node.line, node.column, node.name)
		return false
	}
	for &child in node.children {
		if child.kind == .Text {
			if strings.trim_space(child.text) != "" && node.name != "style" && node.name != "title" && node.name != "desc" {
				svg_push(ctx.result, .Unsupported_Feature, "text content is unsupported outside annotations and stylesheets", child.line, child.column, node.name)
				return false
			}
			continue
		}
		annotation := child.name == "title" || child.name == "desc" || child.name == "metadata"
		allowed := true
		switch node.name {
		case "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "use", "stop": allowed = annotation
		case "linearGradient", "radialGradient": allowed = annotation || child.name == "stop"
		case "clipPath": allowed = annotation || svg_is_shape_element(child.name) || child.name == "use"
		case "style", "title", "desc": allowed = false
		}
		if !allowed { svg_push(ctx.result, .Invalid_Value, "element is not allowed in this parent", child.line, child.column, child.name); return false }
	}
	for attr in node.attrs {
		if attr.namespace == XML_NS && (attr.name == "lang" || attr.name == "space") {
			if attr.name == "space" && attr.value != "default" && attr.value != "preserve" { svg_push(ctx.result, .Invalid_Value, "invalid xml:space", node.line, node.column, node.name, "xml:space"); return false }
			continue
		}
		if attr.namespace == XLINK_NS && attr.name == "href" && (node.name == "use" || node.name == "linearGradient" || node.name == "radialGradient") { continue }
		if attr.namespace != "" { svg_push(ctx.result, .Unsupported_Feature, "unsupported namespaced attribute", node.line, node.column, node.name, attr.name); return false }
		if attr.name == "id" || attr.name == "class" || attr.name == "style" { continue }
		if svg_is_property(attr.name) {
			if !svg_validate_property(attr.name, attr.value, node, ctx) { return false }
			continue
		}
		if !strings.contains(svg_attribute_names(node.name), fmt.tprintf(" %s ", attr.name)) {
			svg_push(ctx.result, .Unsupported_Feature, "unsupported attribute", node.line, node.column, node.name, attr.name)
			return false
		}
		valid := true
		switch attr.name {
		case "d", "points", "id", "class", "style":
		case "pathLength": number, parsed := svg_parse_scalar(attr.value); valid = parsed && number >= 0
		case "offset":
			value := strings.trim_suffix(attr.value, "%")
			_, valid = svg_parse_scalar(value)
		case "href":
			_, valid = svg_attr_href(node)
			if !valid { svg_push(ctx.result, .Invalid_Reference, "only nonempty local fragment references are supported", node.line, node.column, node.name, "href"); return false }
		case "viewBox": _, valid = svg_view_box(attr.value)
		case "preserveAspectRatio": _, valid = svg_fit_view_box({0, 0, 1, 1}, {1, 1}, attr.value)
		case "gradientTransform": _, err := Parse_Transform_List(attr.value); valid = err == .None
		case "gradientUnits", "clipPathUnits", "maskUnits", "maskContentUnits": valid = attr.value == "userSpaceOnUse" || attr.value == "objectBoundingBox"
		case "spreadMethod": valid = attr.value == "pad" || attr.value == "reflect" || attr.value == "repeat"
		case "version": valid = attr.value == "1.0" || attr.value == "1.1" || attr.value == "2.0"
		case "baseProfile": valid = attr.value == "full"
		case "type": valid = attr.value == "text/css"
		case:
			v, ok := svg_parse_length(attr.value, 100)
			valid = ok
			if attr.name == "width" || attr.name == "height" || attr.name == "r" || attr.name == "rx" || attr.name == "ry" || attr.name == "fr" || attr.name == "pathLength" { valid = valid && v >= 0 }
		}
		if !valid { svg_push(ctx.result, .Invalid_Value, "malformed attribute value", node.line, node.column, node.name, attr.name); return false }
	}
	if inline, found := svg_attr(node, "style"); found {
		if _, valid := css_parse_declarations(inline, node, ctx); !valid { return false }
	}
	if node.name == "use" || node.name == "linearGradient" || node.name == "radialGradient" {
		if id, found := svg_attr_href(node); found {
			expected := node.name == "use" ? "use" : "gradient"
			if !svg_reference(ctx, node, id, expected, "href") { return false }
		} else if svg_has_href(node) || node.name == "use" {
			svg_push(ctx.result, .Invalid_Reference, "only nonempty local fragment references are supported", node.line, node.column, node.name, "href")
			return false
		}
	}
	if svg_is_shape_element(node.name) {
		path: Path
		limits := DEFAULT_LIMITS
		limits.max_commands = ctx.limits.max_path_commands - ctx.path_commands
		err := svg_shape_path(node, &path, ctx.viewport, limits)
		ctx.path_commands += len(path.commands)
		Destroy_Path(&path)
		if err != .None || ctx.path_commands > ctx.limits.max_path_commands {
			category := err == .Limit_Exceeded || ctx.path_commands > ctx.limits.max_path_commands ? Svg_Diagnostic_Category.Limit_Exceeded : .Invalid_Value
			svg_push(ctx.result, category, fmt.tprintf("invalid geometry; path commands allowed %d", ctx.limits.max_path_commands), node.line, node.column, node.name, node.name == "path" ? "d" : "geometry")
			return false
		}
	}
	style, style_valid := svg_resolve_element_style(node, inherited, ctx.viewport, ctx)
	if !style_valid { return false }
	for &child in node.children { if !svg_validate_tree(&child, ctx, style) { return false } }
	return true
}

