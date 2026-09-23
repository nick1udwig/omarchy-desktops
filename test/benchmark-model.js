#!/usr/bin/env node
// Isolated CPU work, not rendering latency or a simulation of a 400 MHz CPU.
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const assert = require('node:assert/strict')
const {performance} = require('node:perf_hooks')
const root = path.resolve(__dirname, '..')
function load(file, globals = {}) {
  const context = vm.createContext(globals)
  vm.runInContext(fs.readFileSync(path.join(root,file),'utf8').replace(/^\.(pragma|import).*$/gm,''), context)
  return context
}
const WindowModel = load('vendor/expose/WindowModel.js')
const model = load('OverviewModel.js', {WindowModel})
const scheduler = load('CaptureScheduler.js')
const outputs = ['left','middle','right']
const snapshot = {desktops:Array.from({length:10}, (_,d) => ({outputs:Object.fromEntries(
  outputs.map((name,m) => [name,{slots:[1+d*3+m],selected:1}])
)}))}
const queries = snapshot.desktops.flatMap((_,d) => outputs.map(output => ({desktop:d+1,output})))
// Include the three grid lookups, which share the current desktop's lists.
queries.push(...queries.slice(0,3))
function previous(windows) {
  return queries.map(({desktop,output}) => {
    const workspace = model.selectedWorkspace(snapshot,desktop,output)
    return windows.filter(top => WindowModel.isEligible(top)
      && WindowModel.isOnScreen(top,output,true) && WindowModel.isOnWorkspace(top,workspace))
  })
}
function indexed(windows) {
  const index = model.indexWindows(snapshot,windows)
  return queries.map(({desktop,output}) => model.windowsFor(index,desktop,output,''))
}
function startup(windows, batched) {
  const queue = scheduler.createQueue()
  for (const top of windows) {
    const view = {captureEnabled:true,hasContent:false,captureStarted:false,refreshInterval:200,
      refresh() { this.captureStarted=true; return true }}
    queue.add(view)
    if (!batched) queue.prepare(0,32)
  }
  if (batched) queue.prepare(0,32)
  return queue.pending()
}
function compare(before,after,iterations) {
  for (let i=0; i<30; i++) { before(); after() }
  const samples = [[],[]]
  for (let run=0; run<7; run++) for (const which of run%2 ? [1,0] : [0,1]) {
    const action = which ? after : before
    const start = performance.now()
    for (let i=0; i<iterations; i++) action()
    samples[which].push((performance.now()-start)/iterations)
  }
  const medians = samples.map(values => values.sort((a,b)=>a-b)[3])
  return {before_ms:+medians[0].toFixed(4),after_ms:+medians[1].toFixed(4),speedup:+(medians[0]/medians[1]).toFixed(2)}
}
for (const count of [50,200,500,1000]) {
  const windows = Array.from({length:count}, (_,i) => ({
    address:String(i),monitor:{name:outputs[i%3]},workspace:{id:1+i%30},
    wayland:{appId:'app'},lastIpcObject:{mapped:true,pinned:i%37===0},
  }))
  assert.equal(JSON.stringify(previous(windows)),JSON.stringify(indexed(windows)))
  assert.equal(startup(windows,false),startup(windows,true))
  console.log(JSON.stringify({windows:count,queries:queries.length,
    membership:compare(()=>previous(windows),()=>indexed(windows),100),
    registration:compare(()=>startup(windows,false),()=>startup(windows,true),20),
  }))
}
