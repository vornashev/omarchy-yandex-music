#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
probe="$(mktemp -d)"
trap 'rm -rf "$probe"' EXIT
shell_root="${OMARCHY_SHELL_DIR:-/usr/share/omarchy/shell}"
for command in quickshell python3 timeout; do
  command -v "$command" >/dev/null || { echo "Missing prerequisite: $command" >&2; exit 1; }
done
[[ -d "$shell_root/Commons" && -f "$shell_root/Ui/qmldir" ]] || {
  echo "Missing Omarchy shell QML modules: $shell_root" >&2; exit 1;
}
mkdir -p "$probe/harness/Ui"
cp "$root/tests/smoke/navigation/shell.qml" "$root/tests/smoke/navigation/Reg.js" "$probe/harness/"
# Keep production components live; only the compositor-specific host is replaced.
for source in "$root"/*.qml "$root"/*.js; do
  ln -s "$source" "$probe/harness/$(basename "$source")"
done
for source in "$shell_root/Ui/"*; do
  ln -s "$source" "$probe/harness/Ui/$(basename "$source")"
done
rm "$probe/harness/Ui/KeyboardPanel.qml"
cp "$root/tests/smoke/navigation/Ui/KeyboardPanel.qml" "$probe/harness/Ui/KeyboardPanel.qml"
for name in Commons services; do ln -s "$shell_root/$name" "$probe/harness/$name"; done
if [[ -n "${NAV_SCREENSHOT_DIR:-}" ]]; then
  mkdir -p "$NAV_SCREENSHOT_DIR"
  NAV_SCREENSHOT_DIR="$(realpath "$NAV_SCREENSHOT_DIR")"
fi
for mode in wide compact mini; do
  home="$probe/$mode/home"
  runtime="$probe/$mode/runtime"
  mkdir -p "$home/.local/bin" "$home/.config/omarchy/plugins/vornashev.yandex-music" "$runtime"
  chmod 700 "$runtime"
  mkdir -p "$home/.local/state/omarchy/current/theme"
  printf '%s\n' 'foreground = "#DCDCE6"' 'background = "#16161F"' 'accent = "#A99BD6"' \
    'color1 = "#F38BA8"' > "$home/.local/state/omarchy/current/theme/colors.toml"
  cp "$root/tests/smoke/navigation/fake_cli.py" "$home/.local/bin/omarchy-yandex-music"
  chmod +x "$home/.local/bin/omarchy-yandex-music"
  printf '#!/bin/sh\nexit 0\n' > "$home/.config/omarchy/plugins/vornashev.yandex-music/bootstrap.sh"
  chmod +x "$home/.config/omarchy/plugins/vornashev.yandex-music/bootstrap.sh"
  set +e
  env -i HOME="$home" PATH=/usr/bin:/bin QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software QSG_RENDER_LOOP=basic \
    XDG_RUNTIME_DIR="$runtime" XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
    NAV_STATE="$probe/$mode/state.json" NAV_LAYOUT="$mode" \
    NAV_SCREENSHOT_DIR="${NAV_SCREENSHOT_DIR:-}" \
    timeout 120 quickshell -p "$probe/harness/shell.qml" --no-color >"$probe/$mode/output" 2>&1
  status=$?
  set -e
  if [[ "$status" != 0 ]] || ! grep -q "NAVIGATION_SMOKE_OK $mode" "$probe/$mode/output" \
    || grep -Eq 'NAVIGATION_SMOKE_FAILED|ERROR: Failed to load configuration|ReferenceError|TypeError|SyntaxError|Cannot assign|Binding loop|FAIL!' "$probe/$mode/output"; then
    cat "$probe/$mode/output"
    [[ ! -f "$probe/$mode/state.commands" ]] || cat "$probe/$mode/state.commands"
    exit 1
  fi
  grep "NAVIGATION_SMOKE_OK $mode" "$probe/$mode/output"
done
if [[ -n "${NAV_SCREENSHOT_DIR:-}" ]]; then
  for scene in X1WideHistory X2WideLikes X3WideLibraryLikesArtist X4WideSearchArtist X5WideNowSource \
               Y1CompactHistory Y2CompactLikes Y3CompactSearchArtist Y4CompactNowSource; do
    [[ -s "$NAV_SCREENSHOT_DIR/$scene.png" ]] || { echo "Missing screenshot: $scene" >&2; exit 1; }
  done
  echo "Nine full-Panel synthetic screenshots: $NAV_SCREENSHOT_DIR"
fi
echo 'Full Panel navigation real key/mouse smoke: OK (offscreen; no live account/compositor)'
