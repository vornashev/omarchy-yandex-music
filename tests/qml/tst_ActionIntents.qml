import QtQuick
import QtTest
import "../../ActionIntents.js" as ActionIntents

TestCase {
  name: "ActionIntents"
  when: windowShown

  function test_navigation_intents_keep_existing_commands_and_arguments() {
    var cases = [
      ["openLibrarySection", "history", "library_section", "history"],
      ["retryLibrarySection", "history", "library_retry", "history"],
      ["returnLibraryHome", undefined, "library_back", undefined],
      ["loadMoreLibrarySection", undefined, "library_section_more", undefined],
      ["loadMoreLibraryTracks", undefined, "load_more_library", undefined],
      ["openLikes", undefined, "likes", undefined],
      ["openOwnedPlaylist", "playlist:7", "playlist", "playlist:7"],
      ["openPersonalPlaylist", "daily", "browse_personal", "daily"],
      ["searchCatalog", ["all", "two words"], "catalog_search", ["all", "two words"]],
      ["openCatalogArtist", "artist:7", "catalog_artist", "artist:7"],
      ["openCatalogAlbum", "album:7", "catalog_album", "album:7"],
      ["openCatalogPlaylist", ["uuid", "owner", "kind"], "catalog_playlist",
        ["uuid", "owner", "kind"]],
      ["returnCatalogSearch", undefined, "catalog_back", undefined],
      ["loadMoreCatalogSearch", undefined, "catalog_load_more", undefined],
      ["loadMoreCatalogEntity", undefined, "catalog_entity_more", undefined],
      ["loadMoreArtistRelease", "singles", "catalog_artist_more", "singles"]
    ]
    for (var i = 0; i < cases.length; i++) {
      var request = ActionIntents.resolve(cases[i][0], cases[i][1])
      verify(request !== null, cases[i][0])
      compare(request.command, cases[i][2])
      compare(JSON.stringify(request.argument), JSON.stringify(cases[i][3]))
      compare(ActionIntents.policyForCommand(request.command).refresh, "settle")
    }
  }

  function test_collection_and_misc_intents_keep_argument_order() {
    var cases = [
      ["playStation", ["station:7", "Station title"], "play_station"],
      ["inspectPlaylistMembership", ["queue", 2, "track:7", "album:7"], "playlist_memberships"],
      ["addPlaylistTrack", ["kind", "queue", 2, "track:7", "album:7"], "playlist_add_track"],
      ["createPlaylist", ["queue", 2, "track:7", "album:7", "New playlist"], "playlist_create"],
      ["deletePlaylistTrack", ["kind", "queue", 2, "track:7", "album:7"], "playlist_delete_track"],
      ["loadPlaylistRecommendations", ["kind", "Title"], "playlist_recommendations"],
      ["startWave", undefined, "wave"],
      ["startTrackRadio", undefined, "track_radio"],
      ["cyclePlaybackMode", undefined, "mode"],
      ["authenticate", undefined, "auth"],
      ["logout", undefined, "logout"],
      ["reconnect", undefined, "reconnect"]
    ]
    for (var i = 0; i < cases.length; i++) {
      var request = ActionIntents.resolve(cases[i][0], cases[i][1])
      verify(request !== null, cases[i][0])
      compare(request.command, cases[i][2])
      compare(JSON.stringify(request.argument), JSON.stringify(cases[i][1]))
    }
  }

  function test_unknown_or_wrong_shape_is_rejected_before_action() {
    compare(ActionIntents.resolve("playQueueTrack", 0), null)
    compare(ActionIntents.resolve("openLikes", "unexpected"), null)
    compare(ActionIntents.resolve("openCatalogPlaylist", ["uuid", "owner"]), null)
    compare(ActionIntents.resolve("openCatalogArtist", ["artist:7"]), null)
    var missingId = ActionIntents.resolve("openCatalogArtist", undefined)
    compare(missingId.command, "catalog_artist")
    compare(missingId.argument, undefined)
    compare(ActionIntents.policyForCommand("arbitrary_shell_command"), null)
    compare(ActionIntents.policyForCommand("pause").refresh, "settle")
  }

  function test_optimistic_loading_preserves_other_fields_and_input() {
    var current = { title: "Current", error: "old", loading: false,
      libraryLoadingMore: false, queueIndex: 4 }
    var wave = ActionIntents.optimisticData(ActionIntents.policyForCommand("wave"), current)
    compare(wave.title, "Current")
    compare(wave.queueIndex, 4)
    compare(wave.loading, true)
    compare(wave.loadingKind, "wave")
    compare(wave.error, "")
    compare(current.loading, false)
    compare(current.error, "old")
    var more = ActionIntents.optimisticData(
      ActionIntents.policyForCommand("load_more_library"), current)
    compare(more.libraryLoadingMore, true)
    compare(more.error, "")
    compare(ActionIntents.optimisticData(ActionIntents.policyForCommand("catalog_album"), current), null)
  }
  function test_browsing_does_not_mark_playback_loading() {
    var current = { playing: true, queueIndex: 7, loading: false, loadingKind: "track" }
    for (var command of ["likes", "playlist", "browse_personal"]) {
      compare(ActionIntents.optimisticData(ActionIntents.policyForCommand(command), current), null)
    }
    compare(current.playing, true)
    compare(current.queueIndex, 7)
    compare(current.loading, false)
    compare(ActionIntents.resolve("closeLibraryQueue"), null)
  }

  function test_home_metadata_requests_do_not_replace_playback_or_visible_cards() {
    var current = { title: "Playing", queueIndex: 4, loading: true,
      loadingKind: "track", error: "Playback error" }
    var cases = [
      ["loadLibraryHome", "library_home"],
      ["retryLibraryHome", "library_home_refresh"]
    ]
    for (var i = 0; i < cases.length; i++) {
      var request = ActionIntents.resolve(cases[i][0])
      compare(request.command, cases[i][1])
      compare(request.argument, undefined)
      compare(ActionIntents.resolve(cases[i][0], "unexpected"), null)
      var policy = ActionIntents.policyForCommand(request.command)
      compare(policy.refresh, "settle")
      compare(ActionIntents.optimisticData(policy, current), null)
      compare(ActionIntents.optimisticLibrary(policy, undefined, 5), null)
    }
    compare(current.queueIndex, 4)
    compare(current.loadingKind, "track")
    compare(current.error, "Playback error")
  }

  function test_local_library_snapshot_and_search_scroll_policy() {
    var section = ActionIntents.optimisticLibrary(
      ActionIntents.policyForCommand("library_section"), "history", 17)
    compare(section.view, "section")
    compare(section.section, "history")
    compare(section.loading, true)
    compare(section.revision, 17)
    compare(section.items.length, 0)
    var home = ActionIntents.optimisticLibrary(
      ActionIntents.policyForCommand("library_back"), undefined, 18)
    compare(home.view, "home")
    compare(home.loading, false)
    compare(home.revision, 18)
    compare(ActionIntents.optimisticLibrary(
      ActionIntents.policyForCommand("catalog_artist"), "artist:7", 19), null)
    compare(ActionIntents.policyForCommand("catalog_search").resetCatalogScroll, true)
    compare(ActionIntents.policyForCommand("catalog_artist").resetCatalogScroll, undefined)
  }
}
