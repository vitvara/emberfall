#!/bin/sh
# Launch Emberfall.  ./run.sh            -> play
#                    ./run.sh editor     -> open in the Godot editor
#                    ./run.sh server [port]  -> dedicated party server (no window)
#                    ./run.sh sim [class] [runs] -> headless balance test
cd "$(dirname "$0")"
GODOT="${GODOT:-$(command -v godot || echo "$HOME/Applications/Godot.app/Contents/MacOS/Godot")}"
case "$1" in
  editor) exec "$GODOT" --editor --path . ;;
  sim)    exec "$GODOT" --headless --path . -- --sim --class="${2:-warden}" --runs="${3:-5}" --verbose ;;
  server) exec "$GODOT" --headless --path . -- --server --port="${2:-24565}" ;;
  *)      exec "$GODOT" --path . ;;
esac
