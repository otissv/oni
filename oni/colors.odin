package oni

import "core:math"


Palette :: [Color]RGBA
// Packed sRGB #RRGGBBAA (e.g. 0xFF0000FF = opaque red).
Hex :: distinct u32

// Hue 0-360°, saturation/lightness 0-1, alpha 0-1.
HSLA :: struct {
	h, s, l, a: f32,
}

// Hue 0-360°, whiteness/blackness 0-1, alpha 0-1.
HWBA :: struct {
	h, w, b, a: f32,
}

// CIE LCH: lightness 0-100, chroma ≥ 0, hue 0-360°, alpha 0-1.
LCHA :: struct {
	l, c, h, a: f32,
}

// OK LCH: lightness 0-1, chroma ≥ 0, hue 0-360°, alpha 0-1.
OKLCHA :: struct {
	l, c, h, a: f32,
}


// Tailwind CSS v4 default color palette.
// Names follow {color}-{shade} (e.g. Red_500 maps to red-500).
// Values converted from OKLCH theme variables to sRGB 0-255.

// Tailwind palette color names.
Color :: enum {
	Invalid,
	Transparent,
	Black,
	White,
	Surface,
	Border,
	Text,
	Text_muted,
	Accent,
	Accent_hover,
	Accent_pressed,
	Danger,
	Success,
	Warning,
	Info,
	Red_50,
	Red_100,
	Red_200,
	Red_300,
	Red_400,
	Red_500,
	Red_600,
	Red_700,
	Red_800,
	Red_900,
	Red_950,
	Orange_50,
	Orange_100,
	Orange_200,
	Orange_300,
	Orange_400,
	Orange_500,
	Orange_600,
	Orange_700,
	Orange_800,
	Orange_900,
	Orange_950,
	Amber_50,
	Amber_100,
	Amber_200,
	Amber_300,
	Amber_400,
	Amber_500,
	Amber_600,
	Amber_700,
	Amber_800,
	Amber_900,
	Amber_950,
	Yellow_50,
	Yellow_100,
	Yellow_200,
	Yellow_300,
	Yellow_400,
	Yellow_500,
	Yellow_600,
	Yellow_700,
	Yellow_800,
	Yellow_900,
	Yellow_950,
	Lime_50,
	Lime_100,
	Lime_200,
	Lime_300,
	Lime_400,
	Lime_500,
	Lime_600,
	Lime_700,
	Lime_800,
	Lime_900,
	Lime_950,
	Green_50,
	Green_100,
	Green_200,
	Green_300,
	Green_400,
	Green_500,
	Green_600,
	Green_700,
	Green_800,
	Green_900,
	Green_950,
	Emerald_50,
	Emerald_100,
	Emerald_200,
	Emerald_300,
	Emerald_400,
	Emerald_500,
	Emerald_600,
	Emerald_700,
	Emerald_800,
	Emerald_900,
	Emerald_950,
	Teal_50,
	Teal_100,
	Teal_200,
	Teal_300,
	Teal_400,
	Teal_500,
	Teal_600,
	Teal_700,
	Teal_800,
	Teal_900,
	Teal_950,
	Cyan_50,
	Cyan_100,
	Cyan_200,
	Cyan_300,
	Cyan_400,
	Cyan_500,
	Cyan_600,
	Cyan_700,
	Cyan_800,
	Cyan_900,
	Cyan_950,
	Sky_50,
	Sky_100,
	Sky_200,
	Sky_300,
	Sky_400,
	Sky_500,
	Sky_600,
	Sky_700,
	Sky_800,
	Sky_900,
	Sky_950,
	Blue_50,
	Blue_100,
	Blue_200,
	Blue_300,
	Blue_400,
	Blue_500,
	Blue_600,
	Blue_700,
	Blue_800,
	Blue_900,
	Blue_950,
	Indigo_50,
	Indigo_100,
	Indigo_200,
	Indigo_300,
	Indigo_400,
	Indigo_500,
	Indigo_600,
	Indigo_700,
	Indigo_800,
	Indigo_900,
	Indigo_950,
	Violet_50,
	Violet_100,
	Violet_200,
	Violet_300,
	Violet_400,
	Violet_500,
	Violet_600,
	Violet_700,
	Violet_800,
	Violet_900,
	Violet_950,
	Purple_50,
	Purple_100,
	Purple_200,
	Purple_300,
	Purple_400,
	Purple_500,
	Purple_600,
	Purple_700,
	Purple_800,
	Purple_900,
	Purple_950,
	Fuchsia_50,
	Fuchsia_100,
	Fuchsia_200,
	Fuchsia_300,
	Fuchsia_400,
	Fuchsia_500,
	Fuchsia_600,
	Fuchsia_700,
	Fuchsia_800,
	Fuchsia_900,
	Fuchsia_950,
	Pink_50,
	Pink_100,
	Pink_200,
	Pink_300,
	Pink_400,
	Pink_500,
	Pink_600,
	Pink_700,
	Pink_800,
	Pink_900,
	Pink_950,
	Rose_50,
	Rose_100,
	Rose_200,
	Rose_300,
	Rose_400,
	Rose_500,
	Rose_600,
	Rose_700,
	Rose_800,
	Rose_900,
	Rose_950,
	Slate_50,
	Slate_100,
	Slate_200,
	Slate_300,
	Slate_400,
	Slate_500,
	Slate_600,
	Slate_700,
	Slate_800,
	Slate_900,
	Slate_950,
	Gray_50,
	Gray_100,
	Gray_200,
	Gray_300,
	Gray_400,
	Gray_500,
	Gray_600,
	Gray_700,
	Gray_800,
	Gray_900,
	Gray_950,
	Zinc_50,
	Zinc_100,
	Zinc_200,
	Zinc_300,
	Zinc_400,
	Zinc_500,
	Zinc_600,
	Zinc_700,
	Zinc_800,
	Zinc_900,
	Zinc_950,
	Neutral_50,
	Neutral_100,
	Neutral_200,
	Neutral_300,
	Neutral_400,
	Neutral_500,
	Neutral_600,
	Neutral_700,
	Neutral_800,
	Neutral_900,
	Neutral_950,
	Stone_50,
	Stone_100,
	Stone_200,
	Stone_300,
	Stone_400,
	Stone_500,
	Stone_600,
	Stone_700,
	Stone_800,
	Stone_900,
	Stone_950,
	Mauve_50,
	Mauve_100,
	Mauve_200,
	Mauve_300,
	Mauve_400,
	Mauve_500,
	Mauve_600,
	Mauve_700,
	Mauve_800,
	Mauve_900,
	Mauve_950,
	Olive_50,
	Olive_100,
	Olive_200,
	Olive_300,
	Olive_400,
	Olive_500,
	Olive_600,
	Olive_700,
	Olive_800,
	Olive_900,
	Olive_950,
	Mist_50,
	Mist_100,
	Mist_200,
	Mist_300,
	Mist_400,
	Mist_500,
	Mist_600,
	Mist_700,
	Mist_800,
	Mist_900,
	Mist_950,
	Taupe_50,
	Taupe_100,
	Taupe_200,
	Taupe_300,
	Taupe_400,
	Taupe_500,
	Taupe_600,
	Taupe_700,
	Taupe_800,
	Taupe_900,
	Taupe_950,
}

palette: Palette = {
	.Invalid        = {},
	.Transparent    = RGBA{0, 0, 0, 0},
	.Surface        = RGBA{42, 42, 48, 255},
	.Border         = RGBA{64, 64, 72, 255},
	.Text           = RGBA{235, 235, 240, 255},
	.Text_muted     = RGBA{160, 160, 170, 255},
	.Accent         = RGBA{88, 130, 255, 255},
	.Accent_hover   = RGBA{110, 150, 255, 255},
	.Accent_pressed = RGBA{70, 110, 230, 255},
	.Danger         = RGBA{235, 90, 90, 255},
	.Success        = RGBA{90, 200, 130, 255},
	.Warning        = RGBA{240, 177, 0, 255},
	.Info           = RGBA{142, 197, 255, 255},
	.Black          = RGBA{0, 0, 0, 255},
	.White          = RGBA{255, 255, 255, 255},
	.Red_50         = RGBA{254, 242, 242, 255},
	.Red_100        = RGBA{255, 226, 226, 255},
	.Red_200        = RGBA{255, 201, 201, 255},
	.Red_300        = RGBA{255, 162, 162, 255},
	.Red_400        = RGBA{255, 100, 103, 255},
	.Red_500        = RGBA{251, 44, 54, 255},
	.Red_600        = RGBA{231, 0, 11, 255},
	.Red_700        = RGBA{193, 0, 7, 255},
	.Red_800        = RGBA{159, 7, 18, 255},
	.Red_900        = RGBA{130, 24, 26, 255},
	.Red_950        = RGBA{70, 8, 9, 255},
	.Orange_50      = RGBA{255, 247, 237, 255},
	.Orange_100     = RGBA{255, 237, 212, 255},
	.Orange_200     = RGBA{255, 214, 167, 255},
	.Orange_300     = RGBA{255, 184, 106, 255},
	.Orange_400     = RGBA{255, 137, 4, 255},
	.Orange_500     = RGBA{255, 105, 0, 255},
	.Orange_600     = RGBA{245, 73, 0, 255},
	.Orange_700     = RGBA{202, 53, 0, 255},
	.Orange_800     = RGBA{159, 45, 0, 255},
	.Orange_900     = RGBA{126, 42, 12, 255},
	.Orange_950     = RGBA{68, 19, 6, 255},
	.Amber_50       = RGBA{255, 251, 235, 255},
	.Amber_100      = RGBA{254, 243, 198, 255},
	.Amber_200      = RGBA{254, 230, 133, 255},
	.Amber_300      = RGBA{255, 210, 48, 255},
	.Amber_400      = RGBA{255, 185, 0, 255},
	.Amber_500      = RGBA{254, 154, 0, 255},
	.Amber_600      = RGBA{225, 113, 0, 255},
	.Amber_700      = RGBA{187, 77, 0, 255},
	.Amber_800      = RGBA{151, 60, 0, 255},
	.Amber_900      = RGBA{123, 51, 6, 255},
	.Amber_950      = RGBA{70, 25, 1, 255},
	.Yellow_50      = RGBA{254, 252, 232, 255},
	.Yellow_100     = RGBA{254, 249, 194, 255},
	.Yellow_200     = RGBA{255, 240, 133, 255},
	.Yellow_300     = RGBA{255, 223, 32, 255},
	.Yellow_400     = RGBA{253, 199, 0, 255},
	.Yellow_500     = RGBA{240, 177, 0, 255},
	.Yellow_600     = RGBA{208, 135, 0, 255},
	.Yellow_700     = RGBA{166, 95, 0, 255},
	.Yellow_800     = RGBA{137, 75, 0, 255},
	.Yellow_900     = RGBA{115, 62, 10, 255},
	.Yellow_950     = RGBA{67, 32, 4, 255},
	.Lime_50        = RGBA{247, 254, 231, 255},
	.Lime_100       = RGBA{236, 252, 202, 255},
	.Lime_200       = RGBA{216, 249, 153, 255},
	.Lime_300       = RGBA{187, 244, 81, 255},
	.Lime_400       = RGBA{154, 230, 0, 255},
	.Lime_500       = RGBA{124, 207, 0, 255},
	.Lime_600       = RGBA{94, 165, 0, 255},
	.Lime_700       = RGBA{73, 125, 0, 255},
	.Lime_800       = RGBA{60, 99, 0, 255},
	.Lime_900       = RGBA{53, 83, 14, 255},
	.Lime_950       = RGBA{25, 46, 3, 255},
	.Green_50       = RGBA{240, 253, 244, 255},
	.Green_100      = RGBA{220, 252, 231, 255},
	.Green_200      = RGBA{185, 248, 207, 255},
	.Green_300      = RGBA{123, 241, 168, 255},
	.Green_400      = RGBA{5, 223, 114, 255},
	.Green_500      = RGBA{0, 201, 80, 255},
	.Green_600      = RGBA{0, 166, 62, 255},
	.Green_700      = RGBA{0, 130, 54, 255},
	.Green_800      = RGBA{1, 102, 48, 255},
	.Green_900      = RGBA{13, 84, 43, 255},
	.Green_950      = RGBA{3, 46, 21, 255},
	.Emerald_50     = RGBA{236, 253, 245, 255},
	.Emerald_100    = RGBA{208, 250, 229, 255},
	.Emerald_200    = RGBA{164, 244, 207, 255},
	.Emerald_300    = RGBA{94, 233, 181, 255},
	.Emerald_400    = RGBA{0, 212, 146, 255},
	.Emerald_500    = RGBA{0, 188, 125, 255},
	.Emerald_600    = RGBA{0, 153, 102, 255},
	.Emerald_700    = RGBA{0, 122, 85, 255},
	.Emerald_800    = RGBA{0, 96, 69, 255},
	.Emerald_900    = RGBA{0, 79, 59, 255},
	.Emerald_950    = RGBA{0, 44, 34, 255},
	.Teal_50        = RGBA{240, 253, 250, 255},
	.Teal_100       = RGBA{203, 251, 241, 255},
	.Teal_200       = RGBA{150, 247, 228, 255},
	.Teal_300       = RGBA{70, 236, 213, 255},
	.Teal_400       = RGBA{0, 213, 190, 255},
	.Teal_500       = RGBA{0, 187, 167, 255},
	.Teal_600       = RGBA{0, 150, 137, 255},
	.Teal_700       = RGBA{0, 120, 111, 255},
	.Teal_800       = RGBA{0, 95, 90, 255},
	.Teal_900       = RGBA{11, 79, 74, 255},
	.Teal_950       = RGBA{2, 47, 46, 255},
	.Cyan_50        = RGBA{236, 254, 255, 255},
	.Cyan_100       = RGBA{206, 250, 254, 255},
	.Cyan_200       = RGBA{162, 244, 253, 255},
	.Cyan_300       = RGBA{83, 234, 253, 255},
	.Cyan_400       = RGBA{0, 211, 242, 255},
	.Cyan_500       = RGBA{0, 184, 219, 255},
	.Cyan_600       = RGBA{0, 146, 184, 255},
	.Cyan_700       = RGBA{0, 117, 149, 255},
	.Cyan_800       = RGBA{0, 95, 120, 255},
	.Cyan_900       = RGBA{16, 78, 100, 255},
	.Cyan_950       = RGBA{5, 51, 69, 255},
	.Sky_50         = RGBA{240, 249, 255, 255},
	.Sky_100        = RGBA{223, 242, 254, 255},
	.Sky_200        = RGBA{184, 230, 254, 255},
	.Sky_300        = RGBA{116, 212, 255, 255},
	.Sky_400        = RGBA{0, 188, 255, 255},
	.Sky_500        = RGBA{0, 166, 244, 255},
	.Sky_600        = RGBA{0, 132, 209, 255},
	.Sky_700        = RGBA{0, 105, 168, 255},
	.Sky_800        = RGBA{0, 89, 138, 255},
	.Sky_900        = RGBA{2, 74, 112, 255},
	.Sky_950        = RGBA{5, 47, 74, 255},
	.Blue_50        = RGBA{239, 246, 255, 255},
	.Blue_100       = RGBA{219, 234, 254, 255},
	.Blue_200       = RGBA{190, 219, 255, 255},
	.Blue_300       = RGBA{142, 197, 255, 255},
	.Blue_400       = RGBA{81, 162, 255, 255},
	.Blue_500       = RGBA{43, 127, 255, 255},
	.Blue_600       = RGBA{21, 93, 252, 255},
	.Blue_700       = RGBA{20, 71, 230, 255},
	.Blue_800       = RGBA{25, 60, 184, 255},
	.Blue_900       = RGBA{28, 57, 142, 255},
	.Blue_950       = RGBA{22, 36, 86, 255},
	.Indigo_50      = RGBA{238, 242, 255, 255},
	.Indigo_100     = RGBA{224, 231, 255, 255},
	.Indigo_200     = RGBA{198, 210, 255, 255},
	.Indigo_300     = RGBA{163, 179, 255, 255},
	.Indigo_400     = RGBA{124, 134, 255, 255},
	.Indigo_500     = RGBA{97, 95, 255, 255},
	.Indigo_600     = RGBA{79, 57, 246, 255},
	.Indigo_700     = RGBA{67, 45, 215, 255},
	.Indigo_800     = RGBA{55, 42, 172, 255},
	.Indigo_900     = RGBA{49, 44, 133, 255},
	.Indigo_950     = RGBA{30, 26, 77, 255},
	.Violet_50      = RGBA{245, 243, 255, 255},
	.Violet_100     = RGBA{237, 233, 254, 255},
	.Violet_200     = RGBA{221, 214, 255, 255},
	.Violet_300     = RGBA{196, 180, 255, 255},
	.Violet_400     = RGBA{166, 132, 255, 255},
	.Violet_500     = RGBA{142, 81, 255, 255},
	.Violet_600     = RGBA{127, 34, 254, 255},
	.Violet_700     = RGBA{112, 8, 231, 255},
	.Violet_800     = RGBA{93, 14, 192, 255},
	.Violet_900     = RGBA{77, 23, 154, 255},
	.Violet_950     = RGBA{47, 13, 104, 255},
	.Purple_50      = RGBA{250, 245, 255, 255},
	.Purple_100     = RGBA{243, 232, 255, 255},
	.Purple_200     = RGBA{233, 212, 255, 255},
	.Purple_300     = RGBA{218, 178, 255, 255},
	.Purple_400     = RGBA{194, 122, 255, 255},
	.Purple_500     = RGBA{173, 70, 255, 255},
	.Purple_600     = RGBA{152, 16, 250, 255},
	.Purple_700     = RGBA{130, 0, 219, 255},
	.Purple_800     = RGBA{110, 17, 176, 255},
	.Purple_900     = RGBA{89, 22, 139, 255},
	.Purple_950     = RGBA{60, 3, 102, 255},
	.Fuchsia_50     = RGBA{253, 244, 255, 255},
	.Fuchsia_100    = RGBA{250, 232, 255, 255},
	.Fuchsia_200    = RGBA{246, 207, 255, 255},
	.Fuchsia_300    = RGBA{244, 168, 255, 255},
	.Fuchsia_400    = RGBA{237, 106, 255, 255},
	.Fuchsia_500    = RGBA{225, 42, 251, 255},
	.Fuchsia_600    = RGBA{200, 0, 222, 255},
	.Fuchsia_700    = RGBA{168, 0, 183, 255},
	.Fuchsia_800    = RGBA{138, 1, 148, 255},
	.Fuchsia_900    = RGBA{114, 19, 120, 255},
	.Fuchsia_950    = RGBA{75, 0, 79, 255},
	.Pink_50        = RGBA{253, 242, 248, 255},
	.Pink_100       = RGBA{252, 231, 243, 255},
	.Pink_200       = RGBA{252, 206, 232, 255},
	.Pink_300       = RGBA{253, 165, 213, 255},
	.Pink_400       = RGBA{251, 100, 182, 255},
	.Pink_500       = RGBA{246, 51, 154, 255},
	.Pink_600       = RGBA{230, 0, 118, 255},
	.Pink_700       = RGBA{198, 0, 92, 255},
	.Pink_800       = RGBA{163, 0, 76, 255},
	.Pink_900       = RGBA{134, 16, 67, 255},
	.Pink_950       = RGBA{81, 4, 36, 255},
	.Rose_50        = RGBA{255, 241, 242, 255},
	.Rose_100       = RGBA{255, 228, 230, 255},
	.Rose_200       = RGBA{255, 204, 211, 255},
	.Rose_300       = RGBA{255, 161, 173, 255},
	.Rose_400       = RGBA{255, 99, 126, 255},
	.Rose_500       = RGBA{255, 32, 86, 255},
	.Rose_600       = RGBA{236, 0, 63, 255},
	.Rose_700       = RGBA{199, 0, 54, 255},
	.Rose_800       = RGBA{165, 0, 54, 255},
	.Rose_900       = RGBA{139, 8, 54, 255},
	.Rose_950       = RGBA{77, 2, 24, 255},
	.Slate_50       = RGBA{248, 250, 252, 255},
	.Slate_100      = RGBA{241, 245, 249, 255},
	.Slate_200      = RGBA{226, 232, 240, 255},
	.Slate_300      = RGBA{202, 213, 226, 255},
	.Slate_400      = RGBA{144, 161, 185, 255},
	.Slate_500      = RGBA{98, 116, 142, 255},
	.Slate_600      = RGBA{69, 85, 108, 255},
	.Slate_700      = RGBA{49, 65, 88, 255},
	.Slate_800      = RGBA{29, 41, 61, 255},
	.Slate_900      = RGBA{15, 23, 43, 255},
	.Slate_950      = RGBA{2, 6, 24, 255},
	.Gray_50        = RGBA{249, 250, 251, 255},
	.Gray_100       = RGBA{243, 244, 246, 255},
	.Gray_200       = RGBA{229, 231, 235, 255},
	.Gray_300       = RGBA{209, 213, 220, 255},
	.Gray_400       = RGBA{153, 161, 175, 255},
	.Gray_500       = RGBA{106, 114, 130, 255},
	.Gray_600       = RGBA{74, 85, 101, 255},
	.Gray_700       = RGBA{54, 65, 83, 255},
	.Gray_800       = RGBA{30, 41, 57, 255},
	.Gray_900       = RGBA{16, 24, 40, 255},
	.Gray_950       = RGBA{3, 7, 18, 255},
	.Zinc_50        = RGBA{250, 250, 250, 255},
	.Zinc_100       = RGBA{244, 244, 245, 255},
	.Zinc_200       = RGBA{228, 228, 231, 255},
	.Zinc_300       = RGBA{212, 212, 216, 255},
	.Zinc_400       = RGBA{159, 159, 169, 255},
	.Zinc_500       = RGBA{113, 113, 123, 255},
	.Zinc_600       = RGBA{82, 82, 92, 255},
	.Zinc_700       = RGBA{63, 63, 70, 255},
	.Zinc_800       = RGBA{39, 39, 42, 255},
	.Zinc_900       = RGBA{24, 24, 27, 255},
	.Zinc_950       = RGBA{9, 9, 11, 255},
	.Neutral_50     = RGBA{250, 250, 250, 255},
	.Neutral_100    = RGBA{245, 245, 245, 255},
	.Neutral_200    = RGBA{229, 229, 229, 255},
	.Neutral_300    = RGBA{212, 212, 212, 255},
	.Neutral_400    = RGBA{161, 161, 161, 255},
	.Neutral_500    = RGBA{115, 115, 115, 255},
	.Neutral_600    = RGBA{82, 82, 82, 255},
	.Neutral_700    = RGBA{64, 64, 64, 255},
	.Neutral_800    = RGBA{38, 38, 38, 255},
	.Neutral_900    = RGBA{23, 23, 23, 255},
	.Neutral_950    = RGBA{10, 10, 10, 255},
	.Stone_50       = RGBA{250, 250, 249, 255},
	.Stone_100      = RGBA{245, 245, 244, 255},
	.Stone_200      = RGBA{231, 229, 228, 255},
	.Stone_300      = RGBA{214, 211, 209, 255},
	.Stone_400      = RGBA{166, 160, 155, 255},
	.Stone_500      = RGBA{121, 113, 107, 255},
	.Stone_600      = RGBA{87, 83, 77, 255},
	.Stone_700      = RGBA{68, 64, 59, 255},
	.Stone_800      = RGBA{41, 37, 36, 255},
	.Stone_900      = RGBA{28, 25, 23, 255},
	.Stone_950      = RGBA{12, 10, 9, 255},
	.Mauve_50       = RGBA{250, 250, 250, 255},
	.Mauve_100      = RGBA{243, 241, 243, 255},
	.Mauve_200      = RGBA{231, 228, 231, 255},
	.Mauve_300      = RGBA{215, 208, 215, 255},
	.Mauve_400      = RGBA{168, 158, 169, 255},
	.Mauve_500      = RGBA{121, 105, 123, 255},
	.Mauve_600      = RGBA{89, 76, 91, 255},
	.Mauve_700      = RGBA{70, 57, 71, 255},
	.Mauve_800      = RGBA{42, 33, 44, 255},
	.Mauve_900      = RGBA{29, 22, 30, 255},
	.Mauve_950      = RGBA{12, 9, 12, 255},
	.Olive_50       = RGBA{251, 251, 249, 255},
	.Olive_100      = RGBA{244, 244, 240, 255},
	.Olive_200      = RGBA{232, 232, 227, 255},
	.Olive_300      = RGBA{216, 216, 208, 255},
	.Olive_400      = RGBA{171, 171, 156, 255},
	.Olive_500      = RGBA{124, 124, 103, 255},
	.Olive_600      = RGBA{91, 91, 75, 255},
	.Olive_700      = RGBA{71, 71, 57, 255},
	.Olive_800      = RGBA{43, 43, 34, 255},
	.Olive_900      = RGBA{29, 29, 22, 255},
	.Olive_950      = RGBA{12, 12, 9, 255},
	.Mist_50        = RGBA{249, 251, 251, 255},
	.Mist_100       = RGBA{241, 243, 243, 255},
	.Mist_200       = RGBA{227, 231, 232, 255},
	.Mist_300       = RGBA{208, 214, 216, 255},
	.Mist_400       = RGBA{156, 168, 171, 255},
	.Mist_500       = RGBA{103, 120, 124, 255},
	.Mist_600       = RGBA{75, 88, 91, 255},
	.Mist_700       = RGBA{57, 68, 71, 255},
	.Mist_800       = RGBA{34, 41, 43, 255},
	.Mist_900       = RGBA{22, 27, 29, 255},
	.Mist_950       = RGBA{9, 11, 12, 255},
	.Taupe_50       = RGBA{251, 250, 249, 255},
	.Taupe_100      = RGBA{243, 241, 241, 255},
	.Taupe_200      = RGBA{232, 228, 227, 255},
	.Taupe_300      = RGBA{216, 210, 208, 255},
	.Taupe_400      = RGBA{171, 160, 156, 255},
	.Taupe_500      = RGBA{124, 109, 103, 255},
	.Taupe_600      = RGBA{91, 79, 75, 255},
	.Taupe_700      = RGBA{71, 60, 57, 255},
	.Taupe_800      = RGBA{43, 36, 34, 255},
	.Taupe_900      = RGBA{29, 24, 22, 255},
	.Taupe_950      = RGBA{12, 10, 9, 255},
}


css_color_to_rgba :: proc(c: Color) -> RGBA {
	if c == .Invalid do return RGBA{}
	return palette[c]
}


Colors :: union {
	Color,
	RGBA,
	Hex,
	HSLA,
	HWBA,
	LCHA,
	OKLCHA,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Colors,
}

color_clamp01 :: proc(v: f32) -> f32 {
	return math.clamp(v, 0, 1)
}

color_u8_from01 :: proc(v: f32) -> u8 {
	return u8(math.round(color_clamp01(v) * 255))
}

color_linear_to_srgb :: proc(c: f32) -> f32 {
	if c <= 0.0031308 {
		return 12.92 * c
	}
	return 1.055 * math.pow(c, 1.0 / 2.4) - 0.055
}

color_hue_to_rgb :: proc(h: f32) -> [3]f32 {
	hue := math.mod(h, 360)
	if hue < 0 do hue += 360
	hue /= 60
	i := int(hue)
	f := hue - f32(i)
	switch i {
	case 0:
		return {1, f, 0}
	case 1:
		return {1 - f, 1, 0}
	case 2:
		return {0, 1, f}
	case 3:
		return {0, 1 - f, 1}
	case 4:
		return {f, 0, 1}
	case:
		return {1, 0, 1 - f}
	}
}

color_hue_to_channel :: proc(p, q, t: f32) -> f32 {
	channel_t := math.mod(t, 1)
	if channel_t < 0 do channel_t += 1
	if channel_t < 1.0 / 6 do return p + (q - p) * 6 * channel_t
	if channel_t < 1.0 / 2 do return q
	if channel_t < 2.0 / 3 do return p + (q - p) * (2.0 / 3 - channel_t) * 6
	return p
}

hsla_to_rgba :: proc(c: HSLA) -> RGBA {
	h := c.h
	s := color_clamp01(c.s)
	l := color_clamp01(c.l)
	a := color_u8_from01(c.a)

	if s == 0 {
		gray := color_u8_from01(l)
		return RGBA{gray, gray, gray, a}
	}

	q := l < 0.5 ? l * (1 + s) : l + s - l * s
	p := 2 * l - q
	hue := h / 360
	r := color_u8_from01(color_hue_to_channel(p, q, hue + 1.0 / 3))
	g := color_u8_from01(color_hue_to_channel(p, q, hue))
	b := color_u8_from01(color_hue_to_channel(p, q, hue - 1.0 / 3))
	return RGBA{r, g, b, a}
}


hwba_to_rgba :: proc(c: HWBA) -> RGBA {
	h := c.h
	w := color_clamp01(c.w)
	b := color_clamp01(c.b)
	a := color_u8_from01(c.a)

	if w + b >= 1 {
		gray := color_u8_from01(w / (w + b))
		return RGBA{gray, gray, gray, a}
	}

	rgb := color_hue_to_rgb(h)
	scale := 1 - w - b
	r := color_u8_from01(rgb[0] * scale + w)
	g := color_u8_from01(rgb[1] * scale + w)
	bl := color_u8_from01(rgb[2] * scale + w)
	return RGBA{r, g, bl, a}
}

lcha_to_rgba :: proc(c: LCHA) -> RGBA {
	l := math.clamp(c.l, 0, 100)
	ch := math.max(c.c, 0)
	h_rad := c.h * math.RAD_PER_DEG
	lab_a := ch * math.cos(h_rad)
	lab_b := ch * math.sin(h_rad)

	fy := (l + 16) / 116
	fx := lab_a / 500 + fy
	fz := fy - lab_b / 200

	epsilon :: 0.008856
	kappa :: 903.3

	f_inv :: proc(t: f32) -> f32 {
		if t > epsilon {
			return t * t * t
		}
		return (116 * t - 16) / kappa
	}

	x := 0.95047 * f_inv(fx)
	y := 1.00000 * f_inv(fy)
	z := 1.08883 * f_inv(fz)

	linear_r := 3.2404542 * x - 1.5371385 * y - 0.4985314 * z
	linear_g := -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
	linear_b := 0.0556434 * x - 0.2040259 * y + 1.0572252 * z

	return RGBA {
		color_u8_from01(color_linear_to_srgb(linear_r)),
		color_u8_from01(color_linear_to_srgb(linear_g)),
		color_u8_from01(color_linear_to_srgb(linear_b)),
		color_u8_from01(c.a),
	}
}

oklcha_to_rgba :: proc(c: OKLCHA) -> RGBA {
	l := color_clamp01(c.l)
	ch := math.max(c.c, 0)
	h_rad := c.h * math.RAD_PER_DEG
	ok_a := ch * math.cos(h_rad)
	ok_b := ch * math.sin(h_rad)

	l_ := l + 0.3963377774 * ok_a + 0.2158037573 * ok_b
	m_ := l - 0.1055613458 * ok_a - 0.0638541728 * ok_b
	s_ := l - 0.0894841775 * ok_a - 1.2914855480 * ok_b

	l_c := l_ * l_ * l_
	m_c := m_ * m_ * m_
	s_c := s_ * s_ * s_

	linear_r := +4.0767416621 * l_c - 3.3077115913 * m_c + 0.2309699292 * s_c
	linear_g := -1.2684380046 * l_c + 2.6097574011 * m_c - 0.3413193965 * s_c
	linear_b := -0.0041960863 * l_c - 0.7034186147 * m_c + 1.7076147010 * s_c

	return RGBA {
		color_u8_from01(color_linear_to_srgb(linear_r)),
		color_u8_from01(color_linear_to_srgb(linear_g)),
		color_u8_from01(color_linear_to_srgb(linear_b)),
		color_u8_from01(c.a),
	}
}
rgba_to_rgba :: proc(c: RGBA) -> RGBA {
	return c
}

hex_to_rgba :: proc(c: Hex) -> RGBA {
	v := u32(c)
	return RGBA{u8(v >> 24), u8(v >> 16), u8(v >> 8), u8(v)}
}


css_color_to_rba :: proc(c: Color) -> RGBA {
	return rgba_to_rgba(css_color_to_rgba(c))
}

to_rgba_color :: proc {
	css_color_to_rba,
	rgba_to_rgba,
	hex_to_rgba,
	hsla_to_rgba,
	hwba_to_rgba,
	lcha_to_rgba,
	oklcha_to_rgba,
}

resolve_color :: proc(c: Colors, state: ^$S, event: Widget_Event(S)) -> (rgba: RGBA, ok: bool) {
	#partial switch v in c {
	case Color:
		if v == .Invalid do return {}, false
		return to_rgba_color(v), true
	case RGBA:
		return to_rgba_color(v), true
	case Hex:
		return to_rgba_color(v), true
	case HSLA:
		return to_rgba_color(v), true
	case HWBA:
		return to_rgba_color(v), true
	case LCHA:
		return to_rgba_color(v), true
	case OKLCHA:
		return to_rgba_color(v), true
	case proc(state: Widget_State, widget_event: Widget_Event(Widget_State)) -> Colors:
		ui_state := (^Widget_State)(cast(rawptr)state)^
		ui_event := Widget_Event(Widget_State) {
			state = ui_state,
		}
		return resolve_color(v(ui_state, ui_event), state, event)
	}
	return {}, false
}

rgba_to_f32 :: proc(c: RGBA) -> [4]f32 {
	return {f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, f32(c.a) / 255}
}

color_to_f32_static :: proc(c: Colors) -> [4]f32 {
	rgba: RGBA

	#partial switch v in c {
	case Color:
		if v == .Invalid do return {}
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

	return rgba_to_f32(rgba)
}

color_to_f32 :: proc(c: Colors, state: ^$S, event: Widget_Event(S)) -> [4]f32 {
	rgba, ok := resolve_color(c, state, event)
	if !ok do return {}
	return rgba_to_f32(rgba)
}
