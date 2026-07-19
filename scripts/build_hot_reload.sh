#!/usr/bin/env bash
set -euo pipefail

# Oni owns build + hot reload. The consumer owns main.odin, app/, and assets/.
#
# Typical layout:
#   <project>/
#     main.odin          # hot-reload host (import oni "./oni")
#     app/               # hot-reload DLL sources
#     assets/
#     oni/               # this framework (or clone/submodule)
#       scripts/build_hot_reload.sh
#       libs/
#       shaders/
#
# Run from anywhere:
#   ./oni/scripts/build_hot_reload.sh run
# Override project root if oni is not a direct child of the project:
#   ONI_PROJECT_ROOT=/path/to/project ./oni/scripts/build_hot_reload.sh run

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -n "${ONI_PROJECT_ROOT:-}" ]]; then
	PROJECT_ROOT="$(cd "$ONI_PROJECT_ROOT" && pwd)"
else
	PROJECT_ROOT="$(cd "$ONI_ROOT/.." && pwd)"
fi

# shellcheck source=../odin_collections.sh
source "${ONI_ROOT}/odin_collections.sh"

OUT_DIR="${PROJECT_ROOT}/build/hot_reload"
HOST_EXE="${PROJECT_ROOT}/game_hot_reload"
WATCH_PID_FILE="${OUT_DIR}/.watch.pid"
BUILD_LOCK_FILE="${OUT_DIR}/.build.lock"

SHADER_DIR="${ONI_ROOT}/shaders"
UI_FRAG="${SHADER_DIR}/ui.frag"
UI_VERT="${SHADER_DIR}/ui.vert"
UI_SPV_FRAG="${SHADER_DIR}/ui.spv.frag"
UI_SPV_VERT="${SHADER_DIR}/ui.spv.vert"

when_os() {
	case "$(uname -s)" in
	Darwin) echo "darwin" ;;
	MINGW* | MSYS* | CYGWIN*) echo "windows" ;;
	*) echo "linux" ;;
	esac
}

OS="$(when_os)"

case "$OS" in
darwin) LIB_EXT=".dylib" ;;
windows) LIB_EXT=".dll" ;;
*) LIB_EXT=".so" ;;
esac

ODIN_FLAGS=(-vet -strict-style -debug)
FONT_LIBS=(-extra-linker-flags:"-lfreetype -lharfbuzz")

has_sdl3_image() {
	for lib in /usr/lib/libSDL3_image.so /usr/local/lib/libSDL3_image.so; do
		if [[ -e "$lib" ]]; then
			return 0
		fi
	done

	local libs
	libs="$(ldconfig -p 2>/dev/null || true)"
	[[ "$libs" == *libSDL3_image* ]]
}

check_project_layout() {
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

check_build_deps() {
	local missing=()

	if ! command -v glslc > /dev/null 2>&1; then
		missing+=("glslc (Vulkan SDK / shaderc package)")
	fi

	if ! has_sdl3_image; then
		case "$OS" in
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

is_app_running() {
	local pid
	pid="$(pgrep -x "$(basename "$HOST_EXE")" 2>/dev/null | head -1)"
	[[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

app_pid() {
	pgrep -x "$(basename "$HOST_EXE")" 2>/dev/null | head -1
}

build_shaders() {
	if ! command -v glslc > /dev/null 2>&1; then
		echo "glslc not found. Install the Vulkan SDK (or a package that provides glslc)."
		exit 1
	fi

	local -a pids=()
	local compiled=false

	if [[ ! -f "$UI_SPV_FRAG" || "$UI_FRAG" -nt "$UI_SPV_FRAG" ]]; then
		echo "Compiling ui.frag"
		glslc "$UI_FRAG" -o "$UI_SPV_FRAG" &
		pids+=($!)
		compiled=true
	fi

	if [[ ! -f "$UI_SPV_VERT" || "$UI_VERT" -nt "$UI_SPV_VERT" ]]; then
		echo "Compiling ui.vert"
		glslc "$UI_VERT" -o "$UI_SPV_VERT" &
		pids+=($!)
		compiled=true
	fi

	local status=0
	for pid in "${pids[@]+"${pids[@]}"}"; do
		if ! wait "$pid"; then
			status=1
		fi
	done
	if ((status != 0)); then
		return 1
	fi

	if [[ "$compiled" == false ]]; then
		echo "Shaders up to date"
	fi
}

build_app_locked() {
	mkdir -p "$OUT_DIR"

	check_build_deps || return 1
	check_project_layout || return 1
	build_shaders
	echo "Compiling app${LIB_EXT}"

	staging="$(mktemp -d "${OUT_DIR}/staging.XXXXXX")"
	cleanup_staging() {
		rm -rf "$staging"
	}
	trap cleanup_staging RETURN

	(
		cd "$PROJECT_ROOT"
		odin build app -build-mode:dll "${ODIN_FLAGS[@]}" "${ODIN_COLLECTION_FLAGS[@]}" "${FONT_LIBS[@]}" -out:"${staging}/app${LIB_EXT}"
	)
	mv -f "${staging}/app${LIB_EXT}" "${OUT_DIR}/app${LIB_EXT}"

	rm -f "${OUT_DIR}"/app_tmp-*.o "${OUT_DIR}"/app_test-*.o "${OUT_DIR}"/game*.so "${OUT_DIR}"/game*.dll "${OUT_DIR}"/game*.dylib 2>/dev/null || true
}

build_app() {
	mkdir -p "$OUT_DIR"
	echo "Building app${LIB_EXT}..."

	if ! (
		flock -x -w 120 9 || {
			echo "Timed out waiting for build lock (${BUILD_LOCK_FILE})."
			echo "Another build may be stuck. Try: pkill -f 'build_hot_reload.sh' && rm -f '${BUILD_LOCK_FILE}'"
			return 1
		}
		build_app_locked
	) 9>"$BUILD_LOCK_FILE"; then
		return 1
	fi
}

build_host() {
	check_build_deps || return 1
	check_project_layout || return 1
	echo "Building $(basename "$HOST_EXE")"
	(
		cd "$PROJECT_ROOT"
		odin build . "${ODIN_FLAGS[@]}" "${ODIN_COLLECTION_FLAGS[@]}" -out:"$HOST_EXE"
	)
}

start_app() {
	if is_app_running; then
		echo "App already running (PID $(app_pid))"
		return
	fi

	if [[ ! -x "$HOST_EXE" ]]; then
		build_host
	fi

	mkdir -p "$OUT_DIR"
	echo "Starting $(basename "$HOST_EXE") (cwd ${PROJECT_ROOT})"
	(
		cd "$PROJECT_ROOT"
		nohup ./$(basename "$HOST_EXE") >>"${OUT_DIR}/app.log" 2>&1 &
		disown -h $! 2>/dev/null || true
		echo "App PID $!"
	)
	echo "Log: ${OUT_DIR}/app.log"
}

stop_app() {
	if is_app_running; then
		pkill -x "$(basename "$HOST_EXE")"
		echo "Stopped $(basename "$HOST_EXE")"
	else
		echo "App is not running"
	fi
}

stop_watch() {
	if [[ -f "$WATCH_PID_FILE" ]]; then
		watch_pid="$(cat "$WATCH_PID_FILE")"
		if kill -0 "$watch_pid" 2>/dev/null; then
			kill "$watch_pid"
			echo "Stopped file watcher (PID ${watch_pid})"
		fi
		rm -f "$WATCH_PID_FILE"
	fi
}

start_watch() {
	if ! command -v inotifywait > /dev/null 2>&1; then
		echo "Install inotify-tools for auto-rebuild on save: sudo pacman -S inotify-tools"
		return 1
	fi

	if [[ -f "$WATCH_PID_FILE" ]]; then
		watch_pid="$(cat "$WATCH_PID_FILE")"
		if kill -0 "$watch_pid" 2>/dev/null; then
			echo "File watcher already running (PID ${watch_pid})"
			return 0
		fi
	fi

	echo "Watching app/, main.odin, and oni/ for changes (save to auto-rebuild)"
	(
		cd "$PROJECT_ROOT"
		while path="$(inotifywait \
			-e close_write,move_self,create \
			-r app "$ONI_ROOT" main.odin \
			--exclude '(\.spv\.(frag|vert)$|/\.watch\.pid$|/\.build\.lock$|/build/|/fixtures/)' \
			--format '%w%f')"; do
			if [[ "$path" == *main.odin ]]; then
				if build_host; then
					echo "Host rebuilt. Restart the window (./oni/scripts/build_hot_reload.sh restart) to pick it up."
				else
					echo "Host rebuild failed."
				fi
				continue
			fi
			if build_app; then
				if is_app_running; then
					echo "Hot reloading..."
				fi
			else
				echo "Build failed — app${LIB_EXT} unchanged. Fix compile errors and save again, or press F5 in the app window to reload."
			fi
		done
	) &
	echo $! > "$WATCH_PID_FILE"
	echo "Watcher PID $(cat "$WATCH_PID_FILE")"
}

cmd="${1:-run}"
case "$cmd" in
run)
	check_project_layout || exit 1
	if is_app_running; then
		if ! build_app; then
			exit 1
		fi
		echo "Hot reloading... (app already running, PID $(app_pid))"
		echo "No new window will open. Use './oni/scripts/build_hot_reload.sh restart' for a fresh window."
		exit 0
	fi

	# Fresh start: compile app and host in parallel after shaders (build_app embeds shader build).
	build_app &
	app_build_pid=$!
	build_host &
	host_build_pid=$!
	app_status=0
	host_status=0
	wait "$app_build_pid" || app_status=$?
	wait "$host_build_pid" || host_status=$?
	if ((app_status != 0 || host_status != 0)); then
		exit 1
	fi
	start_app
	start_watch || true
	echo ""
	echo "Save app/, oni/, or main.odin to auto-rebuild. F5/F6 reload in the app window."
	;;

restart)
	check_project_layout || exit 1
	stop_watch
	stop_app
	build_app &
	app_build_pid=$!
	build_host &
	host_build_pid=$!
	app_status=0
	host_status=0
	wait "$app_build_pid" || app_status=$?
	wait "$host_build_pid" || host_status=$?
	if ((app_status != 0 || host_status != 0)); then
		exit 1
	fi
	start_app
	start_watch || true
	echo ""
	echo "Restarted. Save app/, oni/, or main.odin to auto-rebuild. F5/F6 reload in the app window."
	;;

build)
	check_project_layout || exit 1
	if ! build_app; then
		exit 1
	fi
	if is_app_running; then
		echo "Hot reloading..."
	fi
	;;

watch)
	check_project_layout || exit 1
	start_watch
	;;

stop)
	stop_watch
	stop_app
	pkill -f 'build_hot_reload.sh' 2>/dev/null || true
	rm -f "$BUILD_LOCK_FILE"
	echo "Stopped app, watcher, and build lock"
	;;

*)
	echo "Usage: $0 [run|restart|build|watch|stop]"
	echo "  run      Build and start the app with auto-rebuild watcher (default)"
	echo "  restart  Stop any running app, rebuild, and open a fresh window"
	echo "  build    Rebuild app${LIB_EXT} only"
	echo "  watch    Start auto-rebuild watcher"
	echo "  stop     Stop app and watcher"
	echo ""
	echo "Project root: ${PROJECT_ROOT}"
	echo "Framework:    ${ONI_ROOT}"
	echo "Override with ONI_PROJECT_ROOT if needed."
	exit 1
	;;
esac
