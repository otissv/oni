#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

OUT_DIR="build/hot_reload"
HOST_EXE="game_hot_reload"
WATCH_PID_FILE="build/hot_reload/.watch.pid"
BUILD_LOCK_FILE="build/hot_reload/.build.lock"

SHADER_DIR="game/shaders"
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

is_game_running() {
	local pid
	pid="$(pgrep -x "$HOST_EXE" 2>/dev/null | head -1)"
	[[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

game_pid() {
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

build_game_locked() {
	mkdir -p "$OUT_DIR"

	build_shaders
	echo "Building game${LIB_EXT}"

	staging="$(mktemp -d "${OUT_DIR}/staging.XXXXXX")"
	cleanup_staging() {
		rm -rf "$staging"
	}
	trap cleanup_staging RETURN

	odin build game -build-mode:dll "${ODIN_FLAGS[@]}" "${FONT_LIBS[@]}" -out:"${staging}/game${LIB_EXT}"
	mv -f "${staging}/game${LIB_EXT}" "${OUT_DIR}/game${LIB_EXT}"

	# Drop stale intermediate objects from older build naming schemes.
	rm -f "${OUT_DIR}"/game_tmp-*.o "${OUT_DIR}"/game_test-*.o 2>/dev/null || true
}

build_game() {
	mkdir -p "$OUT_DIR"

	# Serialize builds so the watcher and manual invocations cannot stomp shared .o files.
	(
		flock -x 9 || exit 1
		build_game_locked
	) 9>"$BUILD_LOCK_FILE"
}

build_host() {
	echo "Building ${HOST_EXE}"
	odin build host "${ODIN_FLAGS[@]}" -out:"${HOST_EXE}"
}

start_game() {
	if is_game_running; then
		echo "Game already running (PID $(game_pid))"
		return
	fi

	if [[ ! -x "$HOST_EXE" ]]; then
		build_host
	fi

	mkdir -p "$OUT_DIR"
	echo "Starting ${HOST_EXE}"
	nohup ./"$HOST_EXE" >>"${OUT_DIR}/game.log" 2>&1 &
	disown -h $! 2>/dev/null || true
	echo "Game PID $!"
	echo "Log: ${OUT_DIR}/game.log"
}

stop_game() {
	if is_game_running; then
		pkill -x "$HOST_EXE"
		echo "Stopped ${HOST_EXE}"
	else
		echo "Game is not running"
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

	echo "Watching game/ for changes (save to auto-rebuild)"
	(
		while inotifywait \
			-e close_write,move_self,create \
			-r game \
			--exclude '(\.spv\.(frag|vert)$|/\.watch\.pid$|/\.build\.lock$)' \
			--format '%w%f' > /dev/null; do
			build_game
			if is_game_running; then
				echo "Hot reloading..."
			fi
		done
	) &
	echo $! > "$WATCH_PID_FILE"
	echo "Watcher PID $(cat "$WATCH_PID_FILE")"
}

cmd="${1:-run}"

case "$cmd" in
run)
	build_game

	if is_game_running; then
		echo "Hot reloading... (game already running, PID $(game_pid))"
		echo "No new window will open. Use './build_hot_reload.sh restart' for a fresh window."
		exit 0
	fi

	build_host
	start_game
	start_watch || true
	echo ""
	echo "Save game/*.odin to auto-rebuild. F5/F6 reload in the game window."
	;;

restart)
	stop_watch
	stop_game
	build_game
	build_host
	start_game
	start_watch || true
	echo ""
	echo "Restarted. Save game/*.odin to auto-rebuild. F5/F6 reload in the game window."
	;;

build)
	build_game
	if is_game_running; then
		echo "Hot reloading..."
	fi
	;;

watch)
	start_watch
	;;

stop)
	stop_watch
	stop_game
	;;

*)
	echo "Usage: $0 [run|restart|build|watch|stop]"
	echo "  run      Build and start the game with auto-rebuild watcher (default)"
	echo "  restart  Stop any running game, rebuild, and open a fresh window"
	echo "  build    Rebuild game${LIB_EXT} only"
	echo "  watch    Start auto-rebuild watcher"
	echo "  stop     Stop game and watcher"
	exit 1
	;;
esac
