import QtQuick
import Quickshell

ShellRoot {
  id: shell
  property int failures: 0
  property int muteRequests: 0
  property var volumeRequests: []

  function check(condition, label) {
    if (condition) return
    failures += 1
    console.warn("VOLUME_CONTROL_CHECK_FAILED", label)
  }

  VolumeControl {
    id: regular
    width: 300
    volume: 25
    muted: false
    foreground: "white"
    dim: "gray"
    fontFamily: "Sans"
    onMuteRequested: shell.muteRequests += 1
    onVolumeChangeRequested: function(value) { shell.volumeRequests.push(value) }
  }
  VolumeControl {
    id: expanded
    width: 300
    volume: 80
    muted: true
    foreground: "white"
    dim: "gray"
    fontFamily: "Sans"
  }

  Component.onCompleted: Qt.callLater(function() {
    shell.check(regular.displayText === "25%", "regular volume label")
    shell.check(Math.abs(regular.fillFraction - .25) < .001, "regular fill")
    shell.check(expanded.displayText === "MUTE", "expanded mute label")
    shell.check(Math.abs(expanded.fillFraction - .8) < .001, "mute keeps saved fill")
    regular.requestVolumeAt(regular.trackWidth / 2)
    shell.check(shell.volumeRequests.length === 1
      && Math.abs(shell.volumeRequests[0] - 50) < .01, "drag sends ratio")
    regular.requestMute()
    shell.check(shell.muteRequests === 1, "mute sends one request")
    expanded.muted = false
    expanded.volume = 100
    shell.check(expanded.displayText === "100%" && expanded.fillFraction === 1,
      "expanded updates with snapshot")
    console.log(shell.failures === 0
      ? "VOLUME_CONTROL_SMOKE_OK" : "VOLUME_CONTROL_SMOKE_FAILED")
  })
}
