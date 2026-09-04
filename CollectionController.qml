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
    canDelete: false, playlistKind: "", playlistTitle: "" })
  property string mode: "closed"
  property string draftTitle: ""
  property string playlistKind: ""
  property string playlistTitle: ""
  property bool requestPending: false
  property bool membershipPending: false
  property string localMembershipError: ""
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
      title: String(value.title || "Трек"), canDelete: canDelete === true,
      playlistKind: String(ownerKind || ""), playlistTitle: String(ownerTitle || "") }
  }

  function openTrack(source, index, row, canDelete, ownerKind, ownerTitle) {
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
    if (membershipPending || target.trackId === "") return false
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
    if (busy || !opened) return
    draftTitle = ""
    mode = "create"
  }

  function submitCreate() {
    var title = String(draftTitle || "").trim()
    if (busy || title === "") return false
    requestPending = true
    createRequested(title, target.source, target.index, target.trackId, target.albumId)
    return true
  }

  function requestAdd(kind) {
    var value = String(kind || "")
    if (busy || checkingMemberships || membershipError !== ""
        || value === "" || target.trackId === "" || playlistContains(value)) return false
    requestPending = true
    addRequested(value, target.source, target.index, target.trackId, target.albumId)
    return true
  }

  function beginDelete() {
    if (busy || target.canDelete !== true || target.playlistKind === "") return false
    mode = "delete"
    return true
  }

  function confirmDelete() {
    if (busy || target.canDelete !== true || target.playlistKind === "") return false
    requestPending = true
    deleteRequested(target.playlistKind, target.source, target.index,
                    target.trackId, target.albumId)
    return true
  }

  function openRecommendations(kind, title) {
    var value = String(kind || "")
    if (busy || value === "") return false
    playlistKind = value
    playlistTitle = String(title || "")
    mode = "recommendations"
    requestPending = true
    recommendationsRequested(playlistKind, playlistTitle)
    return true
  }

  function addRecommendation(row) {
    var value = row || {}
    if (busy || playlistKind === "" || String(value.trackId || "") === "") return false
    requestPending = true
    addRequested(playlistKind, "recommendation", Number(value.index || 0),
                 String(value.trackId || ""), String(value.albumId || ""))
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
    if (message !== "" || error !== "") mode = "result"
  }

  function close() {
    mode = "closed"
    draftTitle = ""
    target = ({ source: "", index: -1, trackId: "", albumId: "", title: "",
      canDelete: false, playlistKind: "", playlistTitle: "" })
    playlistKind = ""
    playlistTitle = ""
    requestPending = false
    membershipPending = false
    localMembershipError = ""
    snapshot = ({ busy: false, operation: "", error: "", message: "",
      playlistKind: "", playlistTitle: "", recommendations: [],
      membershipLoading: false, membershipError: "", memberships: {},
      membershipTrackId: "", membershipAlbumId: "", revision: 0 })
    clearRequested()
  }
}
