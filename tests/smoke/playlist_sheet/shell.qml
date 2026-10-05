import QtQuick
import QtQuick.Window
import QtTest
import Quickshell

ShellRoot {
  id: shell
  property int failures: 0
  function check(ok, label) {
    if (!ok) { failures++; console.warn("PLAYLIST_SHEET_CHECK_FAILED", label) }
  }
  Window {
    visible: true; width: 400; height: 640
    TestCase { id: input; name: "PlaylistSheetInput"; when: false }
    CollectionController {
      id: controller
      ownPlaylists: [{ kind: "1", title: "Existing", count: 1 },
        { kind: "2", title: "Available", count: 2 }]
    }
    PlaylistSheet {
      id: sheet
      anchors.fill: parent
      controller: controller
      foreground: "white"; fontFamily: "Sans"
    }
    Timer {
      interval: 250; running: true
      onTriggered: {
        controller.openTrack("queue", 0, { trackId: "t", albumId: "a" }, true, "1", "Existing")
        sheet.activate()
        input.mouseClick(sheet, 120, 180)
        shell.check(!controller.busy, "membership check blocks playlist click")
        controller.applySnapshot({ membershipTrackId: "t", membershipAlbumId: "a", memberships: { "1": true } })
        input.mouseClick(sheet, 120, 128)
        shell.check(!controller.busy, "duplicate playlist click blocked")
        input.keyClick(Qt.Key_Down)
        shell.check(sheet.selectedIndex === 1, "Down skips existing membership")
        input.keyClick(Qt.Key_Up)
        shell.check(sheet.selectedIndex === 2, "Up wraps to new playlist")
        input.keyClick(Qt.Key_Return)
        shell.check(controller.mode === "create", "Enter opens inline create")
        input.keyClick(Qt.Key_Escape)
        shell.check(controller.mode === "track", "Escape cancels form")
        focusCheck.start()
      }
    }
    Timer {
      id: focusCheck; interval: 100
      onTriggered: {
        shell.check(sheet.activeFocus, "cancelled form does not steal focus in deferred callback")
        input.keyClick(Qt.Key_Delete)
        shell.check(controller.mode === "delete", "Delete opens confirmation")
        input.keyClick(Qt.Key_Return)
        shell.check(!controller.busy, "Enter without focused destructive button cannot delete")
        input.keyClick(Qt.Key_Escape)
        shell.check(controller.mode === "track", "Escape cancels confirmation")
        input.mouseClick(sheet, 120, 180)
        shell.check(controller.busy, "available playlist starts mutation")
        controller.applySnapshot({ message: "Added", playlistKind: "2", membershipTrackId: "t", membershipAlbumId: "a", memberships: { "1": true, "2": true } })
        shell.check(controller.mode === "track", "result remains inline")
        input.mouseClick(sheet, 120, 180)
        shell.check(!controller.busy, "successful membership blocks repeated click")
        console.log(shell.failures ? "PLAYLIST_SHEET_SMOKE_FAILED" : "PLAYLIST_SHEET_SMOKE_OK")
        Qt.quit()
      }
    }
  }
}
