import QtQuick
import QtTest
import "../.."

TestCase {
  name: "Collection"
  when: windowShown

  CollectionController { id: controller }
  SignalSpy { id: membershipSpy; target: controller; signalName: "membershipsRequested" }
  SignalSpy { id: addSpy; target: controller; signalName: "addRequested" }
  SignalSpy { id: createSpy; target: controller; signalName: "createRequested" }
  SignalSpy { id: deleteSpy; target: controller; signalName: "deleteRequested" }
  SignalSpy { id: recommendationSpy; target: controller; signalName: "recommendationsRequested" }
  SignalSpy { id: clearSpy; target: controller; signalName: "clearRequested" }

  function init() {
    controller.close()
    membershipSpy.clear(); addSpy.clear(); createSpy.clear(); deleteSpy.clear()
    recommendationSpy.clear(); clearSpy.clear()
    controller.ownPlaylists = [{ kind: "7", title: "Mine", count: 2 }]
  }

  function finishMemberships(memberships) {
    controller.applySnapshot({ busy: false, operation: "", error: "", message: "",
      playlistKind: "", playlistTitle: "", recommendations: [],
      membershipLoading: false, membershipError: "", memberships: memberships || { "7": false },
      membershipTrackId: controller.target.trackId,
      membershipAlbumId: controller.target.albumId, revision: 1 })
  }

  function finishMutation(values) {
    controller.applySnapshot(Object.assign({}, controller.snapshot,
      { busy: false, operation: "", error: "", message: "", revision: 2 }, values))
  }

  function test_target_is_a_value_snapshot_and_add_is_explicit() {
    var row = { trackId: "1", albumId: "10", title: "Track",
      artist: "Artist", artUrl: "https://example.test/cover" }
    controller.openTrack("catalogSearch", 3, row, false, "", "")
    row.trackId = "changed"
    row.albumId = "changed"
    row.title = "Changed"
    row.artist = "Changed"
    row.artUrl = "https://example.test/changed"

    compare(controller.target.trackId, "1")
    compare(controller.target.albumId, "10")
    compare(controller.target.title, "Track")
    compare(controller.target.artist, "Artist")
    compare(controller.target.artUrl, "https://example.test/cover")
    compare(controller.mode, "track")
    compare(membershipSpy.count, 1)
    verify(controller.checkingMemberships)
    compare(addSpy.count, 0)
    controller.applySnapshot({ busy: false, operation: "", error: "", message: "",
      playlistKind: "", playlistTitle: "", recommendations: [],
      membershipLoading: false, membershipError: "", memberships: { "7": false },
      membershipTrackId: "1", membershipAlbumId: "10", revision: 1 })
    verify(!controller.checkingMemberships)
    verify(controller.requestAdd("7"))
    compare(addSpy.count, 1)
    compare(addSpy.signalArguments[0][0], "7")
    compare(addSpy.signalArguments[0][1], "catalogSearch")
    compare(addSpy.signalArguments[0][2], 3)
    compare(addSpy.signalArguments[0][3], "1")
    verify(controller.busy)
  }

  function test_existing_membership_is_visible_and_blocks_duplicate_add() {
    controller.ownPlaylists = [
      { kind: "7", title: "Contains it", count: 2 },
      { kind: "8", title: "Available", count: 1 }
    ]
    controller.openTrack("queue", 0, { trackId: "1", albumId: "10", title: "One" },
                         false, "", "")
    controller.applySnapshot({ busy: false, operation: "", error: "", message: "",
      playlistKind: "", playlistTitle: "", recommendations: [],
      membershipLoading: false, membershipError: "", memberships: { "7": true, "8": false },
      membershipTrackId: "1", membershipAlbumId: "10", revision: 1 })

    verify(controller.playlistContains("7"))
    verify(!controller.playlistContains("8"))
    verify(!controller.requestAdd("7"))
    compare(addSpy.count, 0)
    verify(controller.requestAdd("8"))
    compare(addSpy.count, 1)
    compare(addSpy.signalArguments[0][0], "8")
  }

  function test_create_requires_title_and_keeps_target() {
    controller.openTrack("queue", 0, { trackId: "2", albumId: "20", title: "Two" },
                         false, "", "")
    finishMemberships()
    controller.beginCreate()
    compare(controller.mode, "create")
    verify(!controller.submitCreate())
    compare(createSpy.count, 0)

    controller.draftTitle = "  Private list  "
    verify(controller.submitCreate())
    compare(createSpy.count, 1)
    compare(createSpy.signalArguments[0][0], "Private list")
    compare(createSpy.signalArguments[0][1], "queue")
    compare(createSpy.signalArguments[0][3], "2")
  }

  function test_delete_needs_owned_playlist_and_confirmation() {
    controller.openTrack("library", 4, { trackId: "3", albumId: "30", title: "Three" },
                         true, "7", "Mine")
    finishMemberships()
    verify(!controller.confirmDelete())
    verify(controller.beginDelete())
    compare(controller.mode, "delete")
    compare(deleteSpy.count, 0)
    verify(controller.confirmDelete())
    compare(deleteSpy.count, 1)
    compare(deleteSpy.signalArguments[0][0], "7")
    compare(deleteSpy.signalArguments[0][2], 4)

    controller.requestPending = false
    controller.openTrack("queue", 0, { trackId: "3", albumId: "30" }, false, "", "")
    verify(!controller.beginDelete())
  }

  function test_recommendations_are_lazy_and_added_explicitly() {
    verify(controller.openRecommendations("7", "Mine"))
    compare(recommendationSpy.count, 1)
    compare(addSpy.count, 0)
    verify(controller.busy)

    controller.applySnapshot({ busy: false, operation: "", error: "", message: "",
      playlistKind: "7", playlistTitle: "Mine",
      recommendations: [{ index: 0, trackId: "8", albumId: "80", title: "Eight" }], revision: 1 })
    compare(controller.mode, "recommendations")
    compare(controller.recommendations.length, 1)
    verify(controller.addRecommendation(controller.recommendations[0]))
    compare(addSpy.count, 1)
    compare(addSpy.signalArguments[0][0], "7")
    compare(addSpy.signalArguments[0][1], "recommendation")
    compare(addSpy.signalArguments[0][3], "8")
  }

  function test_add_result_keeps_playlists_and_target_available() {
    controller.openTrack("queue", 0, { trackId: "1", albumId: "10" }, false, "", "")
    finishMemberships({ "7": false, "8": false })
    verify(controller.requestAdd("7"))
    controller.applySnapshot(Object.assign({}, controller.snapshot,
      { busy: true, operation: "add", playlistKind: "7" }))
    compare(controller.mode, "track")
    verify(controller.busy)
    finishMutation({ message: "Added", playlistKind: "7",
      memberships: { "7": true, "8": false } })
    compare(controller.mode, "track")
    compare(controller.target.trackId, "1")
    compare(controller.message, "Added")
    compare(controller.lastSuccessfulKind, "7")
    verify(controller.playlistContains("7"))
    verify(!controller.requestAdd("7"))
    verify(!controller.retryLastMutation())
    verify(controller.requestAdd("8"))
    compare(controller.message, "")
    compare(controller.lastOperation, "add")
  }

  function test_create_result_returns_to_inline_playlist_list() {
    controller.openTrack("queue", 0, { trackId: "2", albumId: "20" }, false, "", "")
    finishMemberships({ "7": true })
    verify(controller.beginCreate())
    controller.draftTitle = "New playlist"
    verify(controller.submitCreate())
    finishMutation({ message: "Created and added", playlistKind: "9",
      memberships: { "7": true, "9": true } })
    compare(controller.mode, "track")
    compare(controller.target.trackId, "2")
    compare(controller.lastSuccessfulKind, "9")
    verify(controller.playlistContains("7"))
    verify(controller.playlistContains("9"))
    verify(!controller.requestAdd("9"))
    verify(!controller.retryLastMutation())
  }

  function test_failed_add_is_inline_and_retry_uses_original_selection() {
    controller.openTrack("catalogSearch", 3, { trackId: "1", albumId: "10" }, false, "", "")
    finishMemberships()
    verify(controller.requestAdd("7"))
    finishMutation({ error: "Network unavailable", playlistKind: "7" })
    compare(controller.mode, "track")
    compare(controller.error, "Network unavailable")
    compare(controller.lastSuccessfulKind, "")
    verify(controller.canRetryLastMutation)
    verify(controller.retryLastMutation())
    compare(addSpy.count, 2)
    compare(Array.prototype.slice.call(addSpy.signalArguments[1]), ["7", "catalogSearch", 3, "1", "10"])
    compare(controller.error, "")
    verify(controller.busy)
    verify(!controller.retryLastMutation())
  }

  function test_failed_create_cannot_repeat_ambiguous_creation() {
    controller.openTrack("queue", 0, { trackId: "2", albumId: "20" }, false, "", "")
    finishMemberships()
    verify(controller.beginCreate())
    controller.draftTitle = "  Private list  "
    verify(controller.submitCreate())
    finishMutation({ error: "Network unavailable" })
    compare(controller.mode, "track")
    verify(!controller.canRetryLastMutation)
    verify(!controller.retryLastMutation())
    compare(createSpy.count, 1)
    compare(controller.target.trackId, "2")
  }

  function test_partial_create_does_not_retry_creation() {
    controller.openTrack("queue", 0, { trackId: "2", albumId: "20" }, false, "", "")
    finishMemberships()
    verify(controller.beginCreate())
    controller.draftTitle = "Private list"
    verify(controller.submitCreate())
    finishMutation({ error: "Плейлист создан, но трек добавить не удалось. Повторите добавление." })
    compare(controller.mode, "track")
    verify(!controller.canRetryLastMutation)
    verify(!controller.retryLastMutation())
    compare(createSpy.count, 1)
    verify(controller.requestAdd("9"))
    compare(Array.prototype.slice.call(addSpy.signalArguments[0]), ["9", "queue", 0, "2", "20"])
  }

  function test_delete_result_invalidates_confirmation_target() {
    var results = [
      { message: "Removed" },
      { error: "Плейлист изменился в другом клиенте. Обновите его и повторите действие." },
      { error: "Список изменился. Выберите трек ещё раз." },
      { error: "Network unavailable" }
    ]
    for (var i = 0; i < results.length; i++) {
      controller.openTrack("library", 4, { trackId: "3", albumId: "30" }, true, "7", "Mine")
      finishMemberships()
      verify(controller.beginDelete())
      verify(controller.confirmDelete())
      finishMutation(results[i])
      compare(controller.mode, "result")
      compare(controller.target.trackId, "")
      verify(!controller.target.canDelete)
      verify(!controller.canRetryLastMutation)
      verify(!controller.retryLastMutation())
      verify(!controller.beginDelete())
      verify(!controller.confirmDelete())
      controller.mode = "track"
      verify(!controller.beginDelete())
    }
    compare(deleteSpy.count, results.length)
  }

  function test_recommendation_errors_and_add_results_remain_inline() {
    verify(controller.openRecommendations("7", "Mine"))
    finishMutation({ error: "Network unavailable", playlistKind: "7" })
    compare(controller.mode, "recommendations")
    verify(!controller.retryLastMutation())
    verify(controller.openRecommendations("7", "Mine"))
    finishMutation({ playlistKind: "7",
      recommendations: [{ index: 0, trackId: "8", albumId: "80", title: "Eight" }] })
    verify(controller.addRecommendation(controller.recommendations[0]))
    finishMutation({ error: "Network unavailable" })
    compare(controller.mode, "recommendations")
    verify(controller.retryLastMutation())
    compare(Array.prototype.slice.call(addSpy.signalArguments[1]), ["7", "recommendation", 0, "8", "80"])
    finishMutation({ message: "Added", recommendations: [] })
    compare(controller.mode, "recommendations")
    compare(controller.lastSuccessfulKind, "7")
    compare(controller.recommendations.length, 0)
  }

  function test_membership_and_busy_states_block_actions() {
    controller.openTrack("library", 4, { trackId: "3", albumId: "30" }, true, "7", "Mine")
    controller.draftTitle = "New"
    verify(!controller.beginCreate())
    verify(!controller.submitCreate())
    verify(!controller.requestAdd("7"))
    verify(!controller.beginDelete())
    verify(!controller.confirmDelete())
    verify(!controller.openRecommendations("7", "Mine"))
    verify(!controller.addRecommendation({ trackId: "4", albumId: "40" }))
    verify(!controller.retryMemberships())
    finishMemberships()
    verify(controller.requestAdd("7"))
    verify(!controller.beginCreate())
    verify(!controller.submitCreate())
    verify(!controller.requestAdd("8"))
    verify(!controller.beginDelete())
    verify(!controller.confirmDelete())
    verify(!controller.retryMemberships())
    verify(!controller.openRecommendations("7", "Mine"))
    compare(createSpy.count, 0)
    compare(deleteSpy.count, 0)
    compare(recommendationSpy.count, 0)
    compare(addSpy.count, 1)
  }

  function test_server_membership_loading_blocks_create_submission() {
    controller.openTrack("queue", 0, { trackId: "1", albumId: "10" }, false, "", "")
    finishMemberships()
    verify(controller.beginCreate())
    controller.draftTitle = "Private list"
    controller.applySnapshot(Object.assign({}, controller.snapshot,
      { membershipLoading: true }))
    verify(controller.checkingMemberships)
    verify(!controller.submitCreate())
    compare(createSpy.count, 0)
    finishMemberships()
    verify(controller.submitCreate())
    controller.applySnapshot(Object.assign({}, controller.snapshot,
      { busy: true, operation: "create" }))
    verify(controller.busy)
    verify(!controller.submitCreate())
    verify(!controller.retryMemberships())
    compare(createSpy.count, 1)
  }

  function test_membership_error_requires_successful_recheck_before_add_or_create() {
    controller.openTrack("queue", 0, { trackId: "1", albumId: "10" }, false, "", "")
    controller.membershipRequestFailed()
    verify(!controller.checkingMemberships)
    verify(!controller.beginCreate())
    verify(!controller.requestAdd("7"))
    verify(controller.retryMemberships())
    verify(controller.checkingMemberships)
    finishMemberships()
    verify(controller.beginCreate())
  }

  function test_reopening_clears_previous_result_and_retry_state() {
    controller.openTrack("queue", 0, { trackId: "1", albumId: "10" }, false, "", "")
    finishMemberships()
    verify(controller.requestAdd("7"))
    finishMutation({ message: "Added", playlistKind: "7", memberships: { "7": true } })
    verify(controller.requestAdd("8"))
    finishMutation({ error: "Network unavailable" })
    verify(controller.canRetryLastMutation)
    controller.openTrack("queue", 1, { trackId: "2", albumId: "20" }, false, "", "")
    compare(controller.lastOperation, "")
    compare(controller.lastSuccessfulKind, "")
    compare(controller.lastMutation.trackId, undefined)
    compare(controller.error, "")
    compare(controller.message, "")
    verify(!controller.playlistContains("7"))
    verify(!controller.retryLastMutation())
    verify(controller.checkingMemberships)
  }

  function test_close_clears_private_snapshot() {
    controller.openTrack("queue", 0, { trackId: "1", albumId: "10",
      artist: "Artist", artUrl: "https://example.test/cover" }, false, "", "")
    finishMemberships()
    verify(controller.requestAdd("7"))
    finishMutation({ error: "Network unavailable" })
    controller.close()
    compare(controller.mode, "closed")
    compare(controller.target.trackId, "")
    compare(controller.target.artist, "")
    compare(controller.target.artUrl, "")
    compare(controller.lastOperation, "")
    compare(controller.lastSuccessfulKind, "")
    compare(controller.lastMutation.trackId, undefined)
    verify(!controller.canRetryLastMutation)
    compare(controller.recommendations.length, 0)
    compare(clearSpy.count, 1)
    finishMutation({ message: "Late result", playlistKind: "7" })
    compare(controller.mode, "closed")
  }
}
