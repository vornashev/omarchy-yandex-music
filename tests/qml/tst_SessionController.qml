import QtQuick
import QtTest
import "../.."

TestCase {
  id: testRoot
  name: "SessionController"
  when: windowShown

  property var session: null
  Component {
    id: sessionFactory
    SessionController {
      pollingEnabled: false
      settleDelay: 25
      volumeDebounceMs: 10
    }
  }
  SignalSpy { id: statusSpy; target: testRoot.session; signalName: "statusRequested" }
  SignalSpy { id: actionSpy; target: testRoot.session; signalName: "actionRequested" }
  SignalSpy { id: actionDoneSpy; target: testRoot.session; signalName: "actionFinished" }
  SignalSpy { id: volumeSpy; target: testRoot.session; signalName: "volumeRequested" }
  SignalSpy { id: volumeDoneSpy; target: testRoot.session; signalName: "volumeDrained" }
  SignalSpy { id: bootstrapSpy; target: testRoot.session; signalName: "bootstrapRequested" }

  function init() {
    session = sessionFactory.createObject(testRoot)
    statusSpy.clear(); actionSpy.clear(); actionDoneSpy.clear()
    volumeSpy.clear(); volumeDoneSpy.clear(); bootstrapSpy.clear()
  }
  function cleanup() { session.destroy(); session = null }

  function test_status_is_single_flight_and_actions_drain_fifo() {
    verify(session.requestStatus())
    verify(!session.requestStatus())
    compare(statusSpy.count, 1)
    verify(session.transport("togglePlayback"))
    verify(session.transport("nextTrack"))
    verify(session.transport("previousTrack"))
    verify(session.transport("toggleLike"))
    compare(actionSpy.count, 1)
    session.completeStatus(0, '{"title":"Track","playing":true}')
    compare(session.snapshot.title, "Track")
    var expected = ["pause", "next", "previous", "like"]
    for (var i = 0; i < expected.length; i++) {
      compare(actionSpy.count, i + 1, "only one command starts per completion")
      compare(actionSpy.signalArguments[i][0], expected[i])
      session.completeAction(0, "", "")
    }
    compare(actionDoneSpy.count, 4)
    compare(actionSpy.count, 4)
    compare(session.actionRunning, false)
  }

  function test_action_and_bootstrap_completion_settle_status() {
    session.startBootstrap()
    compare(bootstrapSpy.count, 1)
    session.completeBootstrap(0, "")
    tryCompare(statusSpy, "count", 1, 200)
    session.completeStatus(0, "{}")
    session.action("pause")
    session.completeAction(0, "", "")
    tryCompare(statusSpy, "count", 2, 200)
  }

  function test_rapid_volume_changes_keep_latest_value() {
    session.queueVolume(20)
    compare(session.snapshot.volume, 20)
    tryCompare(volumeSpy, "count", 1, 200)
    compare(volumeSpy.signalArguments[0][0], 20)
    session.queueVolume(60)
    compare(session.snapshot.volume, 60)
    session.completeVolume(0)
    tryCompare(volumeSpy, "count", 2, 200)
    compare(volumeSpy.signalArguments[1][0], 60)
    session.completeVolume(0)
    compare(volumeDoneSpy.count, 1)
  }

  function test_stale_status_cannot_undo_optimistic_volume() {
    session.requestStatus()
    session.queueVolume(70)
    session.completeStatus(0, '{"volume":10,"muted":true}')
    compare(session.snapshot.volume, 70)
    compare(session.snapshot.muted, false)
    tryCompare(volumeSpy, "count", 1, 200)
    session.completeVolume(0)
    session.requestStatus()
    session.completeStatus(0, '{"volume":70,"muted":false}')
    compare(session.snapshot.volume, 70)
    compare(session.volumePending, false)
  }

  function test_details_started_during_volume_stays_stale_after_status_settles() {
    session.queueVolume(65)
    var requestRevision = session.volumeRevision
    var startedAfterVolume = !session.volumePending
    tryCompare(volumeSpy, "count", 1, 200)
    session.completeVolume(0)
    session.requestStatus()
    session.completeStatus(0, '{"volume":65,"muted":false}')
    compare(session.volumePending, false)
    verify(session.shouldPreserveVolume(requestRevision, startedAfterVolume))
    verify(!session.shouldPreserveVolume(session.volumeRevision, !session.volumePending))
  }

  function test_queued_artist_navigation_runs_after_busy_action() {
    verify(session.action("pause"))
    verify(session.openArtistEventually("artist-old"))
    verify(session.openArtistEventually("artist-new"))
    compare(actionSpy.count, 1)
    session.completeAction(0, "", "")
    compare(actionSpy.count, 2)
    compare(actionSpy.signalArguments[1][0], "catalog_artist")
    compare(actionSpy.signalArguments[1][1], "artist-new")
  }

  function test_seeks_coalesce_without_reordering_discrete_actions() {
    session.transport("togglePlayback")
    session.transport("seek", 10.125)
    session.transport("seek", 15.375)
    session.transport("toggleLike")
    session.transport("seek", 20.625)
    session.transport("seek", 25.875)
    compare(actionSpy.count, 1)
    session.completeAction(0, "", "")
    compare(actionSpy.count, 2)
    compare(actionSpy.signalArguments[1][0], "seek")
    compare(actionSpy.signalArguments[1][1], 15.375)
    session.completeAction(0, "", "")
    compare(actionSpy.signalArguments[2][0], "like")
    session.completeAction(0, "", "")
    compare(actionSpy.signalArguments[3][0], "seek")
    compare(actionSpy.signalArguments[3][1], 25.875)
    session.completeAction(0, "", "")
    compare(actionSpy.count, 4)
    compare(session.actionRunning, false)
  }

  function test_invalid_intents_neither_start_nor_enter_busy_queue() {
    var invalid = [
      ["unrecognized", undefined], ["toggleLike", 1],
      ["playQueueTrack", -1], ["playQueueTrack", true],
      ["playQueueTrack", " "], ["playQueueTrack", 1.25],
      ["playCatalogTrack", ["invalid", 0]],
      ["seek", -0.25], ["seek", NaN], ["seek", Infinity],
      ["seek", "1.25"], ["seek", null], ["seek", undefined]
    ]
    for (var busy = 0; busy < 2; busy++) {
      if (busy) verify(session.transport("togglePlayback"))
      for (var i = 0; i < invalid.length; i++)
        verify(!session.transport(invalid[i][0], invalid[i][1]))
      compare(actionSpy.count, busy)
    }
    verify(session.transport("seek", 0))
    verify(session.transport("seek", 0.125))
    compare(actionSpy.count, 1)
    session.completeAction(0, "", "")
    compare(actionSpy.count, 2)
    compare(actionSpy.signalArguments[1][0], "seek")
    compare(actionSpy.signalArguments[1][1], 0.125)
    session.completeAction(0, "", "")
    compare(actionSpy.count, 2)
    compare(session.actionRunning, false)
  }

  function test_rapid_seeks_accumulate_until_a_post_command_status() {
    session.snapshot = { trackId: "a", position: 10.125, positionObservedAt: 1 }
    session.requestStatus()
    for (var i = 0; i < 4; i++)
      session.transport("seek", session.snapshot.position + 5)
    compare(session.snapshot.position, 30.125)
    compare(session.snapshot.positionObservedAt, 0)
    compare(actionSpy.count, 1)
    session.completeStatus(0, '{"trackId":"a","position":11,"positionObservedAt":2}')
    compare(session.snapshot.position, 30.125)
    session.completeAction(0, "", "")
    compare(actionSpy.signalArguments[1][1], 30.125)
    session.requestStatus()
    session.completeAction(0, "", "")
    session.completeStatus(0, '{"trackId":"a","position":15.125}')
    compare(session.snapshot.position, 30.125, "in-flight status cannot undo latest seek")
    session.requestStatus()
    session.completeStatus(0, '{"trackId":"a","position":30.25,"positionObservedAt":3}')
    compare(session.snapshot.position, 30.25)
    compare(session.snapshot.positionObservedAt, 3)
    session.transport("seek", session.snapshot.position + 5)
    compare(actionSpy.signalArguments[2][1], 35.25)
  }

  function test_track_change_drops_old_track_seeks_but_keeps_fifo_actions() {
    session.snapshot = { trackId: "a", position: 10 }
    session.transport("toggleLike")
    session.transport("seek", 15)
    session.transport("toggleMute")
    session.snapshot = { trackId: "b", position: 1 }
    session.completeAction(0, "", "")
    compare(actionSpy.count, 2)
    compare(actionSpy.signalArguments[1][0], "mute")
    session.transport("seek", session.snapshot.position + 5)
    session.completeAction(0, "", "")
    compare(actionSpy.signalArguments[2][1], 6)
  }

  function test_navigation_does_not_seek_new_track_using_old_track_position() {
    session.snapshot = { trackId: "a", position: 80 }
    session.transport("nextTrack")
    session.transport("seek", 85)
    session.transport("toggleLike")
    session.completeAction(0, "", "")
    compare(actionSpy.count, 2)
    compare(actionSpy.signalArguments[1][0], "like")
    compare(session.snapshot.position, 80)
  }

  function test_failures_reset_pending_position_and_drop_queued_seeks_data() {
    return [
      { tag: "command", failure: "command" },
      { tag: "status", failure: "status" },
      { tag: "malformed-status", failure: "malformed" }
    ]
  }
  function test_failures_reset_pending_position_and_drop_queued_seeks(data) {
    session.snapshot = { trackId: "a", position: 4.25 }
    session.transport("seek", 9.25)
    session.transport("seek", 14.25)
    session.transport("toggleLike")
    if (data.failure === "command") session.completeAction(1, "", "Seek failed")
    else {
      session.requestStatus()
      session.completeStatus(data.failure === "status" ? 1 : 0, "not json")
      session.completeAction(0, "", "")
    }
    compare(session.snapshot.position, 4.25)
    compare(actionSpy.count, 2)
    compare(actionSpy.signalArguments[1][0], "like")
    session.transport("seek", session.snapshot.position + 5)
    session.completeAction(0, "", "")
    compare(actionSpy.signalArguments[2][1], 9.25)
  }

  function test_completion_consumer_cannot_overtake_queued_actions() {
    var enqueue = function() { session.transport("toggleMute") }
    session.transport("togglePlayback")
    session.transport("toggleLike")
    session.actionFinished.connect(enqueue)
    session.completeAction(0, "", "")
    session.actionFinished.disconnect(enqueue)
    compare(actionSpy.count, 2)
    compare(actionSpy.signalArguments[1][0], "like")
    session.completeAction(0, "", "")
    compare(actionSpy.count, 3)
    compare(actionSpy.signalArguments[2][0], "mute")
    session.completeAction(0, "", "")
    compare(session.actionRunning, false)
  }
}
