import QtQuick
import QtTest
import "../.."

TestCase {
  name: "Catalog"
  when: windowShown

  CatalogController { id: controller }
  SignalSpy { id: suggestSpy; target: controller; signalName: "suggestRequested" }
  SignalSpy { id: clearSpy; target: controller; signalName: "suggestionsClearRequested" }
  SignalSpy { id: searchSpy; target: controller; signalName: "searchRequested" }
  SignalSpy { id: entitySpy; target: controller; signalName: "entityRequested" }
  SignalSpy { id: backSpy; target: controller; signalName: "backRequested" }
  SignalSpy { id: loadSpy; target: controller; signalName: "loadMoreRequested" }
  SignalSpy { id: playSpy; target: controller; signalName: "trackPlaybackRequested" }

  function init() {
    suggestSpy.clear(); clearSpy.clear(); searchSpy.clear(); entitySpy.clear()
    backSpy.clear(); loadSpy.clear(); playSpy.clear()
    controller.fieldText = ""
    controller.filter = "all"
    controller.submittedQuery = ""
    controller.view = "search"
    controller.highlightedSuggestionIndex = -1
    controller.suggestionLoading = false
    controller.suggestions = []
    controller.results = { tracks: [], artists: [], albums: [], playlists: [] }
  }

  function test_suggestion_threshold_and_300ms_debounce() {
    controller.updateInput(" x ")
    wait(340)
    compare(suggestSpy.count, 0)
    compare(clearSpy.count, 1)

    controller.updateInput("  xy  ")
    wait(250)
    compare(suggestSpy.count, 0)
    wait(80)
    compare(suggestSpy.count, 1)
    compare(suggestSpy.signalArguments[0][0], "xy")
  }

  function test_suggestion_loading_covers_debounce_and_api_response() {
    controller.updateInput("x")
    verify(!controller.suggestionLoading)

    controller.updateInput("xy")
    verify(controller.suggestionLoading)
    var generation = controller.suggestionGeneration
    verify(!controller.applySuggestions({ generation: generation - 1,
      query: "x", loading: false, items: [] }))
    verify(controller.suggestionLoading)
    verify(controller.applySuggestions({ generation: generation,
      query: "xy", loading: true, items: [] }))
    verify(controller.suggestionLoading)
    verify(controller.applySuggestions({ generation: generation,
      query: "xy", loading: false, items: ["xyz"] }))
    verify(!controller.suggestionLoading)
    compare(controller.suggestions[0], "xyz")

    controller.submit()
    verify(!controller.suggestionLoading)
  }

  function test_stale_suggestions_are_rejected() {
    controller.updateInput("old")
    var oldGeneration = controller.suggestionGeneration
    controller.updateInput("new")
    verify(!controller.applySuggestions({ generation: oldGeneration, query: "old", items: ["old"] }))
    compare(controller.suggestions.length, 0)
    verify(controller.applySuggestions({ generation: controller.suggestionGeneration,
      query: "new", items: ["new value"] }))
    compare(controller.suggestions[0], "new value")
  }

  function test_keyboard_suggestion_navigation_wraps_and_submits() {
    controller.filter = "artist"
    controller.suggestions = ["First", "Second", "Third"]

    verify(controller.moveSuggestion(1))
    compare(controller.highlightedSuggestionIndex, 0)
    verify(controller.moveSuggestion(1))
    compare(controller.highlightedSuggestionIndex, 1)
    verify(controller.moveSuggestion(-1))
    compare(controller.highlightedSuggestionIndex, 0)
    verify(controller.moveSuggestion(-1))
    compare(controller.highlightedSuggestionIndex, 2)
    compare(controller.highlightedSuggestionText(), "Third")

    verify(controller.acceptHighlightedSuggestion())
    compare(controller.fieldText, "Third")
    compare(controller.submittedQuery, "Third")
    compare(controller.highlightedSuggestionIndex, -1)
    compare(controller.suggestions.length, 0)
    compare(searchSpy.count, 1)
    compare(searchSpy.signalArguments[0][0], "Third")
    compare(searchSpy.signalArguments[0][1], "artist")
  }

  function test_input_and_escape_reset_keyboard_selection() {
    controller.suggestions = ["First", "Second"]
    verify(controller.moveSuggestion(1))
    controller.updateInput("new query")
    compare(controller.highlightedSuggestionIndex, -1)
    compare(controller.suggestions.length, 0)

    controller.suggestions = ["New query"]
    verify(controller.moveSuggestion(1))
    controller.dismissSuggestions()
    compare(controller.highlightedSuggestionIndex, -1)
    compare(controller.suggestions.length, 0)
    compare(clearSpy.count, 1)
  }

  function test_suggestion_selection_submits_normal_search() {
    controller.filter = "album"
    controller.suggestions = ["Selected"]
    controller.selectSuggestion("Selected")
    compare(controller.fieldText, "Selected")
    compare(controller.submittedQuery, "Selected")
    compare(controller.suggestions.length, 0)
    compare(searchSpy.count, 1)
    compare(searchSpy.signalArguments[0][0], "Selected")
    compare(searchSpy.signalArguments[0][1], "album")
  }

  function test_four_sections_and_append_deduplication() {
    compare(controller.sectionNames.length, 4)
    compare(controller.sectionNames.join(","), "tracks,artists,albums,playlists")
    controller.append("tracks", [{ trackId: "1" }, { trackId: "2" }])
    controller.append("tracks", [{ trackId: "2" }, { trackId: "3" }])
    compare(controller.results.tracks.length, 3)
    compare(controller.results.tracks[0].trackId, "1")
    compare(controller.results.tracks[2].trackId, "3")
    controller.loadMoreRequested()
    compare(loadSpy.count, 1)
  }

  function test_entity_navigation_preserves_search_and_does_not_play() {
    controller.fieldText = "saved field"
    controller.filter = "artist"
    controller.submittedQuery = "saved query"
    controller.results = { tracks: [{ trackId: "1" }], artists: [{ id: "2" }],
      albums: [], playlists: [] }
    var savedResults = controller.results

    controller.openEntity("artist", "2", "", "", "")
    compare(controller.view, "artist")
    compare(entitySpy.count, 1)
    compare(playSpy.count, 0)
    controller.back()
    compare(controller.view, "search")
    compare(backSpy.count, 1)
    compare(controller.fieldText, "saved field")
    compare(controller.filter, "artist")
    compare(controller.submittedQuery, "saved query")
    compare(controller.results, savedResults)
  }

  function test_playback_requires_explicit_track_action() {
    controller.openEntity("album", "7", "", "", "")
    compare(playSpy.count, 0)
    controller.trackPlaybackRequested("entity", 3)
    compare(playSpy.count, 1)
    compare(playSpy.signalArguments[0][0], "entity")
    compare(playSpy.signalArguments[0][1], 3)
  }
}
