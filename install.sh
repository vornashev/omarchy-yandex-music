#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="vornashev.yandex-music"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
APP_DIR="$HOME/.local/share/omarchy-yandex-music"
UNIT_DIR="$HOME/.config/systemd/user"

for command in python git mpv systemctl jq; do
  if ! command -v "$command" >/dev/null; then
    echo "Missing dependency: $command" >&2
    echo "On Omarchy, install missing packages with: omarchy pkg add python git mpv jq" >&2
    exit 1
  fi
done

mkdir -p "$PLUGIN_DIR" "$APP_DIR" "$HOME/.local/bin" "$UNIT_DIR" \
  "$HOME/.config/omarchy-yandex-music"
chmod 700 "$HOME/.config/omarchy-yandex-music"

# Keep the repository itself usable as an Omarchy plugin checkout. When it is
# cloned elsewhere, install only the plugin-facing files into user config.
if [[ "$(realpath "$ROOT")" != "$(realpath "$PLUGIN_DIR")" ]]; then
  install -m 644 "$ROOT/manifest.json" "$ROOT/BarWidget.qml" \
    "$ROOT/BarPlayer.qml" "$ROOT/WidgetLogic.qml" "$ROOT/Panel.qml" "$PLUGIN_DIR/"
fi

install -m 755 "$ROOT/backend/backend.py" "$APP_DIR/backend.py"
install -m 755 "$ROOT/bin/omarchy-yandex-music" "$HOME/.local/bin/omarchy-yandex-music"
install -m 644 "$ROOT/systemd/omarchy-yandex-music.service" \
  "$UNIT_DIR/omarchy-yandex-music.service"

if [[ ! -x "$APP_DIR/venv/bin/python" ]]; then
  python -m venv "$APP_DIR/venv"
fi
"$APP_DIR/venv/bin/python" -m pip install --upgrade pip
"$APP_DIR/venv/bin/pip" install --upgrade -r "$ROOT/requirements.txt"

systemctl --user daemon-reload
systemctl --user enable omarchy-yandex-music.service >/dev/null
systemctl --user restart omarchy-yandex-music.service

if command -v omarchy-shell >/dev/null && omarchy-shell shell ping >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null
  if omarchy plugin list --json 2>/dev/null | jq -e '.[] | select(.id == "tema.yandex-music")' >/dev/null; then
    omarchy plugin disable tema.yandex-music >/dev/null || true
  fi
  omarchy plugin enable "$PLUGIN_ID" --after omarchy.clock
else
  echo "Omarchy Shell is not running. Enable the plugin after login:"
  echo "  omarchy plugin enable $PLUGIN_ID --after omarchy.clock"
fi

echo
echo "Yandex Music for Omarchy installed."
echo "Click the player in the bar and sign in through Yandex Device OAuth."
