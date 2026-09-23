import QtQuick
import Quickshell
import "." as Desktops

ShellRoot {
  id: test
  property int preparationPasses: 0
  Desktops.CaptureScheduler { id: scheduler }
  Timer {
    interval: 0
    running: true
    onTriggered: {
      var prepare = scheduler.queue.prepare
      scheduler.queue.prepare = function(now, maximum) {
        test.preparationPasses++
        return prepare.call(scheduler.queue, now, maximum)
      }
      scheduler.begin()
      scheduler.active = true
      for (var i = 0; i < 500; i++) scheduler.registerView({
        captureEnabled: true, captureStarted: false, hasContent: false, refreshInterval: 1000,
        refresh: function() { this.captureStarted = true; return true }
      })
      if (test.preparationPasses !== 0) { console.error("not ok - registration scans the growing queue"); Qt.exit(1); return }
      Qt.callLater(function() {
        scheduler.active = false
        if (test.preparationPasses !== 1 || scheduler.requests !== 32 || scheduler.ready) {
          console.error("not ok - batched startup", test.preparationPasses, scheduler.requests)
          Qt.exit(1)
        } else {
          console.log("ok - 500 registrations share one bounded startup pass without premature reveal")
          Qt.exit(0)
        }
      })
    }
  }
}
