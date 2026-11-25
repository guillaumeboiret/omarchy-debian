#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

ROOT="$ROOT" run_node_test <<'JS'
const overview = requireFromRoot('shell/plugins/overview/OverviewModel.js')

const win = (address, key, extra) => Object.assign({ address, key, name: key, workspaceId: 1, focusHistory: 5, width: 1600, height: 1000 }, extra)

const groups = overview.groupWindows([
  win('a', 'google-chrome', { focusHistory: 3 }),
  win('b', 'omarchy-terminal', { name: 'Terminal', focusHistory: 1 }),
  win('c', 'google-chrome', { focusHistory: 0 }),
  win('d', 'org.omarchy.herdr', { workspaceId: -98, focusHistory: 2 }),
  win('e', 'google-chrome', { child: true }),
  win('f', 'slack', { focusHistory: -1 })
])
assertDeepEqual(
  groups.map(group => [group.key, group.windows.map(window => window.address)]),
  [['google-chrome', ['c', 'a']], ['omarchy-terminal', ['b']], ['slack', ['f']]],
  'overview groups windows by app, the app focused last first, leaving out special workspaces and dialogs'
)

const many = [{ key: 'x', name: 'x', windows: [] }]
for (let i = 0; i < 40; i++) many[0].windows.push(win('w' + i, 'x'))
const opts = { gap: 10, groupGap: 30, headerHeight: 30, titleHeight: 20, minHeight: 40, maxHeight: 600 }
const fitted = overview.layout(many, 1400, 900, opts)
assertEqual(fitted.items.length, 40, 'overview places every window')
assert(fitted.height <= 900 && fitted.thumbHeight > 60, 'overview shrinks thumbnails until forty windows fit the screen')
assert(fitted.items.every(item => item.x >= 0 && item.x + item.width <= 1400), 'overview keeps every thumbnail within the screen width')

const one = overview.layout([{ key: 'x', name: 'x', windows: [win('only', 'x')] }], 1400, 900, opts)
assertEqual(one.thumbHeight, 600, 'overview caps a lone thumbnail at its largest size')

const grid = [
  { x: 0, y: 0, width: 100, height: 100 }, { x: 120, y: 0, width: 100, height: 100 },
  { x: 0, y: 150, width: 100, height: 100 }, { x: 120, y: 150, width: 100, height: 100 }
]
assertEqual(overview.neighbor(grid, 0, 'right'), 1, 'right moves to the thumbnail beside')
assertEqual(overview.neighbor(grid, 1, 'down'), 3, 'down moves to the thumbnail below, in line')
assertEqual(overview.neighbor(grid, 1, 'right'), 2, 'right at the end of a row steps on in reading order')
assertEqual(overview.neighbor(grid, 0, 'up'), 0, 'up from the top row stays put')
assertEqual(overview.fallbackName('chrome-claude.ai__artifact_X-Default'), 'claude.ai', 'overview names a Chromium app window without an entry after its site')
assertEqual(overview.fallbackName('xeyes'), 'xeyes', 'overview names any other window without an entry after its class')
JS
