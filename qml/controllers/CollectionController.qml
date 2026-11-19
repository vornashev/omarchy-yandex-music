import QtQuick

Item {
  id: root
  width: 0
  height: 0

  property var snapshot: ({ busy: false, operation: "", error: "", message: "",
    playlistKind: "", playlistTitle: "", recommendations: [],
    membershipLoading: false, membershipError: "", memberships: {},
    membershipTrackId: "", membershipAlbumId: "", revision: 0 })
  property var ownPlaylists: []
  property var target: ({ source: "", index: -1, trackId: "", albumId: "", title: "",
    artist: "", artUrl: "", canDelete: false, playlistKind: "", playlistTitle: "" })
  property string mode: "closed"
  property string draftTitle: ""
  property string playlistKind: ""
  property string playlistTitle: ""
  property bool requestPending: false
  property bool membershipPending: false
  property string localMembershipError: ""
  property string lastOperation: ""
  property string lastSuccessfulKind: ""
  property var lastMutation: ({})
  readonly property bool busy: requestPending || snapshot.busy === true
  readonly property bool checkingMemberships: membershipPending
    || snapshot.membershipLoading === true
  readonly property string membershipError: localMembershipError !== ""
    ? localMembershipError : String(snapshot.membershipError || "")
  readonly property var memberships: snapshot.memberships || ({})
  readonly property string error: String(snapshot.error || "")
  readonly property string message: String(snapshot.message || "")
  readonly property var recommendations: snapshot.recommendations || []
  readonly property bool opened: mode !== "closed"
  readonly property bool canRetryLastMutation: opened && !busy && !checkingMemberships
    && membershipError === "" && error !== ""
    && lastOperation === "add" && String(lastMutation.trackId || "") !== ""

  signal membershipsRequested(string source, int index, string trackId, string albumId)
  signal addRequested(string kind, string source, int index, string trackId, string albumId)
  signal createRequested(string title, string source, int index, string trackId, string albumId)
  signal deleteRequested(string kind, string source, int index, string trackId, string albumId)
  signal recommendationsRequested(string kind, string title)
  signal clearRequested()

  function trackSnapshot(source, index, row, canDelete, ownerKind, ownerTitle) {
    var value = row || {}
    return { source: String(source || ""), index: Number(index),
      trackId: String(value.trackId || ""), albumId: String(value.albumId || ""),
      title: String(value.title || "Трек"), artist: String(value.artist || ""),
      artUrl: String(value.artUrl || ""), canDelete: canDelete === true,
      playlistKind: String(ownerKind || ""), playlistTitle: String(ownerTitle || "") }
  }

  function openTrack(source, index, row, canDelete, ownerKind, ownerTitle) {
    reset()
    target = trackSnapshot(source, index, row, canDelete, ownerKind, ownerTitle)
    draftTitle = ""
    localMembershipError = ""
    membershipPending = true
    mode = "track"
    membershipsRequested(target.source, target.index, target.trackId, target.albumId)
  }

  function playlistContains(kind) {
    return memberships[String(kind || "")] === true
  }

  function retryMemberships() {
    if (busy || checkingMemberships || !opened || target.trackId === "") return false
    localMembershipError = ""
    membershipPending = true
    membershipsRequested(target.source, target.index, target.trackId, target.albumId)
    return true
  }

  function membershipRequestFailed() {
    membershipPending = false
    localMembershipError = "Не удалось начать проверку плейлистов. Повторите попытку."
  }

  function beginCreate() {
    if (busy || checkingMemberships || membershipError !== ""
        || mode !== "track" || target.trackId === "") return false
    draftTitle = ""
    mode = "create"
    return true
  }

  function submitCreate() {
    var title = String(draftTitle || "").trim()
    if (busy || checkingMemberships || membershipError !== ""
        || mode !== "create" || target.trackId === "" || title === "") return false
    startMutation("create", { title: title, source: target.source, index: target.index,
      trackId: target.trackId, albumId: target.albumId })
    createRequested(title, target.source, target.index, target.trackId, target.albumId)
    return true
  }

  function requestAdd(kind) {
    var value = String(kind || "")
    if (busy || checkingMemberships || membershipError !== ""
        || mode !== "track" || value === "" || target.trackId === ""
        || playlistContains(value)) return false
    startMutation("add", { kind: value, source: target.source, index: target.index,
      trackId: target.trackId, albumId: target.albumId })
    addRequested(value, target.source, target.index, target.trackId, target.albumId)
    return true
  }

  function beginDelete() {
    if (busy || checkingMemberships || mode !== "track"
        || target.canDelete !== true || target.playlistKind === "") return false
    mode = "delete"
    return true
  }

  function confirmDelete() {
    if (busy || checkingMemberships || mode !== "delete"
        || target.canDelete !== true || target.playlistKind === "") return false
    startMutation("delete", { kind: target.playlistKind, source: target.source,
      index: target.index, trackId: target.trackId, albumId: target.albumId })
    deleteRequested(target.playlistKind, target.source, target.index,
                    target.trackId, target.albumId)
    return true
  }

  function openRecommendations(kind, title) {
    var value = String(kind || "")
    if (busy || checkingMemberships || value === "") return false
    reset()
    playlistKind = value
    playlistTitle = String(title || "")
    mode = "recommendations"
    requestPending = true
    lastOperation = "recommendations"
    recommendationsRequested(playlistKind, playlistTitle)
    return true
  }

  function addRecommendation(row) {
    var value = row || {}
    if (busy || checkingMemberships || mode !== "recommendations"
        || playlistKind === "" || String(value.trackId || "") === "") return false
    startMutation("add", { kind: playlistKind, source: "recommendation",
      index: Number(value.index || 0), trackId: String(value.trackId || ""),
      albumId: String(value.albumId || "") })
    addRequested(lastMutation.kind, lastMutation.source, lastMutation.index,
                 lastMutation.trackId, lastMutation.albumId)
    return true
  }

  function startMutation(operation, mutation) {
    lastOperation = operation
    lastMutation = mutation
    requestPending = true
    snapshot = Object.assign({}, snapshot, { error: "", message: "" })
  }

  function retryLastMutation() {
    if (!canRetryLastMutation) return false
    var mutation = lastMutation
    if (mutation.source !== "recommendation" && playlistContains(mutation.kind)) return false
    startMutation("add", mutation)
    addRequested(mutation.kind, mutation.source, mutation.index,
                 mutation.trackId, mutation.albumId)
    return true
  }

  function applySnapshot(value) {
    requestPending = false
    snapshot = value || ({ busy: false, operation: "", error: "", message: "",
      playlistKind: "", playlistTitle: "", recommendations: [],
      membershipLoading: false, membershipError: "", memberships: {},
      membershipTrackId: "", membershipAlbumId: "", revision: 0 })
    if (String(snapshot.membershipTrackId || "") === target.trackId
        && String(snapshot.membershipAlbumId || "") === target.albumId) {
      membershipPending = false
      localMembershipError = ""
    }
    if (String(snapshot.playlistKind || "") !== "") playlistKind = String(snapshot.playlistKind)
    if (String(snapshot.playlistTitle || "") !== "") playlistTitle = String(snapshot.playlistTitle)
    if (!opened || busy) return
    if (message !== "" || error !== "") {
      if (lastOperation === "delete") {
        // Any delete response ends this confirmation: refreshed rows may have shifted.
        target = trackSnapshot("", -1, null, false, "", "")
        mode = "result"
      } else if (mode !== "recommendations") {
        mode = "track"
      }
      if (error === "" && message !== ""
          && (lastOperation === "add" || lastOperation === "create"))
        lastSuccessfulKind = String(snapshot.playlistKind || lastMutation.kind || "")
    }
  }

  function reset() {
    mode = "closed"
    draftTitle = ""
    target = ({ source: "", index: -1, trackId: "", albumId: "", title: "",
      artist: "", artUrl: "", canDelete: false, playlistKind: "", playlistTitle: "" })
    playlistKind = ""
    playlistTitle = ""
    requestPending = false
    membershipPending = false
    localMembershipError = ""
    lastOperation = ""
    lastSuccessfulKind = ""
    lastMutation = ({})
    snapshot = ({ busy: false, operation: "", error: "", message: "",
      playlistKind: "", playlistTitle: "", recommendations: [],
      membershipLoading: false, membershipError: "", memberships: {},
      membershipTrackId: "", membershipAlbumId: "", revision: 0 })
  }

  function close() {
    reset()
    clearRequested()
  }
}
