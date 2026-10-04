.pragma library

function revision(snapshot, name) {
  return Number((snapshot || {})[name] || 0)
}

function isStaleResponse(requestActionRevision, currentActionRevision) {
  return requestActionRevision !== currentActionRevision
}

function reconcile(incoming, state, viewport, requestActionRevision, currentActionRevision) {
  if (isStaleResponse(requestActionRevision, currentActionRevision)) return { ignored: true }

  var old = state.data || {}
  var queue = state.queueDisplay || []
  var hub = state.libraryHubDisplay || {}
  var catalog = state.catalogDisplay || {}
  var collection = state.collectionDisplay || {}
  var view = viewport || {}
  var next = {}
  for (var key in incoming) next[key] = incoming[key]

  var queueChanged = revision(next, "queueRevision") !== revision(old, "queueRevision")
  if (queueChanged) queue = next.queueTracks || []
  next.queueTracks = queue

  var libraryExpanded = (next.libraryTracks || []).length > (old.libraryTracks || []).length
  if (revision(next, "libraryRevision") === revision(old, "libraryRevision"))
    next.libraryTracks = old.libraryTracks || []

  var intents = {
    queueCurrent: Number(next.queueIndex || 0) !== Number(state.previousQueueIndex || 0)
      && state.page === 0,
    queueViewport: "none", queueTargetY: Number(view.queueY || 0),
    libraryViewport: "none", libraryTargetY: Number(view.libraryY || 0),
    catalogViewport: "none", catalogTargetY: Number(view.catalogY || 0)
  }
  var browseChanged = String(next.libraryBrowseName || "")
    !== String(old.libraryBrowseName || "")
  if (browseChanged && String(next.libraryBrowseName || "") !== "")
    intents.queueViewport = "reset"
  else if (libraryExpanded) intents.queueViewport = "preserve"

  var hubChanged = !!next.libraryHub
    && revision(next, "libraryHubRevision") !== revision(old, "libraryHubRevision")
  if (hubChanged) {
    var oldHubView = String(hub.view || "home")
    var oldHubSection = String(hub.section || "")
    var newHubView = String(next.libraryHub.view || "home")
    var newHubSection = String(next.libraryHub.section || "")
    var hubExpanded = (next.libraryHub.items || []).length > (hub.items || []).length
    hub = next.libraryHub
    if (oldHubView !== newHubView || oldHubSection !== newHubSection)
      intents.libraryViewport = "reset"
    else if (hubExpanded) intents.libraryViewport = "preserve"
  }
  next.libraryHub = hub

  var collectionChanged = !!next.collection
    && revision(next, "collectionRevision") !== revision(old, "collectionRevision")
  if (collectionChanged) collection = next.collection
  next.collection = collection

  var catalogChanged = !!next.catalog
    && revision(next, "catalogRevision") !== revision(old, "catalogRevision")
  var searchY = Number(state.catalogSearchContentY || 0)
  if (catalogChanged) {
    var oldCatalogView = String(catalog.view || "search")
    var newCatalogView = String(next.catalog.view || "search")
    var oldSearch = catalog.search || {}
    var newSearch = next.catalog.search || {}
    var searchChanged = String(oldSearch.query || "") !== String(newSearch.query || "")
      || String(oldSearch.filter || "all") !== String(newSearch.filter || "all")
    var oldEntity = catalog.entity || {}
    var newEntity = next.catalog.entity || {}
    var entityChanged = String(oldEntity.type || "") !== String(newEntity.type || "")
      || String(oldEntity.id || "") !== String(newEntity.id || "")
    if (oldCatalogView === "search") searchY = Number(view.catalogY || 0)
    if (oldCatalogView !== newCatalogView && newCatalogView === "search") {
      intents.catalogViewport = "restoreSearch"
      intents.catalogTargetY = searchY
    } else if (oldCatalogView !== newCatalogView || searchChanged || entityChanged) {
      intents.catalogViewport = "reset"
    } else {
      intents.catalogViewport = "preserve"
    }
    catalog = next.catalog
  }
  next.catalog = catalog

  return {
    ignored: false, data: next,
    queueDisplay: queue, libraryHubDisplay: hub,
    collectionDisplay: collection, catalogDisplay: catalog,
    previousQueueIndex: Number(next.queueIndex || 0),
    catalogSearchContentY: searchY,
    changed: { queue: queueChanged, libraryHub: hubChanged,
      collection: collectionChanged, catalog: catalogChanged },
    initializeCatalog: catalogChanged && !state.catalogInitialized,
    intents: intents
  }
}
