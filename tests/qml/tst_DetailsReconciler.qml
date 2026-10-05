import QtQuick
import QtTest
import "../../DetailsReconciler.js" as Details

TestCase {
  name: "DetailsReconciler"
  when: windowShown

  function oldState() {
    var queue = [{ trackId: "one" }]
    var library = [{ trackId: "liked" }]
    var hub = { view: "section", section: "history", items: [{ id: "one" }] }
    var catalog = { view: "search", search: { query: "old", filter: "all" },
      entity: {}, suggestions: { items: [] } }
    var collection = { error: "", revision: 1 }
    return {
      data: { queueRevision: 1, libraryRevision: 1, libraryHubRevision: 1,
        catalogRevision: 1, collectionRevision: 1, queueIndex: 1,
        libraryBrowseName: "", libraryTracks: library },
      queueDisplay: queue, libraryHubDisplay: hub, catalogDisplay: catalog,
      collectionDisplay: collection, catalogInitialized: true,
      previousQueueIndex: 1, nowRoot: true
    }
  }

  function incomingFrom(state) {
    return {
      queueRevision: state.data.queueRevision,
      libraryRevision: state.data.libraryRevision,
      libraryHubRevision: state.data.libraryHubRevision,
      catalogRevision: state.data.catalogRevision,
      collectionRevision: state.data.collectionRevision,
      queueIndex: state.data.queueIndex, libraryBrowseName: "",
      queueTracks: [{ trackId: "new copy" }],
      libraryTracks: [{ trackId: "new copy" }],
      libraryHub: { view: "section", section: "history", items: [{ id: "copy" }] },
      catalog: { view: "search", search: { query: "old", filter: "all" },
        entity: {}, suggestions: { items: ["copy"] } },
      collection: { error: "new copy", revision: 1 }, error: ""
    }
  }

  function reconcile(incoming, state, viewport, requested, current) {
    return Details.reconcile(incoming, state, viewport || {
      queueY: 20, libraryY: 40, catalogY: 60
    }, requested === undefined ? 0 : requested, current === undefined ? 0 : current)
  }

  function test_equal_revisions_reuse_heavy_models() {
    var state = oldState()
    var result = reconcile(incomingFrom(state), state)
    verify(!result.ignored)
    verify(result.queueDisplay === state.queueDisplay)
    verify(result.data.queueTracks === state.queueDisplay)
    verify(result.data.libraryTracks === state.data.libraryTracks)
    verify(result.libraryHubDisplay === state.libraryHubDisplay)
    verify(result.data.libraryHub === state.libraryHubDisplay)
    verify(result.catalogDisplay === state.catalogDisplay)
    verify(result.data.catalog === state.catalogDisplay)
    verify(result.collectionDisplay === state.collectionDisplay)
    verify(result.data.collection === state.collectionDisplay)
    compare(result.intents.queueViewport, "none")
    compare(result.intents.libraryViewport, "none")
    compare(result.intents.catalogViewport, "none")
  }

  function test_queue_extension_keeps_scroll_but_browse_does_not_move_queue() {
    var state = oldState()
    var incoming = incomingFrom(state)
    incoming.queueRevision = 2
    incoming.queueIndex = 2
    incoming.queueTracks = [{ trackId: "one" }, { trackId: "two" }]
    incoming.libraryRevision = 2
    incoming.libraryTracks = [{ trackId: "one" }, { trackId: "two" }]
    var result = reconcile(incoming, state)
    verify(result.queueDisplay === incoming.queueTracks)
    compare(result.previousQueueIndex, 2)
    compare(result.intents.queueCurrent, true)
    compare(result.intents.queueViewport, "preserve")
  }

  function test_library_hub_navigation_and_extension_choose_scroll_intent() {
    var state = oldState()
    var next = incomingFrom(state)
    next.libraryHubRevision = 2
    next.libraryHub = { view: "section", section: "albums", items: [] }
    var changed = reconcile(next, state)
    compare(changed.intents.libraryViewport, "reset")
    verify(changed.libraryHubDisplay === next.libraryHub)

    next.libraryHub = { view: "section", section: "history",
      items: [{ id: "one" }, { id: "two" }] }
    var extended = reconcile(next, state)
    compare(extended.intents.libraryViewport, "preserve")

    next.libraryHub = { view: "section", section: "history",
      items: [{ id: "one" }], error: "Локальная ошибка" }
    var error = reconcile(next, state)
    compare(error.intents.libraryViewport, "none")
    compare(error.libraryHubDisplay.error, "Локальная ошибка")
  }

  function test_new_search_resets_viewport_but_entity_return_does_not_own_scroll() {
    var state = oldState()
    var next = incomingFrom(state)
    next.catalogRevision = 2
    next.catalog.search.query = "new"
    compare(reconcile(next, state).intents.catalogViewport, "reset")
    next.catalog.search.query = "old"
    state.catalogDisplay.view = "artist"
    compare(reconcile(next, state).intents.catalogViewport, "preserve")
  }

  function test_stale_response_is_ignored_but_backend_revision_reset_is_allowed() {
    var state = oldState()
    var next = incomingFrom(state)
    next.catalogRevision = 0
    next.catalog = { view: "search", search: {}, entity: {}, suggestions: {} }
    var stale = reconcile(next, state, null, 4, 5)
    compare(stale.ignored, true)
    verify(state.catalogDisplay.view === "search")
    var restarted = reconcile(next, state, null, 5, 5)
    compare(restarted.ignored, false)
    verify(restarted.catalogDisplay === next.catalog)
  }

  function test_stale_transport_failure_can_be_discarded_and_retried() {
    compare(Details.isStaleResponse(4, 5), true)
    compare(Details.isStaleResponse(5, 5), false)
  }

  function test_collection_error_stays_local_and_requires_new_revision() {
    var state = oldState()
    var next = incomingFrom(state)
    next.collectionRevision = 2
    next.collection = { revision: 2, error: "Ошибка коллекции", busy: false }
    var result = reconcile(next, state)
    verify(result.collectionDisplay === next.collection)
    compare(result.data.error, "")
    compare(result.intents.catalogViewport, "none")
    compare(result.intents.queueCurrent, false)
  }
}
