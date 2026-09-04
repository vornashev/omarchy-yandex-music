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
    controller.activate(findRow("back", "", ""))
    compare(backSpy.count, 1)
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
