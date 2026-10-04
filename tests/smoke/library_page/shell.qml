import QtQuick
import Quickshell

ShellRoot {
  id: shell
  property int preferenceRequests: 0
  property int waveRequests: 0
  property int failures: 0

  function check(condition, label) {
    if (condition) return
    failures += 1
    console.warn("LIBRARY_PAGE_CHECK_FAILED", label)
  }

  LibraryController { id: controller }
  LibraryPage {
    id: page
    width: 430
    controller: controller
    foreground: "white"
    dim: "gray"
    fontFamily: "Sans"
    preferences: ({ waveMood: "calm" })
    settingsRunning: false
    settingsOpen: false
    panelOpened: false
    onPreferenceRequested: function(key, value) { shell.preferenceRequests += 1 }
    onWaveRequested: shell.waveRequests += 1
  }

  Component.onCompleted: Qt.callLater(function() {
    shell.check(page.controller === controller, "controller binding")
    shell.check(page.preference("waveMood", "all") === "calm", "preference binding")
    shell.check(page.preference("waveLanguage", "any") === "any", "preference fallback")
    shell.check(page.stationSearchVisible === false, "initial station search")
    controller.applySnapshot({ view: "section", section: "stations", loading: false,
      items: [{ entityType: "station", title: "Test station", stationId: "test" }] })
    Qt.callLater(function() {
      shell.check(page.stationSearchVisible === true, "station search visibility")
      page.resetViewport()
      shell.check(page.viewportY === 0, "reset viewport")
      page.preferenceRequested("waveMood", "active")
      page.waveRequested()
      shell.check(shell.preferenceRequests === 1, "preference signal")
      shell.check(shell.waveRequests === 1, "wave signal")
      console.log(shell.failures === 0 ? "LIBRARY_PAGE_SMOKE_OK" : "LIBRARY_PAGE_SMOKE_FAILED")
    })
  })
}
