import QtQuick
import qs.Commons
import qs.Commons as Commons

// Favorite/pin state of the open catalog entity. The item itself draws
// nothing: headers place `EntityToggles` bound to it, so the wide card and the
// recycled compact list delegate share one request/poll lifecycle.
Item {
  id:root
  property var panel: null
  property var entity: ({})
  property bool active: true
  property string requestedKey: ""
  property bool pending: false
  property int sentRevision: -1
  property bool uncertain: false
  readonly property var spec: ({view:"entity", actionsOnly:true, type:String(entity.type || ""),
    id:String(entity.id || ""), owner:String(entity.owner || ""), kind:String(entity.kind || ""),
    uuid:String(entity.uuid || ""), title:String(entity.title || entity.name || "Действия")})
  readonly property string key: JSON.stringify(spec)
  readonly property var snapshot: panel ? panel.entityFeatureDisplay : ({})
  readonly property var status: matches() ? snapshot.entity || ({}) : ({})
  readonly property bool busy: pending || uncertain || !matches() || snapshot.loading === true || snapshot.busy === true
  readonly property string message: uncertain ? "Результат неизвестен. Обновите состояние."
    : (matches() && !!snapshot.error ? String(snapshot.error) : "")
  visible:false

  function matches() {
    if (!snapshot || !snapshot.identity) return false
    try {
      var value=JSON.parse(String(snapshot.identity))
      return value.actionsOnly === true && value.type === spec.type && value.id === spec.id
        && value.kind === spec.kind && value.owner === spec.owner && value.uuid === spec.uuid
    } catch (_) {return false}
  }
  function reload() {
    if (!panel || pending || snapshot.busy === true || snapshot.loading === true) return
    sentRevision=Number(snapshot.revision || 0);pending=true;uncertain=false
    if (!panel.intent("entityFeatureOpen",JSON.stringify({request:spec,force:true}))) pending=false
    else deadline.restart()
  }
  function send(op,value,confirmed) {
    if(busy || !panel) return
    sentRevision=Number(snapshot.revision || 0);pending=true
    if(!panel.intent("entityFeatureAction",JSON.stringify({op:op,value:value,confirmed:confirmed === true,identity:snapshot.identity}))) pending=false
    else deadline.restart()
  }
  onSnapshotChanged: {
    if(matches() && Number(snapshot.revision || 0) > sentRevision && snapshot.busy !== true) {pending=false;uncertain=false;deadline.stop()}
  }
  onKeyChanged: {requestedKey="";pending=false;uncertain=false;deadline.stop()}
  onActiveChanged: {
    if(active) requestedKey=""
    else {pending=false;uncertain=false;deadline.stop()}
  }
  Timer {
    id:poll;interval:150;repeat:true;running:root.active && !!root.panel && root.entity.loading !== true && root.spec.type !== "" && root.requestedKey !== root.key
    onTriggered:{
      if(root.panel.session && !root.panel.session.actionRunning && root.panel.routeReady && (root.panel.catalogRoute || root.panel.collectionRoute)){
        if(root.panel.intent("entityFeatureOpen",root.key))root.requestedKey=root.key
      }
    }
  }
  Timer {id:deadline;interval:25000;onTriggered:{root.pending=false;root.uncertain=true}}
}
