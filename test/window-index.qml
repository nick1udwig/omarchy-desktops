import QtQuick
import Quickshell
import "." as Desktops

ShellRoot {
  id: test
  property bool failed: false
  property int updates: 0
  function check(condition, message) {
    if (!condition) { failed = true; console.error("not ok -", message) }
    else console.log("ok -", message)
  }
  Component {
    id: top
    QtObject {
      property var wayland: ({appId:"test"})
      property var monitor: ({name:"left"})
      property var workspace: ({id:1})
      property var lastIpcObject: ({mapped:true,pinned:false})
    }
  }
  Desktops.WindowIndex {
    id: index
    snapshot: ({desktops:[{outputs:{left:{slots:[1],selected:1}}},{outputs:{left:{slots:[2],selected:1}}}]})
    onValueChanged: test.updates++
  }
  Timer {
    interval: 0
    running: true
    onTriggered: {
      var windows = []
      for (var i = 0; i < 500; i++) windows.push(top.createObject(test))
      index.toplevels = windows
      index.rebuild()
      test.check(index.value[1].left.length === 500, "opening flushes pending window membership before preview preparation")
      var updates = test.updates
      for (var w = 0; w < windows.length; w++)
        windows[w].lastIpcObject = {mapped:true,pinned:false,title:"new title",size:[400+w,300]}
      test.check(!index.dirty && test.updates === updates, "500 title/size metadata updates cause no window-list rebuilds")
      for (var moved = 0; moved < 250; moved++) windows[moved].workspace = {id:2}
      windows[250].lastIpcObject = {mapped:true,pinned:true}
      windows[251].lastIpcObject = {mapped:false,pinned:false}
      test.check(index.dirty && test.updates === updates, "membership changes batch until the next turn")
      Qt.callLater(function() {
        test.check(test.updates === updates + 1, "252 membership changes share one index rebuild")
        test.check(index.value[1].left.length === 249 && index.value[2].left.length === 251,
          "batched moves, pins, and unmapping produce correct lists")
        Qt.exit(test.failed ? 1 : 0)
      })
    }
  }
}
