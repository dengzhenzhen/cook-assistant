import { storage } from './lib/storage.js'

export function cachedRecipes() {
  const ids = storage.get('recipe_index')
  if (!Array.isArray(ids)) return storage.get('recipes') || []
  return ids.map(id => storage.get(`recipe:${id}`)).filter(Boolean)
}

export function cacheRecipes(recipes) {
  // WeChat storage limits each key: keep each recipe in its own entry.
  const ids = recipes.map(recipe => recipe.recipe_id)
  for (const recipe of recipes) storage.set(`recipe:${recipe.recipe_id}`, recipe)
  storage.set('recipe_index', ids)
  storage.remove('recipes')
}

export function overlayPending(recipes, edits) {
  let result = recipes.slice()
  for (const edit of edits) {
    if (edit.kind !== 'recipe') continue
    result = [edit.document, ...result.filter(recipe => recipe.recipe_id !== edit.document.recipe_id)]
  }
  return result
}
