#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
probe="$(mktemp -d)"
trap 'rm -rf "$probe"' EXIT
mkdir -p "$probe/harness" "$probe/home" "$probe/runtime" "$probe/config"
chmod 700 "$probe/runtime"
cp "$root/tests/smoke/library_page/shell.qml" "$probe/harness/shell.qml"
for name in LibraryPage.qml LibraryController.qml CatalogImage.qml SkeletonList.qml MusicSegmented.qml OptionTile.qml IconButton.qml LucideIcon.qml LucideIcons.js; do
  ln -s "$root/$name" "$probe/harness/$name"
done
for name in Commons Ui services; do
  ln -s "/usr/share/omarchy/shell/$name" "$probe/harness/$name"
done
set +e
env -i HOME="$probe/home" PATH=/usr/bin:/bin QT_QPA_PLATFORM=offscreen \
  XDG_RUNTIME_DIR="$probe/runtime" XDG_CONFIG_HOME="$probe/config" \
  timeout 5 quickshell -p "$probe/harness/shell.qml" --no-color >"$probe/output" 2>&1
set -e
if ! grep -q 'LIBRARY_PAGE_SMOKE_OK' "$probe/output"; then
  sed -n '1,100p' "$probe/output"
  exit 1
fi
if grep -Eq 'LIBRARY_PAGE_CHECK_FAILED|LIBRARY_PAGE_SMOKE_FAILED|ERROR: Failed to load configuration|ReferenceError|TypeError|SyntaxError' "$probe/output"; then
  sed -n '1,100p' "$probe/output"
  exit 1
fi
echo 'LibraryPage Quickshell smoke: OK'
