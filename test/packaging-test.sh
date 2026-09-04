#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('node:fs')
const manifest = requireFromRoot('manifest.json')
assertEqual(manifest.schemaVersion, 1, 'plugin uses the supported manifest schema')
assertEqual(manifest.id, 'nick.desktops', 'plugin preserves the installed third-party identity')
assertDeepEqual(manifest.kinds, ['overlay', 'bar-widget'], 'plugin supplies the same overlay and bar widget')
assertEqual(manifest.keepLoaded, true, 'overview lifecycle remains unchanged')
for (const entry of Object.values(manifest.entryPoints)) {
  assert(!path.isAbsolute(entry) && !entry.split('/').includes('..') && fs.statSync(path.join(root, entry)).isFile(), 'manifest entrypoint is contained and present: ' + entry)
}
function inspect(dir) {
  for (const entry of fs.readdirSync(dir, {withFileTypes:true})) {
    if (entry.name === '.git') continue
    assert(!entry.isSymbolicLink(), 'repository entry is self-contained: ' + path.relative(root, path.join(dir, entry.name)))
    if (entry.isDirectory()) inspect(path.join(dir, entry.name))
  }
}
inspect(root)
const controller = fs.readFileSync(path.join(root, 'hypr/desktops.lua'), 'utf8')
const bar = fs.readFileSync(path.join(root, 'DesktopBar.qml'), 'utf8')
assert(controller.includes('options.overview_plugin or "' + manifest.id + '"'), 'controller targets this plugin by default')
assert(bar.includes('moduleName: "' + manifest.id + '"'), 'bar targets this plugin by default')
for (const filename of ['hypr/desktops.lua', 'DesktopBar.qml', 'DesktopState.qml', 'DesktopModel.js', 'Overview.qml', 'WorkspaceTile.qml', 'WindowPreview.qml']) {
  const text = fs.readFileSync(path.join(root, filename), 'utf8')
  assert(!text.includes('/Work/git/omarchy/') && !text.includes('shell/plugins/desktops') && !text.includes('default/hypr/desktops'), 'runtime file has no former checkout dependency: ' + filename)
}
JS
