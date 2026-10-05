# Changelog

[Русская версия](CHANGELOG.ru.md)

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.11.0] - 2026-10-05

### Added

- Independent navigation stacks for Now Playing, Library, and Search, with a shared Back/breadcrumb header, per-page scroll restoration, and artist, album, and playlist pages inside the current tab. Switching tabs restores their last page; reselecting a tab returns to its root without clearing Search input, query, filter, loaded results, or scroll. Rail shortcuts reset the Library stack and highlight its current context
- Dedicated collection pages for Likes, owned playlists, and personal mixes, with artwork, available count/duration, local loading/error states, and explicit Listen/Shuffle actions. Browsing never replaces the playback queue; Shuffle covers the complete collection while loading track metadata lazily
- A queue-source link opens the source in Library without changing playback. Deep pages in Now Playing replace the large player and queue above the persistent mini player. Navigation from a previously saved Mini layout temporarily opens Compact without changing that preference
- `Alt+Left` and `Backspace` go Back without interfering with focused nonempty text fields. Escape closes overlays/settings first, then goes Back, and closes the popup only at a root, including from the Search field
- Personal Library cards with artwork for Playlist of the Day, Missed Likes, Premiere, and Deja Vu; Wide also shows Podcasts of the Week. Home metadata loads lazily, coalesces simultaneous requests, and shares bounded memory-only caches with personal collection browsing. Unavailable mixes and local errors remain visible, with explicit refresh rather than automatic retry loops
- A dedicated My Wave screen with a theme-aware radio-glow card, description, and Start beside mood, selection, and language controls in Wide; Compact stacks them on one scrollable page. Instrumental music is now a language option. The mini player remains below; Start or Enter launches the wave, while saving settings or connecting prevents another start
- A redesigned sign-in flow with an introduction, step-by-step device-code screen, large per-character code, Copy (`C`), Open page (`Enter`), and a live expiry countdown. Expired codes offer Get a new code (`R`), sign-in can be cancelled explicitly, and the success screen shows the login and Plus status with actions to start My Wave or open Library
- Optional track time and a Like button in the bar, controlled by `showTime` and `showLike`

### Changed

- The popup offers Compact (400×640, page tabs, a 72 px track header, and one-row controls) and Wide (1040×640, navigation rail, current track, and queue/lyrics/track info side by side). Settings offer these two layouts only: the 380×101 Mini layout remains implemented and previously saved preferences still work, but its selector option is deferred to a future update. The persistent mini player under Library, Search, Settings, and deeper pages is separate and remains available
- `W` (`Ц` on a Russian keyboard) and the layout buttons switch Compact/Wide and remember the choice; the retained Mini strip has an expand button. Screens too narrow for Wide fall back to Compact
- The Wide rail starts directly with navigation, without a logo or application-name header. Its Compact-view button sits beside Settings at the bottom: a square 37×37 control, with a full-opacity dim icon and no border or background at rest. Hover adds a subtle border/fill, Tab focus adds an accent border, and pressing adds an accent border/icon with a soft accent fill. The tooltip appears after 500 ms of hover or immediately on keyboard focus; activation gives 120 ms of pressed feedback before switching
- Now Playing places artwork, details, progress, transport, and volume on the left of the Wide view, beside tabbed queue/lyrics/track info with 48–52 px rows and artwork thumbnails. Compact opens volume from its speaker button. The centred Actions sheet includes the current track
- Library keeps quick My Wave settings on its Wide home alongside owned collections and section shortcuts. Search adds a best result and counters; Wide artist pages place popular tracks beside albums, with Radio available for the best-matching or opened artist
- Settings use two columns in Wide, compact toggle rows, a bar preview, and a popup-view selector. Select controls distinguish default, hover, focus, open, changed, busy, and error states
- The playlist picker is a bottom sheet in Compact and a 340 px row-anchored popover without dimming in Wide. It includes track artwork, playlist thumbnails, membership checks, inline private-playlist creation, results alongside the list, and separate removal confirmation. Row actions use Lucide list-plus, or ellipsis in an editable owned playlist; ↑/↓, Enter, Escape, and Delete support keyboard operation. A previously saved Mini layout temporarily expands to Compact while picking
- Playlist additions can be retried; creation and deletion never offer potentially duplicate or destructive retries. Membership checks block duplicate additions and mutations while checking. Deletion always requires confirmation; after any completed deletion attempt the target is cleared, and a revision conflict refreshes the list so another attempt requires selecting and confirming the track again
- Popup and bar icons use the bundled ISC-licensed Lucide set instead of font glyphs
- The bar dims artwork/text when paused, shows a stream-connection spinner while loading, offers one sign-in action when signed out, and shows a red dot with a short message on errors. Progress sits under track information; volume shows its percentage. Right-click toggles play/pause, and the wheel over track information adjusts volume
- Bar buttons show hover, pressed, keyboard-focus, and disabled states with 24 px-wide hit zones, 14 px icons, and 2 px spacing; pressed icons shrink to 13 px over an accent fill. Like shows a half-opacity pending heart, a 200 ms success flash, or a red error dot. Volume adds hover/drag/wheel feedback, quiet/mute icons, and an unavailable state; Previous/Next show a short spinner while the stream loads

### Fixed

- Owned playlists are individual Library-home cards, sharing three equal-width wrapping columns with Likes and Recently Played in Wide. Compact keeps one column. Every playlist remains reachable through the outer page scroll, without a nested one- or two-card viewport
- Previous/Next, Play/Pause, Like, and Mute respond over the full bar height, including the top and bottom edges, without enlarging their icons. The volume slider also accepts wheel events across the full height while its visible track stays centred
- Hidden editors return focus to panel navigation. Stale browse/entity responses cannot replace a newer destination; reopening the current destination does not duplicate it. Each tab preserves its root within an eight-level limit, dropping the oldest non-root page when necessary
- Returning to Now Playing no longer lets a delayed details response reset the queue after manual scrolling
- Cancelled sign-in attempts cannot overwrite a new code, report an old error, or save/connect an old token, including when cancellation arrives during account initialization

### Removed

- Expandable cover mode and its `F` shortcut, replaced by the redesigned Compact and Wide views
- Collection browsing inside the Now Playing queue and special cross-tab catalog return rules; browsing now follows the active tab's stack independently of playback

## [0.10.0] - 2026-10-04

### Added

- A volume control in the bar to the right of the track title: a mute icon plus a level track, adjusted with the mouse wheel in 5% steps
- Session restore retries transient network errors after boot or resume and shows a reconnecting message; the panel's retry action uses a new `reconnect` command
- A persistent Show volume setting toggles the existing bar volume control independently of popup volume and transport buttons; enabled by default

### Changed

- Starting an uncached track is faster: Yandex Music API calls reuse one keep-alive HTTP session, only the played download variant resolves a direct link, listening reports wait until the new track has started, and mpv reuses its HTTP connection while opening a stream
- Mute, the volume slider, and its percentage moved from the Actions sheet to directly under the transport controls in the regular and expanded cover views
- Volume follows a perceptual curve: UI percentages remain 0–100 while the mpv gain grows more slowly, so low settings stay audible (7% ≈ 20, 15% ≈ 32, 50% ≈ 66)
- The full `details` snapshot is polled only while the panel is open; the bar keeps polling the compact `status`
- `Panel.qml` is split into catalog, library, session, details, intent, volume and skeleton components covered by QML unit tests and Quickshell smoke tests

### Fixed

- Concurrent state saves use unique temporary files and can no longer publish an older snapshot last
- Service IPC reads are bounded by a one-second deadline and the 64 KiB limit; a stalled client no longer blocks the service
- Status polling no longer overwrites the volume while it is being changed
- Now Playing sizes its list, lyrics, and track-info panes to the available height after adding the volume row, removing the redundant outer scrollbar without clipping controls; very short viewports retain an accessible scrolling fallback

## [0.9.0] - 2026-10-04

### Added

- Bounded on-disk audio cache with background preparation of the next selected track and local playback of completed downloads
- A 256 MiB total budget and 64 MiB per-file limit, LRU eviction, protection of current/next tracks, account/quality/codec isolation, and atomic publication of complete files

### Changed

- Automatic track transitions use mpv playlist entries and file events instead of the one-second playback poll; shuffle reuses the prepared candidate
- Installation delivers the audio-cache module, tracks backend changes independently of the version marker, and grants the service write access only to its configured audio-cache directory
- Sign-out clears the account's cached audio; uninstall also removes the previously configured cache after an XDG cache-path change

### Fixed

- My Wave and track radio fetch the next batch while the last queued track is playing, allowing preparation of its successor before the current batch ends
- Incomplete or damaged downloads are discarded; cache and download failures retain ordinary streaming as a fallback

## [0.8.2] - 2026-09-28

### Security

- Repository coding-agent instructions and task artifacts are no longer shipped in the plugin checkout
- Every Qt Quick `Text` element now forces `Text.PlainText`, preventing API, backend, error, catalogue, playlist, track, artist, album, lyrics, writer, and user-controlled strings from being interpreted as rich text or loading referenced resources

### Fixed

- The panel opens again: removed the duplicate `textFormat` assignment in the search suggestion spinner (issue #1)
- Playback retries now rotate through Yandex Music's available download variants instead of requesting the same unreachable CDN stream three times; each stalled attempt is cancelled after five seconds, exhausted tracks advance without flashing an error, and a final error appears only after every queued track fails
- Opening My Likes or another Library collection is no longer blocked by an audio stream that is still connecting; collection loading owns its independent UI state and playback completion cannot replace it with the old queue
- When My Wave adds a new batch and starts its next track, loading now transfers to that track and clears after playback starts instead of leaving the queue hidden behind a permanent spinner

## [0.8.1] - 2026-09-05

### Security

- Backend bootstrap no longer upgrades `pip` or resolves a live VCS dependency: every runtime package and transitive dependency is version-locked with SHA-256 hashes, source distributions are refused, and the `yandex-music` wheel is vendored from commit `0fa54f2d32084a9e461bce41890d1c9ab70d91aa`
- Unix-socket requests, CLI responses, and `mpv` IPC responses now have explicit size and newline-termination limits; direct HTTP JSON responses are streamed with a 1 MB cap, while notification artwork uses an atomic temporary file and a 5 MB hard cap instead of buffering unbounded bodies

## [0.8.0] - 2026-09-05

### Added

- “Do not recommend” action and `D` keyboard shortcut for toggling the feedback on the current track
- `N` and `P` shortcuts for next and previous, plus `F` for cover mode, while the popup is open
- Animated full-width cover mode with track details, a seekable progress bar, and primary playback actions
- Standard listening start and finish reports through `play_audio`
- “My Wave” feedback for radio start, track start, natural completion, and manual skips
- Synced LRC lyrics with active-line highlighting, auto-scroll, and click-to-seek
- Plain-text fallback, a local unavailable state, and manual retry after loading errors
- In-memory LRU lyrics cache for the current and seven recently opened tracks
- Track Radio with a dedicated action, recommendation queue, and continued radio chain
- On-demand current-track view for release details and recording credits
- A separate in-memory LRU detailed-information cache for the eight most recent tracks
- Unified Search catalog with `All`, Tracks, Artists, Albums, and Playlists filters, 300 ms suggestions, and paginated results
- Keyboard navigation through search suggestions with ↑/↓, highlighted selection, and Enter confirmation
- An in-field spinner covering both the suggestion debounce and API loading interval
- Non-autoplay album, artist, and playlist pages with explicit track playback, linked metadata, and preserved search back-navigation
- Artist biography, popular tracks, similar artists, and independently paginated Albums and Singles sections
- Stage 4 Library sections for Playlist of the Day, Missed Likes, Premiere, Deja Vu, listening history, favorite albums and artists, saved playlists, and searchable radio stations with automatic scroll pagination
- Stage 5 collection management: add tracks from the queue, Library, listening history, or catalog to an owned playlist; create a private playlist; confirm removal; and lazily browse recommendations
- Per-track membership checks mark owned playlists that already contain the selected track and disable duplicate additions
- A dedicated `CollectionController.qml`, sixteen backend mutation-flow tests, and seven QML interaction tests
- Fake backend coverage and automated QML interaction tests for catalog search, suggestions, pagination, navigation, caching, personalization, collection mutations, and explicit playback

### Changed

- Background reporting is ordered, serialized with other API calls, and never blocks player controls
- Disliking a track in “My Wave” immediately advances to the next track
- Previous, Play/Pause, Next, and Like button tooltips now show their keyboard shortcuts
- Now Playing has an explicit visual hierarchy: Like and Actions symmetrically frame the larger transport, volume sits at the top of the action sheet, List/Lyrics/Track Info are labeled tabs, and infrequent commands, queue mode, and Settings share one menu
- The public preview and Library, Search, and Settings screenshots now show the v0.8.0 interface using privacy-safe demo data
- Track playlist actions now appear on row hover and replace the queue duration without taking additional horizontal space
- Full-width cover mode remains active when the popup is closed and reopened
- Letter commands follow physical QWERTY key positions and work with English and Russian layouts
- Lyrics load on demand through a separate background operation, do not inflate regular status/details polling, and never turn failures into global player errors
- Explicit List, Lyrics, and Track Info tabs replace the former queue-header icon toggles
- Artist and album links from Now Playing, queue rows, and track information now open the unified Search catalog
- Catalog SDK requests share the serialized API wrapper and 2/5/10-second rate-limit retries; stale session and suggestion responses are discarded
- Artist popular-track queues prefetch subsequent 20-track pages and preserve their continuation context across backend restarts
- Artist pages now order Popular Tracks, Albums, Singles, and up to ten Similar Artists
- The legacy artist list no longer replaces the Now Playing queue
- Expanded Library sections load only when opened, use generation/client guards, and retain data in a bounded ten-minute memory-only cache; Recently Played resolves metadata in 50-item pages instead of eagerly loading the full history
- History tracks, generated playlists, and stations replace the queue only after an explicit selection; favorite entity pages return to the Library
- Personal playlists returned with `ready=false` are shown dimmed and cannot be activated until Yandex has formed them
- Status refresh during a panel/plugin reload no longer reports a malformed service response before the queue view has initialized
- Playback mode moved into the labeled Actions sheet, while open collections retain a compact back-to-queue control in their heading
- Every playlist mutation refetches the current `revision`; safe inserts retry once after conflict, while deletion refreshes the list and requires a new confirmation
- Mutation results use client/generation guards, share `_api_call()`/`api_lock`, refresh the open playlist, invalidate related memory caches, and never replace or start the queue
- Frequent `status` responses expose only `collectionRevision`; membership results, recommendation rows, and local operation results are included only in `details`
- Membership lookup batches owned playlist IDs, falls back only for incomplete track lists, and is protected by target/client/generation guards; backend insertion independently skips duplicates

### Fixed

- Catalog artwork retries transient CDN/HTTP2 failures up to three times and falls back to an unavailable-image glyph
- Album and single rows no longer render the same artist twice through both linked and fallback metadata
- The logout unit test now uses temporary token/state paths and can no longer delete the developer’s real OAuth session during verification
- Artist release pagination respects a known exact total, and loading more preserves the current viewport
- Search results no longer show through and overlap the open suggestions popup
- “My Likes” resolves compound `track:album` identifiers correctly instead of showing an empty unavailable-tracks error
- Liking removes an existing dislike, while disliking removes a like and consistently updates the open “My Likes” list, queue, and cache
- Extending the “My Wave” sequence waits until finished/skip feedback for the previous track has been sent
- The `L` shortcut is intercepted before built-in `h/j/k/l` navigation and no longer switches player tabs
- After an external Stop command, playback is marked as stopped, position resets, and Play starts the current track from the beginning
- Leaving Search now releases the hidden field focus, restoring tab/player shortcuts and preventing hidden query edits
- Cover mode vertical animations are synchronized, the gutter remains constant, panel height is held through transitions, and the temporary second inter-block gap is compensated without a final tab-row snap
- LRC highlighting no longer trails the one-second monitor/status cycles: the backend records fractional mpv position and its observation time, while the panel smoothly interpolates between updates
- Paginated search tracks receive stable indexes after deduplication, so playback and playlist actions address the selected row instead of the first result
- Playlist deletion preserves each row’s original `trackId:albumId` reference, including duplicate track IDs attached to different albums
- Collection actions no longer become permanently busy when another UI command is in flight; closing the main panel clears an idle dialog or resumes an in-flight result safely
- The collection dialog now sizes itself from the visible `KeyboardPanel` viewport instead of the zero-sized controller root, so the pressed add button opens a visible dialog
- Playlist rows are re-fetched from a complete server snapshot after a confirmed mutation because SDK mutation responses may omit `tracks`; deleting one row no longer makes a non-empty playlist look empty
- The empty-playlist hint is hidden while lyrics or track information are open instead of overlapping that content
- The lyrics-writer footer height no longer creates a QML binding loop when the panel opens

## [0.7.4] - 2026-09-03

### Added

- Installed plugin version in the settings header
- Automatic rate-limit retries with 2, 5, and 10 second backoff delays

### Changed

- Yandex Music API requests are serialized to avoid request bursts across library, search, radio, artist, and playback operations
- The liked-track index loaded during startup is reused when opening “My Likes”
- Search results scroll independently while the tabs and search field stay fixed

### Fixed

- The queue preserves its scroll position on manual selection and does not scroll again when the next or previous track is already fully visible
- Unliking a track removes it immediately from the open “My Likes” list or its active queue and updates the cache without reloading the full collection
- Raw Yandex Music HTTP 429 responses are replaced with a concise actionable message
- Opening “My Likes” during startup no longer duplicates the liked-tracks request

## [0.7.3] - 2026-09-03

### Added

- Lazy loading for “My Likes” and personal playlists in pages of 50 tracks
- In-memory collection cache that instantly restores previously loaded playlist pages
- Loader tooltip with the current operation, elapsed wait time, API latency, and regional availability

### Changed

- Collection metadata is fetched in batches instead of one API request per track
- The queue/list renderer is virtualized, avoiding hundreds of simultaneous QML delegates
- Playback started from a partially loaded collection extends its queue in the background while preserving source order
- Collection cache entries expire after 10 minutes and use an eight-entry LRU limit

## [0.7.2] - 2026-09-03

### Added

- Copy button and `C` keyboard shortcut for the Yandex Device OAuth code
- Short visual confirmation after the authorization code is copied to the clipboard

## [0.7.1] - 2026-09-03

### Added

- One-command installation through `omarchy plugin add <url> --enable`
- Automatic backend, Python environment, CLI, and systemd user-service bootstrap on first load
- Automatic backend synchronization after `omarchy plugin update`
- Marketplace-ready preview and documentation screenshot gallery

### Changed

- Installation, updating, and removal documentation now follows the standard Omarchy plugin workflow

## [0.7.0] - 2026-09-03

### Added

- Internal settings page with a compact gear/back control
- Persistent preferences stored with mode `600`
- Independent queue, position, volume, and playback-resume restoration settings
- Best-quality and traffic-saving audio modes
- Ordered, shuffle, repeat queue, and repeat track playback modes
- MPRIS loop and shuffle state synchronization
- “My Wave” mood, discovery, and language controls
- Configurable bar controls, artist, title, artwork, progress, and information width
- Square, rounded, and circular artwork options
- Truncated and smoothly scrolling combined `Artist — Title` text
- Track-change notifications with temporary cached album artwork
- Contextual loading states and actionable error cards with retry/dismiss controls
- Stable shimmer skeletons for queue headers, track lists, artist pages, playlists, likes, and search
- Non-destructive artist, “My Likes”, and playlist browsing with manual track selection

### Changed

- Signing out moved from the main popup to Settings and now requires confirmation
- Artist names are independently clickable when a track has multiple artists
- Album artwork and player metadata use one continuous popup hit area in the bar
- Loading indicators in the popup and bar now share the same circular design and retain their rotation position
- Queue and skeleton areas use stable dimensions to avoid popup resizing
- Library collections no longer start their first track automatically
- Opening an artist no longer replaces the active queue or interrupts playback
- “My Wave” settings are submitted using the JSON format required by the current API

### Fixed

- Smooth drag behavior for volume and seek controls
- Seek target preview while preserving the real playback position display
- Bar text baseline and combined marquee movement
- Starting the next track after a paused or stopped state
- Scrollbar overlap in the Settings page
- Popup height jumps while loading queue and search results

## [0.6.0] - 2026-09-03

### Added

- “My Wave” personalized radio
- Automatic radio queue replenishment
- Radio state restoration after backend restart

## [0.5.0] - 2026-09-03

### Added

- Privacy-safe MPRIS integration
- System media-key support
- Sanitized metadata and artwork publication without temporary stream URLs

## [0.4.1] - 2026-09-02

### Added

- Like/unlike control and `L` keyboard shortcut

## [0.4.0] - 2026-09-02

### Added

- Initial public release
- Device OAuth, background `mpv` playback, library, search, queue, and persistent state

[Unreleased]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.11.0...HEAD
[0.11.0]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.8.2...v0.9.0
[0.8.2]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.7.4...v0.8.0
[0.7.4]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.7.3...v0.7.4
[0.7.3]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.7.2...v0.7.3
[0.7.2]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.7.1...v0.7.2
[0.7.1]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/vornashev/omarchy-yandex-music/releases/tag/v0.4.0
