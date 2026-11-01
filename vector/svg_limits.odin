package oni_vector

import "core:mem"

SVG_NS :: "http://www.w3.org/2000/svg"
XLINK_NS :: "http://www.w3.org/1999/xlink"
XML_NS :: "http://www.w3.org/XML/1998/namespace"

Svg_Limits :: struct {
	max_source_bytes: int,
	max_xml_depth: int,
	max_reference_depth: int,
	max_elements: int,
	max_expanded_references: int,
	max_path_commands: int,
	max_css_rules: int,
	max_selector_ops: int,
	max_decoded_bytes: int,
}

DEFAULT_SVG_LIMITS :: Svg_Limits {
	max_source_bytes         = 8 * 1024 * 1024,
	max_xml_depth            = 64,
	max_reference_depth      = 32,
	max_elements             = 100_000,
	max_expanded_references  = 100_000,
	max_path_commands        = 1_000_000,
	max_css_rules            = 4_096,
	max_selector_ops         = 16_000_000,
	max_decoded_bytes        = 64 * 1024 * 1024,
}

Svg_Diagnostic_Category :: enum {
	None,
	Invalid_Handle,
	Duplicate_Override,
	Rendering_Failed,
	Malformed_Xml,
	Unsupported_Feature,
	Invalid_Value,
	Limit_Exceeded,
	Duplicate_Id,
	Missing_Reference,
	Reference_Cycle,
	Invalid_Reference,
	Allocation_Failed,
}

Svg_Diagnostic :: struct {
	category: Svg_Diagnostic_Category,
	message:  string,
	line:     int,
	column:   int,
	element:  string,
	property: string,
}

Svg_Load_Result :: struct {
	ok:          bool,
	error: Svg_Diagnostic_Category,
	diagnostics: [dynamic]Svg_Diagnostic,
	allocator: mem.Allocator,
}
