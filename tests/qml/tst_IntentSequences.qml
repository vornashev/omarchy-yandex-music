import QtQuick
import QtTest
import "../../qml/controllers/ActionIntents.js" as ActionIntents
import "../../qml/controllers/TransportIntents.js" as TransportIntents

TestCase {
  id: root
  name: "IntentSequences"
  when: windowShown

  property list<var> payload: []
  property var resolved: null
  property bool transport: false
  signal requested(string intent, var argument)
  onRequested: function(intent, argument) {
    resolved = transport ? TransportIntents.resolve(intent, argument)
                         : ActionIntents.resolve(intent, argument)
  }

  function test_action_sequences_data() {
    return [
      { tag: "two", intent: "searchCatalog", args: ["all", "слова, с пробелами"], command: "catalog_search" },
      { tag: "three", intent: "openCatalogPlaylist", args: ["", "123", "7"], command: "catalog_playlist" },
      { tag: "four", intent: "inspectPlaylistMembership", args: ["entity", 0, "42", ""], command: "playlist_memberships" },
      { tag: "five", intent: "createPlaylist", args: ["entity", 0, "42", "", "Мой плейлист"], command: "playlist_create" }
    ]
  }
  function test_action_sequences(data) {
    transport = false
    payload = data.args
    verify(!Array.isArray(payload), "exercise a real Qt sequence")
    requested(data.intent, payload)
    verify(resolved !== null)
    compare(resolved.command, data.command)
    compare(resolved.argument.length, data.args.length)
    for (var i = 0; i < data.args.length; i++) compare(resolved.argument[i], data.args[i])
  }

  function test_action_sequences_keep_arity_validation() {
    transport = false
    payload = ["artist:7"]
    requested("openCatalogArtist", payload)
    compare(resolved, null)
    payload = ["uuid", "owner"]
    requested("openCatalogPlaylist", payload)
    compare(resolved, null)
    payload = []
    requested("openLikes", payload)
    compare(resolved, null)
  }

  function test_transport_sequences_keep_source_and_index_validation() {
    transport = true
    payload = ["entity", 0]
    verify(!Array.isArray(payload), "exercise a real Qt sequence")
    requested("playCatalogTrack", payload)
    verify(resolved !== null)
    compare(resolved.command, "play_catalog_track")
    compare(resolved.argument[0], "entity")
    compare(resolved.argument[1], 0)
    for (var invalid of [["unknown", 0], ["entity", -1], ["entity", "0"], ["entity", 0.5], ["entity"]]) {
      payload = invalid
      requested("playCatalogTrack", payload)
      compare(resolved, null)
    }
  }
}
