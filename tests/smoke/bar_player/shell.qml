import QtQuick
import Quickshell

ShellRoot {
  BarWidget { id: widget }

  Timer {
    interval: 1400
    running: true
    repeat: false
    onTriggered: {
      var logic = widget.logic
      var player = null
      for (var i = 0; i < widget.children.length; i++) {
        var loaded = widget.children[i].item
        if (loaded && loaded.label !== undefined) player = loaded
      }
      if (!logic || !player) {
        console.log("BAR_PLAYER_SMOKE_FAILED", "loader missing")
        Qt.quit()
        return
      }
      var snapshot = logic.snapshot
      var trackCorrect = snapshot && snapshot.title === "Sample track"
        && snapshot.volume === 25 && logic.hasTrack && player.hasTrack
        && player.label === "Sample artist — Sample track"
        && player.logic === logic
      var wheelCorrect = false
      if (trackCorrect && typeof player.changeVolumeFromWheel === "function") {
        player.changeVolumeFromWheel(40)
        var first = logic.snapshot.volume
        player.changeVolumeFromWheel(40)
        var second = logic.snapshot.volume
        player.changeVolumeFromWheel(40)
        var third = logic.snapshot.volume
        player.changeVolumeFromWheel(480)
        var oversized = logic.snapshot.volume
        player.changeVolumeFromWheel(-40)
        player.changeVolumeFromWheel(-40)
        var beforeReverseStep = logic.snapshot.volume
        player.changeVolumeFromWheel(-40)
        var reverseStep = logic.snapshot.volume
        wheelCorrect = first === 25 && second === 25 && third === 30
          && oversized === 35 && beforeReverseStep === 35 && reverseStep === 30
      }
      console.log(trackCorrect && wheelCorrect ? "BAR_PLAYER_SMOKE_OK" : "BAR_PLAYER_SMOKE_FAILED",
        JSON.stringify({
          snapshotIsObject: snapshot !== undefined && snapshot !== null,
          logicHasTrack: logic.hasTrack,
          playerHasTrack: player.hasTrack,
          playerHasLogic: player.logic === logic,
          labelMatches: player.label === "Sample artist — Sample track",
          wheelCorrect: wheelCorrect
        }))
      Qt.quit()
    }
  }
}
