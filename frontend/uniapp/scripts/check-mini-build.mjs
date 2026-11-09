// Validate compiled output: Node's core modules are unavailable in WeChat.
import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { builtinModules } from 'node:module'
import { checkWxmlAttributes } from './wxml-checks.mjs'
const builtins = new Set(builtinModules.flatMap(name => [name, `node:${name}`]))
function check(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name)
    if (entry.isDirectory()) check(path)
    else if (entry.name.endsWith('.wxml')) {
      checkWxmlAttributes(readFileSync(path, 'utf8'), path)
    } else if (entry.name.endsWith('.js')) {
      const source = readFileSync(path, 'utf8')
      for (const match of source.matchAll(/\brequire\s*\(\s*['"]([^'"]+)['"]\s*\)/g)) {
        assert.ok(!builtins.has(match[1]), `${path} requires Node module ${match[1]}`)
      }
    }
  }
}
check('dist/build/mp-weixin')
const client = readFileSync('dist/build/mp-weixin/lib/client.js', 'utf8')
assert.ok(!client.includes('import.meta'), 'Unresolved import.meta in mini-program client')
if (process.env.VITE_API_BASE_URL) {
  assert.ok(client.includes(JSON.stringify(process.env.VITE_API_BASE_URL)), 'Backend URL was not injected')
}
console.log('Mini-program output: WXML attribute newlines checked; no Node core imports; backend configuration checked.')
