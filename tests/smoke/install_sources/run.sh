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
  "$root/vendor/yandex_music-3.1.0b2-py3-none-any.whl" | cut -d' ' -f1 | sha256sum | cut -d' ' -f1)" \
  >"$app/.installed-dependencies"
printf '#!/bin/sh\nexit 0\n' >"$app/venv/bin/python"
chmod +x "$app/venv/bin/python"
: >"$app/backend.py"
: >"$home/.local/bin/omarchy-yandex-music"
chmod +x "$home/.local/bin/omarchy-yandex-music"
: >"$unit"
printf '#!/bin/sh\nexit 0\n' >"$probe/bin/systemctl"
chmod +x "$probe/bin/systemctl"

HOME="$home" XDG_RUNTIME_DIR="$runtime" PATH="$probe/bin:$PATH" \
  bash "$root/install.sh" --backend-only >"$probe/output" 2>&1

for name in BarWidget.qml BarPlayer.qml WidgetLogic.qml Panel.qml VolumeControl.qml \
  MusicSession.qml SessionController.qml DetailsReconciler.js TransportIntents.js ActionIntents.js \
  CatalogController.qml CatalogImage.qml CatalogPage.qml LibraryController.qml LibraryPage.qml \
  CollectionController.qml PlaylistSheet.qml SkeletonList.qml AuthPage.qml BarButton.qml IconButton.qml LucideIcon.qml LucideIcons.js CompactPlayer.qml MiniBar.qml MusicSegmented.qml MusicSelect.qml NavController.qml NavHeader.qml CollectionPage.qml NowPane.qml OptionTile.qml PageTabs.qml PlayButton.qml RailItem.qml RailPane.qml RoundImage.qml SeekBar.qml SettingRow.qml SettingsPage.qml TrackPane.qml; do
  if [[ ! -f "$plugin/$name" ]] || ! cmp -s "$root/$name" "$plugin/$name"; then
    echo "Installer omitted or changed $name" >&2
    exit 1
  fi
done
echo 'Installer source copy smoke: OK'
