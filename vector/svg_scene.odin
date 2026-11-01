package oni_vector

Svg_Draw_Kind :: enum { Path, Group, Clip, Mask }
Svg_Draw_Node :: struct {
	kind: Svg_Draw_Kind,
	opacity: f64,
	item: Svg_Path_Item,
	children: []Svg_Draw_Node,
	clip_items: []Svg_Path_Item,
	clip_nodes: []Svg_Draw_Node,
	mask_nodes: []Svg_Draw_Node,
	mask_alpha: bool,
}
svg_count_path_leaves :: proc(nodes: []Svg_Draw_Node) -> int {
	count := 0
	for node in nodes {
		switch node.kind {
		case .Path: count += 1
		case .Group, .Clip, .Mask: count += svg_count_path_leaves(node.children)
		}
	}
	return count
}
svg_flatten_paths :: proc(nodes: []Svg_Draw_Node, out: ^[dynamic]Svg_Path_Item) {
	for node in nodes {
		switch node.kind {
		case .Path: append(out, node.item)
		case .Group, .Clip, .Mask: svg_flatten_paths(node.children, out)
		}
	}
}

