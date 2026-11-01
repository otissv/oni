#!/usr/bin/env bash
set -euo pipefail

# Oni production build: one optimized executable + staged runtime assets + bundled libs.
# No hot-reload DLL, no debug info, no file watcher, no *_test.odin in the link
# (test sources use #+test and are excluded unless `odin test`).
#
# Typical layout after build:
#   <project>/build/production/
#     <app-name>[.exe]    # statically linked binary
#     assets/             # copied from the consumer project
#     settings.kdl        # copied when present
#     lib/                # bundled shared libraries (Linux/macOS)
#     packages/           # created by `package`
#
# Commands:
#   ./oni/scripts/build_production.sh build
#   ./oni/scripts/build_production.sh run
#   ./oni/scripts/build_production.sh smoke   # build + ONI_SMOKE_FRAMES=3
#   ./oni/scripts/build_production.sh package
#   ./oni/scripts/build_production.sh clean
#
# Override project root / binary name:
#   ONI_PROJECT_ROOT=/path/to/project ONI_APP_NAME=myapp ./oni/scripts/build_production.sh build

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=lib_build.sh
source "${SCRIPT_DIR}/lib_build.sh"

OUT_DIR="${PROJECT_ROOT}/build/production"
RELEASE_DIR="${PROJECT_ROOT}/release"
RELEASE_MAIN="${RELEASE_DIR}/main.odin"
TEMPLATE_MAIN="${ONI_ROOT}/templates/release/main.odin"
PACKAGE_DIR="${OUT_DIR}/packages"

ODIN_RELEASE_FLAGS=(-vet -strict-style -o:speed -disable-assert)

# Shared libraries that must come from the OS (GPU/display stack + libc).
# Everything else NEEDED by the binary is bundled into lib/.
is_system_runtime_lib() {
	local path="$1"
	local base
	base="$(basename "$path")"
	case "$base" in
	libc.so* | libm.so* | libdl.so* | librt.so* | libpthread.so* | libresolv.so* | \
	libgcc_s.so* | libstdc++.so* | ld-linux* | ld64.so* | \
	libvulkan.so* | libdrm.so* | libglapi.so* | libGL.so* | libEGL.so* | libGLESv2.so* | \
	libwayland*.so* | libxkbcommon*.so* | libX*.so* | libxcb*.so* | \
	libffi.so* | libbsd.so* | libmd.so*)
		return 0
		;;
	esac
	return 1
}

ensure_release_host() {
	if [[ -f "$RELEASE_MAIN" ]]; then
		return 0
	fi

	if [[ ! -f "$TEMPLATE_MAIN" ]]; then
		echo "Missing production host template: ${TEMPLATE_MAIN}"
		return 1
	fi

	mkdir -p "$RELEASE_DIR"
	cp "$TEMPLATE_MAIN" "$RELEASE_MAIN"
	echo "Created ${RELEASE_MAIN} from template"
}

# Copies a shared library into dest_dir, preserving the SONAME symlink layout.
copy_lib_tree() {
	local src="$1"
	local dest_dir="$2"
	local base target real_base
	base="$(basename "$src")"
	target="$(readlink -f "$src")"
	real_base="$(basename "$target")"

	cp -f "$target" "${dest_dir}/${real_base}"

	if [[ "$base" != "$real_base" ]]; then
		ln -sfn "$real_base" "${dest_dir}/${base}"
	fi
}

# Prefer patched SDL3 from oni/build/sdl3 when present.
stage_preferred_sdl3() {
	local dest="${OUT_DIR}/lib"
	mkdir -p "$dest"

	if [[ -d "${ONI_ROOT}/build/sdl3/lib" ]]; then
		case "$ONI_OS" in
		linux)
			local f
			for f in "${ONI_ROOT}/build/sdl3/lib"/libSDL3.so*; do
				[[ -e "$f" ]] || continue
				copy_lib_tree "$f" "$dest"
			done
			;;
		darwin)
			local f
			for f in "${ONI_ROOT}/build/sdl3/lib"/libSDL3*.dylib; do
				[[ -e "$f" ]] || continue
				cp -a "$f" "$dest/"
			done
			;;
		windows)
			local f
			for f in "${ONI_ROOT}/build/sdl3/bin"/SDL3.dll "${ONI_ROOT}/build/sdl3/lib"/SDL3.dll; do
				if [[ -f "$f" ]]; then
					cp -f "$f" "${OUT_DIR}/"
				fi
			done
			;;
		esac
	fi
}

# After the exe exists: bundle every NEEDED shared lib that is not a system/GPU lib.
stage_needed_libs_from_exe() {
	local exe="$1"

	case "$ONI_OS" in
	linux)
		if ! command -v ldd > /dev/null 2>&1; then
			echo "ldd not found; cannot bundle shared libraries"
			return 1
		fi
		mkdir -p "${OUT_DIR}/lib"
		local line path
		while IFS= read -r line; do
			path="$(awk '/=>/ {print $3}' <<<"$line")"
			[[ -n "$path" && -e "$path" ]] || continue
			if is_system_runtime_lib "$path"; then
				continue
			fi
			copy_lib_tree "$path" "${OUT_DIR}/lib"
		done < <(ldd "$exe")
		;;
	darwin)
		if ! command -v otool > /dev/null 2>&1; then
			echo "otool not found; cannot bundle shared libraries"
			return 1
		fi
		mkdir -p "${OUT_DIR}/lib"
		local path
		while IFS= read -r path; do
			[[ -e "$path" ]] || continue
			case "$path" in
			/usr/lib/* | /System/*) continue ;;
			esac
			cp -a "$path" "${OUT_DIR}/lib/"
		done < <(otool -L "$exe" | awk 'NR>1 {print $1}')
		;;
	windows)
		# Copy peer DLLs we know about from common install locations / PATH.
		local name
		for name in SDL3.dll SDL3_image.dll libfreetype-6.dll libharfbuzz-0.dll; do
			if command -v "$name" > /dev/null 2>&1; then
				cp -f "$(command -v "$name")" "${OUT_DIR}/"
				continue
			fi
			local candidate
			for candidate in "/mingw64/bin/${name}" "/ucrt64/bin/${name}"; do
				if [[ -f "$candidate" ]]; then
					cp -f "$candidate" "${OUT_DIR}/"
				fi
			done
		done
		;;
	esac
}

stage_assets_and_settings() {
	if [[ -d "${PROJECT_ROOT}/assets" ]]; then
		rm -rf "${OUT_DIR}/assets"
		cp -a "${PROJECT_ROOT}/assets" "${OUT_DIR}/assets"
	else
		echo "Warning: no assets/ directory in ${PROJECT_ROOT}"
	fi

	if [[ -f "${PROJECT_ROOT}/settings.kdl" ]]; then
		cp -f "${PROJECT_ROOT}/settings.kdl" "${OUT_DIR}/settings.kdl"
	fi
}

production_linker_flag() {
	if [[ -d "${ONI_ROOT}/build/sdl3/lib" ]]; then
		case "$ONI_OS" in
		linux)
			PRODUCTION_LINKER_FLAG=(-extra-linker-flags:"-L${ONI_ROOT}/build/sdl3/lib -Wl,-rpath,\$ORIGIN/lib -lfreetype -lharfbuzz")
			;;
		darwin)
			PRODUCTION_LINKER_FLAG=(-extra-linker-flags:"-L${ONI_ROOT}/build/sdl3/lib -Wl,-rpath,@loader_path/lib -lfreetype -lharfbuzz")
			;;
		windows)
			PRODUCTION_LINKER_FLAG=(-extra-linker-flags:"-L${ONI_ROOT}/build/sdl3/lib -lfreetype -lharfbuzz")
			;;
		*)
			PRODUCTION_LINKER_FLAG=(-extra-linker-flags:"${ONI_SDL3_LINKER_FLAGS}-lfreetype -lharfbuzz")
			;;
		esac
	else
		case "$ONI_OS" in
		linux)
			PRODUCTION_LINKER_FLAG=(-extra-linker-flags:"-Wl,-rpath,\$ORIGIN/lib -lfreetype -lharfbuzz")
			;;
		darwin)
			PRODUCTION_LINKER_FLAG=(-extra-linker-flags:"-Wl,-rpath,@loader_path/lib -lfreetype -lharfbuzz")
			;;
		*)
			PRODUCTION_LINKER_FLAG=(-extra-linker-flags:"${ONI_SDL3_LINKER_FLAGS}-lfreetype -lharfbuzz")
			;;
		esac
	fi
}

build_production() {
	local exe_name out_exe
	exe_name="$(oni_production_exe_name)"
	out_exe="${OUT_DIR}/${exe_name}"

	oni_check_build_deps || return 1
	oni_check_production_layout || return 1
	ensure_release_host || return 1
	oni_build_shaders || return 1

	mkdir -p "$OUT_DIR"
	stage_assets_and_settings
	stage_preferred_sdl3
	production_linker_flag

	echo "Compiling production ${exe_name} (-o:speed)"
	(
		cd "$PROJECT_ROOT"
		odin build release \
			"${ODIN_RELEASE_FLAGS[@]}" \
			"${ODIN_COLLECTION_FLAGS[@]}" \
			"${PRODUCTION_LINKER_FLAG[@]}" \
			-out:"${out_exe}"
	)

	if command -v strip > /dev/null 2>&1 && [[ "$ONI_OS" != "windows" ]]; then
		strip "$out_exe"
	fi

	stage_needed_libs_from_exe "$out_exe" || return 1

	echo "Production build: ${out_exe}"
	echo "Run:  ./oni/scripts/build_production.sh run"
	echo "Smoke: ./oni/scripts/build_production.sh smoke"
}

run_production() {
	local exe_name out_exe
	exe_name="$(oni_production_exe_name)"
	out_exe="${OUT_DIR}/${exe_name}"

	if [[ ! -x "$out_exe" && ! -f "$out_exe" ]]; then
		build_production || return 1
	fi

	echo "Starting ${exe_name} (cwd ${OUT_DIR})"
	(
		cd "$OUT_DIR"
		if [[ -d "${OUT_DIR}/lib" ]]; then
			export LD_LIBRARY_PATH="${OUT_DIR}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
			export DYLD_LIBRARY_PATH="${OUT_DIR}/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
		fi
		exec "./${exe_name}" "$@"
	)
}

smoke_production() {
	local exe_name out_exe
	exe_name="$(oni_production_exe_name)"
	out_exe="${OUT_DIR}/${exe_name}"

	if [[ ! -x "$out_exe" && ! -f "$out_exe" ]]; then
		build_production || return 1
	fi

	local frames="${ONI_SMOKE_FRAMES:-3}"
	echo "Smoke: ${exe_name} for ${frames} frames (cwd ${OUT_DIR})"
	(
		cd "$OUT_DIR"
		if [[ -d "${OUT_DIR}/lib" ]]; then
			export LD_LIBRARY_PATH="${OUT_DIR}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
			export DYLD_LIBRARY_PATH="${OUT_DIR}/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
		fi
		export ONI_SMOKE_FRAMES="$frames"
		exec "./${exe_name}"
	)
}

package_production() {
	local exe_name out_exe app_name
	exe_name="$(oni_production_exe_name)"
	app_name="$(oni_app_name)"
	out_exe="${OUT_DIR}/${exe_name}"

	if [[ ! -f "$out_exe" ]]; then
		build_production || return 1
	fi

	local arch stamp archive_name
	arch="$(uname -m)"
	stamp="$(date -u +%Y%m%d)"
	archive_name="${app_name}-${ONI_OS}-${arch}-${stamp}.tar.gz"

	mkdir -p "$PACKAGE_DIR"

	local staging
	staging="$(mktemp -d "${OUT_DIR}/.package.XXXXXX")"
	cleanup_staging() {
		rm -rf "$staging"
	}
	trap cleanup_staging RETURN

	mkdir -p "${staging}/${app_name}"
	cp -a "$out_exe" "${staging}/${app_name}/"
	if [[ -d "${OUT_DIR}/assets" ]]; then
		cp -a "${OUT_DIR}/assets" "${staging}/${app_name}/assets"
	fi
	if [[ -f "${OUT_DIR}/settings.kdl" ]]; then
		cp -f "${OUT_DIR}/settings.kdl" "${staging}/${app_name}/settings.kdl"
	fi
	if [[ -d "${OUT_DIR}/lib" ]]; then
		cp -a "${OUT_DIR}/lib" "${staging}/${app_name}/lib"
	fi
	# Windows DLLs sit next to the exe.
	local dll
	for dll in "${OUT_DIR}"/*.dll; do
		[[ -e "$dll" ]] || continue
		cp -a "$dll" "${staging}/${app_name}/"
	done

	tar -C "$staging" -czf "${PACKAGE_DIR}/${archive_name}" "$app_name"
	echo "Package: ${PACKAGE_DIR}/${archive_name}"
}

clean_production() {
	if [[ -d "$OUT_DIR" ]]; then
		rm -rf "$OUT_DIR"
		echo "Removed ${OUT_DIR}"
	else
		echo "Nothing to clean (${OUT_DIR} absent)"
	fi
}

usage() {
	local exe_name
	exe_name="$(oni_production_exe_name)"
	cat <<EOF
Usage: $0 [build|run|smoke|package|clean|help]

  build    Compile a release executable into build/production/ (default)
  run      Build if needed, then run from build/production/
  smoke    Build if needed, then run ONI_SMOKE_FRAMES frames and exit
  package  Build if needed, then create a .tar.gz under build/production/packages/
  clean    Remove build/production/
  help     Show this help

Production output:
  ${OUT_DIR}/${exe_name}
  ${OUT_DIR}/assets/
  ${OUT_DIR}/settings.kdl   (when present in the project)
  ${OUT_DIR}/lib/           (bundled shared libs; GPU/Vulkan ICD stay on the OS)

Flags: -vet -strict-style -o:speed -disable-assert (no -debug, no hot reload)
Test sources: #+test files are excluded from this build (odin test only)

Still required on the host OS at runtime:
  - Vulkan ICD (and display stack)
  - glibc / OS loader

Project root: ${PROJECT_ROOT}
Framework:    ${ONI_ROOT}
Binary name:  ${exe_name}  (override with ONI_APP_NAME)
EOF
}

cmd="${1:-build}"
shift || true
case "$cmd" in
build)
	build_production
	;;
run)
	run_production "$@"
	;;
smoke)
	smoke_production
	;;
package)
	package_production
	;;
clean)
	clean_production
	;;
help | -h | --help)
	usage
	;;
*)
	usage
	exit 1
	;;
esac
