package oni

import "core:math"


Palette :: [Color]RGBA
// Packed sRGB #RRGGBBAA (e.g. 0xFF0000FF = opaque red).
Hex :: distinct u32

/*
Hue in degrees (0-360), saturation/lightness/alpha in 0-1.
*/
HSLA :: struct {
	h, s, l, a: f32,
}

/*
Hue in degrees (0-360), whiteness/blackness/alpha in 0-1.
*/
HWBA :: struct {
	h, w, b, a: f32,
}

/*
CIE LCH color: lightness 0-100, chroma ≥ 0, hue 0-360°, alpha 0-1.
*/
LCHA :: struct {
	l, c, h, a: f32,
}

/*
OK LCH color: lightness 0-1, chroma ≥ 0, hue 0-360°, alpha 0-1.
*/
OKLCHA :: struct {
	l, c, h, a: f32,
}


// Tailwind CSS v4 default color palette.
// Names follow {color}-{shade} (e.g. Red_500 maps to red-500).
// Values converted from OKLCH theme variables to sRGB 0-255.

// Tailwind palette color names.
Color :: enum {
	INVALID,
	INHERIT,
	TRANSPARENT,
	BLACK,
	WHITE,
	BACKGROUND,
	FOREGROUND,
	BORDER,
	INPUT,
	RING,
	CARD,
	CARD_FOREGROUND,
	POPOVER,
	POPOVER_FOREGROUND,
	PRIMARY,
	PRIMARY_FOREGROUND,
	PRIMARY_HOVER,
	PRIMARY_PRESSED,
	SECONDARY,
	SECONDARY_FOREGROUND,
	SECONDARY_HOVER,
	SECONDARY_PRESSED,
	MUTED,
	MUTED_FOREGROUND,
	ACCENT,
	ACCENT_FOREGROUND,
	ACCENT_HOVER,
	ACCENT_PRESSED,
	DESTRUCTIVE,
	DESTRUCTIVE_FOREGROUND,
	DESTRUCTIVE_HOVER,
	DESTRUCTIVE_PRESSED,
	SUCCESS,
	SUCCESS_FOREGROUND,
	SUCCESS_HOVER,
	SUCCESS_PRESSED,
	WARNING,
	WARNING_FOREGROUND,
	WARNING_HOVER,
	WARNING_PRESSED,
	INFO,
	INFO_FOREGROUND,
	INFO_HOVER,
	INFO_PRESSED,
	SIDEBAR,
	SIDEBAR_FOREGROUND,
	SIDEBAR_PRIMARY,
	SIDEBAR_PRIMARY_FOREGROUND,
	SIDEBAR_ACCENT,
	SIDEBAR_ACCENT_FOREGROUND,
	SIDEBAR_BORDER,
	SIDEBAR_RING,
	RED_50,
	RED_100,
	RED_200,
	RED_300,
	RED_400,
	RED_500,
	RED_600,
	RED_700,
	RED_800,
	RED_900,
	RED_950,
	ORANGE_50,
	ORANGE_100,
	ORANGE_200,
	ORANGE_300,
	ORANGE_400,
	ORANGE_500,
	ORANGE_600,
	ORANGE_700,
	ORANGE_800,
	ORANGE_900,
	ORANGE_950,
	AMBER_50,
	AMBER_100,
	AMBER_200,
	AMBER_300,
	AMBER_400,
	AMBER_500,
	AMBER_600,
	AMBER_700,
	AMBER_800,
	AMBER_900,
	AMBER_950,
	YELLOW_50,
	YELLOW_100,
	YELLOW_200,
	YELLOW_300,
	YELLOW_400,
	YELLOW_500,
	YELLOW_600,
	YELLOW_700,
	YELLOW_800,
	YELLOW_900,
	YELLOW_950,
	LIME_50,
	LIME_100,
	LIME_200,
	LIME_300,
	LIME_400,
	LIME_500,
	LIME_600,
	LIME_700,
	LIME_800,
	LIME_900,
	LIME_950,
	GREEN_50,
	GREEN_100,
	GREEN_200,
	GREEN_300,
	GREEN_400,
	GREEN_500,
	GREEN_600,
	GREEN_700,
	GREEN_800,
	GREEN_900,
	GREEN_950,
	EMERALD_50,
	EMERALD_100,
	EMERALD_200,
	EMERALD_300,
	EMERALD_400,
	EMERALD_500,
	EMERALD_600,
	EMERALD_700,
	EMERALD_800,
	EMERALD_900,
	EMERALD_950,
	TEAL_50,
	TEAL_100,
	TEAL_200,
	TEAL_300,
	TEAL_400,
	TEAL_500,
	TEAL_600,
	TEAL_700,
	TEAL_800,
	TEAL_900,
	TEAL_950,
	CYAN_50,
	CYAN_100,
	CYAN_200,
	CYAN_300,
	CYAN_400,
	CYAN_500,
	CYAN_600,
	CYAN_700,
	CYAN_800,
	CYAN_900,
	CYAN_950,
	SKY_50,
	SKY_100,
	SKY_200,
	SKY_300,
	SKY_400,
	SKY_500,
	SKY_600,
	SKY_700,
	SKY_800,
	SKY_900,
	SKY_950,
	BLUE_50,
	BLUE_100,
	BLUE_200,
	BLUE_300,
	BLUE_400,
	BLUE_500,
	BLUE_600,
	BLUE_700,
	BLUE_800,
	BLUE_900,
	BLUE_950,
	INDIGO_50,
	INDIGO_100,
	INDIGO_200,
	INDIGO_300,
	INDIGO_400,
	INDIGO_500,
	INDIGO_600,
	INDIGO_700,
	INDIGO_800,
	INDIGO_900,
	INDIGO_950,
	VIOLET_50,
	VIOLET_100,
	VIOLET_200,
	VIOLET_300,
	VIOLET_400,
	VIOLET_500,
	VIOLET_600,
	VIOLET_700,
	VIOLET_800,
	VIOLET_900,
	VIOLET_950,
	PURPLE_50,
	PURPLE_100,
	PURPLE_200,
	PURPLE_300,
	PURPLE_400,
	PURPLE_500,
	PURPLE_600,
	PURPLE_700,
	PURPLE_800,
	PURPLE_900,
	PURPLE_950,
	FUCHSIA_50,
	FUCHSIA_100,
	FUCHSIA_200,
	FUCHSIA_300,
	FUCHSIA_400,
	FUCHSIA_500,
	FUCHSIA_600,
	FUCHSIA_700,
	FUCHSIA_800,
	FUCHSIA_900,
	FUCHSIA_950,
	PINK_50,
	PINK_100,
	PINK_200,
	PINK_300,
	PINK_400,
	PINK_500,
	PINK_600,
	PINK_700,
	PINK_800,
	PINK_900,
	PINK_950,
	ROSE_50,
	ROSE_100,
	ROSE_200,
	ROSE_300,
	ROSE_400,
	ROSE_500,
	ROSE_600,
	ROSE_700,
	ROSE_800,
	ROSE_900,
	ROSE_950,
	SLATE_50,
	SLATE_100,
	SLATE_200,
	SLATE_300,
	SLATE_400,
	SLATE_500,
	SLATE_600,
	SLATE_700,
	SLATE_800,
	SLATE_900,
	SLATE_950,
	GRAY_50,
	GRAY_100,
	GRAY_200,
	GRAY_300,
	GRAY_400,
	GRAY_500,
	GRAY_600,
	GRAY_700,
	GRAY_800,
	GRAY_900,
	GRAY_950,
	ZINC_50,
	ZINC_100,
	ZINC_200,
	ZINC_300,
	ZINC_400,
	ZINC_500,
	ZINC_600,
	ZINC_700,
	ZINC_800,
	ZINC_900,
	ZINC_950,
	NEUTRAL_50,
	NEUTRAL_100,
	NEUTRAL_200,
	NEUTRAL_300,
	NEUTRAL_400,
	NEUTRAL_500,
	NEUTRAL_600,
	NEUTRAL_700,
	NEUTRAL_800,
	NEUTRAL_900,
	NEUTRAL_950,
	STONE_50,
	STONE_100,
	STONE_200,
	STONE_300,
	STONE_400,
	STONE_500,
	STONE_600,
	STONE_700,
	STONE_800,
	STONE_900,
	STONE_950,
	MAUVE_50,
	MAUVE_100,
	MAUVE_200,
	MAUVE_300,
	MAUVE_400,
	MAUVE_500,
	MAUVE_600,
	MAUVE_700,
	MAUVE_800,
	MAUVE_900,
	MAUVE_950,
	OLIVE_50,
	OLIVE_100,
	OLIVE_200,
	OLIVE_300,
	OLIVE_400,
	OLIVE_500,
	OLIVE_600,
	OLIVE_700,
	OLIVE_800,
	OLIVE_900,
	OLIVE_950,
	MIST_50,
	MIST_100,
	MIST_200,
	MIST_300,
	MIST_400,
	MIST_500,
	MIST_600,
	MIST_700,
	MIST_800,
	MIST_900,
	MIST_950,
	TAUPE_50,
	TAUPE_100,
	TAUPE_200,
	TAUPE_300,
	TAUPE_400,
	TAUPE_500,
	TAUPE_600,
	TAUPE_700,
	TAUPE_800,
	TAUPE_900,
	TAUPE_950,
}

palette: Palette = {
	.INVALID                    = {},
	.INHERIT                    = {},
	.TRANSPARENT                = {0, 0, 0, 0},
	.BLACK                      = {0, 0, 0, 255},
	.WHITE                      = {255, 255, 255, 255},
	.BACKGROUND                 = RGBA{45, 45, 48, 255},
	.FOREGROUND                 = RGBA{204, 204, 204, 255},
	.CARD                       = RGBA{45, 45, 48, 255},
	.CARD_FOREGROUND            = RGBA{204, 204, 204, 255},
	.POPOVER                    = RGBA{45, 45, 48, 255},
	.POPOVER_FOREGROUND         = RGBA{204, 204, 204, 255},
	.PRIMARY                    = RGBA{0, 120, 212, 255},
	.PRIMARY_FOREGROUND         = RGBA{255, 255, 255, 255},
	.PRIMARY_HOVER              = RGBA{36, 84, 121, 255},
	.PRIMARY_PRESSED            = RGBA{36, 120, 255, 255},
	.SECONDARY                  = RGBA{60, 60, 60, 255},
	.SECONDARY_HOVER            = RGBA{60, 60, 60, 255},
	.SECONDARY_PRESSED          = RGBA{60, 60, 60, 255},
	.SECONDARY_FOREGROUND       = RGBA{204, 204, 204, 255},
	.MUTED                      = RGBA{60, 60, 60, 255},
	.MUTED_FOREGROUND           = RGBA{150, 150, 150, 255},
	.ACCENT                     = RGBA{64, 64, 64, 255},
	.ACCENT_FOREGROUND          = RGBA{204, 204, 204, 255},
	.ACCENT_HOVER               = RGBA{64, 64, 64, 255},
	.ACCENT_PRESSED             = RGBA{64, 64, 64, 255},
	.DESTRUCTIVE                = RGBA{204, 38, 46, 255},
	.DESTRUCTIVE_FOREGROUND     = RGBA{255, 255, 255, 255},
	.DESTRUCTIVE_HOVER          = RGBA{204, 38, 46, 255},
	.DESTRUCTIVE_PRESSED        = RGBA{204, 38, 46, 255},
	.SUCCESS                    = RGBA{5, 137, 62, 255},
	.SUCCESS_FOREGROUND         = RGBA{255, 255, 255, 255},
	.SUCCESS_HOVER              = RGBA{5, 137, 62, 255},
	.SUCCESS_PRESSED            = RGBA{5, 137, 62, 255},
	.INFO                       = RGBA{15, 116, 197, 255},
	.INFO_FOREGROUND            = RGBA{255, 255, 255, 255},
	.INFO_HOVER                 = RGBA{15, 116, 197, 255},
	.INFO_PRESSED               = RGBA{15, 116, 197, 255},
	.WARNING                    = RGBA{206, 146, 0, 255},
	.WARNING_FOREGROUND         = RGBA{22, 22, 22, 255},
	.WARNING_HOVER              = RGBA{206, 146, 0, 255},
	.WARNING_PRESSED            = RGBA{206, 146, 0, 255},
	.BORDER                     = RGBA{64, 64, 64, 255},
	.INPUT                      = RGBA{64, 64, 64, 255},
	.RING                       = RGBA{0, 120, 212, 255},
	.SIDEBAR                    = RGBA{23, 23, 23, 255},
	.SIDEBAR_FOREGROUND         = RGBA{250, 250, 250, 255},
	.SIDEBAR_PRIMARY            = RGBA{20, 71, 230, 255},
	.SIDEBAR_PRIMARY_FOREGROUND = RGBA{250, 250, 250, 255},
	.SIDEBAR_ACCENT             = RGBA{38, 38, 38, 255},
	.SIDEBAR_ACCENT_FOREGROUND  = RGBA{250, 250, 250, 255},
	.SIDEBAR_BORDER             = RGBA{255, 255, 255, 26},
	.SIDEBAR_RING               = RGBA{115, 115, 115, 255},
	.RED_50                     = RGBA{254, 242, 242, 255},
	.RED_100                    = RGBA{255, 226, 226, 255},
	.RED_200                    = RGBA{255, 201, 201, 255},
	.RED_300                    = RGBA{255, 162, 162, 255},
	.RED_400                    = RGBA{255, 100, 103, 255},
	.RED_500                    = RGBA{251, 44, 54, 255},
	.RED_600                    = RGBA{231, 0, 11, 255},
	.RED_700                    = RGBA{193, 0, 7, 255},
	.RED_800                    = RGBA{159, 7, 18, 255},
	.RED_900                    = RGBA{130, 24, 26, 255},
	.RED_950                    = RGBA{70, 8, 9, 255},
	.ORANGE_50                  = RGBA{255, 247, 237, 255},
	.ORANGE_100                 = RGBA{255, 237, 212, 255},
	.ORANGE_200                 = RGBA{255, 214, 167, 255},
	.ORANGE_300                 = RGBA{255, 184, 106, 255},
	.ORANGE_400                 = RGBA{255, 137, 4, 255},
	.ORANGE_500                 = RGBA{255, 105, 0, 255},
	.ORANGE_600                 = RGBA{245, 73, 0, 255},
	.ORANGE_700                 = RGBA{202, 53, 0, 255},
	.ORANGE_800                 = RGBA{159, 45, 0, 255},
	.ORANGE_900                 = RGBA{126, 42, 12, 255},
	.ORANGE_950                 = RGBA{68, 19, 6, 255},
	.AMBER_50                   = RGBA{255, 251, 235, 255},
	.AMBER_100                  = RGBA{254, 243, 198, 255},
	.AMBER_200                  = RGBA{254, 230, 133, 255},
	.AMBER_300                  = RGBA{255, 210, 48, 255},
	.AMBER_400                  = RGBA{255, 185, 0, 255},
	.AMBER_500                  = RGBA{254, 154, 0, 255},
	.AMBER_600                  = RGBA{225, 113, 0, 255},
	.AMBER_700                  = RGBA{187, 77, 0, 255},
	.AMBER_800                  = RGBA{151, 60, 0, 255},
	.AMBER_900                  = RGBA{123, 51, 6, 255},
	.AMBER_950                  = RGBA{70, 25, 1, 255},
	.YELLOW_50                  = RGBA{254, 252, 232, 255},
	.YELLOW_100                 = RGBA{254, 249, 194, 255},
	.YELLOW_200                 = RGBA{255, 240, 133, 255},
	.YELLOW_300                 = RGBA{255, 223, 32, 255},
	.YELLOW_400                 = RGBA{253, 199, 0, 255},
	.YELLOW_500                 = RGBA{240, 177, 0, 255},
	.YELLOW_600                 = RGBA{208, 135, 0, 255},
	.YELLOW_700                 = RGBA{166, 95, 0, 255},
	.YELLOW_800                 = RGBA{137, 75, 0, 255},
	.YELLOW_900                 = RGBA{115, 62, 10, 255},
	.YELLOW_950                 = RGBA{67, 32, 4, 255},
	.LIME_50                    = RGBA{247, 254, 231, 255},
	.LIME_100                   = RGBA{236, 252, 202, 255},
	.LIME_200                   = RGBA{216, 249, 153, 255},
	.LIME_300                   = RGBA{187, 244, 81, 255},
	.LIME_400                   = RGBA{154, 230, 0, 255},
	.LIME_500                   = RGBA{124, 207, 0, 255},
	.LIME_600                   = RGBA{94, 165, 0, 255},
	.LIME_700                   = RGBA{73, 125, 0, 255},
	.LIME_800                   = RGBA{60, 99, 0, 255},
	.LIME_900                   = RGBA{53, 83, 14, 255},
	.LIME_950                   = RGBA{25, 46, 3, 255},
	.GREEN_50                   = RGBA{240, 253, 244, 255},
	.GREEN_100                  = RGBA{220, 252, 231, 255},
	.GREEN_200                  = RGBA{185, 248, 207, 255},
	.GREEN_300                  = RGBA{123, 241, 168, 255},
	.GREEN_400                  = RGBA{5, 223, 114, 255},
	.GREEN_500                  = RGBA{0, 201, 80, 255},
	.GREEN_600                  = RGBA{0, 166, 62, 255},
	.GREEN_700                  = RGBA{0, 130, 54, 255},
	.GREEN_800                  = RGBA{1, 102, 48, 255},
	.GREEN_900                  = RGBA{13, 84, 43, 255},
	.GREEN_950                  = RGBA{3, 46, 21, 255},
	.EMERALD_50                 = RGBA{236, 253, 245, 255},
	.EMERALD_100                = RGBA{208, 250, 229, 255},
	.EMERALD_200                = RGBA{164, 244, 207, 255},
	.EMERALD_300                = RGBA{94, 233, 181, 255},
	.EMERALD_400                = RGBA{0, 212, 146, 255},
	.EMERALD_500                = RGBA{0, 188, 125, 255},
	.EMERALD_600                = RGBA{0, 153, 102, 255},
	.EMERALD_700                = RGBA{0, 122, 85, 255},
	.EMERALD_800                = RGBA{0, 96, 69, 255},
	.EMERALD_900                = RGBA{0, 79, 59, 255},
	.EMERALD_950                = RGBA{0, 44, 34, 255},
	.TEAL_50                    = RGBA{240, 253, 250, 255},
	.TEAL_100                   = RGBA{203, 251, 241, 255},
	.TEAL_200                   = RGBA{150, 247, 228, 255},
	.TEAL_300                   = RGBA{70, 236, 213, 255},
	.TEAL_400                   = RGBA{0, 213, 190, 255},
	.TEAL_500                   = RGBA{0, 187, 167, 255},
	.TEAL_600                   = RGBA{0, 150, 137, 255},
	.TEAL_700                   = RGBA{0, 120, 111, 255},
	.TEAL_800                   = RGBA{0, 95, 90, 255},
	.TEAL_900                   = RGBA{11, 79, 74, 255},
	.TEAL_950                   = RGBA{2, 47, 46, 255},
	.CYAN_50                    = RGBA{236, 254, 255, 255},
	.CYAN_100                   = RGBA{206, 250, 254, 255},
	.CYAN_200                   = RGBA{162, 244, 253, 255},
	.CYAN_300                   = RGBA{83, 234, 253, 255},
	.CYAN_400                   = RGBA{0, 211, 242, 255},
	.CYAN_500                   = RGBA{0, 184, 219, 255},
	.CYAN_600                   = RGBA{0, 146, 184, 255},
	.CYAN_700                   = RGBA{0, 117, 149, 255},
	.CYAN_800                   = RGBA{0, 95, 120, 255},
	.CYAN_900                   = RGBA{16, 78, 100, 255},
	.CYAN_950                   = RGBA{5, 51, 69, 255},
	.SKY_50                     = RGBA{240, 249, 255, 255},
	.SKY_100                    = RGBA{223, 242, 254, 255},
	.SKY_200                    = RGBA{184, 230, 254, 255},
	.SKY_300                    = RGBA{116, 212, 255, 255},
	.SKY_400                    = RGBA{0, 188, 255, 255},
	.SKY_500                    = RGBA{0, 166, 244, 255},
	.SKY_600                    = RGBA{0, 132, 209, 255},
	.SKY_700                    = RGBA{0, 105, 168, 255},
	.SKY_800                    = RGBA{0, 89, 138, 255},
	.SKY_900                    = RGBA{2, 74, 112, 255},
	.SKY_950                    = RGBA{5, 47, 74, 255},
	.BLUE_50                    = RGBA{239, 246, 255, 255},
	.BLUE_100                   = RGBA{219, 234, 254, 255},
	.BLUE_200                   = RGBA{190, 219, 255, 255},
	.BLUE_300                   = RGBA{142, 197, 255, 255},
	.BLUE_400                   = RGBA{81, 162, 255, 255},
	.BLUE_500                   = RGBA{43, 127, 255, 255},
	.BLUE_600                   = RGBA{21, 93, 252, 255},
	.BLUE_700                   = RGBA{20, 71, 230, 255},
	.BLUE_800                   = RGBA{25, 60, 184, 255},
	.BLUE_900                   = RGBA{28, 57, 142, 255},
	.BLUE_950                   = RGBA{22, 36, 86, 255},
	.INDIGO_50                  = RGBA{238, 242, 255, 255},
	.INDIGO_100                 = RGBA{224, 231, 255, 255},
	.INDIGO_200                 = RGBA{198, 210, 255, 255},
	.INDIGO_300                 = RGBA{163, 179, 255, 255},
	.INDIGO_400                 = RGBA{124, 134, 255, 255},
	.INDIGO_500                 = RGBA{97, 95, 255, 255},
	.INDIGO_600                 = RGBA{79, 57, 246, 255},
	.INDIGO_700                 = RGBA{67, 45, 215, 255},
	.INDIGO_800                 = RGBA{55, 42, 172, 255},
	.INDIGO_900                 = RGBA{49, 44, 133, 255},
	.INDIGO_950                 = RGBA{30, 26, 77, 255},
	.VIOLET_50                  = RGBA{245, 243, 255, 255},
	.VIOLET_100                 = RGBA{237, 233, 254, 255},
	.VIOLET_200                 = RGBA{221, 214, 255, 255},
	.VIOLET_300                 = RGBA{196, 180, 255, 255},
	.VIOLET_400                 = RGBA{166, 132, 255, 255},
	.VIOLET_500                 = RGBA{142, 81, 255, 255},
	.VIOLET_600                 = RGBA{127, 34, 254, 255},
	.VIOLET_700                 = RGBA{112, 8, 231, 255},
	.VIOLET_800                 = RGBA{93, 14, 192, 255},
	.VIOLET_900                 = RGBA{77, 23, 154, 255},
	.VIOLET_950                 = RGBA{47, 13, 104, 255},
	.PURPLE_50                  = RGBA{250, 245, 255, 255},
	.PURPLE_100                 = RGBA{243, 232, 255, 255},
	.PURPLE_200                 = RGBA{233, 212, 255, 255},
	.PURPLE_300                 = RGBA{218, 178, 255, 255},
	.PURPLE_400                 = RGBA{194, 122, 255, 255},
	.PURPLE_500                 = RGBA{173, 70, 255, 255},
	.PURPLE_600                 = RGBA{152, 16, 250, 255},
	.PURPLE_700                 = RGBA{130, 0, 219, 255},
	.PURPLE_800                 = RGBA{110, 17, 176, 255},
	.PURPLE_900                 = RGBA{89, 22, 139, 255},
	.PURPLE_950                 = RGBA{60, 3, 102, 255},
	.FUCHSIA_50                 = RGBA{253, 244, 255, 255},
	.FUCHSIA_100                = RGBA{250, 232, 255, 255},
	.FUCHSIA_200                = RGBA{246, 207, 255, 255},
	.FUCHSIA_300                = RGBA{244, 168, 255, 255},
	.FUCHSIA_400                = RGBA{237, 106, 255, 255},
	.FUCHSIA_500                = RGBA{225, 42, 251, 255},
	.FUCHSIA_600                = RGBA{200, 0, 222, 255},
	.FUCHSIA_700                = RGBA{168, 0, 183, 255},
	.FUCHSIA_800                = RGBA{138, 1, 148, 255},
	.FUCHSIA_900                = RGBA{114, 19, 120, 255},
	.FUCHSIA_950                = RGBA{75, 0, 79, 255},
	.PINK_50                    = RGBA{253, 242, 248, 255},
	.PINK_100                   = RGBA{252, 231, 243, 255},
	.PINK_200                   = RGBA{252, 206, 232, 255},
	.PINK_300                   = RGBA{253, 165, 213, 255},
	.PINK_400                   = RGBA{251, 100, 182, 255},
	.PINK_500                   = RGBA{246, 51, 154, 255},
	.PINK_600                   = RGBA{230, 0, 118, 255},
	.PINK_700                   = RGBA{198, 0, 92, 255},
	.PINK_800                   = RGBA{163, 0, 76, 255},
	.PINK_900                   = RGBA{134, 16, 67, 255},
	.PINK_950                   = RGBA{81, 4, 36, 255},
	.ROSE_50                    = RGBA{255, 241, 242, 255},
	.ROSE_100                   = RGBA{255, 228, 230, 255},
	.ROSE_200                   = RGBA{255, 204, 211, 255},
	.ROSE_300                   = RGBA{255, 161, 173, 255},
	.ROSE_400                   = RGBA{255, 99, 126, 255},
	.ROSE_500                   = RGBA{255, 32, 86, 255},
	.ROSE_600                   = RGBA{236, 0, 63, 255},
	.ROSE_700                   = RGBA{199, 0, 54, 255},
	.ROSE_800                   = RGBA{165, 0, 54, 255},
	.ROSE_900                   = RGBA{139, 8, 54, 255},
	.ROSE_950                   = RGBA{77, 2, 24, 255},
	.SLATE_50                   = RGBA{248, 250, 252, 255},
	.SLATE_100                  = RGBA{241, 245, 249, 255},
	.SLATE_200                  = RGBA{226, 232, 240, 255},
	.SLATE_300                  = RGBA{202, 213, 226, 255},
	.SLATE_400                  = RGBA{144, 161, 185, 255},
	.SLATE_500                  = RGBA{98, 116, 142, 255},
	.SLATE_600                  = RGBA{69, 85, 108, 255},
	.SLATE_700                  = RGBA{49, 65, 88, 255},
	.SLATE_800                  = RGBA{29, 41, 61, 255},
	.SLATE_900                  = RGBA{15, 23, 43, 255},
	.SLATE_950                  = RGBA{2, 6, 24, 255},
	.GRAY_50                    = RGBA{249, 250, 251, 255},
	.GRAY_100                   = RGBA{243, 244, 246, 255},
	.GRAY_200                   = RGBA{229, 231, 235, 255},
	.GRAY_300                   = RGBA{209, 213, 220, 255},
	.GRAY_400                   = RGBA{153, 161, 175, 255},
	.GRAY_500                   = RGBA{106, 114, 130, 255},
	.GRAY_600                   = RGBA{74, 85, 101, 255},
	.GRAY_700                   = RGBA{54, 65, 83, 255},
	.GRAY_800                   = RGBA{30, 41, 57, 255},
	.GRAY_900                   = RGBA{16, 24, 40, 255},
	.GRAY_950                   = RGBA{3, 7, 18, 255},
	.ZINC_50                    = RGBA{250, 250, 250, 255},
	.ZINC_100                   = RGBA{244, 244, 245, 255},
	.ZINC_200                   = RGBA{228, 228, 231, 255},
	.ZINC_300                   = RGBA{212, 212, 216, 255},
	.ZINC_400                   = RGBA{159, 159, 169, 255},
	.ZINC_500                   = RGBA{113, 113, 123, 255},
	.ZINC_600                   = RGBA{82, 82, 92, 255},
	.ZINC_700                   = RGBA{63, 63, 70, 255},
	.ZINC_800                   = RGBA{39, 39, 42, 255},
	.ZINC_900                   = RGBA{24, 24, 27, 255},
	.ZINC_950                   = RGBA{9, 9, 11, 255},
	.NEUTRAL_50                 = RGBA{250, 250, 250, 255},
	.NEUTRAL_100                = RGBA{245, 245, 245, 255},
	.NEUTRAL_200                = RGBA{229, 229, 229, 255},
	.NEUTRAL_300                = RGBA{212, 212, 212, 255},
	.NEUTRAL_400                = RGBA{161, 161, 161, 255},
	.NEUTRAL_500                = RGBA{115, 115, 115, 255},
	.NEUTRAL_600                = RGBA{82, 82, 82, 255},
	.NEUTRAL_700                = RGBA{64, 64, 64, 255},
	.NEUTRAL_800                = RGBA{38, 38, 38, 255},
	.NEUTRAL_900                = RGBA{23, 23, 23, 255},
	.NEUTRAL_950                = RGBA{10, 10, 10, 255},
	.STONE_50                   = RGBA{250, 250, 249, 255},
	.STONE_100                  = RGBA{245, 245, 244, 255},
	.STONE_200                  = RGBA{231, 229, 228, 255},
	.STONE_300                  = RGBA{214, 211, 209, 255},
	.STONE_400                  = RGBA{166, 160, 155, 255},
	.STONE_500                  = RGBA{121, 113, 107, 255},
	.STONE_600                  = RGBA{87, 83, 77, 255},
	.STONE_700                  = RGBA{68, 64, 59, 255},
	.STONE_800                  = RGBA{41, 37, 36, 255},
	.STONE_900                  = RGBA{28, 25, 23, 255},
	.STONE_950                  = RGBA{12, 10, 9, 255},
	.MAUVE_50                   = RGBA{250, 250, 250, 255},
	.MAUVE_100                  = RGBA{243, 241, 243, 255},
	.MAUVE_200                  = RGBA{231, 228, 231, 255},
	.MAUVE_300                  = RGBA{215, 208, 215, 255},
	.MAUVE_400                  = RGBA{168, 158, 169, 255},
	.MAUVE_500                  = RGBA{121, 105, 123, 255},
	.MAUVE_600                  = RGBA{89, 76, 91, 255},
	.MAUVE_700                  = RGBA{70, 57, 71, 255},
	.MAUVE_800                  = RGBA{42, 33, 44, 255},
	.MAUVE_900                  = RGBA{29, 22, 30, 255},
	.MAUVE_950                  = RGBA{12, 9, 12, 255},
	.OLIVE_50                   = RGBA{251, 251, 249, 255},
	.OLIVE_100                  = RGBA{244, 244, 240, 255},
	.OLIVE_200                  = RGBA{232, 232, 227, 255},
	.OLIVE_300                  = RGBA{216, 216, 208, 255},
	.OLIVE_400                  = RGBA{171, 171, 156, 255},
	.OLIVE_500                  = RGBA{124, 124, 103, 255},
	.OLIVE_600                  = RGBA{91, 91, 75, 255},
	.OLIVE_700                  = RGBA{71, 71, 57, 255},
	.OLIVE_800                  = RGBA{43, 43, 34, 255},
	.OLIVE_900                  = RGBA{29, 29, 22, 255},
	.OLIVE_950                  = RGBA{12, 12, 9, 255},
	.MIST_50                    = RGBA{249, 251, 251, 255},
	.MIST_100                   = RGBA{241, 243, 243, 255},
	.MIST_200                   = RGBA{227, 231, 232, 255},
	.MIST_300                   = RGBA{208, 214, 216, 255},
	.MIST_400                   = RGBA{156, 168, 171, 255},
	.MIST_500                   = RGBA{103, 120, 124, 255},
	.MIST_600                   = RGBA{75, 88, 91, 255},
	.MIST_700                   = RGBA{57, 68, 71, 255},
	.MIST_800                   = RGBA{34, 41, 43, 255},
	.MIST_900                   = RGBA{22, 27, 29, 255},
	.MIST_950                   = RGBA{9, 11, 12, 255},
	.TAUPE_50                   = RGBA{251, 250, 249, 255},
	.TAUPE_100                  = RGBA{243, 241, 241, 255},
	.TAUPE_200                  = RGBA{232, 228, 227, 255},
	.TAUPE_300                  = RGBA{216, 210, 208, 255},
	.TAUPE_400                  = RGBA{171, 160, 156, 255},
	.TAUPE_500                  = RGBA{124, 109, 103, 255},
	.TAUPE_600                  = RGBA{91, 79, 75, 255},
	.TAUPE_700                  = RGBA{71, 60, 57, 255},
	.TAUPE_800                  = RGBA{43, 36, 34, 255},
	.TAUPE_900                  = RGBA{29, 24, 22, 255},
	.TAUPE_950                  = RGBA{12, 10, 9, 255},
}


/*
Returns the sRGB RGBA value for a named palette Color enum member.
*/
css_color_to_rgba :: proc(c: Color) -> RGBA {
	if c == .INVALID do return RGBA{}
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
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Colors,
}

/*
Returns true when a Colors union value is a dynamic callback proc.
*/
colors_is_proc :: proc(c: Colors) -> bool {
	#partial switch _ in c {
	case proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Colors:
		return true
	}
	return false
}

/*
Clamps a float to the 0-1 range for color channel math.
*/
color_clamp01 :: proc(v: f32) -> f32 {
	return math.clamp(v, 0, 1)
}

/*
Converts a 0-1 float to an 8-bit channel, clamped and rounded.
*/
color_u8_from01 :: proc(v: f32) -> u8 {
	return u8(math.round(color_clamp01(v) * 255))
}

/*
Converts a linear RGB component to sRGB using the standard gamma curve.
*/
color_linear_to_srgb :: proc(c: f32) -> f32 {
	if c <= 0.0031308 {
		return 12.92 * c
	}
	return 1.055 * math.pow(c, 1.0 / 2.4) - 0.055
}

/*
Maps a hue angle (0-360°) to a unit RGB triple for pure hue.
*/
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

/*
Computes one HSL channel from p, q, and normalized hue offset t.
*/
color_hue_to_channel :: proc(p, q, t: f32) -> f32 {
	channel_t := math.mod(t, 1)
	if channel_t < 0 do channel_t += 1
	if channel_t < 1.0 / 6 do return p + (q - p) * 6 * channel_t
	if channel_t < 1.0 / 2 do return q
	if channel_t < 2.0 / 3 do return p + (q - p) * (2.0 / 3 - channel_t) * 6
	return p
}

/*
Converts HSLA (hue/saturation/lightness/alpha) to sRGB RGBA.
*/
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


/*
Converts HWBA (hue/whiteness/blackness/alpha) to sRGB RGBA.
*/
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

/*
Converts CIE LCH (L*a*b* polar) to sRGB RGBA.
*/
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

	/*
	Inverts the CIE Lab lightness function f for LCH-to-XYZ conversion.
	*/
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

/*
Converts OK LCH perceptual color to sRGB RGBA.
*/
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
/*
Identity conversion; passes RGBA through unchanged.
*/
rgba_to_rgba :: proc(c: RGBA) -> RGBA {
	return c
}

/*
Unpacks a packed #RRGGBBAA Hex value into RGBA byte channels.
*/
hex_to_rgba :: proc(c: Hex) -> RGBA {
	v := u32(c)
	return RGBA{u8(v >> 24), u8(v >> 16), u8(v >> 8), u8(v)}
}


/*
Alias that normalizes a palette Color through the RGBA identity path.
*/
css_color_to_rba :: proc(c: Color) -> RGBA {
	return rgba_to_rgba(css_color_to_rgba(c))
}

/*
Overloaded conversion dispatch from each Colors variant type to RGBA.
*/
to_rgba_color :: proc {
	css_color_to_rba,
	rgba_to_rgba,
	hex_to_rgba,
	hsla_to_rgba,
	hwba_to_rgba,
	lcha_to_rgba,
	oklcha_to_rgba,
}

/*
Resolves any Colors value (including callbacks) to RGBA using widget context.

Handles .Inherit by walking the current style stack for a parent color.
*/
to_rgba :: proc(c: Colors, state: ^$S, event: Widget_Event(S)) -> (rgba: RGBA, ok: bool) {
	#partial switch v in c {
	case Color:
		if v == .INVALID do return {}, false
		if v == .INHERIT {
			parent := ui_style_current()
			#partial switch c in parent.color {
			case RGBA:
				return c, true
			case Color:
				if c == .INVALID do return {}, false
				return css_color_to_rgba(c), true
			}
			return {}, false
		}
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
	case proc(
		     frame_state: Widget_Frame_State,
		     widget_event: Widget_Event(Widget_Frame_State),
	     ) -> Colors:
		ui_state := (^Widget_Frame_State)(cast(rawptr)state)^
		ui_event := Widget_Event(Widget_Frame_State) {
			frame_state = ui_state,
		}
		return to_rgba(v(ui_state, ui_event), state, event)
	}
	return {}, false
}

/*
Converts RGBA 0-255 channels to normalized [4]f32 for GPU/shader use.
*/
rgba_to_f32 :: proc(c: RGBA) -> [4]f32 {
	return {f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, f32(c.a) / 255}
}

/*
Converts any static Colors variant to normalized [4]f32.

Callback proc variants are not supported; returns zero for .Invalid.
*/
color_to_f32 :: proc(c: Colors) -> [4]f32 {
	rgba: RGBA

	#partial switch v in c {
	case Color:
		if v == .INVALID do return {}
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
