import QtQuick

QtObject {
  id: root

  property var _state: ({ page: 0, stacks: [
    [routeSnapshot({ kind: "now", title: "Сейчас" })],
    [routeSnapshot({ kind: "libraryHome", title: "Медиатека" })],
    [routeSnapshot({ kind: "search", title: "Поиск" })]
  ] })
  readonly property int page: _state.page
  readonly property var stacks: _state.stacks
  readonly property var breadcrumbs: stacks[page]
  readonly property var top: breadcrumbs[breadcrumbs.length - 1]
  readonly property string selectedShortcut: shortcutFor(stacks[1])

  signal routeActivated(int page, var route)


  function copy(value) {
    return JSON.parse(JSON.stringify(value))
  }

  function routeSnapshot(route) {
    var y = Number(route.scrollY || 0)
    return { kind: String(route.kind), args: copy(route.args || {}),
      title: String(route.title || ""), scrollY: isFinite(y) ? Math.max(0, y) : 0 }
  }

  function identity(route) {
    var args = route.args || {}
    if (route.kind === "artist" || route.kind === "album")
      return JSON.stringify([route.kind, String(args.id || "")])
    if (route.kind === "playlist")
      return JSON.stringify([route.kind, args.uuid ? String(args.uuid) : "",
        args.uuid ? "" : String(args.owner || ""), args.uuid ? "" : String(args.kind || "")])
    if (route.kind === "collection")
      return JSON.stringify([route.kind, String(args.command || ""), String(args.argument || "")])
    if (route.kind === "librarySection")
      return JSON.stringify([route.kind, String(args.section || "")])
    return route.kind
  }

  function commit(nextPage, stack, activate) {
    var next = stacks.slice()
    next[nextPage] = stack
    _state = { page: nextPage, stacks: next }
    if (activate) routeActivated(page, top)
  }

  function push(route) {
    var nextRoute = routeSnapshot(route)
    if (identity(top) === identity(nextRoute)) return
    var next = breadcrumbs.slice()
    next.push(nextRoute)
    // Корень остаётся доступен даже при длинной цепочке сущностей.
    if (next.length > 8) next.splice(1, 1)
    commit(page, next, true)
  }

  function pop() {
    popTo(breadcrumbs.length - 2)
  }

  function popTo(depth) {
    if (depth < 0 || depth >= breadcrumbs.length - 1 || Math.floor(depth) !== depth) return
    commit(page, breadcrumbs.slice(0, depth + 1), true)
  }

  function popToRoot() {
    popTo(0)
  }

  function selectTab(index) {
    if (index < 0 || index >= stacks.length || Math.floor(index) !== index) return
    if (index === page) {
      popToRoot()
      return
    }
    commit(index, stacks[index], true)
  }

  function openFromRail(section, argument, title) {
    var route
    if (section === "likes" || section === "playlist") {
      route = { kind: "collection", args: { command: section, argument: String(argument || "") },
        title: title || (section === "likes" ? "Мне нравится" : "Плейлист") }
    } else {
      route = { kind: "librarySection", args: { section: String(section) },
        title: title || (section === "wave" ? "Моя волна" : section === "history" ? "Недавно слушали" : section) }
    }
    commit(1, [stacks[1][0], routeSnapshot(route)], true)
  }

  function saveScroll(y) {
    var nextRoute = routeSnapshot({ kind: top.kind, args: top.args, title: top.title, scrollY: y })
    if (nextRoute.scrollY === top.scrollY) return
    var next = breadcrumbs.slice()
    next[next.length - 1] = nextRoute
    commit(page, next, false)
  }

  function saveSearchState(state) {
    var next = stacks[2].slice()
    var search = next[0]
    next[0] = routeSnapshot({ kind: search.kind, title: search.title, scrollY: search.scrollY, args: state })
    var all = stacks.slice()
    all[2] = next
    _state = { page: page, stacks: all }
  }

  function setTitle(title) {
    var next = breadcrumbs.slice()
    next[next.length - 1] = routeSnapshot({ kind: top.kind, args: top.args,
      title: title, scrollY: top.scrollY })
    commit(page, next, false)
  }

  function setRootTitle(index, title) {
    if (index < 0 || index >= stacks.length || Math.floor(index) !== index) return
    var next = stacks[index].slice()
    var route = next[0]
    next[0] = routeSnapshot({ kind: route.kind, args: route.args, title: title, scrollY: route.scrollY })
    var all = stacks.slice()
    all[index] = next
    _state = { page: page, stacks: all }
  }
  function shortcutFor(stack) {
    for (var i = stack.length - 1; i > 0; i--) {
      var route = stack[i]
      if (route.kind === "collection") {
        if (route.args.command === "likes") return "likes"
        if (route.args.command === "playlist") return "playlist:" + String(route.args.argument || "")
      }
      if (route.kind === "librarySection"
          && (route.args.section === "wave" || route.args.section === "history")) return route.args.section
    }
    return ""
  }
}
