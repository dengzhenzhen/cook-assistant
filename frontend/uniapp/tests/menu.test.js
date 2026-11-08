import test from 'node:test'
import assert from 'node:assert/strict'
import { applyResolution, candidateSummary, menuSettings, settingsForMode, normalizeDishes, editDish, menuRequest, parseIngredients, resolveRowsSafely } from '../src/lib/menu.js'

test('mode presets and custom limits stay within supported bounds', () => {
  assert.deepEqual(settingsForMode('quick'), { mode: 'quick', servings: 2, dish_count: 1, time_minutes: 10, effort: 'low' })
  assert.deepEqual(settingsForMode('feast', { servings: 4 }), { mode: 'feast', servings: 4, dish_count: 3, time_minutes: 60, effort: 'high' })
  assert.deepEqual(menuSettings({ mode: 'everyday', dish_count: 9, time_minutes: 0, effort: 'invalid' }),
    { mode: 'everyday', servings: 2, dish_count: 6, time_minutes: 1, effort: 'medium' })
})

test('dish names are trimmed and deduplicated before display and exclusion', () => {
  const dishes = normalizeDishes([{ name: ' 番茄  炒蛋 ', matched_recipe_id: 'r1' }, { name: '番茄 炒蛋' }, { name: '  ' }, { name: '青椒肉丝' }])
  assert.deepEqual(dishes.map(dish => dish.name), ['番茄 炒蛋', '青椒肉丝'])
  assert.deepEqual(menuRequest({ mode: 'quick' }, dishes).exclude_names, ['番茄 炒蛋', '青椒肉丝'])
  assert.equal(normalizeDishes(Array.from({ length: 7 }, (_, i) => ({ name: `菜${i}` }))).length, 6)
})

test('editing a matched dish invalidates its recipe link', () => {
  const original = [{ name: '番茄炒蛋', matched_recipe_id: 'r1', reason: '快手' }]
  assert.equal(editDish(original, 0, ' 番茄炒蛋 ')[0].matched_recipe_id, 'r1')
  assert.deepEqual(editDish(original, 0, '韭菜炒蛋')[0], { name: '韭菜炒蛋', reason: '', estimated_minutes: null, effort: null })
  assert.equal(original[0].matched_recipe_id, 'r1')
})

test('ingredients split, deduplicate, and reject oversized input', () => {
  assert.deepEqual(parseIngredients(' 番茄、鸡蛋\n番茄, 青椒，鸡蛋 '), ['番茄', '鸡蛋', '青椒'])
  assert.deepEqual(menuRequest({ mode: 'quick' }, [], '鸡蛋、番茄').ingredients, ['鸡蛋', '番茄'])
  assert.throws(() => parseIngredients('菜'.repeat(41)), /40 字/)
  assert.throws(() => parseIngredients(Array.from({ length: 31 }, (_, i) => `食材${i}`).join('、')), /30 项/)
})

test('resolve merges per row and ignores deleted or renamed rows', () => {
  const requested = [{ row_id: 'a', name: '番茄炒蛋' }, { row_id: 'b', name: '青椒肉丝' }]
  const current = [
    { row_id: 'a', name: '韭菜炒蛋' },
    { row_id: 'b', name: '青椒肉丝' },
    { row_id: 'c', name: '蒸米饭', resolution: { status: 'matched', recipe_id: 'r3' } },
  ]
  const merged = applyResolution(current, requested, [{ name: '番茄炒蛋', status: 'import_pending', job_id: 'j1' }, { name: '青椒肉丝', status: 'matched', recipe_id: 'r2' }])
  assert.equal(merged[0].resolution, undefined)
  assert.deepEqual(merged[1].resolution, { status: 'matched', recipe_id: 'r2' })
  assert.deepEqual(merged[2].resolution, { status: 'matched', recipe_id: 'r3' })
  assert.deepEqual(applyResolution([{ row_id: 'b', name: '青椒肉丝' }], requested, [])[0].resolution, { status: 'failed', error: '未收到这道菜的处理结果，可单独重试。' })
})

test('late resolve response uses current rows and cannot cross account changes', async () => {
  let finish
  const call = request => {
    assert.deepEqual(request, { names: ['番茄炒蛋'], selected_recipe_ids: { 番茄炒蛋: 'r1' } })
    return new Promise(resolve => { finish = resolve })
  }
  const requested = [{ row_id: 'a', name: '番茄炒蛋', choice_recipe_id: 'r1' }]
  let rows = [{ row_id: 'a', name: '番茄炒蛋' }]
  let active = true
  const pending = resolveRowsSafely(call, requested, () => rows, () => active)
  rows = [{ row_id: 'a', name: '韭菜炒蛋' }]
  finish({ items: [{ name: '番茄炒蛋', status: 'matched', recipe_id: 'r1' }] })
  assert.equal((await pending)[0].resolution, undefined)

  const changedAccount = resolveRowsSafely(() => Promise.resolve({ items: [{ name: '番茄炒蛋', status: 'matched', recipe_id: 'r1' }] }), requested, () => rows, () => active)
  active = false
  assert.equal(await changedAccount, null)
})

test('same-name candidates include available servings and ingredient clues', () => {
  assert.equal(candidateSummary({ name: '番茄炒蛋', servings: 2, ingredient_names: ['番茄', '鸡蛋'], confirmed: true }), '番茄炒蛋 · 2 人份 · 番茄、鸡蛋')
  assert.equal(candidateSummary({ name: '番茄炒蛋', confirmed: false }), '番茄炒蛋（待审核）')
})
