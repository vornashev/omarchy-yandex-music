import QtQuick

Item {
  property var bar: null
  property var settings: null
  property var anchorItem: null
  property var hostWidget: null
  property var session: null
  property bool opened: false
  function open() { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened }
}
