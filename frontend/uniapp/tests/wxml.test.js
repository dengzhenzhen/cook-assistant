import test from 'node:test'
import assert from 'node:assert/strict'
import { checkWxmlAttributes } from '../scripts/wxml-checks.mjs'

test('rejects decoded multiline placeholder in compiled WXML', () => {
  const compiled = '<textarea placeholder="0.5 | 0.7\n1 | 1\n2 | 1.6" value="{{ingredient.t}}"/>'
  assert.throws(() => checkWxmlAttributes(compiled, 'pages/editor.wxml'), /editor\.wxml: attribute placeholder contains a newline/)
})

test('accepts dynamic multiline placeholders and template line breaks outside attributes', () => {
  assert.doesNotThrow(() => checkWxmlAttributes('<view>\n<textarea placeholder="{{curvePlaceholder}}"/>\n</view>'))
})

test('rejects CRLF and literal newline escape sequences in static attributes', () => {
  assert.throws(() => checkWxmlAttributes('<input placeholder="one\r\ntwo"/>'), /contains a newline/)
  assert.throws(() => checkWxmlAttributes('<input placeholder="one\\ntwo"/>'), /contains a newline/)
})
