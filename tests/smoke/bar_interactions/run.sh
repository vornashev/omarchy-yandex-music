#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
probe="$(mktemp -d)"
trap 'rm -rf "$probe"' EXIT
mkdir -p "$probe/harness" "$probe/home" "$probe/runtime" "$probe/config"
chmod 700 "$probe/runtime"
cp "$root/tests/smoke/bar_interactions/shell.qml" "$probe/harness/shell.qml"
for name in BarPlayer.qml BarButton.qml LucideIcon.qml LucideIcons.js SessionController.qml TransportIntents.js; do
  ln -s "$root/$name" "$probe/harness/$name"
done
for name in Commons Ui; do
  ln -s "/usr/share/omarchy/shell/$name" "$probe/harness/$name"
done
# Synthetic logic only: no MusicSession, CLI processes, account data, or shell config writes.
set +e
env -i HOME="$probe/home" PATH=/usr/bin:/bin QT_QPA_PLATFORM=offscreen \
  QT_QUICK_BACKEND=software QSG_RENDER_LOOP=basic \
  XDG_RUNTIME_DIR="$probe/runtime" XDG_CONFIG_HOME="$probe/config" \
  BAR_SCREENSHOT_DIR="${BAR_SCREENSHOT_DIR:-}" \
  timeout 10 quickshell -p "$probe/harness/shell.qml" --no-color >"$probe/output" 2>&1
result=$?
set -e
if [[ "$result" != 0 ]] || ! grep -q 'BAR_INTERACTIONS_SMOKE_OK' "$probe/output" \
    || grep -Eq 'BAR_INTERACTIONS_SMOKE_FAILED|ReferenceError|TypeError|SyntaxError' "$probe/output"; then
  cat "$probe/output"
  exit 1
fi
echo 'BarPlayer production pointer interactions: OK'
