#!/usr/bin/env bash
# Shared build helpers for Oni hot-reload and production scripts.
# shellcheck shell=bash
#
# Required before sourcing:
#   ONI_ROOT  — absolute path to the framework root
# Optional:
#   PROJECT_ROOT — absolute path to the consumer project (parent of oni/ by default)

if [[ -z "${ONI_ROOT:-}" ]]; then
	echo "lib_build.sh: ONI_ROOT must be set before sourcing" >&2
	return 1 2>/dev/null || exit 1
fi

# shellcheck source=../odin_collections.sh
source "${ONI_ROOT}/odin_collections.sh"

if [[ -z "${PROJECT_ROOT:-}" ]]; then
	if [[ -n "${ONI_PROJECT_ROOT:-}" ]]; then
		PROJECT_ROOT="$(cd "$ONI_PROJECT_ROOT" && pwd)"
	else
		PROJECT_ROOT="$(cd "${ONI_ROOT}/.." && pwd)"
	fi
fi

oni_when_os() {
	case "$(uname -s)" in
	Darwin) echo "darwin" ;;
	MINGW* | MSYS* | CYGWIN*) echo "windows" ;;
	*) echo "linux" ;;
	esac
}

ONI_OS="$(oni_when_os)"

case "$ONI_OS" in
darwin) ONI_LIB_EXT=".dylib" ;;
windows) ONI_LIB_EXT=".dll" ;;
*) ONI_LIB_EXT=".so" ;;
esac

# Single -extra-linker-flags (Odin keeps only the last occurrence).
# Callers may override ONI_EXTRA_LINKER_FLAGS before calling oni_font_libs.
oni_font_libs() {
	local extra="${ONI_EXTRA_LINKER_FLAGS:-${ONI_SDL3_LINKER_FLAGS}-lfreetype -lharfbuzz}"
	echo "-extra-linker-flags:${extra}"
}

oni_has_sdl3_image() {
	for lib in /usr/lib/libSDL3_image.so /usr/local/lib/libSDL3_image.so; do
		if [[ -e "$lib" ]]; then
			return 0
		fi
	done

	local libs
	libs="$(ldconfig -p 2>/dev/null || true)"
	[[ "$libs" == *libSDL3_image* ]]
}

oni_check_project_layout() {
	local missing=()

	if [[ ! -f "${PROJECT_ROOT}/main.odin" ]]; then
		missing+=("main.odin (hot-reload host; see oni/templates/main.odin)")
	fi
	if [[ ! -d "${PROJECT_ROOT}/app" ]]; then
		missing+=("app/ (copy from oni/templates/app/)")
	fi

	if ((${#missing[@]} > 0)); then
		echo "Project root: ${PROJECT_ROOT}"
		echo "Missing consumer files (Oni is a framework — the user project owns these):"
		for dep in "${missing[@]}"; do
			echo "  - ${dep}"
		done
		echo "Set ONI_PROJECT_ROOT if the project root is not the parent of oni/."
		return 1
	fi
}

# Production builds need app/; release/main.odin is created from the template when missing.
# Hot-reload main.odin is not required.
oni_check_production_layout() {
	local missing=()

	if [[ ! -d "${PROJECT_ROOT}/app" ]]; then
		missing+=("app/ (copy from oni/templates/app/)")
	fi

	if ((${#missing[@]} > 0)); then
		echo "Project root: ${PROJECT_ROOT}"
		echo "Missing consumer files for a production build:"
		for dep in "${missing[@]}"; do
			echo "  - ${dep}"
		done
		echo "Set ONI_PROJECT_ROOT if the project root is not the parent of oni/."
		return 1
	fi
}

oni_app_name() {
	if [[ -n "${ONI_APP_NAME:-}" ]]; then
		echo "$ONI_APP_NAME"
		return
	fi
	basename "$PROJECT_ROOT"
}

# Executable filename for the current OS (adds .exe on Windows).
oni_production_exe_name() {
	local name
	name="$(oni_app_name)"
	case "$ONI_OS" in
	windows) echo "${name}.exe" ;;
	*) echo "$name" ;;
	esac
}

oni_check_build_deps() {
	local missing=()

	if ! command -v odin > /dev/null 2>&1; then
		missing+=("odin (https://odin-lang.org/)")
	fi

	if ! command -v python3 > /dev/null 2>&1; then
		missing+=("python3 (shader bundle verification / build)")
	fi

	if ! oni_has_sdl3_image; then
		case "$ONI_OS" in
		darwin)
			missing+=("SDL3_image (e.g. brew install sdl3_image)")
			;;
		linux)
			missing+=("sdl3_image (sudo pacman -S sdl3_image)")
			;;
		windows)
			missing+=("SDL3_image.dll on PATH")
			;;
		esac
	fi

	if ((${#missing[@]} > 0)); then
		echo "Missing build dependencies:"
		for dep in "${missing[@]}"; do
			echo "  - ${dep}"
		done
		return 1
	fi
}

oni_build_shaders() {
	python3 "${ONI_ROOT}/scripts/build_shaders.py"
}
