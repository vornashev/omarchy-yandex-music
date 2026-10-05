import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import Quickshell.Io
import "Reg.js" as Reg

ShellRoot {
  id: shell
  readonly property string mode: Quickshell.env("NAV_LAYOUT")
  readonly property string outputDirectory: Quickshell.env("NAV_SCREENSHOT_DIR")
  property int assertions: 0
  property int screenshots: 0
  readonly property var p: panelLoader.item
  readonly property var card: p && p.opened && Reg.panel ? Reg.panel.grabItem : null

  function check(condition, label) {
    assertions++
    if (!condition) throw new Error(label)
  }
  function until(predicate, label) {
    for (var n = 0; n < 100 && !predicate(); n++) input.wait(80)
    input.wait(80) // allow bindings, polish and deferred focus/viewport callbacks
    check(predicate(), label + " (page=" + p.page + ", ready=" + p.routeReady + ", busy=" + p.busy + ")")
  }
  function nodes(root, predicate) {
    var found = []
    function walk(item) {
      if (!item) return
      if (predicate(item)) found.push(item)
      var children = item.children || []
      for (var i = 0; i < children.length; i++) walk(children[i])
    }
    walk(root)
    return found
  }
  function onScreen(item) {
    if (!item || !item.visible || item.width <= 0 || item.height <= 0) return false
    var at = item
    while (at && at !== card) {
      if (!at.visible) return false
      if (at.clip) {
        var local = item.mapToItem(at, item.width / 2, item.height / 2)
        if (local.x < 0 || local.y < 0 || local.x >= at.width || local.y >= at.height) return false
      }
      at = at.parent
    }
    var pos = item.mapToItem(card, item.width / 2, item.height / 2)
    return pos.x >= 0 && pos.y >= 0 && pos.x < card.width && pos.y < card.height
  }
  function named(name) {
    var result = nodes(card, function(item) { return item.objectName === name })
    check(result.length === 1, "unique real control: " + name)
    return result[0]
  }
  function text(value, scope) {
    var found = nodes(scope || card, function(item) { return item.text === value && onScreen(item) })
    return found.length ? found[0] : null
  }
  function click(item, label) {
    check(onScreen(item), "visible mouse target: " + label)
    input.mouseClick(item, item.width / 2, item.height / 2)
    input.wait(80)
  }
  function clickText(value, scope) { click(text(value, scope), value) }
  function key(value, modifiers) {
    named("keyCatcher").forceActiveFocus()
    input.keyClick(value, modifiers || Qt.NoModifier)
    input.wait(80)
  }
  function route(page, kind) {
    until(function() { return p.page === page && p.activeRoute.kind === kind && p.routeReady && !p.busy },
          "route " + page + ":" + kind)
  }
  function tab(index) {
    var labels = ["Сейчас", "Медиатека", "Поиск"]
    // Tabs/rail precede page content; only their exact labels are selected.
    clickText(labels[index])
    until(function() { return p.page === index && p.routeReady && !p.busy }, "tab " + index)
  }
  function wheel(surface, delta) {
    input.mouseMove(surface, surface.width / 2, surface.height / 2)
    input.wait(20)
    input.mouseWheel(surface, surface.width / 2, surface.height / 2, 0, delta)
    input.wait(240)
    until(function() { return !surface.moving }, "wheel settles")
  }
  function reveal(value, page) {
    for (var n = 0; n < 30 && !text(value, page); n++) wheel(page.viewport, -600)
    check(!!text(value, page), "scroll reveals " + value)
  }
  function shot(name) {
    if (!outputDirectory) return
    var done = false
    check(card.grabToImage(function(result) {
      check(result.saveToFile(outputDirectory + "/" + name + ".png"), "save " + name)
      screenshots++
      done = true
    }), "grab " + name)
    until(function() { return done }, "screenshot callback " + name)
  }
  function playbackCount(expected) {
    until(function() { return Number(p.data.testPlaybackCount) === expected }, "playback command count " + expected)
  }
  function fixture(kind) {
    probe.command = [p.cli, "test_stale", kind]
    probe.running = true
    until(function() { return !probe.running }, "fixture command completes")
  }
  function stale(kind, inspect) {
    var previous = Number(p.data.testStaleReads || 0)
    fixture(kind)
    until(function() { return Number(p.data.testStaleReads || 0) > previous }, "real details consumes stale " + kind)
    inspect()
    fixture("")
    input.wait(1200)
  }
  function libraryLikes() {
    tab(1)
    if (!p.atRoot) tab(1)
    route(1, "libraryHome")
    var page = named("libraryPage")
    reveal("Мне нравится", page)
    clickText("Мне нравится", page)
    route(1, "collection")
  }
  function scenarios() {
    until(function() { return p && p.authenticated && card && p.queueDisplay.length === 50 && !p.busy }, "full Panel fake CLI ready")
    check(p.popupLayout === mode, "fixture chooses saved layout")
    if (mode === "mini") {
      check(p.layoutMini && card.height === 101, "Mini initially visible")
      key(Qt.Key_2)
      route(1, "libraryHome")
      check(!p.layoutMini && p.popupLayout === "mini", "navigation temporarily expands Mini without changing preference")
      key(Qt.Key_1)
      route(0, "now")
      key(Qt.Key_Escape)
      until(function() { return !p.opened }, "Escape closes root popup")
      p.open() // synthetic host reopens popup; no route is set by the harness
      until(function() { return p.layoutMini && p.opened && card }, "reopening restores saved Mini")
      playbackCount(0)
      return
    }
    var wide = mode === "wide"
    var prefix = wide ? "X" : "Y"
    tab(1)
    route(1, "libraryHome")
    var library = named("libraryPage")
    var libraryIdentity = library
    reveal("Недавно слушали", library)
    clickText("Недавно слушали", library)
    route(1, "librarySection")
    check(p.activeRoute.args.section === "history" && p.libraryHubDisplay.items.length === 50, "history has 50 fixture tracks")
    shot(prefix + "1" + (wide ? "WideHistory" : "CompactHistory"))
    key(Qt.Key_Escape)
    route(1, "libraryHome")
    check(named("libraryPage") === libraryIdentity && p.opened, "Escape returns to same Library root instance")
    libraryLikes()
    check(p.libraryDisplay.length === 50 && p.browseDisplay.libraryTotal === 78, "Likes loads 50 of 78 without playback")
    shot(prefix + "2" + (wide ? "WideLikes" : "CompactLikes"))
    stale("library", function() {
      check(p.activeRoute.args.command === "likes" && p.libraryDisplay.length === 50
            && p.libraryDisplay[0].title !== "STALE COLLECTION MUST NOT APPEAR", "stale library identity cannot replace Likes")
    })
    var collection = named("collectionPage")
    clickText("Creedence Clearwater Revival", collection)
    route(1, "artist")
    check(p.catalogDisplay.entity.id === "ccr", "Likes artist stays in Library stack")
    if (wide) shot("X3WideLibraryLikesArtist")
    stale("entity", function() {
      check(p.catalogDisplay.entity.id === "ccr" && p.activeRoute.args.id === "ccr", "stale artist identity cannot replace active entity")
    })
    if (!wide) {
      click(named("navBack"), "Compact artist Back")
      route(1, "collection")
    }
    click(named("navDepth0"), "Library root breadcrumb")
    route(1, "libraryHome")
    check(p.atRoot, "root breadcrumb removes whole deep path")

    tab(2)
    route(2, "search")
    var catalog = named("catalogPage")
    var field = nodes(catalog, function(item) { return item.placeholderText === "Трек, исполнитель, альбом или плейлист" })[0]
    click(field, "search input")
    for (var character = 0; character < "creedence".length; character++)
      input.keyClick("creedence"[character])
    input.keyClick(Qt.Key_Backspace)
    input.wait(80)
    check(field.text === "creedenc" && p.page === 2 && p.atRoot, "Backspace edits nonempty root search")
    input.keyClick("e")
    input.keyClick(Qt.Key_Return)
    until(function() { return p.catalogDisplay.search.query === "creedence" && !p.busy }, "search command response")
    clickText("Треки", catalog)
    until(function() { return p.catalogDisplay.search.filter === "track" && !p.busy }, "typed search filter response")
    reveal("Загрузить ещё", catalog)
    clickText("Загрузить ещё", catalog)
    until(function() { return p.catalogDisplay.search.page === 1 && !p.busy }, "search loads next page")
    wheel(catalog.viewport, 6000)
    wheel(catalog.viewport, -360)
    check(catalog.viewportY > 0, "real wheel scrolls search results")
    var savedY = catalog.viewportY
    var savedSearch = JSON.stringify(p.catalogDisplay.search)
    var savedField = field.text
    clickText("Creedence Clearwater Revival", catalog)
    route(2, "artist")
    shot(wide ? "X4WideSearchArtist" : "Y3CompactSearchArtist")
    click(named("navBack"), "search artist Back")
    route(2, "search")
    check(field.text === savedField && JSON.stringify(p.catalogDisplay.search) === savedSearch,
          "Back preserves input/filter/query/page/models")
    check(Math.abs(catalog.viewportY - savedY) < 3, "Back preserves search scroll")
    tab(1)
    route(1, "libraryHome")
    tab(2)
    route(2, "search")
    check(Math.abs(catalog.viewportY - savedY) < 3, "independent Search scroll survives tab switch")
    // Repeated digit and repeated tab both return the active stack to its root.
    clickText("Creedence Clearwater Revival", catalog)
    route(2, "artist")
    key(Qt.Key_3)
    route(2, "search")
    check(p.atRoot, "repeat 3 returns Search to root")
    clickText("Creedence Clearwater Revival", catalog)
    route(2, "artist")
    tab(2)
    route(2, "search")
    check(p.atRoot, "active tab click returns Search to root")
    clickText("Creedence Clearwater Revival", catalog)
    route(2, "artist")
    key(Qt.Key_Left, Qt.AltModifier)
    route(2, "search")
    clickText("Creedence Clearwater Revival", catalog)
    route(2, "artist")
    key(Qt.Key_Backspace)
    route(2, "search")

    tab(0)
    route(0, "now")
    var queue = named("queueList")
    wheel(queue, -360)
    var queueY = queue.contentY
    check(queueY > 0, "real wheel scrolls Now queue")
    clickText("Creedence Clearwater Revival", named(wide ? "nowPane" : "compactPlayer"))
    route(0, "artist")
    check(p.page === 0 && !p.nowRoot && !named(wide ? "nowPane" : "compactPlayer").visible,
          "Now artist replaces player rather than changing tab")
    check(named(wide ? "wideMiniBar" : "compactMini").visible, "deep Now retains MiniBar")
    key(Qt.Key_1)
    route(0, "now")
    check(Math.abs(queue.contentY - queueY) < 3, "repeat 1 restores Now queue viewport")
    shot(wide ? "X5WideNowSource" : "Y4CompactNowSource")
    clickText("Из: Мне нравится ↗")
    route(1, "collection")
    check(p.activeRoute.args.command === "likes", "queue source switches to Library Likes")
    key(Qt.Key_2)
    route(1, "libraryHome")
    check(p.atRoot, "repeat 2 returns Library to root")

    libraryLikes()
    collection = named("collectionPage")
    var list = nodes(collection, function(item) { return item.contentY !== undefined && item.count === 50 })[0]
    check(!!list, "actual collection ListView")
    wheel(list, -240)
    var collectionY = list.contentY
    check(collectionY > 0, "real wheel scrolls Likes")
    tab(0)
    route(0, "now")
    check(Math.abs(queue.contentY - queueY) < 3, "Library scrolling leaves Now scroll independent")
    tab(1)
    route(1, "collection")
    check(Math.abs(list.contentY - collectionY) < 3, "tab switch restores Likes viewport")
    // Action hit area is disjoint from the row playback area and artist link.
    var row = nodes(list, function(item) {
      return item.modelData && item.modelData.trackId && item.height > 30 && onScreen(item)
    })[0]
    check(!!row, "visible collection track row")
    input.mouseMove(row, row.width - 20, row.height / 2)
    input.wait(80)
    var action = nodes(row, function(item) { return item.tooltipText === "В плейлист…" })[0]
    click(action, "collection playlist action")
    until(function() { return !!text("В ПЛЕЙЛИСТ") && !p.busy }, "playlist membership details arrive")
    playbackCount(0)
    key(Qt.Key_Escape)
    until(function() { return !text("В ПЛЕЙЛИСТ") }, "Escape closes playlist sheet")
    playbackCount(0)
    // Explicit title click is the first playback boundary in the entire run.
    input.mouseClick(row, Math.min(140, row.width / 2), 12)
    input.wait(80)
    playbackCount(1)
    check(p.data.playing === true, "explicit row starts playback")
    tab(1)
    if (!p.atRoot) tab(1)
    if (wide) clickText("Моя волна")
    else clickText("Моя волна", library)
    route(1, "librarySection")
    check(p.activeRoute.args.section === "wave", "My Wave opens without playback")
    playbackCount(1)
    shot(wide ? "WaveWide" : "WaveCompactHero")
    reveal("Спокойное", library)
    clickText("Спокойное", library)
    until(function() { return p.data.preferences.waveMood === "calm" && !library.settingsRunning }, "mood persists")
    reveal("Любимое", library)
    clickText("Любимое", library)
    until(function() { return p.data.preferences.waveDiversity === "favorite" && !library.settingsRunning }, "selection persists")
    reveal("Без слов", library)
    clickText("Без слов", library)
    until(function() { return p.data.preferences.waveLanguage === "without-words" && !library.settingsRunning }, "instrumental language persists")
    playbackCount(1)
    shot(wide ? "WaveWideSelected" : "WaveCompactSettings")
    library.resetViewport()
    input.wait(80)
    click(named("waveStart"), "explicit My Wave start")
    playbackCount(2)
    key(Qt.Key_Return)
    playbackCount(3)
    key(Qt.Key_Escape)
    route(1, "libraryHome")
    // Closing is terminal for the offscreen input window; exercise all pointer scenarios first.
    key(Qt.Key_3)
    route(2, "search")
    field.forceActiveFocus()
    input.keyClick(Qt.Key_Escape)
    until(function() { return !p.opened }, "focused Search root Escape closes popup")
  }

  QtObject {
    id: fakeBar
    property color foreground: "#DCDCE6"
    property color barForeground: "#DCDCE6"
    property string fontFamily: "JetBrainsMono Nerd Font"
    property string position: "top"
    property int barSize: 30
    property var activePopout: null
    property var clickTargets: []
    function requestPopout(k) {}
    function releasePopout(k) {}
    function switchPanelFrom(a, b) { return false }
  }
  Process {
    id: probe
    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }
  Window {
    visible: true; width: 1100; height: 700; color: "#0b0b10"
    Item { id: host; anchors.fill: parent }
    TestCase { id: input; parent: shell.card || host; name: "FullPanelNavigationInput"; when: false }
    Loader {
      id: musicLoader
      source: Qt.resolvedUrl("MusicSession.qml")
      onLoaded: item.panelOpened = true
    }
    Loader {
      id: panelLoader
      source: Qt.resolvedUrl("Panel.qml")
      onLoaded: {
        item.bar = fakeBar
        item.settings = ({})
        item.anchorItem = host
        item.hostWidget = host
        item.session = Qt.binding(function() { return musicLoader.item })
        item.open()
      }
    }
    Timer {
      interval: 300; running: true
      onTriggered: {
        try {
          shell.scenarios()
          console.log("NAVIGATION_SMOKE_OK", shell.mode, "assertions=" + shell.assertions,
                      "screenshots=" + shell.screenshots)
        } catch (error) {
          console.error("NAVIGATION_SMOKE_FAILED", shell.mode, String(error), error.stack)
        }
        Qt.quit()
      }
    }
  }
}
