import QtQuick
import Quickshell
import "." as Desktops

ShellRoot {
  id: test
  property bool failed: false
  property int requestsAtClose: 0
  function check(condition, message) {
    if (!condition) { failed = true; console.error("not ok -", message) }
    else console.log("ok -", message)
  }
  Desktops.CaptureScheduler { id: scheduler }
  QtObject {
    id: slow
    property bool captureEnabled: true
    property bool captureStarted: false
    property bool hasContent: false
    property int refreshInterval: 1000
    function refresh() { captureStarted = true; return true }
  }
  Timer {
    interval: 0
    running: true
    onTriggered: {
      scheduler.registerView(slow)
      scheduler.begin()
      scheduler.active = true
      oldDeadline.start()
      painted.start()
      finish.start()
    }
  }
  Timer {
    id: oldDeadline
    interval: 550
    onTriggered: {
      test.check(!scheduler.ready && scheduler.preparing, "a slow preview never reveals an incomplete overview at 500 ms")
      test.check(scheduler.requests === 1, "waiting for a first frame does not duplicate its export")
    }
  }
  Timer { id: painted; interval: 700; onTriggered: slow.hasContent = true }
  Timer {
    id: finish
    interval: 850
    onTriggered: {
      test.check(scheduler.ready && scheduler.missingAtReveal === 0, "reveal waits for the slow preview to be rendered")
      test.check(scheduler.preparationMs >= 650, "slow-source preparation records actual readiness instead of a deadline")
      scheduler.active = false
      test.requestsAtClose = scheduler.requests
      idle.start()
    }
  }
  Timer {
    id: idle
    interval: 100
    onTriggered: {
      test.check(scheduler.requests === test.requestsAtClose, "retaining a closed preview issues no background captures")
      scheduler.begin()
      test.check(scheduler.ready && scheduler.preparationMs === 0, "a retained complete preview is ready immediately on reopening")
      test.check(scheduler.requests === test.requestsAtClose, "reopening a retained preview needs no first-frame export")
      scheduler.ready = false
      slow.hasContent = false
      scheduler.begin()
      scheduler.active = true
      scheduler.active = false
      test.check(!scheduler.preparing && !scheduler.ready, "cancelling a pending opening stops preparation")
      Qt.exit(test.failed ? 1 : 0)
    }
  }
}
