#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="vornashev.yandex-music"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
APP_DIR="$HOME/.local/share/omarchy-yandex-music"
UNIT="$HOME/.config/systemd/user/omarchy-yandex-music.service"

if command -v omarchy >/dev/null; then
  omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
fi
systemctl --user disable --now omarchy-yandex-music.service >/dev/null 2>&1 || true
rm -f "$UNIT" "$HOME/.local/bin/omarchy-yandex-music"
rm -rf "$APP_DIR" "$PLUGIN_DIR"
systemctl --user daemon-reload

if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "$HOME/.config/omarchy-yandex-music"
  echo "Removed the plugin, backend, token, and playback state."
else
  echo "Removed the plugin and backend. OAuth token and playback state were kept."
  echo "Run '$0 --purge' to remove them too."
fi
