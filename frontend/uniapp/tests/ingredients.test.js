import test from 'node:test'
import assert from 'node:assert/strict'
import { editableIngredient, savedIngredient } from '../src/lib/ingredients.js'
import { createSession } from '../src/lib/session.js'

test('editing quantities preserves individual rules and removes stale parsed amounts', () => {
  const original = { name: '生抽', quantity: '10', unit: 'ml', role: 'seasoning',
    amount: { kind: 'exact', value: '10', unit: 'ml' }, scaling: { mode: 'power', exponent: 0.7 } }
  const editable = editableIngredient(original)
  editable.quantity = '20'
  const saved = savedIngredient(editable)
  assert.equal(saved.quantity, '20')
  assert.equal(saved.scaling.exponent, 0.7)
  assert.equal(saved.amount, undefined)
  assert.equal(saved.curveText, undefined)
  assert.equal(original.quantity, '10')
})

test('piecewise rules must include the base anchor and monotone ratios', () => {
  const editable = editableIngredient({ name: '油', scaling: { mode: 'piecewise' } })
  editable.curveText = '0.5 | 0.7\n1 | 1\n2 | 1.6'
  assert.equal(savedIngredient(editable).scaling.points[2].factor, 1.6)
  editable.curveText = '1 | 1\n1 | 2'
  assert.throws(() => savedIngredient(editable), /递增节点/)
})

test('cooking sessions keep a deep copy of the meal ingredient snapshot', () => {
  const snapshot = { origin: new Date().toISOString(), request: { tasks: [{ id: 'a' }] }, plan: { tasks: [{ task_id: 'a', start_seconds: 0 }] },
    recipe_snapshots: { r: { ingredients: [{ name: '盐', quantity: '3.48' }], target_servings: 4 } } }
  const session = createSession(snapshot, 'session')
  snapshot.recipe_snapshots.r.ingredients[0].quantity = '100'
  assert.equal(session.snapshot.recipe_snapshots.r.ingredients[0].quantity, '3.48')
})
