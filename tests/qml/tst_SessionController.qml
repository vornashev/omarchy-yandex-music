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

  function test_status_and_actions_are_single_flight() {
    verify(session.requestStatus())
    verify(!session.requestStatus())
    compare(statusSpy.count, 1)
    verify(session.action("play_station", ["station:1", "Title"]))
    verify(!session.action("next"))
    compare(session.lastCommand, "play_station")
    compare(session.lastArgument[1], "Title")
    compare(actionSpy.count, 1)
    compare(actionSpy.signalArguments[0][0], "play_station")
    compare(actionSpy.signalArguments[0][1][0], "station:1")
    session.completeStatus(0, '{"title":"Track","playing":true}')
    compare(session.snapshot.title, "Track")
    session.completeAction(0, "", "")
    compare(actionDoneSpy.count, 1)
    verify(session.action("next"))
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

  function test_action_revision_changes_only_for_started_commands() {
    compare(session.actionRevision, 0)
    verify(session.action("pause"))
    compare(session.actionRevision, 1)
    verify(!session.action("next"))
    compare(session.actionRevision, 1)
    session.completeAction(0, "", "")
    verify(session.action("next"))
    compare(session.actionRevision, 2)
  }

  function test_transport_intents_emit_existing_commands_and_preserve_arguments() {
    var cases = [
      ["togglePlayback", undefined, "pause", undefined],
      ["nextTrack", undefined, "next", undefined],
      ["previousTrack", undefined, "previous", undefined],
      ["toggleMute", undefined, "mute", undefined],
      ["toggleLike", undefined, "like", undefined],
      ["dislikeTrack", undefined, "dislike", undefined],
      ["playQueueTrack", 0, "play_queue", 0],
      ["playLibraryTrack", 4, "play_library_track", 4],
      ["playLibraryHubTrack", 7, "play_library_hub_track", 7],
      ["playCatalogTrack", ["entity", 2], "play_catalog_track", ["entity", 2]]
    ]
    for (var i = 0; i < cases.length; i++) {
      verify(session.transport(cases[i][0], cases[i][1]), cases[i][0])
      compare(actionSpy.signalArguments[i][0], cases[i][2])
      compare(JSON.stringify(actionSpy.signalArguments[i][1]), JSON.stringify(cases[i][3]))
      session.completeAction(0, "", "")
    }
    compare(actionSpy.count, cases.length)
  }

  function test_transport_rejects_unknown_and_invalid_without_taking_action_slot() {
    verify(!session.transport("unrecognized"))
    verify(!session.transport("playQueueTrack", -1))
    verify(!session.transport("playQueueTrack", true))
    verify(!session.transport("playQueueTrack", " "))
    verify(!session.transport("playCatalogTrack", ["invalid", 0]))
    compare(actionSpy.count, 0)
    compare(session.actionRevision, 0)
    verify(session.transport("togglePlayback"))
    verify(!session.transport("nextTrack"))
    compare(actionSpy.count, 1)
    compare(session.actionRevision, 1)
  }
}
