package colors

import "core:math"
import "core:testing"

expect_close :: proc(t: ^testing.T, got, want: f32, epsilon: f32 = 1e-5, loc := #caller_location) {
	testing.expectf(
		t,
		abs(got - want) <= epsilon,
		"got=%v want=%v epsilon=%v",
		got,
		want,
		epsilon,
		loc = loc,
	)
}

expect_rgba :: proc(t: ^testing.T, got, want: RGBA, loc := #caller_location) {
	testing.expectf(
		t,
		got == want,
		"got=%v want=%v",
		got,
		want,
		loc = loc,
	)
}

expect_rgba_near :: proc(t: ^testing.T, got, want: RGBA, slack: u8 = 1, loc := #caller_location) {
	ok :=
		abs(i32(got.r) - i32(want.r)) <= i32(slack) &&
		abs(i32(got.g) - i32(want.g)) <= i32(slack) &&
		abs(i32(got.b) - i32(want.b)) <= i32(slack) &&
		got.a == want.a
	testing.expectf(
		t,
		ok,
		"got=%v want=%v slack=%v",
		got,
		want,
		slack,
		loc = loc,
	)
}

expect_f32x4 :: proc(t: ^testing.T, got, want: [4]f32, epsilon: f32 = 1e-5, loc := #caller_location) {
	ok :=
		abs(got[0] - want[0]) <= epsilon &&
		abs(got[1] - want[1]) <= epsilon &&
		abs(got[2] - want[2]) <= epsilon &&
		abs(got[3] - want[3]) <= epsilon
	testing.expectf(
		t,
		ok,
		"got=%v want=%v epsilon=%v",
		got,
		want,
		epsilon,
		loc = loc,
	)
}

expect_vec3_close :: proc(t: ^testing.T, got, want: [3]f32, epsilon: f32 = 1e-5, loc := #caller_location) {
	ok :=
		abs(got[0] - want[0]) <= epsilon &&
		abs(got[1] - want[1]) <= epsilon &&
		abs(got[2] - want[2]) <= epsilon
	testing.expectf(
		t,
		ok,
		"got=%v want=%v epsilon=%v",
		got,
		want,
		epsilon,
		loc = loc,
	)
}

@(test)
test_color_clamp01 :: proc(t: ^testing.T) {
	expect_close(t, color_clamp01(0), 0)
	expect_close(t, color_clamp01(1), 1)
	expect_close(t, color_clamp01(0.5), 0.5)
	expect_close(t, color_clamp01(-0.25), 0)
	expect_close(t, color_clamp01(1.25), 1)
	expect_close(t, color_clamp01(-100), 0)
	expect_close(t, color_clamp01(100), 1)
	expect_close(t, color_clamp01(math.inf_f32(1)), 1)
	expect_close(t, color_clamp01(math.inf_f32(-1)), 0)
}

@(test)
test_color_u8_from01 :: proc(t: ^testing.T) {
	testing.expect_value(t, color_u8_from01(0), u8(0))
	testing.expect_value(t, color_u8_from01(1), u8(255))
	testing.expect_value(t, color_u8_from01(0.5), u8(128))
	testing.expect_value(t, color_u8_from01(-1), u8(0))
	testing.expect_value(t, color_u8_from01(2), u8(255))
	// 254.5/255 rounds to 255 after clamp path; mid-high channel
	testing.expect_value(t, color_u8_from01(254.0 / 255.0), u8(254))
	testing.expect_value(t, color_u8_from01(1.0 / 255.0), u8(1))
}

@(test)
test_color_linear_to_srgb :: proc(t: ^testing.T) {
	expect_close(t, color_linear_to_srgb(0), 0)
	expect_close(t, color_linear_to_srgb(1), 1, 1e-6)

	// Linear segment at and below the IEC 61966-2-1 threshold.
	threshold :: f32(0.0031308)
	expect_close(t, color_linear_to_srgb(threshold), 12.92 * threshold)
	expect_close(t, color_linear_to_srgb(threshold * 0.5), 12.92 * threshold * 0.5)
	expect_close(t, color_linear_to_srgb(0.001), 12.92 * 0.001)

	// Gamma branch just above the threshold.
	above := threshold + 1e-7
	want_above := 1.055 * math.pow(above, 1.0 / 2.4) - 0.055
	expect_close(t, color_linear_to_srgb(above), want_above, 1e-6)
	expect_close(t, color_linear_to_srgb(0.5), 1.055 * math.pow(f32(0.5), 1.0 / 2.4) - 0.055, 1e-6)
}

@(test)
test_color_hue_to_rgb_sectors :: proc(t: ^testing.T) {
	expect_vec3_close(t, color_hue_to_rgb(0), {1, 0, 0})
	expect_vec3_close(t, color_hue_to_rgb(30), {1, 0.5, 0})
	expect_vec3_close(t, color_hue_to_rgb(60), {1, 1, 0})
	expect_vec3_close(t, color_hue_to_rgb(90), {0.5, 1, 0})
	expect_vec3_close(t, color_hue_to_rgb(120), {0, 1, 0})
	expect_vec3_close(t, color_hue_to_rgb(150), {0, 1, 0.5})
	expect_vec3_close(t, color_hue_to_rgb(180), {0, 1, 1})
	expect_vec3_close(t, color_hue_to_rgb(210), {0, 0.5, 1})
	expect_vec3_close(t, color_hue_to_rgb(240), {0, 0, 1})
	expect_vec3_close(t, color_hue_to_rgb(270), {0.5, 0, 1})
	expect_vec3_close(t, color_hue_to_rgb(300), {1, 0, 1})
	expect_vec3_close(t, color_hue_to_rgb(330), {1, 0, 0.5})
}

@(test)
test_color_hue_to_rgb_wrap :: proc(t: ^testing.T) {
	expect_vec3_close(t, color_hue_to_rgb(360), color_hue_to_rgb(0))
	expect_vec3_close(t, color_hue_to_rgb(420), color_hue_to_rgb(60))
	expect_vec3_close(t, color_hue_to_rgb(-60), color_hue_to_rgb(300))
	expect_vec3_close(t, color_hue_to_rgb(-360), color_hue_to_rgb(0))
	expect_vec3_close(t, color_hue_to_rgb(720), color_hue_to_rgb(0))
}

@(test)
test_color_hue_to_channel_branches :: proc(t: ^testing.T) {
	p: f32 = 0.2
	q: f32 = 0.8

	// t in [0, 1/6)
	expect_close(t, color_hue_to_channel(p, q, 0), p)
	expect_close(t, color_hue_to_channel(p, q, 1.0 / 12), p + (q - p) * 6 * (1.0 / 12))

	// t in [1/6, 1/2)
	expect_close(t, color_hue_to_channel(p, q, 1.0 / 6), q)
	expect_close(t, color_hue_to_channel(p, q, 0.25), q)
	expect_close(t, color_hue_to_channel(p, q, 0.49), q)

	// t in [1/2, 2/3)
	expect_close(t, color_hue_to_channel(p, q, 0.5), q)
	t_mid := f32(0.6)
	expect_close(t, color_hue_to_channel(p, q, t_mid), p + (q - p) * (2.0 / 3 - t_mid) * 6)

	// t in [2/3, 1)
	expect_close(t, color_hue_to_channel(p, q, 2.0 / 3), p)
	expect_close(t, color_hue_to_channel(p, q, 0.9), p)

	// Wrap positive and negative offsets into [0, 1).
	expect_close(t, color_hue_to_channel(p, q, 1.25), color_hue_to_channel(p, q, 0.25))
	expect_close(t, color_hue_to_channel(p, q, -0.1), color_hue_to_channel(p, q, 0.9))
}

@(test)
test_hex_to_rgba :: proc(t: ^testing.T) {
	expect_rgba(t, hex_to_rgba(Hex(0xFF0000FF)), RGBA{255, 0, 0, 255})
	expect_rgba(t, hex_to_rgba(Hex(0x00FF0080)), RGBA{0, 255, 0, 128})
	expect_rgba(t, hex_to_rgba(Hex(0x0000FF00)), RGBA{0, 0, 255, 0})
	expect_rgba(t, hex_to_rgba(Hex(0x12345678)), RGBA{0x12, 0x34, 0x56, 0x78})
	expect_rgba(t, hex_to_rgba(Hex(0)), RGBA{0, 0, 0, 0})
	expect_rgba(t, hex_to_rgba(Hex(0xFFFFFFFF)), RGBA{255, 255, 255, 255})
}

@(test)
test_rgba_to_rgba_identity :: proc(t: ^testing.T) {
	c := RGBA{10, 20, 30, 40}
	expect_rgba(t, rgba_to_rgba(c), c)
	expect_rgba(t, rgba_to_rgba({}), {})
}

@(test)
test_rgba_to_f32 :: proc(t: ^testing.T) {
	expect_f32x4(t, rgba_to_f32({}), {0, 0, 0, 0})
	expect_f32x4(t, rgba_to_f32({255, 255, 255, 255}), {1, 1, 1, 1})
	expect_f32x4(t, rgba_to_f32({0, 0, 0, 255}), {0, 0, 0, 1})
	expect_f32x4(t, rgba_to_f32({128, 64, 32, 16}), {128.0 / 255, 64.0 / 255, 32.0 / 255, 16.0 / 255})
}

@(test)
test_hsla_to_rgba_primaries_and_grays :: proc(t: ^testing.T) {
	expect_rgba(t, hsla_to_rgba({0, 1, 0.5, 1}), RGBA{255, 0, 0, 255})
	expect_rgba(t, hsla_to_rgba({120, 1, 0.5, 1}), RGBA{0, 255, 0, 255})
	expect_rgba(t, hsla_to_rgba({240, 1, 0.5, 1}), RGBA{0, 0, 255, 255})
	expect_rgba(t, hsla_to_rgba({60, 1, 0.5, 1}), RGBA{255, 255, 0, 255})
	expect_rgba(t, hsla_to_rgba({180, 1, 0.5, 1}), RGBA{0, 255, 255, 255})
	expect_rgba(t, hsla_to_rgba({300, 1, 0.5, 1}), RGBA{255, 0, 255, 255})

	expect_rgba(t, hsla_to_rgba({0, 0, 1, 1}), RGBA{255, 255, 255, 255})
	expect_rgba(t, hsla_to_rgba({0, 0, 0, 1}), RGBA{0, 0, 0, 255})
	expect_rgba(t, hsla_to_rgba({0, 0, 0.5, 1}), RGBA{128, 128, 128, 255})
	expect_rgba(t, hsla_to_rgba({90, 0, 0.25, 0.5}), RGBA{64, 64, 64, 128})
}

@(test)
test_hsla_to_rgba_clamping_and_q_branches :: proc(t: ^testing.T) {
	// Saturation / lightness / alpha out of range are clamped.
	expect_rgba(t, hsla_to_rgba({0, 2, 0.5, 2}), RGBA{255, 0, 0, 255})
	expect_rgba(t, hsla_to_rgba({0, -1, 0.5, -1}), RGBA{128, 128, 128, 0})

	// l < 0.5 uses q = l*(1+s); l >= 0.5 uses q = l+s-l*s.
	dark := hsla_to_rgba({0, 1, 0.25, 1})
	light := hsla_to_rgba({0, 1, 0.75, 1})
	testing.expect(t, dark.r > dark.g && dark.r > dark.b)
	testing.expect(t, light.r > light.g && light.r > light.b)
	testing.expect(t, light.r >= dark.r)
}

@(test)
test_hwba_to_rgba :: proc(t: ^testing.T) {
	expect_rgba(t, hwba_to_rgba({0, 0, 0, 1}), RGBA{255, 0, 0, 255})
	expect_rgba(t, hwba_to_rgba({120, 0, 0, 1}), RGBA{0, 255, 0, 255})
	expect_rgba(t, hwba_to_rgba({240, 0, 0, 1}), RGBA{0, 0, 255, 255})
	expect_rgba(t, hwba_to_rgba({0, 1, 0, 1}), RGBA{255, 255, 255, 255})
	expect_rgba(t, hwba_to_rgba({0, 0, 1, 1}), RGBA{0, 0, 0, 255})

	// w + b >= 1 collapses to gray from w/(w+b).
	expect_rgba(t, hwba_to_rgba({0, 0.5, 0.5, 1}), RGBA{128, 128, 128, 255})
	expect_rgba(t, hwba_to_rgba({90, 0.75, 0.25, 0.25}), RGBA{191, 191, 191, 64})
	expect_rgba(t, hwba_to_rgba({180, 0.8, 0.8, 1}), RGBA{128, 128, 128, 255})

	// Clamping of w/b/a.
	expect_rgba(t, hwba_to_rgba({0, 2, -1, 2}), RGBA{255, 255, 255, 255})

	// Partial mix: white lifted red.
	mixed := hwba_to_rgba({0, 0.25, 0, 1})
	testing.expect(t, mixed.r == 255)
	testing.expect(t, mixed.g == mixed.b)
	testing.expect(t, mixed.g > 0 && mixed.g < 255)
}

@(test)
test_lcha_to_rgba :: proc(t: ^testing.T) {
	// Neutral axis (C=0) — CIE Lab D65 → sRGB (ColorAide lch-d65).
	expect_rgba(t, lcha_to_rgba({0, 0, 0, 1}), RGBA{0, 0, 0, 255})
	expect_rgba(t, lcha_to_rgba({100, 0, 0, 1}), RGBA{255, 255, 255, 255})
	expect_rgba(t, lcha_to_rgba({50, 0, 0, 1}), RGBA{119, 119, 119, 255})

	// Negative chroma clamps to achromatic.
	expect_rgba(t, lcha_to_rgba({50, -10, 180, 1}), RGBA{119, 119, 119, 255})

	// L clamps to [0, 100].
	expect_rgba(t, lcha_to_rgba({150, 0, 0, 1}), RGBA{255, 255, 255, 255})
	expect_rgba(t, lcha_to_rgba({-20, 0, 0, 0.5}), RGBA{0, 0, 0, 128})

	// Chromatic sample: should not be neutral.
	chromatic := lcha_to_rgba({50, 40, 30, 1})
	testing.expect(t, chromatic.r != chromatic.g || chromatic.g != chromatic.b)
	testing.expect_value(t, chromatic.a, u8(255))
}

@(test)
test_oklcha_to_rgba :: proc(t: ^testing.T) {
	expect_rgba(t, oklcha_to_rgba({0, 0, 0, 1}), RGBA{0, 0, 0, 255})
	expect_rgba(t, oklcha_to_rgba({1, 0, 0, 1}), RGBA{255, 255, 255, 255})
	expect_rgba(t, oklcha_to_rgba({0.5, 0, 0, 1}), RGBA{99, 99, 99, 255})

	// Negative chroma → achromatic.
	expect_rgba(t, oklcha_to_rgba({0.5, -1, 90, 1}), RGBA{99, 99, 99, 255})

	// L clamped.
	expect_rgba(t, oklcha_to_rgba({2, 0, 0, 1}), RGBA{255, 255, 255, 255})
	expect_rgba(t, oklcha_to_rgba({-1, 0, 0, 0}), RGBA{0, 0, 0, 0})

	// Approximate pure red in OKLCH.
	expect_rgba_near(t, oklcha_to_rgba({0.628, 0.2577, 29.234, 1}), RGBA{255, 0, 0, 255}, 2)

	chromatic := oklcha_to_rgba({0.7, 0.15, 140, 1})
	testing.expect(t, chromatic.r != chromatic.g || chromatic.g != chromatic.b)
}

@(test)
test_css_color_to_rgba_and_alias :: proc(t: ^testing.T) {
	expect_rgba(t, css_color_to_rgba(.INVALID), {})
	expect_rgba(t, css_color_to_rgba(.INHERIT), {})
	expect_rgba(t, css_color_to_rgba(.TRANSPARENT), RGBA{0, 0, 0, 0})
	expect_rgba(t, css_color_to_rgba(.BLACK), RGBA{0, 0, 0, 255})
	expect_rgba(t, css_color_to_rgba(.WHITE), RGBA{255, 255, 255, 255})
	expect_rgba(t, css_color_to_rgba(.RED_500), RGBA{251, 44, 54, 255})
	expect_rgba(t, css_color_to_rgba(.PRIMARY), RGBA{0, 120, 212, 255})
	expect_rgba(t, css_color_to_rgba(.SIDEBAR_BORDER), RGBA{255, 255, 255, 26})

	// Alias matches the direct lookup path.
	expect_rgba(t, css_color_to_rba(.BLUE_700), css_color_to_rgba(.BLUE_700))
	expect_rgba(t, css_color_to_rba(.INVALID), {})
}

@(test)
test_palette_complete_and_consistent :: proc(t: ^testing.T) {
	count := 0
	for c in Color {
		count += 1
		got := css_color_to_rgba(c)
		if c == .INVALID {
			expect_rgba(t, got, {})
			continue
		}
		expect_rgba(t, got, palette[c])
	}

	// Enum must stay in sync with the palette table size.
	testing.expect_value(t, count, len(Color))
	testing.expect_value(t, len(palette), len(Color))
}

@(test)
test_to_rgba_color_overload :: proc(t: ^testing.T) {
	expect_rgba(t, to_rgba_color(Color.GREEN_500), css_color_to_rgba(.GREEN_500))
	expect_rgba(t, to_rgba_color(RGBA{1, 2, 3, 4}), RGBA{1, 2, 3, 4})
	expect_rgba(t, to_rgba_color(Hex(0xAABBCCDD)), RGBA{0xAA, 0xBB, 0xCC, 0xDD})
	expect_rgba(t, to_rgba_color(HSLA{0, 1, 0.5, 1}), RGBA{255, 0, 0, 255})
	expect_rgba(t, to_rgba_color(HWBA{0, 0, 0, 1}), RGBA{255, 0, 0, 255})
	expect_rgba(t, to_rgba_color(LCHA{100, 0, 0, 1}), RGBA{255, 255, 255, 255})
	expect_rgba(t, to_rgba_color(OKLCHA{1, 0, 0, 1}), RGBA{255, 255, 255, 255})
}

@(test)
test_color_to_f32_all_variants :: proc(t: ^testing.T) {
	expect_f32x4(t, color_to_f32(Color.INVALID), {})
	expect_f32x4(t, color_to_f32(Color.BLACK), {0, 0, 0, 1})
	expect_f32x4(t, color_to_f32(Color.WHITE), {1, 1, 1, 1})
	expect_f32x4(t, color_to_f32(Color.RED_500), rgba_to_f32(palette[.RED_500]))

	expect_f32x4(t, color_to_f32(RGBA{255, 0, 0, 128}), {1, 0, 0, 128.0 / 255})
	expect_f32x4(t, color_to_f32(Hex(0x00FF00FF)), {0, 1, 0, 1})
	expect_f32x4(t, color_to_f32(HSLA{120, 1, 0.5, 1}), {0, 1, 0, 1})
	expect_f32x4(t, color_to_f32(HWBA{240, 0, 0, 1}), {0, 0, 1, 1})
	expect_f32x4(t, color_to_f32(LCHA{100, 0, 0, 1}), {1, 1, 1, 1})
	expect_f32x4(t, color_to_f32(OKLCHA{0, 0, 0, 1}), {0, 0, 0, 1})

	// Untagged / nil Colors falls through to zero.
	empty: Colors
	expect_f32x4(t, color_to_f32(empty), {})
}

@(test)
test_colors_union_roundtrip_consistency :: proc(t: ^testing.T) {
	// Each Colors variant path in color_to_f32 must match rgba_to_f32(to_rgba_color(...)).
	samples := []Colors {
		Color.PRIMARY,
		RGBA{40, 50, 60, 70},
		Hex(0x11223344),
		HSLA{200, 0.8, 0.4, 0.9},
		HWBA{45, 0.1, 0.2, 0.8},
		LCHA{70, 20, 100, 1},
		OKLCHA{0.6, 0.1, 250, 0.75},
	}
	for sample in samples {
		via_f32 := color_to_f32(sample)
		rgba: RGBA
		switch v in sample {
		case Color:
			rgba = to_rgba_color(v)
		case RGBA:
			rgba = to_rgba_color(v)
		case Hex:
			rgba = to_rgba_color(v)
		case HSLA:
			rgba = to_rgba_color(v)
		case HWBA:
			rgba = to_rgba_color(v)
		case LCHA:
			rgba = to_rgba_color(v)
		case OKLCHA:
			rgba = to_rgba_color(v)
		}
		expect_f32x4(t, via_f32, rgba_to_f32(rgba))
	}
}

@(test)
test_hex_endian_channel_order :: proc(t: ^testing.T) {
	// Documented packing is #RRGGBBAA (not ARGB / ABGR).
	c := hex_to_rgba(Hex(0xDEADC0DE))
	testing.expect_value(t, c.r, u8(0xDE))
	testing.expect_value(t, c.g, u8(0xAD))
	testing.expect_value(t, c.b, u8(0xC0))
	testing.expect_value(t, c.a, u8(0xDE))
}

@(test)
test_semantic_palette_spot_checks :: proc(t: ^testing.T) {
	expect_rgba(t, palette[.BACKGROUND], RGBA{45, 45, 48, 255})
	expect_rgba(t, palette[.FOREGROUND], RGBA{204, 204, 204, 255})
	expect_rgba(t, palette[.DESTRUCTIVE], RGBA{204, 38, 46, 255})
	expect_rgba(t, palette[.SUCCESS], RGBA{5, 137, 62, 255})
	expect_rgba(t, palette[.WARNING], RGBA{206, 146, 0, 255})
	expect_rgba(t, palette[.INFO], RGBA{15, 116, 197, 255})
	expect_rgba(t, palette[.TAUPE_950], RGBA{12, 10, 9, 255})
	expect_rgba(t, palette[.MIST_50], RGBA{249, 251, 251, 255})
	expect_rgba(t, palette[.OLIVE_500], RGBA{124, 124, 103, 255})
	expect_rgba(t, palette[.MAUVE_400], RGBA{168, 158, 169, 255})
}

@(test)
test_tailwind_shade_ladders_monotonic :: proc(t: ^testing.T) {
	// Each Tailwind family lists shades from light (50) to dark (950).
	ladders := [][11]Color {
		{.RED_50, .RED_100, .RED_200, .RED_300, .RED_400, .RED_500, .RED_600, .RED_700, .RED_800, .RED_900, .RED_950},
		{.ORANGE_50, .ORANGE_100, .ORANGE_200, .ORANGE_300, .ORANGE_400, .ORANGE_500, .ORANGE_600, .ORANGE_700, .ORANGE_800, .ORANGE_900, .ORANGE_950},
		{.AMBER_50, .AMBER_100, .AMBER_200, .AMBER_300, .AMBER_400, .AMBER_500, .AMBER_600, .AMBER_700, .AMBER_800, .AMBER_900, .AMBER_950},
		{.YELLOW_50, .YELLOW_100, .YELLOW_200, .YELLOW_300, .YELLOW_400, .YELLOW_500, .YELLOW_600, .YELLOW_700, .YELLOW_800, .YELLOW_900, .YELLOW_950},
		{.LIME_50, .LIME_100, .LIME_200, .LIME_300, .LIME_400, .LIME_500, .LIME_600, .LIME_700, .LIME_800, .LIME_900, .LIME_950},
		{.GREEN_50, .GREEN_100, .GREEN_200, .GREEN_300, .GREEN_400, .GREEN_500, .GREEN_600, .GREEN_700, .GREEN_800, .GREEN_900, .GREEN_950},
		{.EMERALD_50, .EMERALD_100, .EMERALD_200, .EMERALD_300, .EMERALD_400, .EMERALD_500, .EMERALD_600, .EMERALD_700, .EMERALD_800, .EMERALD_900, .EMERALD_950},
		{.TEAL_50, .TEAL_100, .TEAL_200, .TEAL_300, .TEAL_400, .TEAL_500, .TEAL_600, .TEAL_700, .TEAL_800, .TEAL_900, .TEAL_950},
		{.CYAN_50, .CYAN_100, .CYAN_200, .CYAN_300, .CYAN_400, .CYAN_500, .CYAN_600, .CYAN_700, .CYAN_800, .CYAN_900, .CYAN_950},
		{.SKY_50, .SKY_100, .SKY_200, .SKY_300, .SKY_400, .SKY_500, .SKY_600, .SKY_700, .SKY_800, .SKY_900, .SKY_950},
		{.BLUE_50, .BLUE_100, .BLUE_200, .BLUE_300, .BLUE_400, .BLUE_500, .BLUE_600, .BLUE_700, .BLUE_800, .BLUE_900, .BLUE_950},
		{.INDIGO_50, .INDIGO_100, .INDIGO_200, .INDIGO_300, .INDIGO_400, .INDIGO_500, .INDIGO_600, .INDIGO_700, .INDIGO_800, .INDIGO_900, .INDIGO_950},
		{.VIOLET_50, .VIOLET_100, .VIOLET_200, .VIOLET_300, .VIOLET_400, .VIOLET_500, .VIOLET_600, .VIOLET_700, .VIOLET_800, .VIOLET_900, .VIOLET_950},
		{.PURPLE_50, .PURPLE_100, .PURPLE_200, .PURPLE_300, .PURPLE_400, .PURPLE_500, .PURPLE_600, .PURPLE_700, .PURPLE_800, .PURPLE_900, .PURPLE_950},
		{.FUCHSIA_50, .FUCHSIA_100, .FUCHSIA_200, .FUCHSIA_300, .FUCHSIA_400, .FUCHSIA_500, .FUCHSIA_600, .FUCHSIA_700, .FUCHSIA_800, .FUCHSIA_900, .FUCHSIA_950},
		{.PINK_50, .PINK_100, .PINK_200, .PINK_300, .PINK_400, .PINK_500, .PINK_600, .PINK_700, .PINK_800, .PINK_900, .PINK_950},
		{.ROSE_50, .ROSE_100, .ROSE_200, .ROSE_300, .ROSE_400, .ROSE_500, .ROSE_600, .ROSE_700, .ROSE_800, .ROSE_900, .ROSE_950},
		{.SLATE_50, .SLATE_100, .SLATE_200, .SLATE_300, .SLATE_400, .SLATE_500, .SLATE_600, .SLATE_700, .SLATE_800, .SLATE_900, .SLATE_950},
		{.GRAY_50, .GRAY_100, .GRAY_200, .GRAY_300, .GRAY_400, .GRAY_500, .GRAY_600, .GRAY_700, .GRAY_800, .GRAY_900, .GRAY_950},
		{.ZINC_50, .ZINC_100, .ZINC_200, .ZINC_300, .ZINC_400, .ZINC_500, .ZINC_600, .ZINC_700, .ZINC_800, .ZINC_900, .ZINC_950},
		{.NEUTRAL_50, .NEUTRAL_100, .NEUTRAL_200, .NEUTRAL_300, .NEUTRAL_400, .NEUTRAL_500, .NEUTRAL_600, .NEUTRAL_700, .NEUTRAL_800, .NEUTRAL_900, .NEUTRAL_950},
		{.STONE_50, .STONE_100, .STONE_200, .STONE_300, .STONE_400, .STONE_500, .STONE_600, .STONE_700, .STONE_800, .STONE_900, .STONE_950},
		{.MAUVE_50, .MAUVE_100, .MAUVE_200, .MAUVE_300, .MAUVE_400, .MAUVE_500, .MAUVE_600, .MAUVE_700, .MAUVE_800, .MAUVE_900, .MAUVE_950},
		{.OLIVE_50, .OLIVE_100, .OLIVE_200, .OLIVE_300, .OLIVE_400, .OLIVE_500, .OLIVE_600, .OLIVE_700, .OLIVE_800, .OLIVE_900, .OLIVE_950},
		{.MIST_50, .MIST_100, .MIST_200, .MIST_300, .MIST_400, .MIST_500, .MIST_600, .MIST_700, .MIST_800, .MIST_900, .MIST_950},
		{.TAUPE_50, .TAUPE_100, .TAUPE_200, .TAUPE_300, .TAUPE_400, .TAUPE_500, .TAUPE_600, .TAUPE_700, .TAUPE_800, .TAUPE_900, .TAUPE_950},
	}

	luma :: proc(c: RGBA) -> int {
		return int(c.r) + int(c.g) + int(c.b)
	}

	for ladder in ladders {
		for i in 0 ..< len(ladder) - 1 {
			testing.expectf(
				t,
				luma(palette[ladder[i]]) >= luma(palette[ladder[i + 1]]),
				"shade order broken: %v (%d) then %v (%d)",
				ladder[i],
				luma(palette[ladder[i]]),
				ladder[i + 1],
				luma(palette[ladder[i + 1]]),
			)
			testing.expect_value(t, palette[ladder[i]].a, u8(255))
		}
		testing.expect_value(t, palette[ladder[len(ladder) - 1]].a, u8(255))
	}
}

@(test)
test_color_to_f32_inherit_and_transparent :: proc(t: ^testing.T) {
	expect_f32x4(t, color_to_f32(Color.INHERIT), {})
	expect_f32x4(t, color_to_f32(Color.TRANSPARENT), {0, 0, 0, 0})
}

@(test)
test_lcha_oklcha_alpha_and_hue_wrap :: proc(t: ^testing.T) {
	a := lcha_to_rgba({50, 30, 0, 0.25})
	b := lcha_to_rgba({50, 30, 360, 0.25})
	// Hue 0 and 360 are the same angle.
	expect_rgba(t, a, b)
	testing.expect_value(t, a.a, u8(64))

	oa := oklcha_to_rgba({0.55, 0.12, -30, 0.5})
	ob := oklcha_to_rgba({0.55, 0.12, 330, 0.5})
	expect_rgba_near(t, oa, ob, 1)
	testing.expect_value(t, oa.a, u8(128))
}

@(test)
test_hsla_alpha_channel :: proc(t: ^testing.T) {
	expect_rgba(t, hsla_to_rgba({0, 1, 0.5, 0}), RGBA{255, 0, 0, 0})
	expect_rgba(t, hsla_to_rgba({0, 1, 0.5, 0.2}), RGBA{255, 0, 0, 51})
}
