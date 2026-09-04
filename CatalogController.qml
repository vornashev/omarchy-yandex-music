import QtQuick

Item {
  id: root
  width: 0
  height: 0

  property string fieldText: ""
  property string filter: "all"
  property string submittedQuery: ""
  property string view: "search"
  property int suggestionGeneration: 0
  property int highlightedSuggestionIndex: -1
  property bool suggestionLoading: false
  property var suggestions: []
  property var results: ({ tracks: [], artists: [], albums: [], playlists: [] })
  readonly property var sectionNames: ["tracks", "artists", "albums", "playlists"]
  readonly property bool suggestionsVisible: view === "search" && suggestions.length > 0

  signal suggestRequested(string query, int generation)
  signal suggestionsClearRequested(string fieldText)
  signal searchRequested(string query, string filter)
  signal entityRequested(string type, string id, string uuid, string owner, string kind)
  signal backRequested()
  signal loadMoreRequested()
  signal releaseMoreRequested(string section)
  signal trackPlaybackRequested(string source, int index)

  function trimmedText() { return String(fieldText || "").trim() }

  function updateInput(value) {
    fieldText = String(value || "")
    suggestionGeneration += 1
    highlightedSuggestionIndex = -1
    suggestions = []
    var query = trimmedText()
    suggestionLoading = query.length >= 2
    if (query.length < 2) {
      suggestionTimer.stop()
      suggestionsClearRequested(fieldText)
      return
    }
    suggestionTimer.restart()
  }

  function applySuggestions(snapshot) {
    var value = snapshot || {}
    if (Number(value.generation || 0) !== suggestionGeneration) return false
    if (String(value.query || "").trim() !== trimmedText()) return false
    suggestions = value.items || []
    suggestionLoading = value.loading === true
    highlightedSuggestionIndex = -1
    return true
  }

  function submit() {
    var query = trimmedText()
    if (query === "") return
    suggestionTimer.stop()
    suggestionGeneration += 1
    highlightedSuggestionIndex = -1
    suggestionLoading = false
    suggestions = []
    submittedQuery = query
    view = "search"
    searchRequested(query, filter)
  }

  function selectSuggestion(value) {
    fieldText = String(value || "")
    submit()
  }

  function moveSuggestion(step) {
    var count = suggestions.length
    if (count === 0) return false
    var direction = Number(step || 0)
    if (direction === 0) return false
    if (highlightedSuggestionIndex < 0)
      highlightedSuggestionIndex = direction > 0 ? 0 : count - 1
    else
      highlightedSuggestionIndex = (highlightedSuggestionIndex + direction + count) % count
    return true
  }

  function highlightedSuggestionText() {
    if (highlightedSuggestionIndex < 0 || highlightedSuggestionIndex >= suggestions.length)
      return ""
    return String(suggestions[highlightedSuggestionIndex] || "")
  }

  function acceptHighlightedSuggestion() {
    var value = highlightedSuggestionText()
    if (value === "") return false
    selectSuggestion(value)
    return true
  }

  function dismissSuggestions() {
    suggestionTimer.stop()
    suggestionGeneration += 1
    highlightedSuggestionIndex = -1
    suggestionLoading = false
    suggestions = []
    suggestionsClearRequested(fieldText)
  }

  function openEntity(type, id, uuid, owner, kind) {
    view = String(type || "")
    highlightedSuggestionIndex = -1
    suggestionLoading = false
    suggestions = []
    entityRequested(view, String(id || ""), String(uuid || ""),
                    String(owner || ""), String(kind || ""))
  }

  function back() {
    view = "search"
    backRequested()
  }

  function append(section, rows) {
    if (sectionNames.indexOf(section) < 0) return
    var current = results[section] || []
    var seen = {}
    var merged = []
    for (var i = 0; i < current.length; i++) {
      var oldKey = rowKey(section, current[i])
      if (!seen[oldKey]) { seen[oldKey] = true; merged.push(current[i]) }
    }
    var incoming = rows || []
    for (var j = 0; j < incoming.length; j++) {
      var key = rowKey(section, incoming[j])
      if (!seen[key]) { seen[key] = true; merged.push(incoming[j]) }
    }
    var copy = { tracks: results.tracks || [], artists: results.artists || [],
      albums: results.albums || [], playlists: results.playlists || [] }
    copy[section] = merged
    results = copy
  }

  function rowKey(section, row) {
    var value = row || {}
    if (section === "tracks") return String(value.trackId || value.title || "")
    if (section === "playlists")
      return String(value.uuid || (String(value.owner || "") + ":" + String(value.kind || ""))
                    || value.title || "")
    return String(value.id || value.name || value.title || "")
  }

  Timer {
    id: suggestionTimer
    interval: 300
    repeat: false
    onTriggered: {
      var query = root.trimmedText()
      if (query.length >= 2) root.suggestRequested(query, root.suggestionGeneration)
    }
  }
}
