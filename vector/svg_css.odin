package oni_vector

import "core:fmt"
import "core:strings"
import "core:strconv"
import "core:unicode/utf8"

Css_Specificity :: [4]int
Css_Declaration :: struct { property, value: string, important: bool }
Css_Test :: struct { kind: u8, value: string }
Css_Selector_Step :: struct { tests: [dynamic]Css_Test, child: bool }
Css_Selector :: struct { steps: [dynamic]Css_Selector_Step, specificity: Css_Specificity }
Css_Rule :: struct { selectors: [dynamic]Css_Selector, declarations: [dynamic]Css_Declaration, order: int }
Css_Stylesheet :: struct { rules: [dynamic]Css_Rule }
Css_Table :: struct { sheets: [dynamic]Css_Stylesheet }
@(private)
Css_Cascade_Winner :: struct { decl: Css_Declaration, spec: Css_Specificity, order: int }

@(private)
css_skip_ws :: proc(text: string, i: ^int) {
	for i^ < len(text) && strings.contains_any(text[i^:i^ + 1], " \t\r\n\x01") { i^ += 1 }
}
@(private)
css_skip_comments :: proc(text: string, i: ^int) {
	for i^ < len(text) && text[i^] == '\x01' { i^ += 1 }
}
@(private)
css_ident :: proc(text: string, i: ^int) -> string {
	start := i^
	if start >= len(text) || !(xml_name_start(text[start]) || text[start] == '-' || text[start] == '\\') { return "" }
	builder := strings.builder_make(context.allocator)
	for i^ < len(text) {
		c := text[i^]
		if c == '\\' {
			i^ += 1
			if i^ == len(text) || text[i^] == '\n' || text[i^] == '\r' { return "" }
			hex_start := i^
			for i^ < len(text) && i^ - hex_start < 6 {
				digit := text[i^]
				if !(digit >= '0' && digit <= '9' || digit >= 'a' && digit <= 'f' || digit >= 'A' && digit <= 'F') { break }
				i^ += 1
			}
			if i^ > hex_start {
				code, _ := strconv.parse_u64(text[hex_start:i^], 16)
				if code == 0 || code > 0x10FFFF || code >= 0xD800 && code <= 0xDFFF { code = 0xFFFD }
				encoded, count := utf8.encode_rune(rune(code))
				strings.write_bytes(&builder, encoded[:count])
				if i^ < len(text) && strings.contains_any(text[i^:i^ + 1], " \t\r\n") { i^ += 1 }
			} else { strings.write_byte(&builder, text[i^]); i^ += 1 }
			continue
		}
		if !(xml_name_start(c) || c >= '0' && c <= '9' || c == '-') { break }
		strings.write_byte(&builder, c)
		i^ += 1
	}
	return strings.to_string(builder)
}
@(private)
css_remove_comments :: proc(text: string) -> (string, bool) {
	if !strings.contains(text, "/*") { return text, true }
	builder := strings.builder_make(context.temp_allocator)
	quote: u8
	for i := 0; i < len(text); {
		if text[i] == '\\' && i + 1 < len(text) {
			strings.write_string(&builder, text[i:i + 2])
			i += 2
		} else if quote != 0 {
			if text[i] == quote { quote = 0 }
			strings.write_byte(&builder, text[i])
			i += 1
		} else if text[i] == '"' || text[i] == '\'' {
			quote = text[i]
			strings.write_byte(&builder, text[i])
			i += 1
		} else if strings.has_prefix(text[i:], "/*") {
			end := strings.index(text[i + 2:], "*/")
			if end < 0 { return "", false }
			i += end + 4
			strings.write_byte(&builder, '\x01')
		} else { strings.write_byte(&builder, text[i]); i += 1 }
	}
	return strings.to_string(builder), true
}
@(private)
css_parse_selector :: proc(text: string) -> (selector: Css_Selector, ok: bool) {
	i := 0
	deferred_child := false
	for {
		css_skip_ws(text, &i)
		if i == len(text) { return selector, len(selector.steps) > 0 && !deferred_child }
		step := Css_Selector_Step{child = deferred_child}
		if text[i] == '*' { i += 1 }
		else if text[i] != '.' && text[i] != '#' {
			tag := css_ident(text, &i)
			if tag == "" { return selector, false }
			append(&step.tests, Css_Test{kind = 't', value = tag})
			selector.specificity[3] += 1
		}
		css_skip_comments(text, &i)
		for i < len(text) && (text[i] == '.' || text[i] == '#') {
			kind := text[i]
			i += 1
			value := css_ident(text, &i)
			if value == "" { return selector, false }
			append(&step.tests, Css_Test{kind = kind, value = value})
			selector.specificity[kind == '#' ? 1 : 2] += 1
			css_skip_comments(text, &i)
		}
		append(&selector.steps, step)
		before := i
		css_skip_ws(text, &i)
		if i == len(text) { return selector, true }
		deferred_child = text[i] == '>'
		if deferred_child { i += 1; css_skip_ws(text, &i); if i == len(text) { return selector, false } }
		else if before == i || !strings.contains_any(text[before:i], " \t\r\n") { return selector, false }
	}
}
@(private)
css_parse_declarations :: proc(input: string, node: ^Xml_Node, ctx: ^Svg_Build_Ctx) -> (decls: [dynamic]Css_Declaration, ok: bool) {
	text, comments_valid := css_remove_comments(input)
	if !comments_valid { return decls, false }
	i := 0
	for {
		css_skip_ws(text, &i)
		for i < len(text) && text[i] == ';' { i += 1; css_skip_ws(text, &i) }
		if i == len(text) { return decls, true }
		name := strings.to_lower(css_ident(text, &i), context.allocator)
		css_skip_ws(text, &i)
		if name == "" || i == len(text) || text[i] != ':' { return decls, false }
		if !svg_is_property(name) { svg_push(ctx.result, .Unsupported_Feature, fmt.tprintf("unsupported CSS property %q", name), node.line, node.column, node.name, name); return decls, false }
		i += 1
		start := i
		quote: u8
		nesting := 0
		for i < len(text) {
			c := text[i]
			if quote != 0 { if c == quote { quote = 0 } }
			else if c == '"' || c == '\'' { quote = c }
			else if c == '(' { nesting += 1 }
			else if c == ')' { nesting -= 1; if nesting < 0 { return decls, false } }
			else if c == ';' && nesting == 0 { break }
			else if c == '{' || c == '}' { return decls, false }
			i += 1
		}
		if quote != 0 || nesting != 0 { return decls, false }
		value := strings.trim_space(text[start:i])
		value, _ = strings.replace_all(value, "\x01", " ", context.temp_allocator)
		value = strings.trim_space(value)
		important := false
		if bang := strings.last_index_byte(value, '!'); bang >= 0 {
			if strings.to_lower(strings.trim_space(value[bang + 1:]), context.temp_allocator) != "important" { return decls, false }
			value = strings.trim_space(value[:bang])
			important = true
		}
		if !svg_validate_property(name, value, node, ctx) { return decls, false }
		append(&decls, Css_Declaration{property = name, value = strings.clone(value), important = important})
		if i < len(text) { i += 1 }
	}
}
Parse_Css_Stylesheet :: proc(text: string, ctx: ^Svg_Build_Ctx, order_base: int) -> (sheet: Css_Stylesheet, ok: bool) {
	clean, clean_valid := css_remove_comments(text)
	if !clean_valid { svg_push(ctx.result, .Invalid_Value, "unterminated CSS comment", 0, 0); return sheet, false }
	i := 0
	for {
		css_skip_ws(clean, &i)
		if i == len(clean) { return sheet, true }
		if len(sheet.rules) + order_base >= ctx.limits.max_css_rules {
			svg_push(ctx.result, .Limit_Exceeded, fmt.tprintf("CSS rules consumed %d, allowed %d", len(sheet.rules) + order_base + 1, ctx.limits.max_css_rules), 0, 0)
			return sheet, false
		}
		end := strings.index_byte(clean[i:], '{')
		if end < 0 { break }
		selector_text := clean[i:i + end]
		rule := Css_Rule{order = order_base + len(sheet.rules)}
		for selector_part in strings.split(selector_text, ",", context.temp_allocator) {
			selector, valid := css_parse_selector(strings.trim_space(selector_part))
			if !valid { svg_push(ctx.result, .Unsupported_Feature, "unsupported or malformed selector", 0, 0); return sheet, false }
			append(&rule.selectors, selector)
		}
		i += end + 1
		end = strings.index_byte(clean[i:], '}')
		if end < 0 { break }
		decls, valid := css_parse_declarations(clean[i:i + end], &Xml_Node{}, ctx)
		if !valid { svg_push(ctx.result, .Invalid_Value, "invalid CSS declaration", 0, 0); return sheet, false }
		rule.declarations = decls
		append(&sheet.rules, rule)
		i += end + 1
	}
	svg_push(ctx.result, .Invalid_Value, "unterminated stylesheet", 0, 0)
	return sheet, false
}
@(private)
css_charge :: proc(ctx: ^Svg_Build_Ctx) -> bool {
	if ctx.selector_ops >= ctx.limits.max_selector_ops {
		if len(ctx.result.diagnostics) == 0 { svg_push(ctx.result, .Limit_Exceeded, fmt.tprintf("selector operations consumed %d, allowed %d", ctx.selector_ops + 1, ctx.limits.max_selector_ops), 0, 0) }
		return false
	}
	ctx.selector_ops += 1
	return true
}
@(private)
css_step_matches :: proc(node: ^Xml_Node, step: Css_Selector_Step, ctx: ^Svg_Build_Ctx) -> bool {
	if len(step.tests) == 0 && !css_charge(ctx) { return false }
	for test in step.tests {
		if !css_charge(ctx) { return false }
		switch test.kind {
		case 't': if node.name != test.value { return false }
		case '#': id, _ := svg_attr(node, "id"); if id != test.value { return false }
		case '.':
			classes, _ := svg_attr(node, "class")
			found := false
			for class in strings.fields(classes, context.temp_allocator) { if class == test.value { found = true; break } }
			if !found { return false }
		}
	}
	return true
}
@(private)
css_match_from :: proc(node: ^Xml_Node, selector: Css_Selector, index: int, ctx: ^Svg_Build_Ctx) -> bool {
	if !css_step_matches(node, selector.steps[index], ctx) { return false }
	if index == 0 { return true }
	parent := ctx.parents[node]
	for parent != nil {
		if !css_charge(ctx) { return false }
		if css_match_from(parent, selector, index - 1, ctx) { return true }
		if selector.steps[index].child { return false }
		parent = ctx.parents[parent]
	}
	return false
}
@(private)
css_wins :: proc(a, b: Css_Cascade_Winner) -> bool {
	if a.decl.important != b.decl.important { return a.decl.important }
	for n in 0 ..< 4 { if a.spec[n] != b.spec[n] { return a.spec[n] > b.spec[n] } }
	return a.order >= b.order
}
Apply_Css_Cascade :: proc(node: ^Xml_Node, style: ^Computed_Style, viewport: [2]f64, ctx: ^Svg_Build_Ctx, inherited: Computed_Style) -> bool {
	winners := make(map[string]Css_Cascade_Winner, context.temp_allocator)
	for attr in node.attrs {
		if attr.namespace == "" && svg_is_property(attr.name) { winners[attr.name] = {decl = {property = attr.name, value = attr.value}, order = -1} }
	}
	for sheet in ctx.css.sheets {
		for rule in sheet.rules {
			for selector in rule.selectors {
				if !css_match_from(node, selector, len(selector.steps) - 1, ctx) { continue }
				for decl in rule.declarations {
					candidate := Css_Cascade_Winner{decl = decl, spec = selector.specificity, order = rule.order}
					previous, found := winners[decl.property]
					if !found || css_wins(candidate, previous) { winners[decl.property] = candidate }
				}
			}
		}
	}
	if ctx.selector_ops > ctx.limits.max_selector_ops || len(ctx.result.diagnostics) > 0 { return false }
	if inline, has_inline := svg_attr(node, "style"); has_inline {
		declarations, valid := css_parse_declarations(inline, node, ctx)
		if !valid { return false }
		for decl, index in declarations {
			candidate := Css_Cascade_Winner{decl = decl, spec = {1, 0, 0, 0}, order = index}
			previous, found := winners[decl.property]
			if !found || css_wins(candidate, previous) { winners[decl.property] = candidate }
		}
	}
	for name in SVG_PROPERTIES {
		winner, found := winners[name]
		if !found { continue }
		value := winner.decl.value
		if keyword, is_wide := svg_css_wide(value); is_wide { value = keyword }
		if !svg_validate_property(name, value, node, ctx) { return false }
		if value == "inherit" || value == "unset" && svg_inherited_property(name) { svg_copy_property(style, inherited, name) }
		else if value == "initial" || value == "unset" { svg_copy_property(style, Default_Computed_Style(), name) }
		else if !svg_merge_property(style, name, value, viewport) {
			svg_push(ctx.result, .Invalid_Value, "invalid property value", node.line, node.column, node.name, name)
			return false
		}
	}
	return true
}
