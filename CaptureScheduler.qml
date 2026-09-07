import QtQuick
import "CaptureScheduler.js" as Scheduler

Item {
  id: root
  property bool active: false
  readonly property var queue: Scheduler.createQueue()
  property int viewCount: 0
  property int requests: 0
  property bool preparing: false
  property bool ready: false
  property double startedAt: 0
  property int preparationMs: 0
  property int missingAtReveal: 0
  onActiveChanged: {
    if (!active && preparing) { preparing = false; ready = false }
    else prime()
  }

  function begin() {
    startedAt = Date.now()
    // A toggle during the close animation can reverse the fade immediately.
    if (queue.cached()) { preparationMs = 0; missingAtReveal = 0; preparing = false; ready = true; return }
    preparing = true
    ready = false
  }
  function reveal() {
    missingAtReveal = queue.pending()
    preparationMs = Date.now() - startedAt
    preparing = false
    ready = true
  }

  function prime() {
    if (active && preparing) requests += queue.prepare(Date.now(), 32)
  }
  function registerView(view) { queue.add(view); viewCount = queue.entries.length; prime() }
  function unregisterView(view) { queue.remove(view); viewCount = queue.entries.length }

  Timer {
    // At most one full-window export per tick, about 30/s in total.
    interval: 33
    repeat: true
    running: root.active && !root.preparing && root.viewCount > 0
    onTriggered: if (root.queue.tick(Date.now())) root.requests++
  }
  Timer {
    // First frames should fit inside the opening animation. Limit both the
    // work issued per turn and outstanding exports; steady updates stay cheap.
    interval: 8
    repeat: true
    running: root.active && root.preparing
    onTriggered: {
      var now = Date.now()
      root.requests += root.queue.prepare(now, 32)
      // Use elapsed wall time: animation timers can advance unevenly while
      // several output surfaces map. A slow source cannot block interaction.
      if (root.queue.pending() === 0 || now - root.startedAt >= 500) root.reveal()
    }
  }
}
