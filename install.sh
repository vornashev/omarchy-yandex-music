#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="vornashev.yandex-music"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
APP_DIR="$HOME/.local/share/omarchy-yandex-music"
UNIT_DIR="$HOME/.config/systemd/user"
MARKER="$APP_DIR/.installed-version"
BACKEND_ONLY=0

case "${1:-}" in
"") ;;
--backend-only) BACKEND_ONLY=1 ;;
*)
  echo "Usage: $0 [--backend-only]" >&2
  exit 2
  ;;
esac

for command in python git mpv systemctl jq flock; do
  if ! command -v "$command" >/dev/null; then
    echo "Missing dependency: $command" >&2
    echo "On Omarchy, install missing packages with: omarchy pkg add python git mpv jq util-linux" >&2
    exit 1
  fi
done

VERSION="$(jq -er '.version' "$ROOT/manifest.json")"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
mkdir -p "$RUNTIME_DIR"
exec 9>"$RUNTIME_DIR/omarchy-yandex-music-install.lock"
flock 9

mkdir -p "$PLUGIN_DIR" "$APP_DIR" "$HOME/.local/bin" "$UNIT_DIR" \
  "$HOME/.config/omarchy-yandex-music"
chmod 700 "$HOME/.config/omarchy-yandex-music"

# `omarchy plugin add` clones the whole repository directly into PLUGIN_DIR.
# Keep legacy `git clone && ./install.sh` installations compatible by copying
# everything required for future automatic backend updates into that location.
if [[ "$(realpath "$ROOT")" != "$(realpath "$PLUGIN_DIR")" ]]; then
  mkdir -p "$PLUGIN_DIR/backend" "$PLUGIN_DIR/bin" "$PLUGIN_DIR/systemd"
  install -m 644 "$ROOT/manifest.json" "$ROOT/BarWidget.qml" \
    "$ROOT/BarPlayer.qml" "$ROOT/WidgetLogic.qml" "$ROOT/Panel.qml" \
    "$ROOT/CatalogController.qml" "$ROOT/CatalogImage.qml" "$ROOT/LibraryController.qml" \
    "$ROOT/requirements.txt" "$PLUGIN_DIR/"
  install -m 755 "$ROOT/install.sh" "$ROOT/bootstrap.sh" "$ROOT/uninstall.sh" "$PLUGIN_DIR/"
  install -m 755 "$ROOT/backend/backend.py" "$PLUGIN_DIR/backend/backend.py"
  install -m 755 "$ROOT/bin/omarchy-yandex-music" "$PLUGIN_DIR/bin/omarchy-yandex-music"
  install -m 644 "$ROOT/systemd/omarchy-yandex-music.service" \
    "$PLUGIN_DIR/systemd/omarchy-yandex-music.service"
fi

# Fast path used whenever the plugin is loaded. It also starts a previously
# installed but inactive service without reinstalling Python dependencies.
if ((BACKEND_ONLY)) &&
  [[ -r "$MARKER" && "$(<"$MARKER")" == "$VERSION" ]] &&
  [[ -x "$APP_DIR/venv/bin/python" && -f "$APP_DIR/backend.py" ]] &&
  [[ -x "$HOME/.local/bin/omarchy-yandex-music" && -f "$UNIT_DIR/omarchy-yandex-music.service" ]]; then
  systemctl --user daemon-reload
  systemctl --user enable --now omarchy-yandex-music.service >/dev/null
  echo "Yandex Music backend $VERSION is ready."
  exit 0
fi

install -m 755 "$ROOT/backend/backend.py" "$APP_DIR/backend.py"
install -m 755 "$ROOT/bin/omarchy-yandex-music" "$HOME/.local/bin/omarchy-yandex-music"
install -m 644 "$ROOT/systemd/omarchy-yandex-music.service" \
  "$UNIT_DIR/omarchy-yandex-music.service"

if [[ ! -x "$APP_DIR/venv/bin/python" ]]; then
  python -m venv "$APP_DIR/venv"
fi
"$APP_DIR/venv/bin/python" -m pip install --disable-pip-version-check --quiet --upgrade pip
"$APP_DIR/venv/bin/pip" install --disable-pip-version-check --quiet --upgrade -r "$ROOT/requirements.txt"

systemctl --user daemon-reload
systemctl --user enable omarchy-yandex-music.service >/dev/null
systemctl --user restart omarchy-yandex-music.service
printf '%s\n' "$VERSION" >"$MARKER"
chmod 644 "$MARKER"

if ((BACKEND_ONLY)); then
  echo "Yandex Music backend $VERSION installed."
  exit 0
fi

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
