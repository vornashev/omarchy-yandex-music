.pragma library

var simpleCommands = {
  togglePlayback: "pause",
  nextTrack: "next",
  previousTrack: "previous",
  toggleMute: "mute",
  toggleLike: "like",
  dislikeTrack: "dislike"
}

var indexedCommands = {
  playQueueTrack: "play_queue",
  playLibraryTrack: "play_library_track",
  playLibraryHubTrack: "play_library_hub_track"
}

function indexOf(value) {
  return typeof value === "number" && isFinite(value)
    && value >= 0 && Math.floor(value) === value ? value : -1
}

function resolve(intent, payload) {
  if (Object.prototype.hasOwnProperty.call(simpleCommands, intent)) {
    if (payload !== undefined) return null
    return { command: simpleCommands[intent], argument: undefined }
  }
  if (Object.prototype.hasOwnProperty.call(indexedCommands, intent)) {
    var index = indexOf(payload)
    return index < 0 ? null : { command: indexedCommands[intent], argument: index }
  }
  if (intent === "playCatalogTrack") {
    if (!Array.isArray(payload) || payload.length !== 2) return null
    var source = payload[0]
    var trackIndex = indexOf(payload[1])
    if ((source !== "search" && source !== "entity") || trackIndex < 0) return null
    return { command: "play_catalog_track", argument: [source, trackIndex] }
  }
  return null
}
