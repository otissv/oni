package colors

import "core:testing"

rgba_channel_delta :: proc(a, b: RGBA) -> int {
	return max(
		abs(int(a.r) - int(b.r)),
		max(abs(int(a.g) - int(b.g)), abs(int(a.b) - int(b.b))),
	)
}

expect_rgba_exact :: proc(t: ^testing.T, got, want: RGBA, note: string, loc := #caller_location) {
	testing.expectf(t, got == want, "%s: got=%v want=%v", note, got, want, loc = loc)
}

expect_rgba_within :: proc(
	t: ^testing.T,
	got, want: RGBA,
	slack: int,
	note: string,
	loc := #caller_location,
) {
	testing.expectf(
		t,
		rgba_channel_delta(got, want) <= slack && got.a == want.a,
		"%s: got=%v want=%v slack=%d delta=%d",
		note,
		got,
		want,
		slack,
		rgba_channel_delta(got, want),
		loc = loc,
	)
}

/*
Every Tailwind shade in the package palette must match ColorAide conversion of the
official theme.css OKLCH token (exact sRGB bytes).
*/
@(test)
test_external_tailwind_palette_rgb_goldens :: proc(t: ^testing.T) {
	testing.expect_value(t, len(TAILWIND_SHADE_GOLDENS), 286)
	seen: [Color]bool
	for g in TAILWIND_SHADE_GOLDENS {
		testing.expectf(t, !seen[g.color], "duplicate golden for %v", g.color)
		seen[g.color] = true
		expect_rgba_exact(
			t,
			palette[g.color],
			g.rgb,
			"palette entry vs ColorAide/Tailwind golden",
		)
		expect_rgba_exact(
			t,
			css_color_to_rgba(g.color),
			g.rgb,
			"css_color_to_rgba vs ColorAide/Tailwind golden",
		)
	}
}

/*
Official Tailwind OKLCH tokens converted through this package must land on the
same sRGB bytes as ColorAide (allow ±1 for f32 rounding).
*/
@(test)
test_external_tailwind_oklch_via_package_converter :: proc(t: ^testing.T) {
	for g in TAILWIND_SHADE_GOLDENS {
		got := oklcha_to_rgba(g.oklch)
		expect_rgba_within(
			t,
			got,
			g.rgb,
			1,
			"oklcha_to_rgba(theme OKLCH) vs ColorAide/Tailwind RGB",
		)
	}
}

@(test)
test_external_black_white_tokens :: proc(t: ^testing.T) {
	expect_rgba_exact(t, palette[.BLACK], RGBA{0, 0, 0, 255}, "Tailwind/CSS black")
	expect_rgba_exact(t, palette[.WHITE], RGBA{255, 255, 255, 255}, "Tailwind/CSS white")
	expect_rgba_exact(t, palette[.TRANSPARENT], RGBA{0, 0, 0, 0}, "transparent")
}

/*
Frozen Oni semantic theme tokens (not Tailwind shades). Guards against accidental edits.
*/
@(test)
test_external_semantic_theme_token_goldens :: proc(t: ^testing.T) {
	Semantic_Golden :: struct {
		color: Color,
		rgb:   RGBA,
	}
	goldens := []Semantic_Golden {
		{.BACKGROUND, {45, 45, 48, 255}},
		{.FOREGROUND, {204, 204, 204, 255}},
		{.CARD, {45, 45, 48, 255}},
		{.CARD_FOREGROUND, {204, 204, 204, 255}},
		{.POPOVER, {45, 45, 48, 255}},
		{.POPOVER_FOREGROUND, {204, 204, 204, 255}},
		{.PRIMARY, {0, 120, 212, 255}},
		{.PRIMARY_FOREGROUND, {255, 255, 255, 255}},
		{.PRIMARY_HOVER, {36, 84, 121, 255}},
		{.PRIMARY_PRESSED, {36, 120, 255, 255}},
		{.SECONDARY, {60, 60, 60, 255}},
		{.SECONDARY_HOVER, {60, 60, 60, 255}},
		{.SECONDARY_PRESSED, {60, 60, 60, 255}},
		{.SECONDARY_FOREGROUND, {204, 204, 204, 255}},
		{.MUTED, {60, 60, 60, 255}},
		{.MUTED_FOREGROUND, {150, 150, 150, 255}},
		{.ACCENT, {64, 64, 64, 255}},
		{.ACCENT_FOREGROUND, {204, 204, 204, 255}},
		{.ACCENT_HOVER, {64, 64, 64, 255}},
		{.ACCENT_PRESSED, {64, 64, 64, 255}},
		{.DESTRUCTIVE, {204, 38, 46, 255}},
		{.DESTRUCTIVE_FOREGROUND, {255, 255, 255, 255}},
		{.DESTRUCTIVE_HOVER, {204, 38, 46, 255}},
		{.DESTRUCTIVE_PRESSED, {204, 38, 46, 255}},
		{.SUCCESS, {5, 137, 62, 255}},
		{.SUCCESS_FOREGROUND, {255, 255, 255, 255}},
		{.SUCCESS_HOVER, {5, 137, 62, 255}},
		{.SUCCESS_PRESSED, {5, 137, 62, 255}},
		{.INFO, {15, 116, 197, 255}},
		{.INFO_FOREGROUND, {255, 255, 255, 255}},
		{.INFO_HOVER, {15, 116, 197, 255}},
		{.INFO_PRESSED, {15, 116, 197, 255}},
		{.WARNING, {206, 146, 0, 255}},
		{.WARNING_FOREGROUND, {22, 22, 22, 255}},
		{.WARNING_HOVER, {206, 146, 0, 255}},
		{.WARNING_PRESSED, {206, 146, 0, 255}},
		{.BORDER, {64, 64, 64, 255}},
		{.INPUT, {64, 64, 64, 255}},
		{.RING, {0, 120, 212, 255}},
		{.SIDEBAR, {23, 23, 23, 255}},
		{.SIDEBAR_FOREGROUND, {250, 250, 250, 255}},
		{.SIDEBAR_PRIMARY, {20, 71, 230, 255}},
		{.SIDEBAR_PRIMARY_FOREGROUND, {250, 250, 250, 255}},
		{.SIDEBAR_ACCENT, {38, 38, 38, 255}},
		{.SIDEBAR_ACCENT_FOREGROUND, {250, 250, 250, 255}},
		{.SIDEBAR_BORDER, {255, 255, 255, 26}},
		{.SIDEBAR_RING, {115, 115, 115, 255}},
	}
	for g in goldens {
		expect_rgba_exact(t, palette[g.color], g.rgb, "semantic theme token")
	}
}

/*
WPT CSS Color Level 4 OKLCH -> sRGB reference vectors.
*/
@(test)
test_external_wpt_oklch_goldens :: proc(t: ^testing.T) {
	for g in WPT_OKLCH_GOLDENS {
		got := oklcha_to_rgba(g.input)
		expect_rgba_exact(t, got, g.rgb, g.note)
		expect_rgba_exact(t, to_rgba_color(g.input), g.rgb, g.note)
		expect_f32x4(t, color_to_f32(g.input), rgba_to_f32(g.rgb), 1e-4)
	}
}

/*
CIE Lab LCH with D65 white point (ColorAide lch-d65), matching this package.
*/
@(test)
test_external_lch_d65_goldens :: proc(t: ^testing.T) {
	for g in LCH_D65_GOLDENS {
		got := lcha_to_rgba(g.input)
		expect_rgba_within(t, got, g.rgb, 1, g.note)
		expect_rgba_within(t, to_rgba_color(g.input), g.rgb, 1, g.note)
	}
}

/*
CSS Color 4 / WPT lch() uses D50 Lab. This package uses D65. Assert the known
divergence so a silent switch to D50 (or accidental match) is visible.
*/
@(test)
test_external_css_color4_lch_d50_diverges_from_d65_path :: proc(t: ^testing.T) {
	for g in CSS_COLOR4_LCH_D50_WPT {
		got := lcha_to_rgba(g.input)
		testing.expectf(
			t,
			got != g.css_rgb,
			"%s: D65 path unexpectedly equals CSS D50 WPT rgb=%v",
			g.note,
			got,
		)
		// Still a nearby red/magenta or cyan — not garbage.
		testing.expectf(
			t,
			rgba_channel_delta(got, g.css_rgb) <= 20,
			"%s: D65 vs D50 delta too large got=%v css=%v delta=%d",
			g.note,
			got,
			g.css_rgb,
			rgba_channel_delta(got, g.css_rgb),
		)
	}
}

@(test)
test_external_hsl_css_goldens :: proc(t: ^testing.T) {
	for g in HSL_GOLDENS {
		expect_rgba_exact(t, hsla_to_rgba(g.input), g.rgb, g.note)
		expect_rgba_exact(t, to_rgba_color(g.input), g.rgb, g.note)
	}
}

@(test)
test_external_hwb_css_wpt_goldens :: proc(t: ^testing.T) {
	for g in HWB_GOLDENS {
		expect_rgba_exact(t, hwba_to_rgba(g.input), g.rgb, g.note)
		expect_rgba_exact(t, to_rgba_color(g.input), g.rgb, g.note)
	}
}

/*
MDN / CSS Color 4: sRGB red is approximately oklch(0.628 0.258 29.234).
*/
@(test)
test_external_oklch_srgb_red_mdn :: proc(t: ^testing.T) {
	got := oklcha_to_rgba({0.627966, 0.257704, 29.2346, 1})
	expect_rgba_within(t, got, RGBA{255, 0, 0, 255}, 2, "MDN oklch of hsl(0 100% 50%)")
}

/*
Independent sRGB primary round-trips through OKLCH via ColorAide-derived LCH/OKLCH coords
are covered above; also check hex packing against CSS #RRGGBBAA semantics.
*/
@(test)
test_external_hex_css_rrggbbaa :: proc(t: ^testing.T) {
	expect_rgba_exact(t, hex_to_rgba(Hex(0xFF0000FF)), RGBA{255, 0, 0, 255}, "#FF0000FF")
	expect_rgba_exact(t, hex_to_rgba(Hex(0x008000FF)), RGBA{0, 128, 0, 255}, "#008000FF")
	expect_rgba_exact(t, hex_to_rgba(Hex(0x0000FFFF)), RGBA{0, 0, 255, 255}, "#0000FFFF")
	expect_f32x4(t, color_to_f32(Hex(0x008000FF)), rgba_to_f32({0, 128, 0, 255}))
}
