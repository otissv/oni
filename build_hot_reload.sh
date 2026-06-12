#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

OUT_DIR="build/hot_reload"
HOST_EXE="game_hot_reload"
WATCH_PID_FILE="build/hot_reload/.watch.pid"

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

is_game_running() {
	pgrep -x "$HOST_EXE" > /dev/null 2>&1
}

build_game() {
	mkdir -p "$OUT_DIR"
	echo "Building game${LIB_EXT}"
	odin build game -build-mode:dll "${ODIN_FLAGS[@]}" -out:"${OUT_DIR}/game_tmp${LIB_EXT}"
	mv -f "${OUT_DIR}/game_tmp${LIB_EXT}" "${OUT_DIR}/game${LIB_EXT}"
}

build_host() {
	echo "Building ${HOST_EXE}"
	odin build host "${ODIN_FLAGS[@]}" -out:"${HOST_EXE}"
}

start_game() {
	if is_game_running; then
		echo "Game already running"
		return
	fi

	if [[ ! -x "$HOST_EXE" ]]; then
		build_host
	fi

	echo "Starting ${HOST_EXE}"
	./"$HOST_EXE" &
	echo "Game PID $!"
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
		while inotifywait -e close_write,move_self,create -r game --format '%w%f' > /dev/null; do
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
		echo "Hot reloading..."
		exit 0
	fi

	build_host
	start_game
	start_watch || true
	echo ""
	echo "Save game/*.odin to auto-rebuild. F5/F6 reload in the game window."
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
	echo "Usage: $0 [run|build|watch|stop]"
	echo "  run    Build and start the game with auto-rebuild watcher (default)"
	echo "  build  Rebuild game${LIB_EXT} only"
	echo "  watch  Start auto-rebuild watcher"
	echo "  stop   Stop game and watcher"
	exit 1
	;;
esac
