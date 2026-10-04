import QtQuick
import Quickshell

ShellRoot {
  id: shell
  property int failures: 0
  property int playbackRequests: 0
  property int artistRequests: 0
  property int retryRequests: 0
  property var catalogSnapshot: ({ view: "search", search: { query: "test", filter: "all",
    loading: false, sections: {
      tracks: { items: [{ title: "Test track", index: 0 }], total: 1, hasMore: false },
      artists: { items: [], total: 0, hasMore: false },
      albums: { items: [], total: 0, hasMore: false },
      playlists: { items: [], total: 0, hasMore: false }
    } }, entity: {} })

  function check(condition, label) {
    if (condition) return
    failures += 1
    console.warn("CATALOG_PAGE_CHECK_FAILED", label)
  }

  CatalogController {
    id: controller
    onTrackPlaybackRequested: shell.playbackRequests += 1
  }
  CatalogPage {
    id: page
    width: 430
    controller: controller
    snapshot: shell.catalogSnapshot
    foreground: "white"
    dim: "gray"
    fontFamily: "Sans"
    returnToLibrary: false
    hasVisibleError: false
    errorCardHeight: 0
    onArtistRequested: shell.artistRequests += 1
    onRetryEntityRequested: shell.retryRequests += 1
  }

  Component.onCompleted: Qt.callLater(function() {
    shell.check(page.controller === controller, "controller binding")
    shell.check(page.rows.some(function(row) { return row.kind === "track" }), "search track row")
    shell.check(page.searchListLoading === false, "initial loading state")
    shell.check(shell.playbackRequests === 0, "search does not start playback")
    page.scrollToBeginning()
    shell.check(page.viewportY === 0, "reset viewport")
    shell.catalogSnapshot = { view: "artist", search: shell.catalogSnapshot.search,
      entity: { type: "artist", title: "Test artist", error: "Local error", tracks: [] } }
    Qt.callLater(function() {
      shell.check(page.rows.some(function(row) { return row.kind === "entityHeader" }), "entity header")
      shell.check(page.rows.some(function(row) { return row.kind === "retryEntity" }), "local retry row")
      shell.check(shell.playbackRequests === 0, "entity navigation does not start playback")
      page.activateRow({ kind: "artist", value: { id: "artist-test" } })
      shell.check(shell.artistRequests === 1 && shell.playbackRequests === 0,
        "artist row only navigates")
      page.activateRow({ kind: "retryEntity" })
      shell.check(shell.retryRequests === 1 && shell.playbackRequests === 0,
        "local retry does not start playback")
      page.activateRow({ kind: "track", source: "entity", value: { index: 0 } })
      shell.check(shell.playbackRequests === 1, "track activation starts playback")
      console.log(shell.failures === 0 ? "CATALOG_PAGE_SMOKE_OK" : "CATALOG_PAGE_SMOKE_FAILED")
    })
  })
}
