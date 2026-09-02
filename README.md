# Yandex Music for Omarchy

A native, browser-free Yandex Music mini-player for the [Omarchy](https://omarchy.org/) shell.
The browser is used only for Yandex Device OAuth. Playback runs in a sandboxed user service through `mpv`.

> This project uses the unofficial [yandex-music-api](https://github.com/MarshalX/yandex-music-api) library and is not affiliated with Yandex. A Yandex Music subscription may be required for full tracks.

## Features

- Mini-player in the Omarchy bar: previous, play/pause, next, cover, artist, title, and progress
- Popup with Now Playing, Library, and Search tabs
- Liked tracks and personal playlists
- Add or remove the current track from “My Likes”
- Scrollable playback queue with direct track selection
- Clickable individual artists in the popup and queue
- Drag-to-seek with a live target-time preview
- Smooth volume slider and mute toggle
- Queue, position, volume, and pause state restoration after restart
- Automatic OAuth token refresh and stream retry/recovery
- System media keys and MPRIS integration with sanitized metadata
- No permanently open browser and no Yandex credentials stored

## Requirements

- Omarchy 4.x
- Python 3
- `mpv`
- `git`
- An active network connection

## Install

```bash
git clone https://github.com/vornashev/omarchy-yandex-music.git
cd omarchy-yandex-music
./install.sh
```

The installer works without `sudo`. It creates:

- `~/.config/omarchy/plugins/vornashev.yandex-music/`
- `~/.local/share/omarchy-yandex-music/`
- `~/.local/bin/omarchy-yandex-music`
- `~/.config/systemd/user/omarchy-yandex-music.service`

After installation, click the player in the bar and complete Yandex Device OAuth in your browser. The browser can then be closed.

## Controls

### Bar

- Previous / Play-Pause / Next buttons control playback
- Keyboard media keys control previous, play/pause, and next through MPRIS
- Click the cover or track information to open the popup

### Popup

- Drag the progress slider; seeking is committed when released
- Drag or click the volume slider; click the speaker to mute
- Click the heart button (or press `L`) to like/unlike the current track
- Click any queue track to play it
- Click an artist in the header or queue to load that artist's tracks
- Use `1`, `2`, `3` to switch tabs and `Escape` to close

## Update

```bash
cd omarchy-yandex-music
git pull --ff-only
./install.sh
```

## Uninstall

Keep the local OAuth token and playback state:

```bash
./uninstall.sh
```

Remove everything, including the token:

```bash
./uninstall.sh --purge
```

## Troubleshooting

```bash
systemctl --user status omarchy-yandex-music.service
journalctl --user -u omarchy-yandex-music.service -n 100
omarchy-yandex-music status | jq
omarchy restart shell
```

OAuth token and playback state are stored under `~/.config/omarchy-yandex-music/` with mode `600` and are excluded from this repository. The MPRIS interface publishes only track metadata and artwork—not temporary audio stream URLs.

---

## Русский

Нативный мини-плеер Яндекс Музыки для верхней панели Omarchy. Браузер нужен только один раз для Device OAuth; музыку в фоне воспроизводит `mpv`.

### Установка

```bash
git clone https://github.com/vornashev/omarchy-yandex-music.git
cd omarchy-yandex-music
./install.sh
```

После установки нажмите на плеер в панели и подтвердите вход через Яндекс. Для полного воспроизведения может потребоваться подписка Яндекс Музыки.

Проект использует неофициальный API и не связан с компанией Яндекс.
