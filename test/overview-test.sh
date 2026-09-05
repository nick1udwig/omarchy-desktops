#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('node:fs')
const vm = require('node:vm')
function qmlJs(file, globals = {}) {
  const context = vm.createContext(globals)
  vm.runInContext(fs.readFileSync(path.join(root, file), 'utf8').replace(/^\.(pragma|import).*$/gm, ''), context, {filename:file})
  return context
}
const WindowModel = qmlJs('vendor/expose/WindowModel.js')
const model = qmlJs('OverviewModel.js', {WindowModel})
const layout = qmlJs('vendor/expose/Layout.js', {WindowModel})
const icons = qmlJs('vendor/expose/IconResolver.js')
const snapshot = {desktops:[
  {outputs:{left:{slots:[1,2,3],selected:2},right:{slots:[4,5,6],selected:1}}},
  {outputs:{left:{slots:[11,12,13],selected:3},right:{slots:[14,15,16],selected:2}}}
]}
function top(address, output, workspace, title = 'Window', ratio = 1.6) {
  return {address,title,monitor:{name:output},workspace:{id:workspace},wayland:{appId:'terminal'},lastIpcObject:{mapped:true,class:'foot',size:[ratio*1000,1000]}}
}
const tops = [top('a','left',1),top('b','left',2,'Alpha editor'),top('c','right',4),top('d','right',5),top('e','left',13),top('f','right',15)]
assertDeepEqual(model.selectedWorkspace(snapshot,1,'left'), {id:2,slot:2}, 'desktop thumbnails use the remembered workspace, not always slot one')
assertDeepEqual(model.windowsFor(snapshot,1,'left',tops,'').map(w=>w.address), ['b'], 'left Exposé shows only its selected workspace')
assertDeepEqual(model.windowsFor(snapshot,1,'right',tops,'').map(w=>w.address), ['c'], 'right Exposé has its own selected workspace')
assertDeepEqual(model.windowsFor(snapshot,2,'left',tops,'').map(w=>w.address), ['e'], 'desktop switching changes the left workspace scope')
assertDeepEqual(model.windowsFor(snapshot,2,'right',tops,'').map(w=>w.address), ['f'], 'desktop switching changes the right workspace scope')
assertDeepEqual(model.windowsFor(snapshot,1,'left',tops,' ALPHA ').map(w=>w.address), ['b'], 'filter is case-insensitive and searches titles')
assertEqual(model.windowsFor(snapshot,1,'left',tops,'terminal').length, 1, 'filter searches application identities using the upstream model')
assertEqual(model.windowsFor(snapshot,1,'right',tops,'Alpha').length, 0, 'shared search never leaks another monitor’s windows into the grid')
assertEqual(model.windowsFor(snapshot,99,'left',tops,'').length, 0, 'missing desktop is safe during asynchronous updates')
assertEqual(model.windowsFor(snapshot,1,'removed',tops,'').length, 0, 'removed monitor is safe')
const pinned = top('pin','left',1); pinned.lastIpcObject.pinned = true
assertEqual(model.windowsFor(snapshot,1,'left',[pinned],'').length, 1, 'pinned windows remain visible on their monitor')
assertEqual(model.windowsFor(snapshot,1,'right',[pinned],'').length, 0, 'pinned windows do not appear on every monitor')
tops[1].lastIpcObject.mapped = false
assertEqual(model.windowsFor(snapshot,1,'left',tops,'').length, 0, 'closing a window removes its card')
tops[1].lastIpcObject.mapped = true
assert(model.sameWindows(tops,tops.slice()), 'metadata updates keep stable card instances')
assert(!model.sameWindows(tops,tops.slice().reverse()), 'a changed card order is detected')

for (const size of [[1100,740],[940,2100],[700,560],[300,240]]) {
  for (const count of [0,1,2,3,6,12,20]) {
    const windows = Array.from({length:count},(_,i)=>top(String(i),'left',2,'Window',[0.45,1,1.6,2.5,4][i%5]))
    const rects = layout.computeWindowLayout(windows,size[0],size[1],24,6,40,size[0]/size[1])
    // Very small, overcrowded surfaces may have no feasible composition.
    if (size[0] >= 700) assertEqual(rects.length, count, `Exposé composes ${count} windows at ${size.join('×')}`)
    rects.forEach((r,i)=>{
      if (!(r.x>=0 && r.y>=0 && r.width>0 && r.height>0 && r.x+r.width<=size[0]+0.01 && r.y+r.height<=size[1]+0.01)) throw new Error('layout out of bounds')
      for (let j=0;j<i;j++) {
        const b=rects[j]
        if (r.x < b.x+b.width-0.01 && r.x+r.width > b.x+0.01 && r.y < b.y+b.height-0.01 && r.y+r.height > b.y+0.01) throw new Error('overlapping previews')
      }
    })
  }
}
pass('upstream composition stays in bounds without overlaps on landscape, portrait, and small surfaces')
const spatial = [{x:0,y:0,width:100,height:80},{x:180,y:0,width:100,height:80},{x:0,y:180,width:100,height:80}]
assertEqual(model.directionalIndex(spatial,0,1,0),1,'Right selects the nearest right-hand card')
assertEqual(model.directionalIndex(spatial,0,0,1),2,'Down selects the nearest lower card')
assertEqual(model.directionalIndex(spatial,0,-1,0),0,'navigation at an edge keeps its selection')
const identity = icons.identityFor({wayland:{appId:'Terminal.desktop'},lastIpcObject:{class:'foot'}})
assertDeepEqual(identity.candidates,['terminal','foot'],'upstream icon resolver retains stable application identities')
JS
