import QtQuick
import "CaptureScheduler.js" as Scheduler

Item {
  id: root
  property bool active: false
  readonly property var queue: Scheduler.createQueue()
  property int viewCount: 0
  property int requests: 0

  function registerView(view) { queue.add(view); viewCount = queue.entries.length }
  function unregisterView(view) { queue.remove(view); viewCount = queue.entries.length }

  Timer {
    // At most one full-window export per tick, about 30/s in total.
    interval: 33
    repeat: true
    running: root.active && root.viewCount > 0
    onTriggered: if (root.queue.tick(Date.now())) root.requests++
  }
}
