export const resourceNames = {
  burner: '灶眼', wok: '炒锅', pot: '汤锅', steamer: '蒸锅', rice_cooker: '电饭煲',
  oven: '烤箱', microwave: '微波炉', air_fryer: '空气炸锅', board: '菜板',
  knife: '菜刀', plate: '盘子', bowl: '小碗', large_bowl: '大碗'
}

export function uid() {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}-${Math.random().toString(36).slice(2)}`
}

export function newTask(recipeId) {
  return { id: uid(), recipe_id: recipeId, name: '', notes: '', duration_seconds: 60,
    attention_type: 'active', dependencies: [], resources: {} }
}

export function newRecipe() {
  const id = uid()
  return { schema_version: '1.0', recipe_id: id, name: '', servings: 2,
    ingredients: [], tasks: [newTask(id)], holds: [], max_holding_seconds: 300,
    favorite: false, confirmed: true, source_type: 'manual', estimated_fields: [] }
}

export function errorText(error) {
  const detail = error?.detail ?? error?.data?.detail
  if (typeof detail === 'string') return detail
  if (Array.isArray(detail)) return detail.map(item => item.msg || String(item)).join('；')
  if (typeof detail === 'object' && detail?.message) return detail.message
  return error?.message || '请求失败，请检查网络后重试。'
}

export function toast(message) {
  uni.showToast({ title: String(message), icon: 'none', duration: 2600 })
}

export function go(path, query = '') {
  uni.navigateTo({ url: `/pages/${path}${query}` })
}

export function tab(path) {
  uni.switchTab({ url: `/pages/${path}` })
}

export function formatSeconds(seconds) {
  const total = Math.max(0, Math.ceil(Number(seconds) || 0))
  const m = Math.floor(total / 60)
  return `${String(m).padStart(2, '0')}:${String(total % 60).padStart(2, '0')}`
}
