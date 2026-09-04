import QtQuick
import QtTest
import "../.."

TestCase {
  name: "Library"
  when: windowShown

  LibraryController { id: controller }
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
    compare(empty.title, "Ничего не найдено")
  }

  function test_history_load_more_is_explicit_and_shows_loading_state() {
    controller.applySnapshot({ view: "section", section: "history", loading: false,
      loadingMore: false, hasMore: true, total: 125,
      error: "", warning: "", items: [{ entityType: "track", trackIndex: 0 }] })
    var row = findRow("loadMore", "", "")
    verify(row !== null)
    compare(row.title, "Загрузить ещё")
    controller.activate(row)
    compare(loadMoreSpy.count, 1)
    verify(controller.loadingMore)
    compare(findRow("loadMore", "", "").title, "Загружаем…")
  }

  function test_partial_error_retry_and_back_are_local() {
    controller.applySnapshot({ view: "section", section: "artists", loading: false,
      error: "Ошибка раздела", warning: "", items: [] })
    verify(findRow("error", "", "") !== null)
    controller.activate(findRow("retry", "", ""))
    compare(retrySpy.count, 1)
    compare(retrySpy.signalArguments[0][0], "artists")
    var backRow = findRow("back", "", "")
    compare(backRow.icon, "󰁍")
    controller.activate(backRow)
    compare(backSpy.count, 1)
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
