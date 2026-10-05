# Yandex Music for Omarchy

[Русская версия](README.ru.md)

A native Yandex Music mini-player for the [Omarchy](https://omarchy.org/) shell. The browser is used only for Yandex Device OAuth; playback runs in the background through `mpv`.

> This project uses the unofficial [yandex-music-api](https://github.com/MarshalX/yandex-music-api) library and is not affiliated with Yandex. A Yandex Music subscription may be required for full-track playback.

## Screenshots

<p align="center">
  <img src="preview.webp" alt="Yandex Music Now Playing popup in Omarchy" width="900">
</p>

<p align="center">
  <a href="docs/screenshots/library.webp"><img src="docs/screenshots/library.webp" alt="Personalized Yandex Music library sections" width="49%"></a>
  <a href="docs/screenshots/search.webp"><img src="docs/screenshots/search.webp" alt="Unified Yandex Music catalog search" width="49%"></a>
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
- Add tracks to playlists, create private playlists, remove tracks from owned playlists, and browse recommendations for extending them
- Synced lyrics with active-line highlighting, auto-scroll, and click-to-seek
- Track radio with a sequence of similar recommendations and radio feedback
- On-demand release details and recording credits
- Ordered, shuffle, repeat queue, and repeat track modes
- Bounded audio cache and background preparation of the next selected track
- System media keys and privacy-safe MPRIS integration
- Persistent queue, position, volume, pause state, and preferences
- Configurable bar layout, artwork shape, marquee text, and notifications
- Retry/recovery for interrupted streams and expiring OAuth tokens

## Screens and controls

### Bar

The bar player can show previous, play/pause, and next controls, a Like button, album artwork, artist, track title, elapsed/total time, progress, and a volume control. Scroll over the volume area or track information to change the level in 5% steps; click the speaker to mute, right-click the track information to toggle play/pause, or click the artwork/track information to open the popup. Buttons and the volume wheel area respond over the full bar height, including its edges.

The bar and popup use Lucide icons. Paused tracks dim their artwork/text; loading shows a connection spinner, signed-out state offers sign-in, and errors show a red dot with a short message. Buttons have hover, pressed, keyboard-focus, and disabled feedback; Like shows pending, success, or failure, while volume shows drag/wheel feedback.

Long artist/title text can be truncated or scrolled as one continuous line. The information width, controls, artwork, progress line, and bar volume control are configurable. Settings → Bar → Show volume hides the bar volume area independently of the popup slider; it is enabled by default. Show track time (`showTime`) and Like button (`showLike`) independently toggle the time display and heart.

### Navigation

- Now Playing, Library, and Search each keep an independent stack of pages and scroll positions. Artist, album, and playlist links open inside the current tab, without changing playback
- Switching tabs restores their last page. Clicking the active tab again, or repeating its `1`/`2`/`3` shortcut, returns to its root. Returning to the Search root preserves the input, query, filter, loaded pages, result models, and scroll position
- Back goes up one page; breadcrumbs jump to an ancestor. Library shortcuts in the Wide rail select Library and reset its stack to the home screen plus the chosen destination; the Library tab and matching shortcut stay highlighted
- Opening an entity from Now Playing keeps that tab selected. In Wide, the page replaces both the large player and queue above the mini player; Compact also keeps the mini player below the page. Navigation from Mini temporarily expands to Compact without changing the saved layout
- The queue's source link opens its collection or entity in Library without starting playback. Track selection, artist links, and playlist actions have separate click targets
- Reopening the current destination does not add a duplicate. Each tab keeps at most eight levels including its root; a longer chain drops the oldest non-root page


### Now Playing

- Drag the seek slider and release to apply it; the real position remains visible while the target time is shown in parentheses
- In Wide, Previous, Play/Pause, and Next form a larger centered transport group, with Play/Pause emphasized and Like/Actions at the outer edges. Compact places transport, seek, volume, and Actions in one row below the track header
- Wide places mute, the volume slider, and its percentage below the transport controls; Compact opens them from the speaker button. Volume follows a perceptual curve so quiet settings stay audible, while the centred Actions sheet shows the current track and keeps infrequent commands out of the way
- Like or unlike with the heart button or `L`; use Actions or `D` to toggle “Do not recommend”, which immediately skips a new dislike in “My Wave”
- Actions also provides Add current track to playlist, Track Radio, queue mode, and Settings
- Choose Compact (400×640) or Wide (1040×640) in Settings → Playback → Popup view; these are the only options currently offered. The separate Mini layout remains implemented for previously saved preferences, but its selector option is deferred to a future update. This does not remove the persistent mini player below Library, Search, Settings, and deeper pages. Press `W` to switch Compact/Wide; screens too narrow for Wide fall back to Compact. Wide shows a navigation rail, the current track and the queue, lyrics or track info side by side
- In Wide, the Compact-view button is at the bottom of the navigation rail, next to Settings: a square 37×37 button, borderless at rest, with hover/press feedback, a keyboard-focus accent border, and a tooltip showing `W`. Tab focuses it; Space or Enter activates it
- Explicit List, Lyrics, and Track Info tabs replace the former cluster of ambiguous queue-header icons
- The list, lyrics, and track-info areas fit the remaining popup height and scroll internally, keeping the player controls stationary; exceptionally short screens retain outer scrolling so controls stay reachable
- In Lyrics, synced LRC lines highlight and scroll with playback and clicking a line seeks to it; plain lyrics are used as a fallback, while missing lyrics or loading errors never interrupt playback
- Track Info shows available album, release date, genre, labels, track number, version, description, and recording credits
- Select any queue item directly
- Hover a track row to reveal its playlist action; in the queue it replaces the duration, opens an owned-playlist picker or creates a new private playlist without activating the row, and playlists that already contain the track are marked and cannot receive a duplicate
- The picker opens as a bottom sheet in Compact and a popover next to the row in Wide, without dimming the wide player. Membership checking disables mutations; private-playlist creation, results and removal confirmation stay inside the picker. Use ↑/↓ and Enter to choose, Delete to open removal confirmation, and Escape to cancel the form/confirmation or close the picker. Mini temporarily shows Compact while the picker is open
- Failed additions offer Retry; creation never offers a retry that could create a duplicate playlist. Deletion requires confirmation and clears the selected target after every completed attempt. A revision conflict refreshes the list; select the track again and reconfirm rather than repeating a destructive action
- Click an artist or album link to open its page inside the current tab

Opening “My Likes” or a personal library playlist does **not** interrupt the current track. A dedicated collection page loads a separate list; playback starts only through **Listen**, **Shuffle**, or explicit track selection. Large library collections load in batches of 50 tracks, with the next page fetched automatically when you reach the end of the list. Shuffle includes the full collection, resolving the remaining track metadata lazily rather than restricting playback to the first loaded page. Recently opened collections and all pages already fetched for them are restored from a short-lived in-memory cache. Loading and errors remain local to browsing; unknown total duration is not replaced by the duration of the first page. Lyrics and detailed track information load only on demand and remain in memory for the current and a few recently opened tracks.

### Audio caching

During playback, one background downloader prepares the next selected track, then caches the current track when it was opened from the network. This can download the current track a second time; preparing the next track takes priority. Completed files play locally, including when the network goes away after preparation. Automatic transitions use mpv's playlist and file events instead of waiting for the one-second position poll. Shuffle reuses the candidate chosen for preparation; manual Next still advances in repeat-track mode.

The audio cache is limited to **256 MiB**, including temporary downloads, with a **64 MiB** limit per file. Least recently used files are evicted while the current and next tracks are protected. Partial or damaged files are discarded, and cache/network failures fall back to ordinary streaming. This is a playback cache, not an offline library. Tracks that have not finished downloading and radio boundaries requiring another batch may still have a network delay. Preloading does not send listening feedback or show a loading indicator.

Files are separated by account, quality, codec, and bitrate in `$XDG_CACHE_HOME/omarchy-yandex-music/audio`, or `~/.cache/omarchy-yandex-music/audio` when `XDG_CACHE_HOME` is unset or relative. The installer captures this path in the service environment and grants write access only to the audio subdirectory alongside the existing configuration/runtime allowances. Rerun `./install.sh --backend-only` after changing `XDG_CACHE_HOME`. Sign-out removes that account's audio; uninstall removes the audio cache even without `--purge`. To clear it manually, stop the service, remove this directory, recreate it with mode `700`, and start the service again.

### Library

- Browse “My Likes” and owned playlists without autoplay
- Wide places Likes, each owned playlist, and Recently Played in a three-column wrapping grid; Compact keeps one column. All playlist cards remain reachable through the page's outer scroll, without a nested playlist scroller
- Remove a selected track from an owned playlist after confirmation, or open playlist recommendations and add one explicitly
- Artwork cards for Playlist of the Day, Missed Likes, Premiere, and Deja Vu; Wide also shows Podcasts of the Week. Opening the Library loads only their metadata, not tracks or other sections. Unformed mixes are disabled; the refresh button reloads the cards explicitly
- A Recently Played section whose tracks and listening contexts load in pages of 50 items
- Favorite albums, artists, and saved third-party playlists linked to the existing catalog pages
- A searchable catalog of genre, activity, mood, and other stations with automatic scroll pagination; a queue starts only after an explicit station selection
- Sections and fetched data use bounded memory-only caches cleared on sign-out or backend restart
- Wide keeps quick “My Wave” controls on the Library home. Its dedicated screen has a theme-aware radio-glow card with description and Start on the left, mood, selection and language on the right, and the mini player below. Compact stacks the card and settings in one scrollable page. The Wide home play/pause control operates the active wave without replacing its queue; Start or Enter on the wave screen starts a new wave, as does Enter on the Library home. Starting is blocked while settings are saving or the wave is connecting. These settings apply only to My Wave, not track radio
  - mood: any, fun, active, calm, or sad
  - selection: balanced, favorites, popular, or discovery
  - language: any, Russian, non-Russian, or instrumental

### Search

Search across tracks, artists, albums, and playlists, or use the sectioned **All** view. Suggestions appear after 300 ms once at least two characters are entered; a spinner inside the field remains visible while they are loading. Use ↑/↓ to highlight one and Enter or a mouse click to search for it. Results load page by page with an explicit load-more action.

Search shows a best result and result counters. Wide artist pages place popular tracks beside albums; the best-matching and opened artist offer Radio as an explicit playback action.

Artist, album, and playlist pages opened from Search stay in that tab without changing playback; the same pages also work inside Now Playing and Library. Every track row has a separate add-to-playlist action that does not start playback. Back restores the unchanged input, query, filter, loaded pages, result models, and scroll position. Album pages show metadata and tracks; artist pages place popular tracks first, followed by independently paginated Albums and Singles, then up to ten similar artists; playlist pages expose their tracks. Playback requires an explicit track selection or playback action such as Radio. When playback starts from an artist’s popular tracks, the queue fetches subsequent 20-track pages in the background and continues past the initially visible list. Catalog lists use their own virtualized scrolling below the fixed tabs and controls. Artwork automatically retries transient CDN failures and shows a fallback icon if the image remains unavailable.

### Settings

Open Settings from the labeled Actions menu or the Wide navigation rail. Wide uses two columns; Compact has a denser single column and a Back button in the top-left corner. Compact toggle rows, a bar preview, and selectors with focus, changed, busy, and error feedback keep configuration inside the popup. The header shows the running backend version.

Available options:

- Resume playback after service restart
- Restore queue, track position, and volume independently
- Best available or traffic-saving audio quality
- Compact or Wide popup layout
- Show/hide bar controls, volume, Like, track time, artist, title, artwork, and progress independently
- Square, rounded, or circular artwork
- Compact, normal, or wide track information
- Truncated or smoothly scrolling long text
- Track-change notifications with album artwork
- Sign out with confirmation

Preferences are stored in `~/.config/omarchy-yandex-music/preferences.json` with mode `600`.

### Sign-in

The Device OAuth screen explains the steps and shows a large code with a live expiry countdown. Copy it with `C` or the Copy button and open the authorization page with Enter or Open page. Cancel sign-in stops the current attempt; an expired code offers Get a new code (`R`) rather than a raw error. After success, the screen shows the signed-in login and Plus status and offers My Wave or Library. The browser is only needed for authorization.

## System media controls

The backend exposes a sanitized MPRIS player named **Yandex Music**. Omarchy and keyboard media keys can control play/pause, previous, and next. MPRIS includes track metadata and artwork but never publishes temporary audio stream URLs.

## Requirements

- Omarchy 4.x
- Python 3
- `mpv`
- `jq`
- `util-linux` (`flock`)
- `coreutils` (`sha256sum`)
- Network access

## Installation

Install and enable the plugin with the standard Omarchy command:

```bash
omarchy plugin add https://github.com/vornashev/omarchy-yandex-music.git --enable
```

No manual `git clone`, `cd`, or `sudo` is required. On its first load, the plugin automatically installs its Python environment, CLI, and systemd user service. Python packages are installed only from the complete version- and SHA-256-locked wheel set in `requirements.txt`; the installer neither upgrades `pip` nor executes a live VCS dependency. This initial setup may take a moment. It creates:

- `~/.config/omarchy/plugins/vornashev.yandex-music/`
- `~/.local/share/omarchy-yandex-music/`
- `~/.local/bin/omarchy-yandex-music`
- `~/.config/systemd/user/omarchy-yandex-music.service`

After installation, click the player in the bar, start Yandex Device OAuth, and use the button beside the displayed code to copy it before opening the authorization page. The browser can be closed after sign-in.

## Keyboard shortcuts

Inside the popup:

Letter shortcuts follow physical QWERTY key positions, so they work with both English and Russian layouts. They are active only while the popup is open and are not intercepted in the search field or settings. The UI keeps the Latin mnemonic labels. There is no separate Stop shortcut: `Space` pauses playback without losing the position.

- `1`, `2`, `3` — select Now Playing, Library, Search; repeat the active tab's shortcut to return to its root
- `Space` — play/pause
- `N` — next track
- `P` — previous track
- `L` — like/unlike
- `D` — toggle “Do not recommend”
- `W` — switch between Compact and Wide views
- `C` — copy the Device OAuth code while signing in
- `Alt+Left`, `Backspace` — Back one page, except while editing a focused nonempty text field
- `Escape` — close a dialog or Actions first, return from Settings, then go Back; at a tab root, close the popup, including when the Search field has focus

Hardware media keys are handled through MPRIS.

The Search root focuses its input. Leaving an editor for another page returns focus to panel navigation, so a hidden search or station filter cannot consume player shortcuts.

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

## Development

`omarchy plugin add` clones the repository straight into `~/.config/omarchy/plugins/vornashev.yandex-music`, so that checkout is both the installed plugin and a working copy. Run the checks from the repository root:

```bash
python -m compileall -q backend tests
HOME="$(mktemp -d)" ~/.local/share/omarchy-yandex-music/venv/bin/python -m unittest discover -s tests
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml -import .
for smoke in tests/smoke/*/run.sh; do bash "$smoke"; done
bash -n bootstrap.sh install.sh uninstall.sh bin/omarchy-yandex-music
omarchy plugin validate .
```

The temporary `HOME` keeps the suite away from your real token and playback state. The real-mpv audio tests additionally need `mpv` and `ffmpeg`; see [audio cache validation](docs/audio-cache-validation.md). After changing the backend, run `./install.sh --backend-only` (it reinstalls the service whenever backend files change) and `omarchy restart shell` to reload QML.

## License

[MIT](LICENSE)
