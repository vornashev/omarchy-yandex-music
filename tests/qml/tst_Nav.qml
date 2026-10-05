import QtQuick
import QtTest
import "../.."

TestCase {
  name: "Nav"
  when: windowShown

  property var nav
  Component { id: controllerFactory; NavController {} }
  SignalSpy { id: activationSpy; target: nav; signalName: "routeActivated" }

  function init() {
    nav = createTemporaryObject(controllerFactory, this)
    activationSpy.clear()
  }

  function artist(id, title) {
    return { kind: "artist", args: { id: id }, title: title || "Исполнитель " + id }
  }

  function album(id) {
    return { kind: "album", args: { id: id }, title: "Альбом " + id }
  }

  function test_each_tab_retains_its_own_route_and_scroll() {
    nav.saveScroll(18)
    nav.push(artist("now-artist"))
    nav.saveScroll(90)
    nav.selectTab(1)
    nav.saveScroll(42)
    nav.push({ kind: "collection", args: { command: "likes", argument: "" }, title: "Мне нравится" })
    nav.saveScroll(120)
    nav.push(artist("library-artist"))
    nav.selectTab(2)
    nav.saveScroll(250)
    nav.push(album("search-album"))
    nav.selectTab(0)
    compare(nav.top.args.id, "now-artist")
    compare(nav.top.scrollY, 90)
    nav.selectTab(1)
    compare(nav.top.args.id, "library-artist")
    nav.pop()
    compare(nav.top.kind, "collection")
    compare(nav.top.scrollY, 120)
    nav.selectTab(2)
    compare(nav.top.args.id, "search-album")
    nav.pop()
    compare(nav.top.kind, "search")
    compare(nav.top.scrollY, 250)
    nav.selectTab(0)
    nav.pop()
    compare(nav.top.kind, "now")
    compare(nav.top.scrollY, 18)
  }

  function test_reselect_current_tab_returns_only_that_stack_to_root() {
    nav.push(artist("a"))
    nav.selectTab(1)
    nav.saveScroll(24)
    nav.push(album("b"))
    nav.selectTab(1)
    compare(nav.page, 1)
    compare(nav.top.kind, "libraryHome")
    compare(nav.top.scrollY, 24)
    compare(nav.stacks[0][1].args.id, "a")
    compare(nav.stacks[1].length, 1)
    var count = activationSpy.count
    nav.pop()
    nav.selectTab(1)
    compare(activationSpy.count, count)
  }

  function test_ancestor_navigation_uses_zero_based_depth() {
    nav.selectTab(1)
    nav.push({ kind: "librarySection", args: { section: "artists" }, title: "Исполнители" })
    nav.saveScroll(184)
    nav.push(artist("a"))
    nav.push(album("b"))
    nav.popTo(1)
    compare(nav.breadcrumbs.length, 2)
    compare(nav.top.args.section, "artists")
    compare(nav.top.scrollY, 184)
    compare(activationSpy.signalArguments[activationSpy.count - 1][0], 1)
    compare(activationSpy.signalArguments[activationSpy.count - 1][1].args.section, "artists")
    nav.popToRoot()
    compare(nav.top.kind, "libraryHome")
  }

  function test_search_root_state_survives_entity_and_tab_navigation() {
    var state = { fieldText: "запрос", filter: "album", query: "запрос", resultPage: 2 }
    nav.selectTab(2)
    nav.saveSearchState(state)
    nav.setRootTitle(2, "Поиск «запрос»")
    nav.saveScroll(231)
    nav.push(album("a"))
    nav.selectTab(1)
    state.query = "изменённый исходник"
    nav.selectTab(2)
    nav.pop()
    compare(nav.top.args.query, "запрос")
    compare(nav.top.args.fieldText, "запрос")
    compare(nav.top.args.filter, "album")
    compare(nav.top.args.resultPage, 2)
    compare(nav.top.title, "Поиск «запрос»")
    compare(nav.top.scrollY, 231)
  }

  function test_route_snapshots_are_deeply_isolated() {
    var input = { kind: "artist", args: { id: "a", nested: { values: ["before"] } },
      title: "До", scrollY: 31 }
    nav.push(input)
    var oldStacks = nav.stacks
    var oldTop = nav.top
    input.args.id = "b"
    input.args.nested.values[0] = "after"
    input.title = "После"
    compare(nav.top.args.id, "a")
    compare(nav.top.args.nested.values[0], "before")
    compare(nav.top.title, "До")
    nav.saveScroll(200)
    nav.setTitle("Обновлённое название")
    compare(oldTop.scrollY, 31)
    compare(oldTop.title, "До")
    compare(oldStacks[0][1].scrollY, 31)
    compare(nav.top.scrollY, 200)
    compare(nav.top.title, "Обновлённое название")
    nav.push(album("c"))
    compare(oldStacks[0].length, 2)
  }

  function test_adjacent_dedupe_ignores_presentation_but_not_entity_identity() {
    nav.push(artist("a", "Первое название"))
    nav.saveScroll(80)
    var count = activationSpy.count
    nav.push({ kind: "artist", args: { id: "a", metadata: "changed" }, title: "Другое", scrollY: 0 })
    compare(nav.breadcrumbs.length, 2)
    compare(nav.top.scrollY, 80)
    compare(activationSpy.count, count)
    nav.push(artist("b"))
    compare(nav.breadcrumbs.length, 3)
    nav.push(artist("a"))
    compare(nav.breadcrumbs.length, 4)
    nav.pop()
    compare(nav.top.args.id, "b")
    nav.push(album("b"))
    compare(nav.top.kind, "album")
  }

  function test_playlist_dedupe_uses_uuid_or_owner_and_kind() {
    nav.push({ kind: "playlist", args: { uuid: "u", owner: "one", kind: "1" } })
    nav.push({ kind: "playlist", args: { uuid: "u", owner: "two", kind: "2" }, title: "Переименован" })
    compare(nav.breadcrumbs.length, 2)
    nav.push({ kind: "playlist", args: { owner: "one", kind: "1" } })
    nav.push({ kind: "playlist", args: { kind: "1", owner: "one" } })
    compare(nav.breadcrumbs.length, 3)
    nav.push({ kind: "playlist", args: { owner: "two", kind: "1" } })
    compare(nav.breadcrumbs.length, 4)
  }

  function test_collection_dedupe_distinguishes_commands_and_arguments() {
    nav.push({ kind: "collection", args: { command: "playlist", argument: "1" } })
    nav.push({ kind: "collection", args: { argument: "1", command: "playlist" }, title: "Другое" })
    compare(nav.breadcrumbs.length, 2)
    nav.push({ kind: "collection", args: { command: "playlist", argument: "2" } })
    nav.push({ kind: "collection", args: { command: "browse_personal", argument: "2" } })
    compare(nav.breadcrumbs.length, 4)
  }

  function test_depth_cap_preserves_root_and_newest_seven_routes() {
    nav.saveScroll(19)
    for (var i = 1; i <= 10; i++) nav.push(artist(String(i)))
    compare(nav.breadcrumbs.length, 8)
    compare(nav.breadcrumbs[0].kind, "now")
    compare(nav.breadcrumbs[0].scrollY, 19)
    for (var depth = 1; depth < 8; depth++) compare(nav.breadcrumbs[depth].args.id, String(depth + 3))
    nav.pop()
    compare(nav.top.args.id, "9")
    nav.popToRoot()
    compare(nav.top.kind, "now")
    compare(nav.top.scrollY, 19)
  }

  function test_rail_resets_only_library_and_keeps_secondary_selection_under_entity() {
    nav.push(artist("now"))
    nav.selectTab(2)
    nav.push(album("search"))
    nav.openFromRail("likes")
    compare(nav.page, 1)
    compare(nav.breadcrumbs.length, 2)
    compare(nav.top.args.command, "likes")
    compare(nav.selectedShortcut, "likes")
    nav.push(artist("library"))
    compare(nav.selectedShortcut, "likes")
    nav.selectTab(0)
    compare(nav.top.args.id, "now")
    compare(nav.selectedShortcut, "likes")
    nav.openFromRail("playlist", "42", "Коллекция")
    compare(nav.breadcrumbs.length, 2)
    compare(nav.top.title, "Коллекция")
    compare(nav.selectedShortcut, "playlist:42")
    nav.openFromRail("playlist", "43", "Другая коллекция")
    compare(nav.selectedShortcut, "playlist:43")
    compare(nav.top.args.argument, "43")
    nav.openFromRail("history")
    compare(nav.top.kind, "librarySection")
    compare(nav.top.args.section, "history")
    compare(nav.selectedShortcut, "history")
    nav.openFromRail("wave")
    compare(nav.top.args.section, "wave")
    compare(nav.selectedShortcut, "wave")
    nav.pop()
    compare(nav.selectedShortcut, "")
    nav.selectTab(2)
    compare(nav.top.args.id, "search")
  }

  function test_scroll_and_titles_do_not_reactivate_routes() {
    nav.selectTab(2)
    nav.push(artist("a"))
    var count = activationSpy.count
    nav.saveScroll(99.5)
    nav.setTitle("Имя из ответа")
    nav.setRootTitle(2, "Поиск «пример»")
    nav.saveSearchState({ query: "пример" })
    compare(activationSpy.count, count)
    compare(nav.top.scrollY, 99.5)
    nav.pop()
    compare(nav.top.title, "Поиск «пример»")
    compare(nav.top.args.query, "пример")
    nav.saveScroll(-10)
    compare(nav.top.scrollY, 0)
  }
}
