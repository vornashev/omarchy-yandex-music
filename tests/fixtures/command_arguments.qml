import QtQuick
import Quickshell
import "controllers"

ShellRoot {
  id: root
  property int expectedCount: 0
  property var expectations: JSON.parse(Quickshell.env("COMMAND_CASES"))
  property int completed: 0

  MusicSession {
    id: session
    onActionFinished: function(exitCode, stdoutText, stderrText) {
      var expectedError = root.expectations[root.completed].error
      if (expectedError ? (exitCode === 0 || stderrText !== expectedError) : exitCode !== 0) {
        console.error("COMMAND_ARGUMENTS_FAILED", exitCode, stderrText)
        Qt.quit()
        return
      }
      root.completed += 1
      if (root.completed === root.expectedCount) {
        console.log("COMMAND_ARGUMENTS_OK", root.completed)
        Qt.quit()
      }
    }
  }

  Timer {
    interval: 50
    running: true
    onTriggered: {
      // Queue every command while the first real CLI process is still running.
      // This crosses both the var property and var signal in SessionController.
      var cases = JSON.parse(Quickshell.env("COMMAND_CASES"))
      root.expectedCount = cases.length
      for (var i = 0; i < cases.length; i++) {
        var entry = cases[i]
        var accepted = entry.intent
          ? session.transport(entry.intent, entry.argument)
          : session.action(entry.command, entry.argument)
        if (!accepted) {
          console.error("COMMAND_ARGUMENTS_FAILED", "rejected", i)
          Qt.quit()
          return
        }
      }
    }
  }
}
