package oni

import "core:strings"

Text_Document :: struct {
	runs:        []Text_Run,
	plain:       string,
	layout_runs: []Layout_Text_Run,
}

text_document_free_runs :: proc(doc: ^Text_Document, allocator := context.allocator) {
	if allocator == context.temp_allocator {
		doc^ = {}

		return
	}

	if doc.runs != nil {
		for run in doc.runs {
			if len(run.text) > 0 {
				delete(run.text)
			}
		}

		delete(doc.runs)
	}

	if doc.layout_runs != nil {
		delete(doc.layout_runs)
	}

	if len(doc.plain) > 0 {
		delete(doc.plain)
	}

	doc^ = {}
}

text_document_rebuild :: proc(doc: ^Text_Document, allocator := context.allocator) {
	doc.plain, doc.layout_runs = text_runs_to_layout(doc.runs[:], allocator)
}

text_document_from_tagged :: proc(tagged: string, allocator := context.allocator) -> Text_Document {
	parsed := text_tags_parse(tagged, allocator)
	doc: Text_Document

	if len(parsed.runs) == 0 do return doc

	doc.runs = make([]Text_Run, len(parsed.runs), allocator)

	for run, i in parsed.runs {
		doc.runs[i] = Text_Run {
			text  = strings.clone(run.text, allocator),
			style = run.style,
		}
	}

	text_document_rebuild(&doc, allocator)

	if allocator != context.temp_allocator {
		for run in parsed.runs {
			if len(run.text) > 0 {
				delete(run.text)
			}
		}

		delete(parsed.runs)

		for diagnostic in parsed.diagnostics {
			delete(diagnostic.message)
		}

		delete(parsed.diagnostics)
	}

	return doc
}

text_document_to_tagged :: proc(doc: ^Text_Document, allocator := context.allocator) -> string {
	return text_runs_to_tagged(doc.runs[:], allocator)
}

text_document_style_at :: proc(doc: ^Text_Document, offset: int) -> Text_Run_Style {
	clamped := text_edit_clamp_offset(doc.plain, offset)

	for lr in doc.layout_runs {
		if clamped >= lr.start && clamped < lr.end {
			return lr.style
		}
	}

	if len(doc.layout_runs) > 0 {
		return doc.layout_runs[len(doc.layout_runs) - 1].style
	}

	return TEXT_RUN_STYLE_DEFAULT
}

text_document_insert_plain :: proc(
	doc: ^Text_Document,
	offset: int,
	insert: string,
	allocator := context.allocator,
) -> bool {
	if len(insert) == 0 do return false

	clamped := text_edit_clamp_offset(doc.plain, offset)
	style := text_document_style_at(doc, clamped)

	new_runs := make([dynamic]Text_Run, allocator)
	byte_pos := 0
	inserted := false

	for run in doc.runs {
		run_len := len(run.text)
		run_start := byte_pos
		run_end := byte_pos + run_len

		if !inserted && clamped >= run_start && clamped <= run_end {
			rel := clamped - run_start
			left := run.text[:rel]
			right := run.text[rel:]

			if len(left) > 0 {
				append(&new_runs, Text_Run{text = strings.clone(left, allocator), style = run.style})
			}

			append(&new_runs, Text_Run{text = strings.clone(insert, allocator), style = style})
			inserted = true

			if len(right) > 0 {
				append(&new_runs, Text_Run{text = strings.clone(right, allocator), style = run.style})
			}
		} else if !inserted && clamped < run_start {
			append(&new_runs, Text_Run{text = strings.clone(insert, allocator), style = style})
			append(&new_runs, Text_Run{text = strings.clone(run.text, allocator), style = run.style})
			inserted = true
		} else {
			append(&new_runs, Text_Run{text = strings.clone(run.text, allocator), style = run.style})
		}

		byte_pos = run_end
	}

	if !inserted {
		append(&new_runs, Text_Run{text = strings.clone(insert, allocator), style = style})
	}

	text_document_free_runs(doc, allocator)
	doc.runs = new_runs[:]
	text_document_rebuild(doc, allocator)

	return true
}

text_document_delete_range :: proc(
	doc: ^Text_Document,
	start, end: int,
	allocator := context.allocator,
) -> bool {
	start_idx := clamp(start, 0, len(doc.plain))
	end_idx := clamp(end, 0, len(doc.plain))
	if start_idx > end_idx {
		start_idx, end_idx = end_idx, start_idx
	}

	if start_idx == end_idx do return false

	new_runs := make([dynamic]Text_Run, allocator)
	byte_pos := 0

	for run in doc.runs {
		run_len := len(run.text)
		run_start := byte_pos
		run_end := byte_pos + run_len

		if run_end <= start_idx || run_start >= end_idx {
			append(&new_runs, Text_Run{text = strings.clone(run.text, allocator), style = run.style})
		} else {
			rel_start := max(0, start_idx - run_start)
			rel_end := min(run_len, end_idx - run_start)
			left := run.text[:rel_start]
			right := run.text[rel_end:]

			if len(left) > 0 {
				append(&new_runs, Text_Run{text = strings.clone(left, allocator), style = run.style})
			}

			if len(right) > 0 {
				append(&new_runs, Text_Run{text = strings.clone(right, allocator), style = run.style})
			}
		}

		byte_pos = run_end
	}

	text_document_free_runs(doc, allocator)
	doc.runs = new_runs[:]
	text_document_rebuild(doc, allocator)

	return true
}

text_document_splice_plain :: proc(
	doc: ^Text_Document,
	start, end: int,
	insert: string,
	allocator := context.allocator,
) -> bool {
	if !text_document_delete_range(doc, start, end, allocator) && start != end do return false

	return text_document_insert_plain(doc, start, insert, allocator)
}

text_document_copy_plain :: proc(doc: ^Text_Document, sel: Text_Selection) -> bool {
	return text_edit_copy_plain(doc.plain, sel)
}
