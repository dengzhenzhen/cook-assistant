import { get, set, remove } from './storage.js'
import { api } from './client.js'

const KEY = 'edit_outbox'
const INDEX = 'edit_outbox_index'
const keyFor = row => row.kind + ':' + (row.document.recipe_id || row.document.kitchen_id)
function writeQueue(rows) {
  const old = get(INDEX, [])
  const keys = rows.map(keyFor)
  for (const row of rows) set(`${KEY}:${keyFor(row)}`, row)
  set(INDEX, keys)
  for (const key of old) if (!keys.includes(key)) remove(`${KEY}:${key}`)
  remove(KEY)
}
export function pendingEdits() {
  const keys = get(INDEX)
  if (!Array.isArray(keys)) return get(KEY, [])
  return keys.map(key => get(`${KEY}:${key}`)).filter(Boolean)
}
export function queueEdit(kind, base, document) {
  if (!['recipe', 'kitchen'].includes(kind)) throw new Error('未知编辑类型。')
  const key = kind === 'recipe' ? document.recipe_id : document.kitchen_id
  const rows = pendingEdits()
  const index = rows.findIndex(row => row.kind === kind && (row.document.recipe_id || row.document.kitchen_id) === key)
  const edit = { kind, base: index >= 0 ? rows[index].base : base, document, status: 'pending' }
  if (index >= 0) rows[index] = edit
  else rows.push(edit)
  writeQueue(rows)
  return edit
}
export async function flushEdits() {
  const results = []
  const attempted = new Set()
  while (true) {
    const rows = pendingEdits()
    const edit = rows.find(row => row.status !== 'conflict' && !attempted.has(row.kind + ':' + (row.document.recipe_id || row.document.kitchen_id)))
    if (!edit) break
    const key = edit.kind + ':' + (edit.document.recipe_id || edit.document.kitchen_id)
    attempted.add(key)
    try {
      const result = await api.syncEdit({ kind: edit.kind, base: edit.base, document: edit.document })
      const latest = pendingEdits()
      const index = latest.findIndex(row => row.kind + ':' + (row.document.recipe_id || row.document.kitchen_id) === key)
      if (index >= 0) {
        if (JSON.stringify(latest[index].document) === JSON.stringify(edit.document)) latest.splice(index, 1)
        else latest[index].base = result.document
        writeQueue(latest)
      }
      results.push({ edit, result })
    } catch (error) {
      if (error.status === 409) {
        const latest = pendingEdits()
        const index = latest.findIndex(row => row.kind + ':' + (row.document.recipe_id || row.document.kitchen_id) === key)
        if (index >= 0) { latest[index].status = 'conflict'; latest[index].error = error.message; writeQueue(latest) }
        results.push({ edit, error })
      } else { throw error }
    }
  }
  return results
}
export function resolveEdit(index, base, document) {
  const rows = pendingEdits()
  if (!rows[index]) throw new Error('待同步编辑不存在。')
  rows[index] = { ...rows[index], base, document, status: 'pending', error: null }
  writeQueue(rows)
}
export function discardEdit(index) { const rows = pendingEdits(); rows.splice(index, 1); writeQueue(rows) }
