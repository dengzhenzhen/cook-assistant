export const MODE_DEFAULTS = Object.freeze({
  quick: { dish_count: 1, time_minutes: 10, effort: 'low' },
  everyday: { dish_count: 2, time_minutes: 30, effort: 'medium' },
  feast: { dish_count: 3, time_minutes: 60, effort: 'high' },
})

export function cleanName(name) { return String(name ?? '').trim().replace(/\s+/g, ' ') }

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
      next.reason = ''
      next.estimated_minutes = null
      next.effort = null
    }
    return next
  })
}

export function menuRequest(settings, dishes = []) {
  return { ...menuSettings(settings), exclude_names: normalizeDishes(dishes).map(dish => dish.name) }
}
