package oni_vector

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

Xml_Attr :: struct {
	name, namespace, value: string,
}
Xml_Node_Kind :: enum { Element, Text }
Xml_Node :: struct {
	kind: Xml_Node_Kind,
	name, namespace: string,
	attrs: []Xml_Attr,
	children: [dynamic]Xml_Node,
	text: string,
	line, column: int,
	in_metadata: bool,
}
@(private)
Xml_Builder :: struct {
	result: ^Svg_Load_Result,
	limits: Svg_Limits,
	depth, nodes: int,
	position, line, column: int,
}
@(private)
xml_diag :: proc(b: ^Xml_Builder, category: Svg_Diagnostic_Category, message: string, line, column: int) {
	svg_push(b.result, category, message, line, column)
}
@(private)
xml_skip_ws :: proc(data: string, i: ^int) {
	for i^ < len(data) && (data[i^] == ' ' || data[i^] == '\t' || data[i^] == '\n' || data[i^] == '\r') { i^ += 1 }
}
@(private)
xml_location :: proc(b: ^Xml_Builder, data: string, position: int) -> (int, int) {
	for b.position < position {
		if data[b.position] == '\n' { b.line += 1; b.column = 1 } else { b.column += 1 }
		b.position += 1
	}
	return b.line, b.column
}
@(private)
xml_name_start :: proc(c: u8) -> bool {
	return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c == '_' || c >= 0x80
}
@(private)
xml_read_name :: proc(data: string, i: ^int) -> string {
	start := i^
	if start == len(data) { return "" }
	first, count := utf8.decode_rune_in_string(data[start:])
	if !xml_name_start_rune(first) { return "" }
	i^ += count
	for i^ < len(data) {
		c, size := utf8.decode_rune_in_string(data[i^:])
		if !xml_name_start_rune(c) && !(c >= '0' && c <= '9') && c != '-' && c != '.' && c != ':' && c != 0xB7 && !(c >= 0x300 && c <= 0x36F) && !(c >= 0x203F && c <= 0x2040) { break }
		i^ += size
	}
	return data[start:i^]
}

@(private)
xml_name_start_rune :: proc(c: rune) -> bool {
	return c == '_' || c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' ||
	       c >= 0xC0 && c <= 0xD6 || c >= 0xD8 && c <= 0xF6 || c >= 0xF8 && c <= 0x2FF ||
	       c >= 0x370 && c <= 0x37D || c >= 0x37F && c <= 0x1FFF || c >= 0x200C && c <= 0x200D ||
	       c >= 0x2070 && c <= 0x218F || c >= 0x2C00 && c <= 0x2FEF || c >= 0x3001 && c <= 0xD7FF ||
	       c >= 0xF900 && c <= 0xFDCF || c >= 0xFDF0 && c <= 0xFFFD || c >= 0x10000 && c <= 0xEFFFF
}
@(private)
xml_valid_char :: proc(c: rune) -> bool {
	return c == 9 || c == 10 || c == 13 || c >= 0x20 && c <= 0xD7FF || c >= 0xE000 && c <= 0xFFFD || c >= 0x10000 && c <= 0x10FFFF
}
@(private)
xml_decode_text :: proc(data: string, attribute: bool) -> (string, bool) {
	builder := strings.builder_make(context.temp_allocator)
	for i := 0; i < len(data); {
		if data[i] == '<' && attribute { return "", false }
		if data[i] != '&' {
			c := data[i]
			if attribute && (c == '\t' || c == '\r' || c == '\n') { c = ' ' }
			strings.write_byte(&builder, c)
			i += 1
			continue
		}
		end := strings.index_byte(data[i:], ';')
		if end < 0 { return "", false }
		body := data[i + 1:i + end]
		value: string
		switch body {
		case "lt": value = "<"
		case "gt": value = ">"
		case "amp": value = "&"
		case "quot": value = "\""
		case "apos": value = "'"
		case:
			if len(body) < 2 || body[0] != '#' { return "", false }
			base, offset := 10, 1
			if body[1] == 'x' { base, offset = 16, 2 }
			code, valid := strconv.parse_u64(body[offset:], base)
			if !valid || code > 0x10FFFF || !xml_valid_char(rune(code)) { return "", false }
			encoded, n := utf8.encode_rune(rune(code))
			strings.write_bytes(&builder, encoded[:n])
			i += end + 1
			continue
		}
		strings.write_string(&builder, value)
		i += end + 1
	}
	return strings.clone(strings.to_string(builder)), true
}
@(private)
xml_skip_special :: proc(data: string, i: ^int, b: ^Xml_Builder) -> (handled, ok: bool) {
	if strings.has_prefix(data[i^:], "<!--") {
		end := strings.index(data[i^ + 4:], "-->")
		if end < 0 || strings.contains(data[i^ + 4:i^ + 4 + end], "--") { return true, false }
		i^ += end + 7
		return true, true
	}
	if strings.has_prefix(data[i^:], "<?") {
		end := strings.index(data[i^ + 2:], "?>")
		if end < 0 { return true, false }
		target_i := i^ + 2
		target := xml_read_name(data, &target_i)
		if target == "" { return true, false }
		if target == "xml-stylesheet" {
			xml_diag(b, .Unsupported_Feature, "external stylesheet processing instructions are unsupported", b.line, b.column)
			return true, false
		}
		if strings.to_lower(target, context.temp_allocator) == "xml" {
			if target != "xml" || b.depth > 0 || i^ > 3 || !xml_declaration_valid(data[target_i:i^ + end + 2]) { return true, false }
		}
		i^ += end + 4
		return true, true
	}
	return false, true
}

@(private)
xml_declaration_valid :: proc(body: string) -> bool {
	i, count := 0, 0
	last_order := -1
	for {
		start := i
		xml_skip_ws(body, &i)
		if i == len(body) { return count > 0 }
		if i == start { return false }
		name := xml_read_name(body, &i)
		order := name == "version" ? 0 : name == "encoding" ? 1 : name == "standalone" ? 2 : -1
		if order < 0 || order <= last_order || count == 0 && name != "version" { return false }
		xml_skip_ws(body, &i)
		if i == len(body) || body[i] != '=' { return false }
		i += 1
		xml_skip_ws(body, &i)
		if i == len(body) || body[i] != '"' && body[i] != '\'' { return false }
		quote := body[i]
		i += 1
		value_start := i
		for i < len(body) && body[i] != quote { i += 1 }
		if i == len(body) { return false }
		value := body[value_start:i]
		switch name {
		case "version": if value != "1.0" { return false }
		case "encoding": if strings.to_lower(value, context.temp_allocator) != "utf-8" { return false }
		case "standalone": if value != "yes" && value != "no" { return false }
		}
		i += 1
		count += 1
		last_order = order
	}
}
@(private)
xml_resolve_name :: proc(name: string, namespaces: map[string]string, attribute: bool) -> (local, ns: string, ok: bool) {
	colon := strings.index_byte(name, ':')
	if colon < 0 {
		return name, attribute ? "" : namespaces[""], true
	}
	if colon == 0 || colon + 1 == len(name) || strings.contains(name[colon + 1:], ":") { return "", "", false }
	first, _ := utf8.decode_rune_in_string(name[colon + 1:])
	if !xml_name_start_rune(first) { return "", "", false }
	ns, ok = namespaces[name[:colon]]
	return name[colon + 1:], ns, ok && ns != ""
}
@(private)
xml_parse_element :: proc(data: string, i: ^int, b: ^Xml_Builder, parent_ns: map[string]string, in_metadata: bool) -> (node: Xml_Node, ok: bool) {
	line, column := xml_location(b, data, i^)
	fail :: proc(b: ^Xml_Builder, message: string, line, column: int) { xml_diag(b, .Malformed_Xml, message, line, column) }
	if b.depth >= b.limits.max_xml_depth || b.nodes >= b.limits.max_elements {
		xml_diag(b, .Limit_Exceeded, fmt.tprintf("XML depth/elements consumed %d/%d, allowed %d/%d", b.depth + 1, b.nodes + 1, b.limits.max_xml_depth, b.limits.max_elements), line, column)
		return {}, false
	}
	defer if !ok { Destroy_Xml_Node(&node) }
	if i^ == len(data) || data[i^] != '<' { fail(b, "expected start tag", line, column); return {}, false }
	i^ += 1
	qname := xml_read_name(data, i)
	if qname == "" { fail(b, "invalid element name", line, column); return {}, false }
	raw_attrs := make([dynamic]Xml_Attr)
	defer {
		for attr in raw_attrs { delete(attr.value) }
		delete(raw_attrs)
	}
	self_closing := false
	for {
		before := i^
		xml_skip_ws(data, i)
		if i^ == len(data) { fail(b, "unterminated start tag", line, column); return {}, false }
		if data[i^] == '>' { i^ += 1; break }
		if strings.has_prefix(data[i^:], "/>") { i^ += 2; self_closing = true; break }
		if i^ == before { fail(b, "attributes require whitespace", line, column); return {}, false }
		name := xml_read_name(data, i)
		if name == "" { fail(b, "invalid attribute name", line, column); return {}, false }
		for attr in raw_attrs { if attr.name == name { fail(b, "duplicate attribute", line, column); return {}, false } }
		xml_skip_ws(data, i)
		if i^ == len(data) || data[i^] != '=' { fail(b, "attribute missing value", line, column); return {}, false }
		i^ += 1
		xml_skip_ws(data, i)
		if i^ == len(data) || (data[i^] != '"' && data[i^] != '\'') { fail(b, "attribute must be quoted", line, column); return {}, false }
		quote := data[i^]
		i^ += 1
		start := i^
		for i^ < len(data) && data[i^] != quote { i^ += 1 }
		if i^ == len(data) { fail(b, "unterminated attribute", line, column); return {}, false }
		value, valid := xml_decode_text(data[start:i^], true)
		if !valid { fail(b, "invalid entity or attribute character", line, column); return {}, false }
		if _, err := append(&raw_attrs, Xml_Attr{name = name, value = value}); err != nil { delete(value); return {}, false }
		i^ += 1
	}
	namespaces := make(map[string]string)
	defer delete(namespaces)
	for k, v in parent_ns { namespaces[k] = v }
	for attr in raw_attrs {
		if attr.name == "xmlns" {
			if attr.value == XML_NS || attr.value == "http://www.w3.org/2000/xmlns/" { fail(b, "reserved default namespace", line, column); return {}, false }
			namespaces[""] = attr.value
		} else if strings.has_prefix(attr.name, "xmlns:") {
			prefix := attr.name[6:]
			if prefix == "" || prefix == "xmlns" || prefix == "xml" && attr.value != XML_NS || attr.value == "http://www.w3.org/2000/xmlns/" || attr.value == XML_NS && prefix != "xml" || attr.value == "" {
				fail(b, "invalid namespace declaration", line, column); return {}, false
			}
			namespaces[prefix] = attr.value
		}
	}
	local, ns, name_valid := xml_resolve_name(qname, namespaces, false)
	if !name_valid { fail(b, "undeclared element prefix", line, column); return {}, false }
	node = {kind = .Element, name = strings.clone(local), namespace = strings.clone(ns), line = line, column = column, in_metadata = in_metadata || local == "metadata" && ns == SVG_NS}
	attrs := make([dynamic]Xml_Attr)
	defer {
		for attr in attrs { delete(attr.name); delete(attr.namespace); delete(attr.value) }
		delete(attrs)
	}
	for attr in raw_attrs {
		if attr.name == "xmlns" || strings.has_prefix(attr.name, "xmlns:") { continue }
		name, attr_ns, valid := xml_resolve_name(attr.name, namespaces, true)
		if !valid { fail(b, "undeclared attribute prefix", line, column); return node, false }
		for a in attrs { if a.name == name && a.namespace == attr_ns { fail(b, "duplicate expanded attribute", line, column); return node, false } }
		append(&attrs, Xml_Attr{name = strings.clone(name), namespace = strings.clone(attr_ns), value = strings.clone(attr.value)})
	}
	node.attrs = attrs[:]
	// Transfer the dynamic allocation to the node's slice.
	attrs = nil
	b.nodes += 1
	if self_closing { return node, true }
	b.depth += 1
	defer b.depth -= 1
	for i^ < len(data) {
		if strings.has_prefix(data[i^:], "</") {
			i^ += 2
			end_name := xml_read_name(data, i)
			xml_skip_ws(data, i)
			if end_name != qname || i^ == len(data) || data[i^] != '>' { fail(b, "mismatched end tag", line, column); return node, false }
			i^ += 1
			return node, true
		}
		if handled, valid := xml_skip_special(data, i, b); handled {
			if !valid { fail(b, "invalid comment or processing instruction", line, column); return node, false }
			continue
		}
		if strings.has_prefix(data[i^:], "<![CDATA[") {
			i^ += 9
			end := strings.index(data[i^:], "]]>")
			if end < 0 { fail(b, "unterminated CDATA", line, column); return node, false }
			append(&node.children, Xml_Node{kind = .Text, text = strings.clone(data[i^:i^ + end]), line = line, column = column})
			i^ += end + 3
			continue
		}
		if data[i^] == '<' {
			child, valid := xml_parse_element(data, i, b, namespaces, node.in_metadata)
			if !valid { return node, false }
			append(&node.children, child)
			continue
		}
		start := i^
		for i^ < len(data) && data[i^] != '<' { i^ += 1 }
		text, valid := xml_decode_text(data[start:i^], false)
		if !valid || strings.contains(data[start:i^], "]]>") { delete(text); fail(b, "invalid character data", line, column); return node, false }
		append(&node.children, Xml_Node{kind = .Text, text = text, line = line, column = column})
	}
	fail(b, "unterminated element", line, column)
	return node, false
}
Parse_Xml_Document :: proc(source: string, limits := DEFAULT_SVG_LIMITS, result: ^Svg_Load_Result) -> (root: Xml_Node, ok: bool) {
	if result == nil { return {}, false }
	b := Xml_Builder{result = result, limits = limits, line = 1, column = 1}
	if len(source) > limits.max_source_bytes {
		xml_diag(&b, .Limit_Exceeded, fmt.tprintf("source bytes consumed %d, allowed %d", len(source), limits.max_source_bytes), 1, 1)
		return {}, false
	}
	if !utf8.valid_string(source) { xml_diag(&b, .Malformed_Xml, "invalid UTF-8", 1, 1); return {}, false }
	for c in source {
		if !xml_valid_char(c) { xml_diag(&b, .Malformed_Xml, "invalid UTF-8/XML character", 1, 1); return {}, false }
	}
	i := 0
	if strings.has_prefix(source, "\xEF\xBB\xBF") { i = 3 }
	namespaces := make(map[string]string)
	defer delete(namespaces)
	namespaces["xml"] = XML_NS
	for {
		xml_skip_ws(source, &i)
		if i == len(source) { xml_diag(&b, .Malformed_Xml, "missing root element", 1, 1); return {}, false }
		handled, valid := xml_skip_special(source, &i, &b)
		if !valid { xml_diag(&b, .Malformed_Xml, "invalid document preamble", 1, 1); return {}, false }
		if !handled { break }
	}
	root, ok = xml_parse_element(source, &i, &b, namespaces, false)
	if !ok { return {}, false }
	for {
		xml_skip_ws(source, &i)
		if i == len(source) { result.ok = true; return root, true }
		handled, valid := xml_skip_special(source, &i, &b)
		if !handled || !valid { Destroy_Xml_Node(&root); xml_diag(&b, .Malformed_Xml, "trailing document content", 1, 1); return {}, false }
	}
}
Destroy_Xml_Node :: proc(node: ^Xml_Node) {
	if node == nil { return }
	delete(node.text)
	delete(node.name)
	delete(node.namespace)
	for attr in node.attrs { delete(attr.name); delete(attr.namespace); delete(attr.value) }
	delete(node.attrs)
	for &child in node.children { Destroy_Xml_Node(&child) }
	delete(node.children)
	node^ = {}
}

