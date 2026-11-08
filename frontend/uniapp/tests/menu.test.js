import test from 'node:test'
import assert from 'node:assert/strict'
import { menuSettings, settingsForMode, normalizeDishes, editDish, menuRequest } from '../src/lib/menu.js'

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
