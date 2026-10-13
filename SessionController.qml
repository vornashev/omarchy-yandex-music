import QtQuick
import "TransportIntents.js" as TransportIntents

Item {
  id: root
  width: 0
  height: 0

  property var snapshot: ({ title: "", artist: "", playing: false })
  property string statusError: ""
  property string bootstrapError: ""
  property bool bootstrapping: false
  property bool statusRunning: false
  property bool actionRunning: false
  property int actionRevision: 0
  property string lastCommand: ""
  property var lastArgument: undefined
  property string pendingArtistId: ""
  property bool volumeRunning: false
  property bool panelOpened: false
  property bool pollingEnabled: false
  property int settleDelay: 300
  property int volumeDebounceMs: 45
  property int pendingVolume: -1
  property int sentVolume: -1
  property int volumeRevision: 0
  property int completedVolumeRevision: 0
  property int verifiedVolumeRevision: 0
  property int statusVolumeRevision: 0
  property bool statusStartedAfterVolume: false
  property real pendingSeek: -1
  property string pendingSeekTrackId: ""
  property int seekRevision: 0
  property int completedSeekRevision: 0
  property int statusSeekRevision: 0
  property bool statusStartedAfterSeek: false
  property real observedPosition: 0
  property real observedPositionAt: 0
  property int sentSeekRevision: 0
  property bool completingAction: false
  readonly property string trackId: String(snapshot.trackId || "")
  onTrackIdChanged: {
    if (pendingSeek >= 0 && pendingSeekTrackId !== trackId) resetSeek(false)
  }

  readonly property bool playing: snapshot.playing === true
  readonly property bool loading: bootstrapping || snapshot.loading === true
    || snapshot.connecting === true || snapshot.restoring === true
  readonly property string error: bootstrapError || statusError || String(snapshot.error || "")
  readonly property bool volumePending: pendingVolume >= 0
    && verifiedVolumeRevision < volumeRevision

  signal bootstrapRequested()
  signal statusRequested()
  signal actionRequested(string command, var argument)
  signal volumeRequested(int value)
  signal actionFinished(int exitCode, string stdoutText, string stderrText)
  signal volumeDrained()

  function startBootstrap() {
    if (bootstrapping) return false
    bootstrapping = true
    bootstrapRequested()
    return true
  }
  function completeBootstrap(exitCode, stderrText) {
    bootstrapping = false
    if (exitCode !== 0) {
      bootstrapError = String(stderrText || "").trim()
        || "Не удалось установить фоновый музыкальный сервис"
      return
    }
    bootstrapError = ""
    settle.restart()
  }
  function requestStatus() {
    if (statusRunning) return false
    statusRunning = true
    statusVolumeRevision = volumeRevision
    statusStartedAfterVolume = !volumeRunning && !volumeDebounce.running
      && completedVolumeRevision === volumeRevision
    statusSeekRevision = seekRevision
    statusStartedAfterSeek = completedSeekRevision === seekRevision
    statusRequested()
    return true
  }
  function completeStatus(exitCode, stdoutText) {
    statusRunning = false
    if (exitCode !== 0) {
      statusError = "Фоновый музыкальный сервис недоступен"
      resetSeek(true)
      return
    }
    try {
      var parsed = JSON.parse(String(stdoutText || "{}"))
      observedPosition = Number(parsed.position || 0)
      observedPositionAt = Number(parsed.positionObservedAt || 0)
      if (pendingSeek >= 0) {
        if (String(parsed.trackId || "") !== pendingSeekTrackId) {
          resetSeek(false)
        } else if (statusSeekRevision === seekRevision && statusStartedAfterSeek) {
          pendingSeek = -1
        } else {
          parsed.position = pendingSeek
          parsed.positionObservedAt = 0
        }
      }
      if (volumePending) {
        if (statusVolumeRevision === volumeRevision && statusStartedAfterVolume
            && completedVolumeRevision === volumeRevision) {
          verifiedVolumeRevision = volumeRevision
        } else {
          parsed.volume = pendingVolume
          parsed.muted = false
        }
      }
      snapshot = parsed
      statusError = ""
    } catch (e) {
      statusError = "Музыкальный сервис вернул некорректный ответ"
      resetSeek(true)
    }
  }
  property var actionQueue: []

  function resetSeek(restorePosition) {
    var restore = restorePosition && pendingSeek >= 0 && pendingSeekTrackId === trackId
    pendingSeek = -1
    completedSeekRevision = seekRevision
    actionQueue = actionQueue.filter(function(entry) { return entry[0] !== "seek" })
    if (restore) {
      var copy = {}
      for (var key in snapshot) copy[key] = snapshot[key]
      copy.position = observedPosition
      copy.positionObservedAt = observedPositionAt
      snapshot = copy
    }
  }
  function action(command, argument) {
    if (command === "seek") {
      // Both direct callers and transport intents must preserve finite fractions.
      if (typeof argument !== "number" || !isFinite(argument) || argument < 0) return false
      if (pendingSeek < 0) {
        observedPosition = Number(snapshot.position || 0)
        observedPositionAt = Number(snapshot.positionObservedAt || 0)
      }
      pendingSeek = argument
      pendingSeekTrackId = trackId
      seekRevision += 1
      var copy = {}
      for (var key in snapshot) copy[key] = snapshot[key]
      copy.position = pendingSeek
      copy.positionObservedAt = 0
      snapshot = copy
    }
    var entry = [command, argument, trackId, seekRevision]
    if (actionRunning || completingAction) {
      // Coalesce only adjacent seeks, never across a discrete user action or track.
      var last = actionQueue.length - 1
      if (command === "seek" && last >= 0 && actionQueue[last][0] === "seek"
          && actionQueue[last][2] === trackId) actionQueue[last] = entry
      else actionQueue.push(entry)
      return true
    }
    startAction(entry)
    return true
  }
  function startAction(entry) {
    actionRevision += 1
    lastCommand = entry[0]
    lastArgument = entry[1]
    sentSeekRevision = entry[3]
    actionRunning = true
    actionRequested(lastCommand, lastArgument)
  }
  function transport(intent, payload) {
    var resolved = TransportIntents.resolve(intent, payload)
    return resolved ? action(resolved.command, resolved.argument) : false
  }
  function openArtistEventually(artistId) {
    var target = String(artistId || "")
    if (target === "") return false
    if (actionRunning) {
      pendingArtistId = target
      return true
    }
    return action("catalog_artist", target)
  }
  function completeAction(exitCode, stdoutText, stderrText) {
    // Completion consumers can enqueue more work; keep it behind the existing FIFO.
    completingAction = true
    actionRunning = false
    if (exitCode !== 0) resetSeek(true)
    else if (lastCommand === "seek") completedSeekRevision = sentSeekRevision
    else if (lastCommand === "next" || lastCommand === "previous"
        || lastCommand.indexOf("play_") === 0 || lastCommand === "wave"
        || lastCommand === "track_radio" || lastCommand === "dislike"
        || lastCommand === "logout") resetSeek(true)
    actionFinished(exitCode, String(stdoutText || ""), String(stderrText || ""))
    completingAction = false
    while (actionQueue.length > 0) {
      var next = actionQueue.shift()
      if (next[0] === "seek" && next[2] !== trackId) continue
      startAction(next)
      return
    }
    if (pendingArtistId !== "" && !actionRunning) {
      var target = pendingArtistId
      pendingArtistId = ""
      action("catalog_artist", target)
    } else {
      settle.restart()
    }
  }
  function queueVolume(value) {
    var number = Number(value)
    if (!isFinite(number)) return false
    pendingVolume = Math.max(0, Math.min(100, Math.round(number)))
    volumeRevision += 1
    var copy = {}
    for (var key in snapshot) copy[key] = snapshot[key]
    copy.volume = pendingVolume
    copy.muted = false
    snapshot = copy
    volumeDebounce.restart()
    return true
  }
  function shouldPreserveVolume(requestRevision, startedAfterVolume) {
    return pendingVolume >= 0 && (volumePending
      || requestRevision !== volumeRevision || !startedAfterVolume)
  }
  function completeVolume(exitCode) {
    volumeRunning = false
    if (pendingVolume !== sentVolume) {
      volumeDebounce.restart()
      return
    }
    completedVolumeRevision = volumeRevision
    volumeDrained()
    settle.restart()
  }

  Timer {
    id: volumeDebounce
    interval: root.volumeDebounceMs
    repeat: false
    onTriggered: {
      if (root.volumeRunning || root.pendingVolume < 0) return
      root.sentVolume = root.pendingVolume
      root.volumeRunning = true
      root.volumeRequested(root.sentVolume)
    }
  }
  Timer {
    id: poll
    interval: root.panelOpened || root.playing ? 1000 : 3000
    running: root.pollingEnabled
    repeat: true
    triggeredOnStart: true
    onTriggered: root.requestStatus()
  }
  Timer {
    id: settle
    interval: root.settleDelay
    repeat: false
    onTriggered: root.requestStatus()
  }
}
