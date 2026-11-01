#!/usr/bin/env bash
# Contract tests for the production build feature.
# Run: ./oni/scripts/test_build_production.sh
# Expects a consumer project as the parent of oni/ (or ONI_PROJECT_ROOT).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_PRODUCTION="${SCRIPT_DIR}/build_production.sh"

if [[ -n "${ONI_PROJECT_ROOT:-}" ]]; then
	PROJECT_ROOT="$(cd "$ONI_PROJECT_ROOT" && pwd)"
else
	PROJECT_ROOT="$(cd "$ONI_ROOT/.." && pwd)"
fi

# shellcheck source=lib_build.sh
source "${SCRIPT_DIR}/lib_build.sh"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

pass() {
	echo "PASS: $*"
}

[[ -x "$BUILD_PRODUCTION" ]] || fail "build_production.sh missing or not executable"

help_out="$("$BUILD_PRODUCTION" help 2>&1)" || fail "help exited non-zero"
[[ "$help_out" == *"build"* ]] || fail "help must document build"
[[ "$help_out" == *"package"* ]] || fail "help must document package"
[[ "$help_out" == *"smoke"* ]] || fail "help must document smoke"
[[ "$help_out" == *"clean"* ]] || fail "help must document clean"
pass "help"

[[ -f "${ONI_ROOT}/templates/release/main.odin" ]] || fail "templates/release/main.odin missing"
pass "release host template"

# #+test must be present so production builds exclude test sources.
sample_test="${ONI_ROOT}/widgets/accordion_test.odin"
[[ -f "$sample_test" ]] || fail "missing ${sample_test}"
head -1 "$sample_test" | rg -q '^#\+test' || fail "accordion_test.odin must start with #+test"
pass "test sources tagged #+test"

OUT_DIR="${PROJECT_ROOT}/build/production"
rm -rf "$OUT_DIR"

# Production must not require hot-reload main.odin. Probe via a subshell with a
# temporary rename only if main exists — restore always.
MAIN_BACKUP=""
if [[ -f "${PROJECT_ROOT}/main.odin" ]]; then
	MAIN_BACKUP="${PROJECT_ROOT}/main.odin.production_test_backup"
	mv "${PROJECT_ROOT}/main.odin" "$MAIN_BACKUP"
fi
restore_main() {
	if [[ -n "$MAIN_BACKUP" && -f "$MAIN_BACKUP" ]]; then
		mv "$MAIN_BACKUP" "${PROJECT_ROOT}/main.odin"
	fi
}
trap restore_main EXIT

build_log="$(mktemp)"
if ! "$BUILD_PRODUCTION" build >"$build_log" 2>&1; then
	cat "$build_log" >&2
	fail "build failed without hot-reload main.odin"
fi
restore_main
trap - EXIT
MAIN_BACKUP=""
pass "build without hot-reload main.odin"

if rg -q 'accordion_test\.odin' "$build_log"; then
	cat "$build_log" >&2
	fail "production build must not compile *_test.odin (accordion_test appeared in log)"
fi
pass "no *_test.odin in production compile"
rm -f "$build_log"

EXE_NAME="$(oni_production_exe_name)"
EXE="${OUT_DIR}/${EXE_NAME}"
[[ -f "$EXE" ]] || fail "expected executable at ${EXE}"
[[ -x "$EXE" || "$ONI_OS" == "windows" ]] || fail "executable not marked executable: ${EXE}"
pass "executable"

[[ -d "${OUT_DIR}/assets" ]] || fail "assets/ not staged into production output"
pass "assets staged"

if [[ -f "${PROJECT_ROOT}/settings.kdl" ]]; then
	[[ -f "${OUT_DIR}/settings.kdl" ]] || fail "settings.kdl not staged"
	pass "settings.kdl staged"
fi

[[ ! -e "${OUT_DIR}/app.so" && ! -e "${OUT_DIR}/app.dll" && ! -e "${OUT_DIR}/app.dylib" ]] ||
	fail "production output must not include a hot-reload app library"
pass "no hot-reload library"

if command -v file > /dev/null 2>&1; then
	file_out="$(file "$EXE")"
	[[ "$file_out" == *"executable"* || "$file_out" == *"ELF"* || "$file_out" == *"Mach-O"* || "$file_out" == *"PE32"* ]] ||
		fail "unexpected binary type: ${file_out}"
	[[ "$file_out" != *"with debug_info"* ]] || fail "production binary must not include debug_info (got: ${file_out})"
	pass "release binary shape"
fi

case "$ONI_OS" in
linux)
	[[ -d "${OUT_DIR}/lib" ]] || fail "linux production output missing lib/"
	[[ -e "${OUT_DIR}/lib/libfreetype.so" || -e "${OUT_DIR}/lib/libfreetype.so.6" ]] ||
		fail "bundled lib/ missing freetype"
	[[ -e "${OUT_DIR}/lib/libharfbuzz.so" || -e "${OUT_DIR}/lib/libharfbuzz.so.0" ]] ||
		fail "bundled lib/ missing harfbuzz"
	[[ -e "${OUT_DIR}/lib/libSDL3_image.so" || -e "${OUT_DIR}/lib/libSDL3_image.so.0" ]] ||
		fail "bundled lib/ missing SDL3_image"
	if [[ -d "${ONI_ROOT}/build/sdl3/lib" ]]; then
		found_sdl=false
		for f in "${OUT_DIR}/lib"/libSDL3.so*; do
			if [[ -e "$f" ]]; then
				found_sdl=true
				break
			fi
		done
		[[ "$found_sdl" == true ]] || fail "patched SDL3 present but not bundled"
	fi
	if command -v readelf > /dev/null 2>&1; then
		rpath="$(readelf -d "$EXE" 2>/dev/null | grep -E 'RPATH|RUNPATH' || true)"
		[[ "$rpath" == *'$ORIGIN/lib'* ]] || fail "expected RUNPATH/RPATH \$ORIGIN/lib, got: ${rpath:-none}"
	fi
	pass "linux libs bundled with \$ORIGIN/lib rpath"
	;;
darwin)
	[[ -d "${OUT_DIR}/lib" ]] || fail "darwin production output missing lib/"
	pass "darwin lib/ staged"
	;;
windows)
	pass "windows packaging path present"
	;;
esac

# Runtime smoke: init + a few frames + clean shutdown.
if ! "$BUILD_PRODUCTION" smoke >"${OUT_DIR}/smoke.log" 2>&1; then
	echo "---- smoke.log ----" >&2
	cat "${OUT_DIR}/smoke.log" >&2 || true
	fail "smoke failed (GPU/Vulkan ICD required for smoke)"
fi
pass "smoke"

PKG_DIR="${OUT_DIR}/packages"
rm -rf "$PKG_DIR"
"$BUILD_PRODUCTION" package || fail "package failed"
shopt -s nullglob
pkgs=("${PKG_DIR}"/*.tar.gz)
((${#pkgs[@]} == 1)) || fail "expected exactly one .tar.gz under ${PKG_DIR}"
# Archive must contain exe + assets + lib (linux)
tar_list="$(tar -tzf "${pkgs[0]}")"
[[ "$tar_list" == *"${EXE_NAME}"* ]] || fail "package missing executable"
[[ "$tar_list" == *assets/* ]] || fail "package missing assets"
if [[ "$ONI_OS" == "linux" ]]; then
	[[ "$tar_list" == *lib/* ]] || fail "package missing lib/"
fi
pass "package archive"

"$BUILD_PRODUCTION" clean || fail "clean failed"
[[ ! -e "$OUT_DIR" ]] || fail "clean must remove ${OUT_DIR}"
pass "clean"

echo ""
echo "All production build contract checks passed."
echo "Project: ${PROJECT_ROOT}"
echo "Framework: ${ONI_ROOT}"
