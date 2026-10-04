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
    statusRequested()
    return true
  }
  function completeStatus(exitCode, stdoutText) {
    statusRunning = false
    if (exitCode !== 0) {
      statusError = "Фоновый музыкальный сервис недоступен"
      return
    }
    try {
      var parsed = JSON.parse(String(stdoutText || "{}"))
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
    }
  }
  function action(command, argument) {
    if (actionRunning) return false
    actionRevision += 1
    lastCommand = command
    lastArgument = argument
    actionRunning = true
    actionRequested(command, argument)
    return true
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
    actionRunning = false
    actionFinished(exitCode, String(stdoutText || ""), String(stderrText || ""))
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
