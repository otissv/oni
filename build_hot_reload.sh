#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

ONI_DIR="oni"
OUT_DIR="build/hot_reload"
HOST_EXE="game_hot_reload"
WATCH_PID_FILE="build/hot_reload/.watch.pid"
BUILD_LOCK_FILE="build/hot_reload/.build.lock"

SHADER_DIR="${ONI_DIR}/shaders"
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
	pid="$(pgrep -x "$HOST_EXE" 2>/dev/null | head -1)"
	[[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

app_pid() {
	pgrep -x "$HOST_EXE" 2>/dev/null | head -1
}

build_shaders() {
	if ! command -v glslc > /dev/null 2>&1; then
		echo "glslc not found. Install the Vulkan SDK (or a package that provides glslc)."
		exit 1
	fi

	local compiled=false

	if [[ ! -f "$UI_SPV_FRAG" || "$UI_FRAG" -nt "$UI_SPV_FRAG" ]]; then
		echo "Compiling ui.frag"
		glslc "$UI_FRAG" -o "$UI_SPV_FRAG"
		compiled=true
	fi

	if [[ ! -f "$UI_SPV_VERT" || "$UI_VERT" -nt "$UI_SPV_VERT" ]]; then
		echo "Compiling ui.vert"
		glslc "$UI_VERT" -o "$UI_SPV_VERT"
		compiled=true
	fi

	if [[ "$compiled" == false ]]; then
		echo "Shaders up to date"
	fi
}

build_app_locked() {
	mkdir -p "$OUT_DIR"

	check_build_deps || return 1
	build_shaders
	echo "Compiling app${LIB_EXT}"

	staging="$(mktemp -d "${OUT_DIR}/staging.XXXXXX")"
	cleanup_staging() {
		rm -rf "$staging"
	}
	trap cleanup_staging RETURN

	odin build app -build-mode:dll "${ODIN_FLAGS[@]}" "${FONT_LIBS[@]}" -out:"${staging}/app${LIB_EXT}"
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
	echo "Building ${HOST_EXE}"
	odin build . "${ODIN_FLAGS[@]}" -out:"${HOST_EXE}"
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
	echo "Starting ${HOST_EXE}"
	nohup ./"$HOST_EXE" >>"${OUT_DIR}/app.log" 2>&1 &
	disown -h $! 2>/dev/null || true
	echo "App PID $!"
	echo "Log: ${OUT_DIR}/app.log"
}

stop_app() {
	if is_app_running; then
		pkill -x "$HOST_EXE"
		echo "Stopped ${HOST_EXE}"
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

	echo "Watching ${ONI_DIR} and app/ for changes (save to auto-rebuild)"
	(
		while inotifywait \
			-e close_write,move_self,create \
			-r "${ONI_DIR}" app \
			--exclude '(\.spv\.(frag|vert)$|/\.watch\.pid$|/\.build\.lock$)' \
			--format '%w%f' > /dev/null; do
			if build_app; then
				if is_app_running; then
					echo "Hot reloading..."
				fi
			else
				echo "Build failed — app.so unchanged. Fix compile errors and save again, or press F5 in the app window to reload."
			fi
		done
	) &
	echo $! > "$WATCH_PID_FILE"
	echo "Watcher PID $(cat "$WATCH_PID_FILE")"
}

cmd="${1:-run}"

case "$cmd" in
run)
	build_app

	if is_app_running; then
		echo "Hot reloading... (app already running, PID $(app_pid))"
		echo "No new window will open. Use './build_hot_reload.sh restart' for a fresh window."
		exit 0
	fi

	build_host
	start_app
	start_watch || true
	echo ""
	echo "Save ${ONI_DIR} or app/ sources to auto-rebuild. F5/F6 reload in the app window."
	;;

restart)
	stop_watch
	stop_app
	build_app
	build_host
	start_app
	start_watch || true
	echo ""
	echo "Restarted. Save ${ONI_DIR}/engine or app/ sources to auto-rebuild. F5/F6 reload in the app window."
	;;

build)
	if ! build_app; then
		exit 1
	fi
	if is_app_running; then
		echo "Hot reloading..."
	fi
	;;

watch)
	start_watch
	;;

stop)
	stop_watch
	stop_app
	pkill -f './build_hot_reload.sh' 2>/dev/null || true
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
	exit 1
	;;
esac
