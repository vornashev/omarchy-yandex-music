# Yandex Music for Omarchy

[Русская версия](README.ru.md)

A native Yandex Music mini-player for the [Omarchy](https://omarchy.org/) shell. The browser is used only for Yandex Device OAuth; playback runs in the background through `mpv`.

> This project uses the unofficial [yandex-music-api](https://github.com/MarshalX/yandex-music-api) library and is not affiliated with Yandex. A Yandex Music subscription may be required for full-track playback.

## Screenshots

<p align="center">
  <img src="preview.webp" alt="Yandex Music Now Playing popup in Omarchy" width="900">
</p>

<p align="center">
  <a href="docs/screenshots/library.webp"><img src="docs/screenshots/library.webp" alt="My Wave controls in the Yandex Music library" width="49%"></a>
  <a href="docs/screenshots/search.webp"><img src="docs/screenshots/search.webp" alt="Yandex Music track search" width="49%"></a>
</p>
<p align="center"><em>Library and search</em></p>

<p align="center">
  <a href="docs/screenshots/settings.webp"><img src="docs/screenshots/settings.webp" alt="Yandex Music plugin settings" width="60%"></a>
</p>
<p align="center"><em>Built-in settings</em></p>

<p align="center">
  <a href="docs/screenshots/signed-out.webp"><img src="docs/screenshots/signed-out.webp" alt="Yandex Device OAuth sign-in screen" width="60%"></a>
</p>
<p align="center"><em>Sign in through Yandex Device OAuth</em></p>

## Highlights

- Native mini-player in the Omarchy bar
- Background playback without an open browser
- Now Playing, Library, and a unified Search catalog for tracks, artists, albums, and playlists
- “My Wave” with mood, discovery, language controls, and recommendation feedback
- Likes, “Do not recommend”, user and generated playlists, listening history, favorite entities, and radio stations
- Synced lyrics with active-line highlighting, auto-scroll, and click-to-seek
- Track radio with a sequence of similar recommendations and radio feedback
- On-demand release details and recording credits
- Ordered, shuffle, repeat queue, and repeat track modes
- System media keys and privacy-safe MPRIS integration
- Persistent queue, position, volume, pause state, and preferences
- Configurable bar layout, artwork shape, marquee text, and notifications
- Retry/recovery for interrupted streams and expiring OAuth tokens

## Screens and controls

### Bar

The bar player can show previous, play/pause, and next controls, album artwork, artist, track title, and progress. Click the artwork or track information to open the popup.

Long artist/title text can be truncated or scrolled as one continuous line. The information width, controls, artwork, and progress line are configurable.

### Now Playing

- Drag the seek slider; the real position remains visible and the target time is shown in parentheses
- Drag the volume slider or click the speaker to mute
- Like or unlike the current track with the heart button or `L`
- Toggle “Do not recommend” with the dislike button or `D`; a new dislike immediately skips a track in “My Wave”
- Click the cover to smoothly expand it across the popup and keep track details, a seekable progress bar, and primary actions; the mode survives closing and reopening the popup, while another click or `Escape` returns to the regular view
- Use the synced-lyrics button to replace the queue with song lyrics; LRC lines highlight and scroll with playback, and clicking a line seeks to it
- If synced LRC is unavailable, plain lyrics are shown instead; missing lyrics or loading errors never interrupt playback
- Start Track Radio from the current song with the radio-tower button
- Open the information view for available album, release date, genre, labels, track number, version, description, and recording credits
- Change playback mode with the button beside the queue counter
- Select any queue item directly
- Click an artist or album link to open its page in the Search catalog

Opening “My Likes” or a personal library playlist does **not** interrupt the current track. A separate list is loaded and playback starts only after you select a track. Large library collections load in batches of 50 tracks, with the next page fetched automatically when you reach the end of the list. Recently opened collections and all pages already fetched for them are restored instantly from a short-lived in-memory cache. Lyrics and detailed track information load only on demand and remain in memory for the current and a few recently opened tracks.

### Library

- Browse “My Likes” and owned playlists without autoplay
- Lazily loaded generated mixes: Playlist of the Day, Missed Likes, Premiere, and Deja Vu
- A Recently Played section whose tracks and listening contexts load in pages of 50 items
- Favorite albums, artists, and saved third-party playlists linked to the existing catalog pages
- A catalog of available genre, activity, mood, and other stations; a queue starts only after an explicit station selection
- Sections and fetched data use bounded memory-only caches cleared on sign-out or backend restart
- Expand “My Wave” and configure:
  - mood: any, fun, active, calm, or sad
  - selection: balanced, favorites, popular, or discovery
  - language: any, Russian, or non-Russian

### Search

Search across tracks, artists, albums, and playlists, or use the sectioned **All** view. Suggestions appear after 300 ms once at least two characters are entered; a spinner inside the field remains visible while they are loading. Use ↑/↓ to highlight one and Enter or a mouse click to search for it. Results load page by page with an explicit load-more action.

Artist, album, and playlist pages open inside the same Search tab without changing playback. Back returns to the unchanged query, filter, loaded pages, and result models. Album pages show metadata and tracks; artist pages place popular tracks first, followed by independently paginated Albums and Singles, then up to ten similar artists; playlist pages expose their tracks. Playback starts only when a track row is selected explicitly. When playback starts from an artist’s popular tracks, the queue fetches subsequent 20-track pages in the background and continues past the initially visible list. Catalog lists use their own virtualized scrolling below the fixed tabs and controls. Artwork automatically retries transient CDN failures and shows a fallback glyph if the image remains unavailable.

### Settings

Open settings with the gear in the top-right corner of the popup.

Available options:

- Resume playback after service restart
- Restore queue, track position, and volume independently
- Best available or traffic-saving audio quality
- Show/hide bar controls, artist, title, artwork, and progress
- Square, rounded, or circular artwork
- Compact, normal, or wide track information
- Truncated or smoothly scrolling long text
- Track-change notifications with album artwork
- Sign out with confirmation

Preferences are stored in `~/.config/omarchy-yandex-music/preferences.json` with mode `600`.

## System media controls

The backend exposes a sanitized MPRIS player named **Yandex Music**. Omarchy and keyboard media keys can control play/pause, previous, and next. MPRIS includes track metadata and artwork but never publishes temporary audio stream URLs.

## Requirements

- Omarchy 4.x
- Python 3
- `mpv`
- `git`
- `jq`
- Network access

## Installation

Install and enable the plugin with the standard Omarchy command:

```bash
omarchy plugin add https://github.com/vornashev/omarchy-yandex-music.git --enable
```

No manual `git clone`, `cd`, or `sudo` is required. On its first load, the plugin automatically installs its Python environment, CLI, and systemd user service. This initial setup may take a moment. It creates:

- `~/.config/omarchy/plugins/vornashev.yandex-music/`
- `~/.local/share/omarchy-yandex-music/`
- `~/.local/bin/omarchy-yandex-music`
- `~/.config/systemd/user/omarchy-yandex-music.service`

After installation, click the player in the bar, start Yandex Device OAuth, and use the button beside the displayed code to copy it before opening the authorization page. The browser can be closed after sign-in.

## Keyboard shortcuts

Inside the popup:

Letter shortcuts follow physical QWERTY key positions, so they work with both English and Russian layouts. They are active only while the popup is open and are not intercepted in the search field or settings. The UI keeps the Latin mnemonic labels. There is no separate Stop shortcut: `Space` pauses playback without losing the position.

- `1`, `2`, `3` — Now Playing, Library, Search
- `Space` — play/pause
- `N` — next track
- `P` — previous track
- `L` — like/unlike
- `D` — toggle “Do not recommend”
- `F` — expand or collapse cover mode
- `C` — copy the Device OAuth code while signing in
- `Escape` — return from settings or close the popup

Hardware media keys are handled through MPRIS.

## Updating

```bash
omarchy plugin update vornashev.yandex-music
```

The backend is updated automatically when the refreshed plugin loads. Regular updates and service restarts preserve the OAuth token; only explicit sign-out or uninstalling with `--purge` removes it.

## Uninstalling

Use the plugin's uninstaller so its background service and CLI are removed too.

Keep the OAuth token, preferences, and playback state:

```bash
~/.config/omarchy/plugins/vornashev.yandex-music/uninstall.sh
```

Remove all local data as well:

```bash
~/.config/omarchy/plugins/vornashev.yandex-music/uninstall.sh --purge
```

## Troubleshooting

```bash
systemctl --user status omarchy-yandex-music.service
journalctl --user -u omarchy-yandex-music.service -n 100
omarchy-yandex-music status | jq
omarchy restart shell
```

## Privacy and storage

- OAuth token: `~/.config/omarchy-yandex-music/token.json`
- Playback state: `~/.config/omarchy-yandex-music/state.json`
- Preferences: `~/.config/omarchy-yandex-music/preferences.json`
- Temporary notification artwork: `$XDG_RUNTIME_DIR/omarchy-yandex-music-covers/`

Credential and state files use mode `600` and are excluded from the repository. Notification artwork is temporary and disappears after reboot.

## License

[MIT](LICENSE)
