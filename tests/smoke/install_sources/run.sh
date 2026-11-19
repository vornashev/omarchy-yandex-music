#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
probe="$(mktemp -d)"
trap 'rm -rf "$probe"' EXIT
home="$probe/home"
runtime="$probe/runtime"
app="$home/.local/share/omarchy-yandex-music"
plugin="$home/.config/omarchy/plugins/vornashev.yandex-music"
unit="$home/.config/systemd/user/omarchy-yandex-music.service"
mkdir -p "$app/venv/bin" "$home/.local/bin" "$(dirname "$unit")" "$runtime" "$probe/bin"
printf '%s\n' "$(jq -r .version "$root/manifest.json")" >"$app/.installed-version"
printf '%s\n' "$(sha256sum "$root/requirements.txt" \
  "$root/vendor/yandex_music-3.2.2-py3-none-any.whl" | cut -d' ' -f1 | sha256sum | cut -d' ' -f1)" \
  >"$app/.installed-dependencies"
printf '#!/bin/sh\nexit 0\n' >"$app/venv/bin/python"
chmod +x "$app/venv/bin/python"
: >"$app/backend.py"
: >"$home/.local/bin/omarchy-yandex-music"
chmod +x "$home/.local/bin/omarchy-yandex-music"
: >"$unit"
printf '#!/bin/sh\nexit 0\n' >"$probe/bin/systemctl"
chmod +x "$probe/bin/systemctl"

mkdir -p "$plugin"
printf 'old layout\n' >"$plugin/BarWidget.qml"

HOME="$home" XDG_RUNTIME_DIR="$runtime" PATH="$probe/bin:$PATH" \
  bash "$root/install.sh" --backend-only >"$probe/output" 2>&1

while IFS= read -r -d '' source; do
  relative="${source#"$root/"}"
  if ! cmp -s "$source" "$plugin/$relative"; then
    echo "Installer omitted or changed $relative" >&2
    exit 1
  fi
  if [[ -e "$plugin/$(basename "$source")" ]]; then
    echo "Installer retained a file from the flat layout: $source" >&2
    exit 1
  fi
done < <(find "$root/qml" -type f \( -name '*.qml' -o -name '*.js' \) -print0)
cmp "$root/manifest.json" "$plugin/manifest.json"
entry="$(jq -r .entryPoints.barWidget "$plugin/manifest.json")"
[[ -f "$plugin/$entry" ]]
echo 'Installer source copy smoke: OK'
