package oni

import "core:strings"
import "core:testing"

@(test)
text_document_tagged_round_trip :: proc(t: ^testing.T) {
	alloc := context.temp_allocator
	doc := text_document_from_tagged("{b}hi{/b} there", alloc)

	testing.expect_value(t, doc.plain, "hi there")
}

@(test)
text_document_insert_plain_preserves_style :: proc(t: ^testing.T) {
	alloc := context.temp_allocator
	doc := text_document_from_tagged("{b}ab{/b}c", alloc)

	changed := text_document_insert_plain(&doc, 1, "Z", alloc)
	testing.expect(t, changed)
	testing.expect_value(t, doc.plain, "aZbc")
}

@(test)
text_document_delete_range_removes_bytes :: proc(t: ^testing.T) {
	alloc := context.temp_allocator
	doc := text_document_from_tagged("{b}hello{/b}", alloc)

	changed := text_document_delete_range(&doc, 1, 4, alloc)
	testing.expect(t, changed)
	testing.expect_value(t, doc.plain, "ho")
}

@(test)
text_document_splice_plain_replaces_range :: proc(t: ^testing.T) {
	alloc := context.temp_allocator
	doc := text_document_from_tagged("abc", alloc)

	changed := text_document_splice_plain(&doc, 1, 2, "Z", alloc)
	testing.expect(t, changed)
	testing.expect_value(t, doc.plain, "aZc")
}

@(test)
text_document_heap_edit_and_free_is_clean :: proc(t: ^testing.T) {
	doc := text_document_from_tagged("{b}hi{/b} there")
	defer text_document_free_runs(&doc)

	testing.expect_value(t, doc.plain, "hi there")
	testing.expect(t, text_document_insert_plain(&doc, 2, "!"))
	testing.expect_value(t, doc.plain, "hi! there")
	testing.expect(t, text_document_delete_range(&doc, 2, 3))
	testing.expect_value(t, doc.plain, "hi there")
	testing.expect(t, text_document_splice_plain(&doc, 0, len(doc.plain), "x"))
	testing.expect_value(t, doc.plain, "x")

	tagged := text_document_to_tagged(&doc)
	defer delete(tagged)
	testing.expect(t, len(tagged) > 0)
}

@(test)
text_runs_to_tagged_serializes_bold :: proc(t: ^testing.T) {
	runs := []Text_Run{{text = "x", style = {fields = {.font_weight}, font_weight = .Bold}}}
	out := text_runs_to_tagged(runs)
	defer delete(out)

	testing.expect(t, strings.contains(out, "{b}"))
	testing.expect(t, strings.contains(out, "{/b}"))
}
