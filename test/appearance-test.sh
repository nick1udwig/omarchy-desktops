#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('node:fs')
const vm = require('node:vm')
const read = file => fs.readFileSync(path.join(root, file), 'utf8')
const card = read('vendor/expose/WindowCard.qml')
const thumbnail = read('DesktopThumbnail.qml')
const screen = read('OverviewScreen.qml')
const clip = read('PreviewClip.qml')
function expression(source, name) {
  const match = source.match(new RegExp('property real ' + name + ': ([^\\n]+)'))
  if (!match) throw new Error('Missing QML property: ' + name)
  return match[1]
}
for (const radius of [0, 2, 8, 16, 24]) {
  const Style = {cornerRadius:radius, spacing:{md:6}}
  assertEqual(vm.runInNewContext(expression(card, 'previewRadius'), {Style}), radius, `Exposé respects rounding ${radius} without a minimum`)
  assertEqual(vm.runInNewContext(expression(thumbnail, 'previewRadius'), {Style}), Math.max(0, radius - 6), `inset workspace corners follow rounding ${radius}`)
  assertEqual(vm.runInNewContext(expression(clip, 'radius'), {Style}), radius, `capture clipping follows rounding ${radius}`)
}
assert(!/radius:\s*(?:Style\.space\(|Math\.max\([1-9])/.test(screen + thumbnail + card), 'surface corners have no hardcoded positive radius')
assert(clip.includes('layer.enabled: root.radius > 0') && card.includes('Desktops.PreviewClip {'), 'grid and sidebar share square/rounded preview clipping')
assert(screen.includes('color: Color.menu.background') && screen.includes('color: Color.menu.scrim'), 'surfaces retain theme-provided menu color and opacity')
assert(thumbnail.includes('Color.menu.selectedBackground') && thumbnail.includes('Color.menu.selectedText'), 'desktop selection uses the menu selection palette')
for (const [name, text] of [['overview',screen],['thumbnail',thumbnail],['card',card]]) {
  assert(text.includes('Border.surfaceSpec(') && text.includes('Border.hyprlandActiveSpec('), `${name} preserves theme border gradients and widths`)
}
assert(card.includes('objectName: "window-caption"') && !card.includes('sourceComponent:'), 'floating captions are created directly without unused footer loaders')
assert(read('Overview.qml').includes('Style.refresh()'), 'opening refreshes the user’s current compositor corner setting')
JS
