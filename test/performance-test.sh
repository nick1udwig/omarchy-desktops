#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('node:fs')
const vm = require('node:vm')
const scheduler = {}
vm.runInNewContext(fs.readFileSync(path.join(root, 'CaptureScheduler.js'), 'utf8').replace(/^\.pragma.*$/mg, ''), scheduler)
function view(interval = 200) {
  return {captureEnabled:true, refreshInterval:interval, requests:0, refresh() { this.requests++; return true }}
}

const queue = scheduler.createQueue()
assertEqual(queue.tick(0), false, 'an empty overview requests no captures')
const views = Array.from({length:60}, () => view())
views.forEach(v => queue.add(v))
for (let frame = 0; frame < 300; frame++) queue.tick(frame * 33)
assertEqual(views.reduce((sum,v) => sum + v.requests, 0), 300, '60 previews across outputs still share one request per tick')
assert(views.every(v => v.requests === 5), 'all previews receive a fair share under saturation')

const rates = scheduler.createQueue()
const card = view(200), thumbnail = view(1000), enlarged = view(66)
;[card,thumbnail,enlarged].forEach(v => rates.add(v))
for (let now = 0; now < 10000; now += 33) rates.tick(now)
assert(card.requests > 30 && card.requests <= 50, 'ordinary cards refresh at most five times per second')
assert(thumbnail.requests > 5 && thumbnail.requests <= 10, 'sidebar thumbnails refresh at most once per second')
assert(enlarged.requests > card.requests && enlarged.requests <= 152, 'Quick Look uses spare budget for a faster preview')

const lifecycle = scheduler.createQueue()
const hidden = view(), pending = view(), ready = view()
hidden.captureEnabled = false
pending.refresh = () => false
;[hidden,pending,ready].forEach(v => lifecycle.add(v))
assert(lifecycle.tick(0), 'a pending first frame does not block a ready preview')
assertEqual(hidden.requests, 0, 'disabled previews consume no capture budget')
assertEqual(ready.requests, 1, 'skipped previews leave the tick available for another source')
assertEqual(lifecycle.tick(100), false, 'a preview retains its frame until its refresh deadline')
hidden.captureEnabled = true
assert(lifecycle.tick(100), 'a newly visible preview can obtain its first frame immediately')
lifecycle.remove(pending)
lifecycle.remove(hidden)
assert(lifecycle.tick(200), 'removing entries around the cursor preserves remaining captures')
assertEqual(ready.requests, 2, 'remaining preview continues at its own deadline')
lifecycle.remove(ready)
assertEqual(lifecycle.tick(1000), false, 'destroying all delegates releases the queue')

const churn = scheduler.createQueue()
const a = view(0), b = view(0), c = view(0)
;[a,b,c].forEach(v => churn.add(v))
churn.tick(0)
churn.remove(a)
churn.tick(1)
assertEqual(b.requests, 1, 'closing a previously serviced window does not skip its neighbor')
churn.remove(c)
churn.tick(2)
assertEqual(b.requests, 2, 'closing the next window safely wraps the cursor')

const startup = scheduler.createQueue()
let clock = 0
const fresh = Array.from({length:60}, () => ({
  ...view(), hasContent:false, captureStarted:false, startedAt:0,
  refresh() { this.requests++; this.captureStarted=true; this.startedAt=clock; return true }
}))
fresh.forEach(v => startup.add(v))
assertEqual(startup.prepare(0,16),16,'startup fills only its bounded concurrency budget')
assertEqual(startup.prepare(0,16),0,'sixteen pending exports prevent an unbounded startup burst')
for (clock=8; clock<=160; clock+=8) {
  fresh.forEach(v => { if (v.captureStarted && clock-v.startedAt>=16) v.hasContent=true })
  const issued=startup.prepare(clock,16)
  assert(issued<=16 && fresh.filter(v=>v.captureStarted&&!v.hasContent).length<=16, 'startup stays bounded while frames complete')
  if (!startup.pending()) break
}
assertEqual(startup.pending(),0,'60 previews with 16ms exports become ready inside the opening animation')
assert(fresh.every(v=>v.requests===1),'startup requests each first frame exactly once without live refresh work')
assertEqual(startup.prepare(clock,16),0,'completed startup never refreshes existing content')
const stalled=scheduler.createQueue()
const blocked={...view(),captureStarted:true,hasContent:false}
stalled.add(blocked)
assertEqual(stalled.pending(),1,'an unfinished frame delays the coherent reveal')
blocked.captureEnabled=false
assertEqual(stalled.pending(),0,'a stopped or hidden source cannot hold up the reveal')
stalled.remove(blocked)
assertEqual(stalled.prepare(0,16),0,'closing releases startup work as well as periodic updates')
JS
