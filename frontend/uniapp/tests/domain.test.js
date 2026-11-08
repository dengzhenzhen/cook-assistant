import test from 'node:test'
import assert from 'node:assert/strict'
import { setAccount, selected, get, set, getGlobal } from '../src/lib/storage.js'
import { queueEdit, pendingEdits, flushEdits } from '../src/lib/outbox.js'
import { api, auth, ApiError, setBaseUrl } from '../src/lib/client.js'
import { createSession, tick, completeTask, buildReplan, finished } from '../src/lib/session.js'
import { cacheRecipes, cachedRecipes, overlayPending } from '../src/catalog-cache.js'

const at = seconds => new Date(1700000000000 + seconds * 1000)
function snapshot() {
  return { origin: at(0).toISOString(), request: { target_finish_seconds: null, cook_count: 1,
    capacities: { oven: 1 }, holds: [], tasks: [
      { id: 'setup', recipe_id: 'r', name: 'setup', duration_seconds: 10, attention_type: 'active', resources: {}, dependencies: [] },
      { id: 'bake', recipe_id: 'r', name: 'bake', duration_seconds: 20, attention_type: 'passive', resources: { oven: 1 }, dependencies: ['setup'] },
    ] }, plan: { tasks: [{ task_id: 'setup', start_seconds: 0 }, { task_id: 'bake', start_seconds: 100 }] } }
}
test('session handoff, automatic appliance completion, and replan facts', () => {
  const session = createSession(snapshot(), 's1', at(0))
  assert.equal(tick(session, at(0)), true)
  assert.equal(session.states.setup.status, 'running')
  assert.equal(completeTask(session, 'setup', at(10)), true)
  assert.equal(session.states.bake.status, 'running')
  assert.equal(session.states.bake.started, 10)
  assert.equal(tick(session, at(89)), false)
  assert.equal(tick(session, at(90)), true)
  assert.equal(finished(session), true)
  assert.deepEqual(buildReplan(session, at(90)).execution.map(row => row.actual_end), [10, 90])
})
test('storage and selected recipes are scoped per account', () => {
  setAccount('one'); selected.set(['r1']); assert.deepEqual(selected.get(), ['r1'])
  setAccount('two'); assert.deepEqual(selected.get(), []); selected.toggle('r2')
  setAccount('one'); assert.deepEqual(selected.get(), ['r1'])
})
test('concurrent 401 responses share one refresh and each replay once', async () => {
  setBaseUrl('https://api.example.test')
  const calls = []
  globalThis.uni = { request({ url, header, success }) {
    calls.push(url)
    queueMicrotask(() => {
      if (url.endsWith('/auth/login')) success({ statusCode: 200, data: { user_id: 'user', access_token: 'old', refresh_token: 'refresh' } })
      else if (url.endsWith('/auth/refresh')) success({ statusCode: 200, data: { user_id: 'user', access_token: 'new', refresh_token: 'rotated' } })
      else success(header.Authorization === 'Bearer new' ? { statusCode: 200, data: [] } : { statusCode: 401, data: { detail: 'expired' } })
    })
  } }
  await api.login('a@example.com', 'password123')
  await Promise.all([api.recipes(), api.recipes()])
  assert.equal(calls.filter(url => url.endsWith('/auth/refresh')).length, 1)
  assert.equal(calls.filter(url => url.endsWith('/recipes')).length, 4)
  assert.equal(auth.value.access_token, 'new')
  delete globalThis.uni
})
test('outbox keeps conflicts and preserves original base across local edits', async () => {
  setAccount('outbox-user')
  queueEdit('recipe', { recipe_id: 'r', name: 'original' }, { recipe_id: 'r', name: 'draft' })
  queueEdit('recipe', { recipe_id: 'r', name: 'draft' }, { recipe_id: 'r', name: 'latest' })
  assert.equal(pendingEdits().length, 1)
  assert.equal(pendingEdits()[0].base.name, 'original')
  assert.deepEqual(get('edit_outbox_index'), ['recipe:r'])
  const original = api.syncEdit
  api.syncEdit = async () => { throw new ApiError(409, 'cloud changed') }
  try { await flushEdits(); assert.equal(pendingEdits()[0].status, 'conflict') }
  finally { api.syncEdit = original }
})
test('session CAS conflict exposes server snapshot for resolution', async () => {
  const previous = auth.value
  auth.value = { user_id: 'cas-user', access_token: 'token', refresh_token: 'refresh' }
  globalThis.uni = { request({ url, success }) {
    queueMicrotask(() => success(url.endsWith('/sessions/s1')
      ? { statusCode: 409, data: { detail: { message: '会话已在其他设备更新。', version: 2, document: { states: {} } } } }
      : { statusCode: 200, data: {} }))
  } }
  try {
    await assert.rejects(api.syncSession({ id: 's1', snapshot: snapshot(), states: {} }, 1, 'mutation'), error => {
      assert.equal(error.conflict, true)
      assert.equal(error.data.detail.version, 2)
      return true
    })
  } finally { delete globalThis.uni; auth.value = previous }
})
test('image import uses the single-file upload shape supported by WeChat', async () => {
  const previous = auth.value
  auth.value = { user_id: 'image-user', access_token: 'token', refresh_token: 'refresh' }
  let upload
  globalThis.uni = { uploadFile(options) {
    upload = options
    options.success({ statusCode: 202, data: JSON.stringify({ job_id: 'job-1' }) })
  } }
  try {
    assert.deepEqual(await api.importImage(['/tmp/recipe.png']), { job_id: 'job-1' })
    assert.equal(upload.filePath, '/tmp/recipe.png')
    assert.equal(upload.name, 'images')
    assert.equal(upload.files, undefined)
  } finally { delete globalThis.uni; auth.value = previous }
})
test('recipe cache stores entries separately and preserves pending edits', () => {
  setAccount('catalog-user')
  cacheRecipes([{ recipe_id: 'r1', name: '云端菜' }, { recipe_id: 'r2', name: '另一道菜' }])
  assert.equal(get('recipes'), null)
  assert.deepEqual(get('recipe_index'), ['r1', 'r2'])
  assert.equal(cachedRecipes().length, 2)
  const merged = overlayPending(cachedRecipes(), [{ kind: 'recipe', document: { recipe_id: 'r1', name: '本机菜' } }])
  assert.equal(merged[0].name, '本机菜')
  assert.equal(merged.length, 2)
})
test('late response from an old account is rejected', async () => {
  const old = auth.value
  auth.value = { user_id: 'old-user', access_token: 'old', refresh_token: 'old-refresh' }
  let respond
  globalThis.uni = { request({ success }) { respond = success } }
  try {
    const pending = api.recipes()
    auth.value = { user_id: 'new-user', access_token: 'new', refresh_token: 'new-refresh' }
    respond({ statusCode: 200, data: [{ recipe_id: 'private' }] })
    await assert.rejects(pending, error => error.status === 401)
  } finally { delete globalThis.uni; auth.value = old }
})

test('WeChat missing storage keys use defaults and first save can sync', async () => {
  const values = new Map()
  const previousAccount = auth.value?.user_id
  const originalSync = api.syncEdit
  globalThis.uni = {
    getStorageSync: key => values.has(key) ? structuredClone(values.get(key)) : '',
    setStorageSync: (key, value) => values.set(key, structuredClone(value)),
    removeStorageSync: key => values.delete(key),
  }
  setAccount('wechat-first-save')
  api.syncEdit = async edit => ({ document: edit.document })
  try {
    assert.equal(get('missing'), null)
    assert.equal(getGlobal('missing', 'fallback'), 'fallback')
    assert.deepEqual(selected.get(), [])
    assert.deepEqual(pendingEdits(), [])
    assert.deepEqual(cachedRecipes(), [])
    const recipe = { recipe_id: 'first', name: '番茄炒蛋' }
    queueEdit('recipe', null, recipe)
    assert.equal(pendingEdits()[0].document.name, recipe.name)
    await flushEdits()
    assert.deepEqual(pendingEdits(), [])
    set('false', false); set('zero', 0)
    assert.equal(get('false', true), false)
    assert.equal(get('zero', 1), 0)
    // Existing legacy queues remain readable after normalization.
    set('edit_outbox_index', null)
    set('edit_outbox', [{ kind: 'recipe', base: null, document: recipe }])
    assert.equal(pendingEdits().length, 1)
  } finally {
    api.syncEdit = originalSync
    delete globalThis.uni
    setAccount(previousAccount)
  }
})

test('kitchen sync overwrites cloud settings with local edits including old conflicts', async () => {
  setAccount('kitchen-local-wins')
  const local = { kitchen_id: 'k', cook_count: 2, capacities: { burner: 3 } }
  queueEdit('kitchen', { ...local, cook_count: 1 }, local)
  const key = 'edit_outbox:kitchen:k'
  set(key, { ...get(key), status: 'conflict' })
  const originalSave = api.saveKitchen
  const originalSync = api.syncEdit
  const calls = []
  api.saveKitchen = async document => { calls.push(document); return document }
  api.syncEdit = async () => { throw new Error('Kitchen must not use conflict-based sync') }
  try {
    await flushEdits()
    assert.deepEqual(calls, [local])
    assert.deepEqual(pendingEdits(), [])
  } finally { api.saveKitchen = originalSave; api.syncEdit = originalSync }
})

test('menu resolve and plan requests preserve edited names, portions, and menu constraints', async () => {
  const previous = auth.value
  auth.value = { user_id: 'menu-contract', access_token: 'token' }
  const calls = []
  globalThis.uni = { request(options) {
    calls.push({ url: options.url, data: options.data })
    options.success({ statusCode: 200, data: {} })
  } }
  try {
    await api.resolveMenu({ names: ['番茄炒蛋'], selected_recipe_ids: { 番茄炒蛋: 'r' } })
    await api.plan(['r'], 'k', null, { r: 4 }, { mode: 'quick', time_minutes: 10, effort: 'low' })
    assert.ok(calls[0].url.endsWith('/recommendations/resolve'))
    assert.deepEqual(calls[0].data.names, ['番茄炒蛋'])
    assert.deepEqual(calls[1].data.servings_by_recipe, { r: 4 })
    assert.deepEqual(calls[1].data.meal_preferences, { mode: 'quick', time_minutes: 10, effort: 'low' })
  } finally { auth.value = previous; delete globalThis.uni }
})
