export const MODE_DEFAULTS = Object.freeze({
  quick: { dish_count: 1, time_minutes: 10, effort: 'low' },
  everyday: { dish_count: 2, time_minutes: 30, effort: 'medium' },
  feast: { dish_count: 3, time_minutes: 60, effort: 'high' },
})

export function cleanName(name) { return String(name ?? '').trim().replace(/\s+/g, ' ') }

export function candidateSummary(candidate) {
  const servings = Number(candidate?.servings)
  const ingredients = Array.isArray(candidate?.ingredient_names) ? candidate.ingredient_names.map(cleanName).filter(Boolean) : []
  return [
    cleanName(candidate?.name),
    Number.isFinite(servings) && servings > 0 ? `${servings} 人份` : '',
    ingredients.length ? `${ingredients.slice(0, 3).join('、')}${ingredients.length > 3 ? '等' : ''}` : '',
  ].filter(Boolean).join(' · ') + (candidate?.confirmed === false ? '（待审核）' : '')
}

export function parseIngredients(text) {
  const parts = String(text ?? '').split(/[,，、\n\r]+/).map(cleanName).filter(Boolean)
  const unique = [...new Map(parts.map(item => [item.toLocaleLowerCase(), item])).values()]
  if (unique.length > 30) throw new Error('现有食材最多填写 30 项。')
  if (unique.some(item => item.length > 40)) throw new Error('每项食材最多 40 字。')
  return unique
}

function boundedInt(value, fallback, min, max) {
  const number = Number(value)
  return Number.isFinite(number) ? Math.min(max, Math.max(min, Math.round(number))) : fallback
}

export function menuSettings(value = {}) {
  const mode = Object.hasOwn(MODE_DEFAULTS, value.mode) ? value.mode : 'everyday'
  const defaults = MODE_DEFAULTS[mode]
  return {
    mode,
    servings: boundedInt(value.servings, 2, 1, 20),
    dish_count: boundedInt(value.dish_count, defaults.dish_count, 1, 6),
    time_minutes: boundedInt(value.time_minutes, defaults.time_minutes, 1, 240),
    effort: ['low', 'medium', 'high'].includes(value.effort) ? value.effort : defaults.effort,
  }
}

export function settingsForMode(mode, current = {}) {
  const selected = Object.hasOwn(MODE_DEFAULTS, mode) ? mode : 'everyday'
  return menuSettings({ ...current, ...MODE_DEFAULTS[selected], mode: selected })
}

export function normalizeDishes(dishes, limit = 6) {
  const seen = new Set()
  const result = []
  for (const dish of Array.isArray(dishes) ? dishes : []) {
    const name = cleanName(dish?.name)
    const key = name.toLocaleLowerCase()
    if (!name || seen.has(key)) continue
    seen.add(key)
    result.push({
      name,
      reason: String(dish?.reason ?? '').trim(),
      estimated_minutes: Number.isFinite(Number(dish?.estimated_minutes)) && Number(dish.estimated_minutes) > 0 ? Math.round(Number(dish.estimated_minutes)) : null,
      effort: ['low', 'medium', 'high'].includes(dish?.effort) ? dish.effort : null,
      ...(dish?.matched_recipe_id ? { matched_recipe_id: dish.matched_recipe_id } : {}),
      ...(dish?.row_id ? { row_id: dish.row_id } : {}),
      ...(dish?.resolution ? { resolution: dish.resolution } : {}),
      ...(dish?.choice_recipe_id ? { choice_recipe_id: dish.choice_recipe_id } : {}),
      ...(dish?.review_opened ? { review_opened: true } : {}),
    })
    if (result.length >= limit) break
  }
  return result
}

export function editDish(dishes, index, name) {
  return dishes.map((dish, position) => {
    if (position !== index) return dish
    const next = { ...dish, name }
    if (cleanName(name) !== cleanName(dish.name)) {
      delete next.matched_recipe_id
      delete next.resolution
      delete next.choice_recipe_id
      delete next.review_opened
      next.reason = ''
      next.estimated_minutes = null
      next.effort = null
    }
    return next
  })
}

export function menuRequest(settings, dishes = [], ingredients = '') {
  return { ...menuSettings(settings), ingredients: parseIngredients(ingredients), exclude_names: normalizeDishes(dishes).map(dish => dish.name) }
}

export function applyResolution(dishes, requested, items) {
  const byName = new Map((Array.isArray(items) ? items : []).map(item => [cleanName(item.name).toLocaleLowerCase(), item]))
  const targets = new Map(requested.map(dish => [dish.row_id, cleanName(dish.name)]))
  return dishes.map(dish => {
    const originalName = targets.get(dish.row_id)
    if (!originalName || cleanName(dish.name) !== originalName) return dish
    const item = byName.get(originalName.toLocaleLowerCase())
    if (!item) return { ...dish, resolution: { status: 'failed', error: '未收到这道菜的处理结果，可单独重试。' } }
    return { ...dish, resolution: {
      status: item.status, ...(item.recipe_id ? { recipe_id: item.recipe_id } : {}),
      ...(item.job_id ? { job_id: item.job_id } : {}),
      ...(item.candidates ? { candidates: item.candidates } : {}),
      ...(item.error ? { error: item.error } : {}),
    } }
  })
}

export async function resolveRowsSafely(call, requested, getRows, isCurrent) {
  const names = requested.map(dish => dish.name)
  const selected_recipe_ids = Object.fromEntries(requested.filter(dish => dish.choice_recipe_id).map(dish => [dish.name, dish.choice_recipe_id]))
  const result = await call({ names, selected_recipe_ids })
  return isCurrent() ? applyResolution(getRows(), requested, result.items) : null
}
