import assert from 'node:assert/strict'

// Keep multiline text in JS data bindings: uni-app may decode HTML newline
// entities into literal WXML attribute newlines rejected by WeChat's compiler.
export function checkWxmlAttributes(source, path = 'WXML') {
  for (const match of source.matchAll(/\b([\w:-]+)\s*=\s*(["'])([\s\S]*?)\2/g)) {
    assert.ok(!/[\r\n]|\\[rn]/.test(match[3]),
      `${path}: attribute ${match[1]} contains a newline; use a data binding instead`)
  }
}
