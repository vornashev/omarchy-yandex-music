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
    membershipSpy.clear(); addSpy.clear(); createSpy.clear(); deleteSpy.clear()
    recommendationSpy.clear(); clearSpy.clear()
    controller.requestPending = false
    controller.membershipPending = false
    controller.localMembershipError = ""
    controller.mode = "closed"
    controller.draftTitle = ""
    controller.playlistKind = ""
    controller.playlistTitle = ""
    controller.ownPlaylists = [{ kind: "7", title: "Mine", count: 2 }]
    controller.applySnapshot({ busy: false, operation: "", error: "", message: "",
      playlistKind: "", playlistTitle: "", recommendations: [],
      membershipLoading: false, membershipError: "", memberships: {},
      membershipTrackId: "", membershipAlbumId: "", revision: 0 })
  }

  function test_target_is_a_value_snapshot_and_add_is_explicit() {
    var row = { trackId: "1", albumId: "10", title: "Track" }
    controller.openTrack("catalogSearch", 3, row, false, "", "")
    row.trackId = "changed"

    compare(controller.target.trackId, "1")
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

  function test_confirmed_result_and_error_have_local_state() {
    controller.openTrack("queue", 0, { trackId: "1", albumId: "10" }, false, "", "")
    controller.applySnapshot({ busy: false, operation: "", error: "", message: "Added",
      playlistKind: "7", playlistTitle: "Mine", recommendations: [], revision: 1 })
    compare(controller.mode, "result")
    compare(controller.message, "Added")

    controller.applySnapshot({ busy: false, operation: "", error: "Conflict", message: "",
      playlistKind: "7", playlistTitle: "Mine", recommendations: [], revision: 2 })
    compare(controller.mode, "result")
    compare(controller.error, "Conflict")
  }

  function test_close_clears_private_snapshot() {
    controller.openTrack("queue", 0, { trackId: "1", albumId: "10" }, false, "", "")
    controller.close()
    compare(controller.mode, "closed")
    compare(controller.target.trackId, "")
    compare(controller.recommendations.length, 0)
    compare(clearSpy.count, 1)
  }
}
