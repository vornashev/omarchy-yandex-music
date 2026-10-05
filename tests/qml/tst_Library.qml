import QtQuick
import QtTest
import "../.."

TestCase {
  name: "Library"
  when: windowShown

  LibraryController { id: controller }
  SignalSpy { id: homeSpy; target: controller; signalName: "homeRequested" }
  SignalSpy { id: sectionSpy; target: controller; signalName: "sectionRequested" }
  SignalSpy { id: backSpy; target: controller; signalName: "backRequested" }
  SignalSpy { id: retrySpy; target: controller; signalName: "retryRequested" }
  SignalSpy { id: loadMoreSpy; target: controller; signalName: "loadMoreRequested" }
  SignalSpy { id: collectionSpy; target: controller; signalName: "collectionRequested" }
  SignalSpy { id: entitySpy; target: controller; signalName: "entityRequested" }
  SignalSpy { id: trackSpy; target: controller; signalName: "trackPlaybackRequested" }
  SignalSpy { id: stationSpy; target: controller; signalName: "stationPlaybackRequested" }

  function init() {
    sectionSpy.clear(); backSpy.clear(); retrySpy.clear(); loadMoreSpy.clear(); collectionSpy.clear()
    entitySpy.clear(); trackSpy.clear(); stationSpy.clear()
    homeSpy.clear()
    controller.homeRequestPending = false
    controller.homeRequestAttempted = false
    controller.homeRequestRevision = 0
    controller.ownPlaylists = []
    controller.stationPageSize = 50
    controller.stationVisibleCount = 50
    controller.setStationQuery("")
    controller.applySnapshot({ view: "home", section: "", loading: false,
      loadingMore: false, hasMore: false, total: 0,
      error: "", warning: "", items: [], revision: 0 })
  }

  function findRow(kind, propertyName, value) {
    for (var i = 0; i < controller.rows.length; i++) {
      var row = controller.rows[i]
      if (row.kind === kind && (propertyName === "" || row[propertyName] === value)) return row
    }
    return null
  }

  function test_home_exposes_all_stage_four_sections_lazily() {
    var expected = ["personal", "history", "albums", "artists", "playlists", "stations"]
    for (var i = 0; i < expected.length; i++)
      verify(findRow("navigation", "section", expected[i]) !== null)
    compare(sectionSpy.count, 0)

    controller.activate(findRow("navigation", "section", "history"))
    compare(sectionSpy.count, 1)
    compare(sectionSpy.signalArguments[0][0], "history")
  }

  function test_home_metadata_is_lazy_and_coalesces_until_ready() {
    compare(homeSpy.count, 0)
    controller.requestHome()
    verify(controller.loading)
    compare(homeSpy.count, 1)
    compare(homeSpy.signalArguments[0][0], false)
    controller.requestHome()
    controller.requestHome(true)
    compare(homeSpy.count, 1)
    controller.applySnapshot({ view: "home", loading: true, homeLoaded: false,
      items: [], revision: 1 })
    controller.requestHome()
    compare(homeSpy.count, 1)
    controller.applySnapshot({ view: "home", loading: false, homeLoaded: true,
      items: [{ entityType: "playlist", personalId: "daily", title: "Daily",
        artUrl: "https://example.test/daily.jpg", available: true, generationReady: true }],
      revision: 2 })
    verify(!controller.loading)
    verify(!controller.homeRequestPending)
    compare(controller.personalItems[0].personalId, "daily")
    compare(controller.personalItems[0].artUrl, "https://example.test/daily.jpg")
    controller.requestHome()
    compare(homeSpy.count, 1)
    compare(sectionSpy.count, 0)
    compare(collectionSpy.count, 0)
    compare(trackSpy.count, 0)
    compare(stationSpy.count, 0)
  }

  function test_ready_home_cache_does_not_request_on_first_open() {
    controller.applySnapshot({ view: "home", loading: false, homeLoaded: true,
      items: [], revision: 3 })
    controller.requestHome()
    compare(homeSpy.count, 0)
    verify(!controller.loading)
  }

  function test_home_pending_requires_completed_new_home_response() {
    controller.applySnapshot({ view: "home", loading: false, homeLoaded: true,
      items: [], revision: 4 })
    controller.requestHome(true)
    controller.applySnapshot({ view: "home", loading: false, homeLoaded: true,
      items: [], revision: 4 })
    verify(controller.homeRequestPending)
    controller.applySnapshot({ view: "section", section: "history", loading: false,
      items: [{ entityType: "track", trackIndex: 0 }], revision: 5 })
    verify(controller.homeRequestPending)
    compare(controller.personalItems.length, 0)
    verify(!controller.loading)
    controller.applySnapshot({ view: "home", loading: false, homeLoaded: false,
      items: [], revision: 6 })
    verify(controller.homeRequestPending)
    controller.applySnapshot({ view: "home", loading: true, homeLoaded: false,
      items: [], revision: 7 })
    verify(controller.homeRequestPending)
    controller.applySnapshot({ view: "home", loading: false, homeLoaded: true,
      items: [], revision: 8 })
    verify(!controller.homeRequestPending)
    verify(!controller.loading)
  }

  function test_home_completion_requires_explicit_retry_data() {
    return [
      { tag: "empty", error: "", warning: "", items: [] },
      { tag: "error", error: "Не удалось загрузить", warning: "", items: [] },
      { tag: "partial", error: "", warning: "Подборка ещё готовится",
        items: [{ entityType: "playlist", personalId: "daily", generationReady: false }] }
    ]
  }

  function test_home_completion_requires_explicit_retry(data) {
    controller.requestHome()
    controller.applySnapshot({ view: "home", loading: false, homeLoaded: true,
      error: data.error, warning: data.warning, items: data.items, revision: 1 })
    verify(!controller.loading)
    compare(controller.snapshot.error, data.error)
    compare(controller.snapshot.warning, data.warning)
    controller.requestHome()
    compare(homeSpy.count, 1)
    controller.applySnapshot({ view: "section", section: "albums", items: [], revision: 2 })
    controller.requestHome()
    compare(homeSpy.count, 1)
    controller.applySnapshot({ view: "home", loading: false, homeLoaded: false,
      items: [], revision: 3 })
    controller.requestHome()
    compare(homeSpy.count, 1)
    controller.requestHome(true)
    compare(homeSpy.count, 2)
    compare(homeSpy.signalArguments[1][0], true)
    verify(controller.loading)
    controller.requestHome(true)
    compare(homeSpy.count, 2)
    controller.applySnapshot({ view: "home", loading: false, homeLoaded: true,
      items: [{ entityType: "playlist", personalId: "daily", generationReady: true }],
      revision: 4 })
    verify(!controller.loading)
    compare(controller.personalItems[0].generationReady, true)
  }

  function test_leaving_pending_home_allows_request_after_return() {
    controller.requestHome()
    controller.openSection("history")
    compare(sectionSpy.count, 1)
    verify(!controller.homeRequestPending)
    controller.applySnapshot({ view: "section", section: "history", items: [], revision: 1 })
    controller.applySnapshot({ view: "home", loading: false, homeLoaded: false,
      items: [], revision: 2 })
    controller.requestHome()
    compare(homeSpy.count, 2)
    verify(controller.loading)
  }

  function test_home_personal_cards_browse_only_when_available_and_generated() {
    controller.applySnapshot({ view: "home", loading: false, homeLoaded: true,
      items: [
        { entityType: "playlist", personalId: "daily", available: true, generationReady: true },
        { entityType: "playlist", personalId: "missedLikes", available: false, generationReady: true },
        { entityType: "playlist", personalId: "neverHeard", available: true, generationReady: false }
      ], revision: 1 })
    compare(collectionSpy.count, 0)
    for (var i = 0; i < controller.personalItems.length; i++)
      controller.activate({ kind: "playlist", value: controller.personalItems[i] })
    compare(collectionSpy.count, 1)
    compare(collectionSpy.signalArguments[0][0], "browse_personal")
    compare(collectionSpy.signalArguments[0][1], "daily")
    compare(entitySpy.count, 0)
    compare(trackSpy.count, 0)
    compare(stationSpy.count, 0)
  }

  function test_existing_collections_remain_explicit_browse_actions() {
    controller.ownPlaylists = [{ kind: "7", title: "Mine", count: 12 }]
    controller.activate(findRow("collection", "command", "likes"))
    controller.activate(findRow("collection", "command", "playlist"))
    compare(collectionSpy.count, 2)
    compare(collectionSpy.signalArguments[0][0], "likes")
    compare(collectionSpy.signalArguments[1][0], "playlist")
    compare(collectionSpy.signalArguments[1][1], "7")
    compare(trackSpy.count, 0)
    compare(stationSpy.count, 0)
  }

  function test_entity_navigation_never_emits_playback() {
    controller.applySnapshot({ view: "section", section: "albums", loading: false,
      error: "", warning: "", items: [{ entityType: "album", id: "8", title: "Album" }] })
    controller.activate(findRow("album", "", ""))
    compare(entitySpy.count, 1)
    compare(entitySpy.signalArguments[0][0], "album")
    compare(entitySpy.signalArguments[0][1], "8")
    compare(trackSpy.count, 0)
    compare(stationSpy.count, 0)
  }

  function test_track_and_station_require_explicit_activation() {
    controller.applySnapshot({ view: "section", section: "history", loading: false,
      error: "", warning: "", items: [{ entityType: "track", trackIndex: 3, title: "Track" }] })
    compare(trackSpy.count, 0)
    controller.activate(findRow("track", "", ""))
    compare(trackSpy.count, 1)
    compare(trackSpy.signalArguments[0][0], 3)

    controller.applySnapshot({ view: "section", section: "stations", loading: false,
      error: "", warning: "", items: [{ entityType: "station", stationId: "genre:rock", title: "Рок" }] })
    compare(stationSpy.count, 0)
    controller.activate(findRow("station", "", ""))
    compare(stationSpy.count, 1)
    compare(stationSpy.signalArguments[0][0], "genre:rock")
    compare(stationSpy.signalArguments[0][1], "Рок")
  }

  function test_stations_are_filtered_and_paginated_locally() {
    controller.stationPageSize = 2
    controller.stationVisibleCount = 2
    controller.applySnapshot({ view: "section", section: "stations", loading: false,
      error: "", warning: "", items: [
        { entityType: "station", stationId: "genre:rock", title: "Рок", subtitle: "Жанр" },
        { entityType: "station", stationId: "mood:calm", title: "Спокойствие", subtitle: "Настроение" },
        { entityType: "station", stationId: "activity:run", title: "Бег", subtitle: "Спорт" }
      ] })

    compare(controller.rows.filter(function(row) { return row.kind === "station" }).length, 2)
    verify(controller.hasMore)
    verify(findRow("loadMore", "", "") === null)
    controller.requestMore()
    compare(controller.rows.filter(function(row) { return row.kind === "station" }).length, 3)
    verify(!controller.hasMore)
    compare(loadMoreSpy.count, 0)

    controller.setStationQuery("НАСТРО")
    compare(controller.stationVisibleCount, 2)
    var stations = controller.rows.filter(function(row) { return row.kind === "station" })
    compare(stations.length, 1)
    compare(stations[0].value.stationId, "mood:calm")
  }

  function test_station_search_resets_after_leaving_section() {
    controller.stationPageSize = 1
    controller.applySnapshot({ view: "section", section: "stations", loading: false,
      error: "", warning: "", items: [
        { entityType: "station", stationId: "genre:rock", title: "Рок" },
        { entityType: "station", stationId: "genre:jazz", title: "Джаз" }
      ] })
    controller.setStationQuery("рок")
    controller.requestMore()
    controller.applySnapshot({ view: "home", section: "", loading: false,
      error: "", warning: "", items: [] })
    compare(controller.stationQuery, "")
    compare(controller.stationVisibleCount, 1)
  }

  function test_station_search_has_empty_result_state() {
    controller.applySnapshot({ view: "section", section: "stations", loading: false,
      error: "", warning: "", items: [
        { entityType: "station", stationId: "genre:rock", title: "Рок", subtitle: "Жанр" }
      ] })
    controller.setStationQuery("джаз")
    var empty = findRow("empty", "", "")
    verify(empty !== null)
  }

  function test_history_load_more_is_explicit_and_shows_loading_state() {
    controller.applySnapshot({ view: "section", section: "history", loading: false,
      loadingMore: false, hasMore: true, total: 125,
      error: "", warning: "", items: [{ entityType: "track", trackIndex: 0 }] })
    var row = findRow("loadMore", "", "")
    verify(row !== null)
    controller.activate(row)
    compare(loadMoreSpy.count, 1)
    verify(controller.loadingMore)
    controller.activate(findRow("loadMore", "", ""))
    compare(loadMoreSpy.count, 1)
  }

  function test_partial_error_retry_keeps_section_without_embedded_navigation() {
    controller.applySnapshot({ view: "section", section: "artists", loading: false,
      error: "Ошибка раздела", warning: "", items: [] })
    verify(findRow("error", "", "") !== null)
    controller.activate(findRow("retry", "", ""))
    compare(retrySpy.count, 1)
    compare(retrySpy.signalArguments[0][0], "artists")
    compare(controller.view, "section")
    compare(controller.section, "artists")
    verify(findRow("back", "", "") === null)
    verify(findRow("section", "", "") === null)
    compare(backSpy.count, 0)
  }

  function test_history_content_and_loaded_pages_survive_entity_navigation() {
    var items = [
      { entityType: "track", trackIndex: 0, title: "Track" },
      { entityType: "album", id: "8", title: "Album" },
      { entityType: "artist", id: "9", name: "Artist" }]
    controller.applySnapshot({ view: "section", section: "history", loading: false,
      loadingMore: false, hasMore: true, total: 120, items: items })
    var snapshot = controller.snapshot
    controller.activate(findRow("album", "", ""))
    controller.activate(findRow("artist", "", ""))
    compare(controller.snapshot, snapshot)
    compare(controller.snapshot.items, items)
    compare(controller.rows[0].kind, "track")
    compare(controller.rows[1].value.id, "8")
    compare(controller.rows[2].value.id, "9")
    verify(controller.hasMore)
    compare(trackSpy.count, 0)
    compare(stationSpy.count, 0)
    compare(sectionSpy.count, 0)
    compare(backSpy.count, 0)
  }

  function test_unavailable_personal_playlist_ignores_activation() {
    controller.applySnapshot({ view: "section", section: "personal", loading: false,
      error: "", warning: "", items: [{ entityType: "playlist", personalId: "missedLikes",
        title: "Тайник", available: false }] })
    controller.activate(findRow("playlist", "", ""))
    compare(collectionSpy.count, 0)
    compare(trackSpy.count, 0)
  }

  function test_personal_playlist_opens_without_playback_signal() {
    controller.applySnapshot({ view: "section", section: "personal", loading: false,
      error: "", warning: "", items: [{ entityType: "playlist", personalId: "daily", title: "Плейлист дня" }] })
    controller.activate(findRow("playlist", "", ""))
    compare(collectionSpy.count, 1)
    compare(collectionSpy.signalArguments[0][0], "browse_personal")
    compare(collectionSpy.signalArguments[0][1], "daily")
    compare(trackSpy.count, 0)
  }
}
