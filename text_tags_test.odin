package oni

import "core:os"
import "core:sync"
import "core:testing"

@(private)
with_text_tag_font_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	if !os.exists(INTER_FONT_FIXTURE) || !os.exists(INTER_ITALIC_FONT_FIXTURE) {
		testing.expectf(
			t,
			false,
			"missing font fixtures; expected %s",
			INTER_FONT_FIXTURE,
		)
		return
	}

	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	test_state: State
	test_theme := Theme {
		font_body = {id = 0, size_px = 16},
		font_heading = {id = 0, size_px = 24},
	}
	saved_state := state
	saved_theme := theme
	defer {
		state = saved_state
		theme = saved_theme
	}

	state = &test_state
	theme = &test_theme

	testing.expect(t, font_init())
	defer font_shutdown()

	inter, inter_ok := font_register_family(
		"InterTagTest",
		{
			{path = INTER_FONT_FIXTURE, style = .NORMAL, weight = .Normal},
			{path = INTER_ITALIC_FONT_FIXTURE, style = .ITALIC, weight = .Normal},
		},
	)
	testing.expect(t, inter_ok)
	test_theme.font_body = font_with_size(inter, 16)
	test_theme.font_heading = font_with_size(inter, 24)

	body(t)
}

@(test)
text_tags_parse_plain_text :: proc(t: ^testing.T) {
	parsed := text_tags_parse("Hello world", context.temp_allocator)
	testing.expect_value(t, parsed.plain, "Hello world")
	testing.expect(t, len(parsed.runs) == 1)
	testing.expect_value(t, parsed.runs[0].text, "Hello world")
}

@(test)
text_tags_parse_color_and_style :: proc(t: ^testing.T) {
	source := "{c:accent}Accent{/c}{b}Bold{/b}{i}Italic{/i}{u}Line{/u}"
	parsed := text_tags_parse(source, context.temp_allocator)
	testing.expect_value(t, parsed.plain, "AccentBoldItalicLine")
	testing.expect(t, len(parsed.runs) == 4)
	testing.expect(t, text_run_style_has(parsed.runs[0].style, .color))
	testing.expect(t, parsed.runs[0].style.color == .ACCENT)
	testing.expect(t, text_run_style_has(parsed.runs[1].style, .font_weight))
	testing.expect(t, parsed.runs[1].style.font_weight == .Bold)
	testing.expect(t, text_run_style_has(parsed.runs[2].style, .font_style))
	testing.expect(t, parsed.runs[2].style.font_style == .ITALIC)
	testing.expect(t, text_run_style_has(parsed.runs[3].style, .text_decoration))
	testing.expect(t, .UNDERLINE in parsed.runs[3].style.text_decoration)
}

@(test)
text_tags_parse_widget_style_fields :: proc(t: ^testing.T) {
	source := "{font_size:20}Size{/font_size}{opacity:0.5}Fade{/opacity}{text_decoration_style:dotted}Dot{/text_decoration_style}"
	parsed := text_tags_parse(source, context.temp_allocator)
	testing.expect_value(t, parsed.plain, "SizeFadeDot")
	testing.expect(t, len(parsed.runs) == 3)
	testing.expect(t, parsed.runs[0].style.font_size == 20)
	testing.expect(t, parsed.runs[1].style.opacity == 0.5)
	testing.expect(t, parsed.runs[2].style.text_decoration_style == .DOTTED)
}

@(test)
text_tags_parse_literal_brace_escape :: proc(t: ^testing.T) {
	parsed := text_tags_parse(`brace: \{ literal`, context.temp_allocator)
	testing.expect_value(t, parsed.plain, "brace: { literal")
}

@(test)
text_tags_unknown_tag_stays_literal :: proc(t: ^testing.T) {
	parsed := text_tags_parse("{unknown}", context.temp_allocator)
	testing.expect_value(t, parsed.plain, "{unknown}")
}

@(test)
text_runs_to_layout_ranges :: proc(t: ^testing.T) {
	style_a := TEXT_RUN_STYLE_DEFAULT
	style_a.fields = {.color}
	style_a.color = .ACCENT
	style_b := TEXT_RUN_STYLE_DEFAULT
	style_b.fields = {.font_weight}
	style_b.font_weight = .Bold

	runs := []Text_Run {
		{text = "A", style = style_a},
		{text = "B", style = style_b},
	}
	plain, layout := text_runs_to_layout(runs, context.temp_allocator)
	testing.expect_value(t, plain, "AB")
	testing.expect(t, len(layout) == 2)
	testing.expect_value(t, layout[0].start, 0)
	testing.expect_value(t, layout[0].end, 1)
	testing.expect_value(t, layout[1].start, 1)
	testing.expect_value(t, layout[1].end, 2)
}

@(test)
text_tags_parse_font_family_and_size :: proc(t: ^testing.T) {
	with_text_tag_font_env(t, proc(t: ^testing.T) {
		parsed := text_tags_parse("{font:InterTagTest:20}Sized{/font}", context.temp_allocator)
		testing.expect_value(t, parsed.plain, "Sized")
		testing.expect(t, len(parsed.runs) == 1)
		testing.expect(t, text_run_style_has(parsed.runs[0].style, .font))
		testing.expect(t, parsed.runs[0].style.font.size_px == 20)
		testing.expect(t, parsed.runs[0].style.font.id == theme.font_body.id)
	})
}

@(test)
text_tags_parse_font_theme_alias :: proc(t: ^testing.T) {
	with_text_tag_font_env(t, proc(t: ^testing.T) {
		parsed := text_tags_parse("{font:heading}Title{/font}", context.temp_allocator)
		testing.expect_value(t, parsed.plain, "Title")
		testing.expect(t, len(parsed.runs) == 1)
		testing.expect(t, text_run_style_has(parsed.runs[0].style, .font))
		testing.expect(t, parsed.runs[0].style.font.id == theme.font_heading.id)
		testing.expect(t, parsed.runs[0].style.font.size_px == 24)
	})
}

@(test)
font_family_by_name_resolves_registered_family :: proc(t: ^testing.T) {
	with_text_tag_font_env(t, proc(t: ^testing.T) {
		handle, ok := font_family_by_name("intertagtest")
		testing.expect(t, ok)
		testing.expect(t, handle.id == theme.font_body.id)
	})
}
