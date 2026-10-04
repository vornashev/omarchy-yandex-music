#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
probe="$(mktemp -d)"
trap 'rm -rf "$probe"' EXIT
mkdir -p "$probe/harness" "$probe/home/.local/bin" \
  "$probe/home/.config/omarchy/plugins/vornashev.yandex-music" "$probe/runtime" "$probe/config"
chmod 700 "$probe/runtime"
cp "$root/tests/smoke/bar_player/shell.qml" "$probe/harness/shell.qml"
cp "$root/tests/smoke/bar_player/Panel.qml" "$probe/harness/Panel.qml"
cp "$root/tests/smoke/bar_player/fake_cli.sh" "$probe/home/.local/bin/omarchy-yandex-music"
chmod 755 "$probe/home/.local/bin/omarchy-yandex-music"
printf '#!/bin/sh\nexit 0\n' >"$probe/home/.config/omarchy/plugins/vornashev.yandex-music/bootstrap.sh"
chmod 755 "$probe/home/.config/omarchy/plugins/vornashev.yandex-music/bootstrap.sh"
for name in BarWidget.qml WidgetLogic.qml MusicSession.qml SessionController.qml TransportIntents.js BarPlayer.qml; do
  ln -s "$root/$name" "$probe/harness/$name"
done
for name in Commons Ui; do
  ln -s "/usr/share/omarchy/shell/$name" "$probe/harness/$name"
done
set +e
env -i HOME="$probe/home" PATH=/usr/bin:/bin QT_QPA_PLATFORM=offscreen \
  XDG_RUNTIME_DIR="$probe/runtime" XDG_CONFIG_HOME="$probe/config" \
  timeout 5 quickshell -p "$probe/harness/shell.qml" --no-color >"$probe/output" 2>&1
set -e
if ! grep -q 'BAR_PLAYER_SMOKE_OK' "$probe/output"; then
  sed -n '1,80p' "$probe/output"
  exit 1
fi
if grep -Eq 'BAR_PLAYER_SMOKE_FAILED|ReferenceError|TypeError|SyntaxError' "$probe/output"; then
  sed -n '1,80p' "$probe/output"
  exit 1
fi
echo 'BarPlayer Quickshell smoke: OK'
