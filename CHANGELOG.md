# Changelog

[Русская версия](CHANGELOG.ru.md)

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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

[0.7.2]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.7.1...v0.7.2
[0.7.1]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/vornashev/omarchy-yandex-music/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/vornashev/omarchy-yandex-music/releases/tag/v0.4.0
