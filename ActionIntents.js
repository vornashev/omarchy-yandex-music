.pragma library

var specs = {
  openLibrarySection: { command: "library_section", arity: 1, libraryView: "section" },
  retryLibrarySection: { command: "library_retry", arity: 1, libraryView: "section" },
  returnLibraryHome: { command: "library_back", arity: 0, libraryView: "home" },
  loadMoreLibrarySection: { command: "library_section_more", arity: 0 },
  loadMoreLibraryTracks: { command: "load_more_library", arity: 0, libraryMore: true },
  openLikes: { command: "likes", arity: 0, loadingKind: "likes" },
  openOwnedPlaylist: { command: "playlist", arity: 1, loadingKind: "playlist" },
  openPersonalPlaylist: { command: "browse_personal", arity: 1, loadingKind: "personal" },
  playStation: { command: "play_station", arity: 2, loadingKind: "station" },
  closeLibraryQueue: { command: "close_library", arity: 0 },
  searchCatalog: { command: "catalog_search", arity: 2, resetCatalogScroll: true },
  openCatalogArtist: { command: "catalog_artist", arity: 1 },
  openCatalogAlbum: { command: "catalog_album", arity: 1 },
  openCatalogPlaylist: { command: "catalog_playlist", arity: 3 },
  returnCatalogSearch: { command: "catalog_back", arity: 0 },
  loadMoreCatalogSearch: { command: "catalog_load_more", arity: 0 },
  loadMoreCatalogEntity: { command: "catalog_entity_more", arity: 0 },
  loadMoreArtistRelease: { command: "catalog_artist_more", arity: 1 },
  inspectPlaylistMembership: { command: "playlist_memberships", arity: 4 },
  addPlaylistTrack: { command: "playlist_add_track", arity: 5 },
  createPlaylist: { command: "playlist_create", arity: 5 },
  deletePlaylistTrack: { command: "playlist_delete_track", arity: 5 },
  loadPlaylistRecommendations: { command: "playlist_recommendations", arity: 2 },
  startWave: { command: "wave", arity: 0, loadingKind: "wave" },
  startTrackRadio: { command: "track_radio", arity: 0, loadingKind: "radio" },
  cyclePlaybackMode: { command: "mode", arity: 0 },
  authenticate: { command: "auth", arity: 0 },
  logout: { command: "logout", arity: 0 },
  reconnect: { command: "reconnect", arity: 0 }
}

// Failed transport actions are retried by their resolved CLI command.
var retryableTransport = {
  pause: true, next: true, previous: true, mute: true, like: true, dislike: true,
  play_queue: true, play_library_track: true, play_library_hub_track: true,
  play_catalog_track: true
}

function resolve(intent, payload) {
  if (!Object.prototype.hasOwnProperty.call(specs, intent)) return null
  var spec = specs[intent]
  if (spec.arity === 0 && payload !== undefined) return null
  if (spec.arity === 1 && Array.isArray(payload)) return null
  if (spec.arity > 1 && (!Array.isArray(payload) || payload.length !== spec.arity)) return null
  return { command: spec.command, argument: payload }
}

function policyForCommand(command) {
  for (var intent in specs) {
    if (!Object.prototype.hasOwnProperty.call(specs, intent)) continue
    var spec = specs[intent]
    if (spec.command === command) return {
      refresh: "settle", loadingKind: spec.loadingKind,
      libraryMore: spec.libraryMore, libraryView: spec.libraryView,
      resetCatalogScroll: spec.resetCatalogScroll
    }
  }
  if (Object.prototype.hasOwnProperty.call(retryableTransport, command))
    return { refresh: "settle" }
  if (command === "artist") return { refresh: "settle", loadingKind: "artist" }
  if (command === "search") return { refresh: "settle", loadingKind: "search" }
  return null
}

function optimisticData(policy, current) {
  if (!policy || (!policy.loadingKind && policy.libraryMore !== true)) return null
  var updated = {}
  for (var key in current) updated[key] = current[key]
  if (policy.loadingKind) {
    updated.loading = true
    updated.loadingKind = policy.loadingKind
  } else {
    updated.libraryLoadingMore = true
  }
  updated.error = ""
  return updated
}

function optimisticLibrary(policy, argument, revision) {
  if (!policy || !policy.libraryView) return null
  var section = policy.libraryView === "section"
  return { view: section ? "section" : "home", section: section ? String(argument || "") : "",
    loading: section, error: "", warning: "", items: [], revision: revision || 0 }
}
