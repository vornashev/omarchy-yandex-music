import QtQuick
import QtQuick.Window
import QtTest
import Quickshell

ShellRoot {
  id: shell
  property int phase: 0
  property int opened: 0
  property var commands: []
  property var volumes: []
  property real stablePlayerWidth: 0
  property real stableSubtitleWidth: 0
  property real pausedOffset: 0

  function check(condition, label) {
    if (!condition) throw new Error(label)
  }
  function stableWave(label) {
    var slot = find(player, "barLyrics")
    check(slot.visible && slot.width === stableSubtitleWidth, label + ": subtitle slot stays reserved")
    check(player.width === stablePlayerWidth, label + ": bar allocation does not jump")
    check(find(player, "barLyricWave").visible && !find(player, "barLyricText").visible,
      label + ": wave replaces unavailable timing")
  }
  function capture(name, finish, after) {
    var directory = Quickshell.env("BAR_SCREENSHOT_DIR")
    if (!directory) {
      if (after) after()
      if (finish) Qt.quit()
      return
    }
    check(player.grabToImage(function(result) {
      check(result.saveToFile(directory + "/" + name + ".png"), "save bar capture")
      if (after) after()
      if (finish) Qt.quit()
    }), "capture production bar")
  }
  function find(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) {
      var found = find(item.children[i], name)
      if (found) return found
    }
    return null
  }
  function point(name, y) {
    var item = find(player, name)
    check(item !== null && item.visible, "visible target " + name)
    var p = item.mapToItem(player, item.width / 2, item.height / 2)
    return Qt.point(p.x, y === undefined ? p.y : y)
  }
  function click(name, y, button) {
    var p = point(name, y)
    check(events.mouseClick(player, p.x, p.y, button === undefined ? Qt.LeftButton : button,
      Qt.NoModifier, 0), "pointer click delivered")
  }
  function hover(name, y) {
    settling.wait(20)
    var p = point(name, y)
    events.mouseMove(player, p.x, p.y, 0, Qt.NoButton, Qt.NoModifier)
    settling.wait(20)
  }
  function wheel(name, delta) {
    var p = point(name)
    check(events.mouseWheel(player, p.x, p.y, Qt.NoButton, Qt.NoModifier, 0, delta, 0),
      "pointer wheel delivered")
  }
  function copySnapshot(changes) {
    var copy = {}
    for (var key in controller.snapshot) copy[key] = controller.snapshot[key]
    for (var changed in changes) copy[changed] = changes[changed]
    controller.snapshot = copy
  }
  function preferences(value) { copySnapshot({ preferences: value }) }
  function drain() {
    var remaining = 20
    while (controller.actionRunning && remaining-- > 0) controller.completeAction(0, "", "")
    check(!controller.actionRunning, "command queue drains")
  }
  function observe(position) {
    drain()
    var copy = {}
    for (var key in controller.snapshot) copy[key] = controller.snapshot[key]
    copy.position = position
    copy.positionObservedAt = 0
    controller.requestStatus()
    controller.completeStatus(0, JSON.stringify(copy))
    commands = []
  }
  function likeAtEdges() {
    var beforeOpen = opened
    for (var y of [1, player.height - 1]) {
      commands = []
      click("barLike", y)
      check(commands.length === 1 && commands[0][0] === "like", "like owns full-height click")
      check(opened === beforeOpen, "like never opens popup")
      drain()
      copySnapshot({ liked: !controller.snapshot.liked })
    }
    commands = []
  }

  SessionController {
    id: controller
    pollingEnabled: false
    settleDelay: 60000
    volumeDebounceMs: 60000
    snapshot: ({ trackId: "synthetic-a", title: "Synthetic track", artist: "Synthetic artist",
      authenticated: true, playing: false, volume: 25, position: 10.125, duration: 180,
      liked: false, preferences: {}, lyrics: {
        trackId: "synthetic-a", available: true, synced: true, lines: [
          { time: 0.125, text: "First fractional line" },
          { time: 0.25, text: "Second fractional line" },
          { time: 0.375, text: "Third fractional line" },
          { time: 1.875, text: "Fourth fractional line" },
          { time: 5.625, text: "Fifth fractional line" }
        ]
      } })
    onActionRequested: function(command, argument) { shell.commands.push([command, argument]) }
  }
  Item {
    id: syntheticLogic
    readonly property var snapshot: controller.snapshot
    readonly property bool hasTrack: true
    readonly property bool playing: controller.playing
    readonly property bool loading: false
    readonly property string error: controller.error
    function transport(intent, payload) { return controller.transport(intent, payload) }
    function queueVolume(value) { shell.volumes.push(value); return controller.queueVolume(value) }
    function toggle() { shell.opened += 1 }
  }
  Window {
    visible: true
    width: 2600
    height: 100
    Rectangle {
      id: neighbor
      visible: false
      y: player.y
      width: 220; height: player.height
      color: "#262630"
      Text { anchors.centerIn: parent; text: "Clock / system widgets"; color: "#dddddd" }
    }
    TestEvent { id: events }
    TestCase { id: settling; when: false }
    BarPlayer {
      id: player
      x: 10; y: 10
      width: implicitWidth
      height: 38
      logic: syntheticLogic
    }
  }

  Timer {
    interval: 100
    running: true
    repeat: false
    onTriggered: {
      try {
        if (shell.phase === 0) {
          shell.check(!player.barMouseControls && !player.showBarLyrics, "new features default off")
          var lyric = shell.find(player, "barLyricText")
          shell.check(lyric.text.length > 0 && lyric.implicitHeight > 0, "first lyric has laid-out text")
          shell.check(Math.abs(lyric.y + lyric.implicitHeight / 2 - lyric.parent.height / 2) < 0.01,
            "first lyric stays vertically centered after font metrics resolve")
          var originalSize = lyric.font.pixelSize
          lyric.font.pixelSize = originalSize + 4
          shell.check(Math.abs(lyric.y + lyric.implicitHeight / 2 - lyric.parent.height / 2) < 0.01,
            "lyric centering remains bound when text height changes")
          lyric.font.pixelSize = originalSize
          shell.click("barTrackInfo", 1)
          shell.check(shell.opened === 1 && shell.commands.length === 0, "default title opens popup")
          shell.click("barTrackInfo", player.height - 1, Qt.RightButton)
          shell.check(shell.commands.length === 1 && shell.commands[0][0] === "pause", "default right click pauses")
          shell.drain()
          shell.commands = []
          shell.wheel("barTrackInfo", 120)
          shell.check(shell.commands.length === 0 && controller.snapshot.volume === 30, "default wheel changes volume")
          shell.preferences({ showLike: true })
        } else if (shell.phase === 1) {
          shell.likeAtEdges()
          shell.preferences({ showLike: true, barMouseControls: true })
        } else if (shell.phase === 2) {
          shell.likeAtEdges()
          shell.check(!player.showBarLyrics, "mouse controls do not enable lyrics")
          shell.observe(10.125)
          shell.wheel("barTrackInfo", 120)
          shell.wheel("barTrackInfo", 120)
          shell.wheel("barTrackInfo", 120)
          shell.check(controller.snapshot.position === 25.125, "rapid wheel accumulates locally")
          shell.check(shell.commands.length === 1 && shell.commands[0][1] === 15.125, "one in-flight seek")
          controller.completeAction(0, "", "")
          shell.check(shell.commands.length === 2 && shell.commands[1][1] === 25.125, "latest seek coalesces")
          shell.observe(0.125)
          shell.preferences({ showLike: true, barMouseControls: true, showBarLyrics: true })
        } else if (shell.phase === 3) {
          shell.likeAtEdges()
          shell.observe(0.125)
          for (var next of [0.25, 0.375, 1.875]) {
            shell.wheel("barLyrics", 120)
            shell.check(controller.snapshot.position === next, "next fractional lyric " + next)
          }
          for (var previous of [0.375, 0.25]) {
            shell.wheel("barLyrics", -120)
            shell.check(controller.snapshot.position === previous, "previous fractional lyric " + previous)
          }
          shell.check(player.activeLyricIndex === 1, "paused line highlight follows fractional target")
          shell.check(shell.commands.length === 1 && shell.commands[0][1] === 0.25, "fraction reaches command unchanged")
          shell.observe(0.25)
          shell.wheel("barLyrics", -120)
          shell.check(controller.snapshot.position === 0.125, "paused previous line does not stick")
          shell.observe(10.125)
          shell.preferences({ showCover: true, showArtist: false, showTitle: false,
            showLike: false, showTime: false, showBarLyrics: false, barMouseControls: true })
        } else if (shell.phase === 4) {
          var beforeOpen = shell.opened
          for (var edge of [1, player.height - 1]) {
            shell.commands = []
            shell.click("barMute", edge)
            shell.check(shell.commands.length === 1 && shell.commands[0][0] === "mute", "cover-only mute owns edge")
            shell.drain()
          }
          shell.commands = []
          var track = shell.find(player, "barVolumeTrack")
          var p = track.mapToItem(player, track.width / 4, 1)
          shell.check(events.mouseClick(player, p.x, p.y, Qt.LeftButton, Qt.NoModifier, 0), "slider pointer delivered")
          shell.check(controller.snapshot.volume === 25, "cover-only slider receives click")
          shell.wheel("barMute", 120)
          shell.check(controller.snapshot.volume === 30 && shell.commands.length === 0,
            "volume wheel remains volume with mouse controls enabled")
          shell.check(shell.opened === beforeOpen, "volume never opens popup")
          shell.click("barCover", 1)
          shell.check(shell.opened === beforeOpen + 1 && shell.commands.length === 0,
            "cover-only popup hit area remains full height")
          shell.preferences({ showVolume: false, showControls: false, showCover: false,
            showBarLyrics: true, barMouseControls: false })
        } else if (shell.phase === 5) {
          shell.check(!shell.find(player, "barMute").visible, "volume toggle stays independent")
          shell.check(player.showBarLyrics && !player.barMouseControls, "lyrics do not enable gestures")
          shell.commands = []
          shell.wheel("barLyrics", 120)
          shell.check(controller.snapshot.volume === 35 && shell.commands.length === 0,
            "lyrics retain default volume wheel when gestures disabled")
          shell.preferences({ showBarLyrics: false, barWidth: "wide", showTime: true,
            showLike: true, showVolume: true })
        } else if (shell.phase === 6) {
          player.x = 1000
          neighbor.x = player.x + player.implicitWidth + 400 + 30
          neighbor.visible = true
          shell.copySnapshot({ playing: true, position: 0, lyrics: {
            trackId: "synthetic-a", available: true, synced: true, lines: [
              { time: 10, text: "A very long synthetic lyric without a natural short ending ".repeat(30) }
            ]
          } })
          shell.preferences({ showBarLyrics: true, barWidth: "wide", showTime: true,
            showLike: true, showVolume: true })
        } else if (shell.phase === 7) {
          var slot = shell.find(player, "barLyrics")
          shell.check(slot.width <= 400, "Auto bounds an arbitrarily long lyric")
          shell.check(player.x + player.width < neighbor.x,
            "wave and trailing volume do not overlap the next block")
        } else if (shell.phase < 10) {
          // Wait for the transition into the introductory wave.
        } else if (shell.phase === 10) {
          shell.check(!shell.find(player, "barLyricText").visible, "introductory wave replaces text")
          shell.capture("wave", false, function() { shell.copySnapshot({ position: 95, playing: false }) })
        } else if (shell.phase < 14) {
          // Wait for the transition into the long lyric.
        } else if (shell.phase === 14) {
          shell.check(shell.find(player, "barLyricText").visible,
            "long lyric replaces the introductory wave")
          var lyric = shell.find(player, "barLyricText")
          var overflow = lyric.implicitWidth - lyric.parent.width
          shell.check(overflow > 0 && Math.abs(lyric.x + overflow / 2) < 0.1,
            "last long line reaches its midpoint by playback position")
          shell.copySnapshot({ position: 10 })
          shell.check(lyric.x === 0, "seeking to line start shows its beginning")
          shell.copySnapshot({ position: 179.9 })
          shell.check(Math.abs(lyric.x + overflow) < 0.1, "line ending is fully exposed before track end")
          shell.copySnapshot({ position: 95 })
          shell.check(Math.abs(lyric.x + overflow / 2) < 0.1, "backward seek restores midpoint")
          shell.check(player.x + player.width < neighbor.x,
            "long displayed lyric and trailing volume stay before the next block")
          shell.stablePlayerWidth = player.width
          shell.stableSubtitleWidth = shell.find(player, "barLyrics").width
          shell.capture("text", false, function() { shell.copySnapshot({ lyrics: {} }) })
        } else if (shell.phase === 15) {
          shell.stableWave("missing lyrics")
          shell.capture("missing", false, function() {
            shell.copySnapshot({ lyrics: { trackId: "synthetic-a", loading: true, lines: [] } })
          })
        } else if (shell.phase === 16) {
          shell.stableWave("loading")
          shell.copySnapshot({ lyrics: { trackId: "synthetic-a", loading: false,
            available: false, error: "Service unavailable", lines: [] } })
        } else if (shell.phase === 17) {
          shell.stableWave("failed lookup")
          shell.copySnapshot({ lyrics: { trackId: "synthetic-a", available: true,
            synced: false, lines: [{ time: -1, text: "Plain lyrics" }] } })
        } else if (shell.phase === 18) {
          shell.stableWave("plain text")
          shell.copySnapshot({ trackId: "synthetic-b", lyrics: { trackId: "synthetic-a",
            available: true, synced: true, lines: [{ time: 0, text: "Old track text" }] } })
        } else if (shell.phase === 19) {
          shell.stableWave("old track response")
          shell.copySnapshot({ lyrics: { trackId: "synthetic-b", available: true,
            synced: true, lines: [{ time: 0, text: "Hi" }] } })
        } else if (shell.phase === 20) {
          shell.check(player.width === shell.stablePlayerWidth
            && shell.find(player, "barLyrics").width === shell.stableSubtitleWidth,
            "short synced lyrics keep the same bar allocation")
          shell.check(shell.find(player, "barLyricText").text === "Hi"
            && shell.find(player, "barLyricText").visible, "only new track lyrics are visible")
          shell.check(shell.find(player, "barLyricText").x === 0, "short line never scrolls")
          var repeated = "Repeated long synthetic lyric ".repeat(8)
          shell.copySnapshot({ playing: false, position: 15, duration: 50, lyrics: {
            trackId: "synthetic-b", available: true, synced: true, lines: [
              { time: 10, text: repeated }, { time: 20, text: repeated },
              { time: 30, text: "" }, { time: 40, text: "Short ending" }
            ]
          } })
        } else if (shell.phase < 25) {
          // Wait for the new text's vertical transition.
        } else if (shell.phase === 25) {
          var lyric = shell.find(player, "barLyricText")
          var overflow = lyric.width - lyric.parent.width
          shell.check(Math.abs(lyric.x + overflow / 2) < 0.1, "next timestamp controls line midpoint")
          shell.copySnapshot({ position: 19.9 })
          shell.check(Math.abs(lyric.x + overflow) < 0.1, "entire line shown before next timestamp")
          shell.copySnapshot({ position: 20 })
          shell.check(lyric.x === 0, "identical consecutive lyrics reset at new timestamp")
          shell.copySnapshot({ position: 25 })
          shell.preferences({ showBarLyrics: true, lyricsWidthMode: "compact", longTitleMode: "truncate",
            showTime: true, showLike: true, showVolume: true })
          overflow = lyric.width - lyric.parent.width
          shell.check(lyric.parent.width === 240 && Math.abs(lyric.x + overflow / 2) < 0.1,
            "resizing recomputes overflow independently of title marquee")
          shell.pausedOffset = lyric.x
          player.positionClockMs = Date.now()
          shell.copySnapshot({ playing: true, positionObservedAt: Date.now() / 1000 })
        } else if (shell.phase === 26) {
          var lyric = shell.find(player, "barLyricText")
          shell.check(lyric.x < shell.pausedOffset, "playing text advances between snapshots")
          shell.copySnapshot({ position: player.displayPosition, playing: false, positionObservedAt: 0 })
          shell.pausedOffset = lyric.x
        } else if (shell.phase === 27) {
          var lyric = shell.find(player, "barLyricText")
          shell.check(Math.abs(lyric.x - shell.pausedOffset) < 0.1, "pause freezes scrolling")
          shell.copySnapshot({ position: 29.9 })
          shell.check(Math.abs(lyric.x + lyric.width - lyric.parent.width) < 0.1,
            "resume interval keeps the ending visible")
          shell.capture("scroll-ending", false)
        } else if (shell.phase === 28) {
          shell.copySnapshot({ position: 30 })
        } else if (shell.phase < 32) {
          // Wait for the empty-line wave transition.
        } else if (shell.phase === 32) {
          shell.check(shell.find(player, "barLyricWave").visible
            && !shell.find(player, "barLyricText").visible, "empty next line returns to decorative wave")
          shell.preferences({ showBarLyrics: false, barWidth: "wide",
            showTime: true, showLike: true, showVolume: true })
        } else if (shell.phase === 33) {
          shell.check(!shell.find(player, "barLyrics").visible, "disabled subtitles release their slot")
          shell.commands = []
          shell.click("barMute")
          shell.check(shell.commands.length === 1 && shell.commands[0][0] === "mute",
            "volume remains independent after disabling subtitles")
          shell.drain()
          shell.commands = []
          shell.preferences({ showCover: false, barMouseControls: true,
            showBarLyrics: true, showTime: true, showLike: true, showVolume: true })
        } else if (shell.phase === 34) {
          var opener = shell.find(player, "barPopupButton")
          shell.check(opener && opener.visible, "hidden cover with gestures retains a popup button")
          for (var height of [32, 48, 64]) {
            player.height = height
            var beforeOpen = shell.opened
            for (var edge of [1, player.height - 1]) {
              shell.hover("barPopupButton", edge)
              shell.check(opener.containsMouse && shell.find(player, "barInfoHover").visible,
                "popup icon participates in full-height information hover")
              shell.click("barPopupButton", edge)
            }
            shell.check(shell.opened === beforeOpen + 2 && shell.commands.length === 0,
              "popup button owns full-height clicks without playback commands")
          }
          player.height = 38
          shell.hover("barPopupButton")
          shell.capture("popup-icon-hover", false, function() {
            var beforeOpen = shell.opened
            shell.click("barTrackInfo")
            shell.check(shell.opened === beforeOpen && shell.commands.length === 1
              && shell.commands[0][0] === "pause", "text retains gesture click beside popup icon")
            shell.drain()
            shell.commands = []
            shell.observe(25)
            shell.wheel("barPopupButton", 120)
            shell.check(controller.snapshot.position === 30,
              "popup icon wheel uses five-second seek, not lyric timestamps")
            shell.observe(25)
            shell.copySnapshot({ artUrl: "data:image/svg+xml;utf8," + encodeURIComponent(
              '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20">'
              + '<rect width="20" height="20" fill="#347a90"/><circle cx="10" cy="10" r="6" fill="#e4ba76"/></svg>') })
            shell.preferences({ showCover: true, barMouseControls: true, showBarLyrics: true,
              showTime: true, showLike: true, showVolume: true })
          })
        } else if (shell.phase === 35) {
          shell.check(!shell.find(player, "barPopupButton").visible, "cover replaces popup icon")
          var sharedHover = shell.find(player, "barInfoHover")
          var cover = shell.find(player, "barCover")
          var localHover = shell.find(player, "barCoverHover")
          var coverLeft = cover.mapToItem(player, 0, 0).x
          var lyrics = shell.find(player, "barLyrics")
          var lyricsRight = lyrics.mapToItem(player, lyrics.width, 0).x
          shell.check(sharedHover.x < coverLeft && sharedHover.x + sharedHover.width > lyricsRight,
            "shared hover spans cover through entire subtitle slot")
          shell.check(sharedHover.x + sharedHover.width
            < shell.find(player, "barMute").mapToItem(player, 0, 0).x,
            "volume remains outside shared hover bounds")
          for (var height of [32, 48, 64]) {
            player.height = height
            for (var edge of [1, player.height - 1]) {
              shell.hover("barCover", edge)
              shell.check(sharedHover.visible && sharedHover.height === player.height,
                "cover activates complete full-height information hover")
              settling.wait(140)
              shell.check(localHover.hovered && localHover.height === player.height
                && Math.abs(localHover.color.a - 0.08) < 0.001,
                "cover also has the button-strength local hover on full-height edges")
              var beforeOpen = shell.opened
              for (var button of [Qt.LeftButton, Qt.RightButton, Qt.MiddleButton])
                shell.click("barCover", edge, button)
              shell.check(shell.opened === beforeOpen + 3 && shell.commands.length === 0,
                "cover clicks open popup, never transport")
            }
          }
          player.height = 38
          for (var target of ["barTrackInfo", "barLike", "barLyrics"]) {
            shell.hover(target)
            shell.check(sharedHover.visible, target + " activates shared hover including cover")
            settling.wait(140)
            shell.check(!localHover.hovered && localHover.color.a === 0,
              "cover local highlight clears while the shared background stays active")
          }
          shell.hover("barMute")
          shell.check(!sharedHover.visible, "hovering volume does not highlight information area")
          events.mouseMove(player, 2, player.height / 2, 0, Qt.NoButton, Qt.NoModifier)
          settling.wait(20)
          shell.check(!sharedHover.visible, "transport lies outside information hover")
          shell.hover("barCover")
          settling.wait(140)
          var coverPoint = shell.point("barCover")
          var beforeOpen = shell.opened
          events.mousePress(player, coverPoint.x, coverPoint.y, Qt.LeftButton, Qt.NoModifier, 0)
          shell.check(localHover.pressed && Math.abs(localHover.color.a - 0.2) < 0.001
            && sharedHover.visible && shell.opened === beforeOpen && shell.commands.length === 0,
            "cover press feedback: pressed=" + localHover.pressed + " alpha=" + localHover.color.a
            + " shared=" + sharedHover.visible + " openDelta=" + (shell.opened - beforeOpen)
            + " commands=" + shell.commands.length)
          shell.capture("cover-pressed", false, function() {
            events.mouseRelease(player, coverPoint.x, coverPoint.y, Qt.LeftButton, Qt.NoModifier, 0)
            shell.check(!localHover.pressed && shell.opened === beforeOpen + 1
              && shell.commands.length === 0, "cover release opens popup once without transport")
          })
        } else if (shell.phase === 36) {
          shell.hover("barCover")
          settling.wait(140)
          shell.check(shell.find(player, "barCoverHover").color.a > 0
            && shell.find(player, "barInfoHover").visible, "local and shared cover hover coexist")
          shell.capture("cover-hover", false, function() {
            shell.observe(25)
            shell.wheel("barCover", 120)
            shell.check(controller.snapshot.position === 30, "cover wheel still seeks five seconds")
            shell.observe(25)
            shell.preferences({ showCover: true, barMouseControls: false })
          })
        } else if (shell.phase === 37) {
          shell.hover("barCover")
          shell.check(shell.find(player, "barInfoHover").visible, "default cover retains shared hover")
          settling.wait(140)
          shell.check(shell.find(player, "barCoverHover").hovered
            && Math.abs(shell.find(player, "barCoverHover").color.a - 0.08) < 0.001,
            "default mode also shows button-strength local cover hover")
          var beforeOpen = shell.opened
          shell.click("barCover")
          shell.check(shell.opened === beforeOpen + 1, "default cover still opens popup")
          shell.preferences({ showCover: false, barMouseControls: false })
        } else if (shell.phase === 38) {
          shell.check(!shell.find(player, "barPopupButton").visible,
            "visible title opens popup without extra icon when gestures are disabled")
          var beforeOpen = shell.opened
          shell.click("barTrackInfo")
          shell.check(shell.opened === beforeOpen + 1, "default title remains popup anchor")
          shell.preferences({ showCover: false, showArtist: false, showTitle: false })
        } else if (shell.phase === 39) {
          shell.check(shell.find(player, "barPopupButton").visible,
            "fully hidden cover and labels retain existing fallback icon")
          var beforeOpen = shell.opened
          shell.click("barPopupButton")
          shell.check(shell.opened === beforeOpen + 1 && shell.commands.length === 0,
            "fallback icon opens popup without gestures")
          shell.copySnapshot({ authenticated: false })
        } else if (shell.phase === 40) {
          shell.check(!shell.find(player, "barPopupButton").visible
            && !shell.find(player, "barInfoHover").visible, "signed-out state hides popup affordances")
          console.log("BAR_INTERACTIONS_SMOKE_OK")
          stop()
          Qt.quit()
          return
        }
        shell.phase += 1
        restart()
      } catch (error) {
        console.error("BAR_INTERACTIONS_SMOKE_FAILED", "phase", shell.phase, String(error))
        stop()
        Qt.quit()
      }
    }
  }
}
