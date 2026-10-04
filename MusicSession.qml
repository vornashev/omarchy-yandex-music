import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  width: 0
  height: 0

  readonly property string cli: Quickshell.env("HOME") + "/.local/bin/omarchy-yandex-music"
  readonly property string pluginDir: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/vornashev.yandex-music"
  property bool panelOpened: false
  readonly property var snapshot: controller.snapshot
  readonly property string statusError: controller.statusError
  readonly property string bootstrapError: controller.bootstrapError
  readonly property bool loading: controller.loading
  readonly property string error: controller.error
  readonly property bool actionRunning: controller.actionRunning
  readonly property int actionRevision: controller.actionRevision
  readonly property string lastCommand: controller.lastCommand
  readonly property var lastArgument: controller.lastArgument
  readonly property bool volumePending: controller.volumePending
  readonly property int pendingVolume: controller.pendingVolume
  readonly property int volumeRevision: controller.volumeRevision

  signal actionFinished(int exitCode, string stdoutText, string stderrText)
  signal volumeDrained()

  function refresh() { return controller.requestStatus() }
  function action(command, argument) { return controller.action(command, argument) }
  function transport(intent, payload) { return controller.transport(intent, payload) }
  function openArtistEventually(artistId) { return controller.openArtistEventually(artistId) }
  function queueVolume(value) { return controller.queueVolume(value) }
  function shouldPreserveVolume(requestRevision, startedAfterVolume) {
    return controller.shouldPreserveVolume(requestRevision, startedAfterVolume)
  }

  Component.onCompleted: controller.startBootstrap()

  SessionController {
    id: controller
    panelOpened: root.panelOpened
    pollingEnabled: true
    onBootstrapRequested: {
      bootstrapProcess.command = [root.pluginDir + "/bootstrap.sh"]
      bootstrapProcess.running = true
    }
    onStatusRequested: {
      statusProcess.command = [root.cli, "status"]
      statusProcess.running = true
    }
    onActionRequested: function(command, argument) {
      var args = [root.cli, command]
      if (Array.isArray(argument)) {
        for (var i = 0; i < argument.length; i++) args.push(String(argument[i]))
      } else if (argument !== undefined && argument !== null) {
        args.push(String(argument))
      }
      actionProcess.command = args
      actionProcess.running = true
    }
    onVolumeRequested: function(value) {
      volumeProcess.command = [root.cli, "volume", String(value)]
      volumeProcess.running = true
    }
    onActionFinished: function(exitCode, stdoutText, stderrText) {
      root.actionFinished(exitCode, stdoutText, stderrText)
    }
    onVolumeDrained: root.volumeDrained()
  }
  Process {
    id: bootstrapProcess
    command: []
    stderr: StdioCollector { id: bootstrapErr; waitForEnd: true }
    onExited: function(exitCode) {
      controller.completeBootstrap(exitCode, bootstrapErr.text)
    }
  }
  Process {
    id: statusProcess
    command: []
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: function(exitCode) {
      controller.completeStatus(exitCode, statusOut.text)
    }
  }
  Process {
    id: actionProcess
    command: []
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      controller.completeAction(exitCode, actionOut.text, actionErr.text)
    }
  }
  Process {
    id: volumeProcess
    command: []
    onExited: function(exitCode) { controller.completeVolume(exitCode) }
  }
}
