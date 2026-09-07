import QtQuick
import Quickshell
import "." as Desktops

ShellRoot {
  id: test
  property bool failed: false
  QtObject { id: windowHandle }
  QtObject {
    id: card
    property bool capturing: false
    property int refreshInterval: 200
    property real width: 320
    property real height: 200
  }
  QtObject {
    id: sidebar
    property bool capturing: false
    property int refreshInterval: 1000
    property real width: 90
    property real height: 50
  }
  Desktops.CaptureScheduler { id: scheduler }
  Desktops.CaptureCache { id: cache; scheduler: scheduler }

  function check(condition, message) {
    if (!condition) { failed = true; console.error("not ok -", message) }
    else console.log("ok -", message)
  }
  Timer {
    interval: 0
    running: true
    onTriggered: {
      var top = {address:"test-window",wayland:windowHandle,lastIpcObject:{size:[800,600]}}
      var first = cache.acquire(top, card)
      var second = cache.acquire(top, sidebar)
      check(first === second && scheduler.viewCount === 1, "card and sidebar share one capture")
      check(first.width === 320 && first.height === 200, "shared texture covers its largest consumer")
      card.capturing = true
      sidebar.capturing = true
      check(first.captureEnabled && first.refreshInterval === 200, "shared capture uses the fastest visible consumer")
      card.capturing = false
      check(first.refreshInterval === 1000, "a hidden card leaves only sidebar refresh work")
      sidebar.capturing = false
      check(!first.captureEnabled, "hidden consumers stop requesting captures")
      sidebar.capturing = true
      scheduler.ready = true
      check(first.frozenFallback && !first.captureEnabled, "a missed opening deadline freezes the fallback")
      scheduler.begin()
      check(!first.frozenFallback && first.captureEnabled, "a new opening retries the frozen source")
      cache.release(first, card)
      check(first.consumers.length === 1 && scheduler.viewCount === 1, "closing one consumer keeps the other capture alive")
      cache.release(first, sidebar)
      check(cache.acquire(top, card) === first, "moving between consumers retains the shared capture")
      first.toplevel = null
      cache.release(first, card)
      finish.start()
    }
  }
  Timer {
    id: finish
    interval: 10
    onTriggered: {
      test.check(scheduler.viewCount === 0, "the last consumer releases the capture scheduler entry")
      test.check(Object.keys(cache.sources).length === 0, "a destroyed toplevel can still release its cache entry")
      Qt.exit(test.failed ? 1 : 0)
    }
  }
}
