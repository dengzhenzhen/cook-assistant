export const scalingModes = [
  ['auto', '自动参考'], ['linear', '按比例'], ['power', '指数曲线'], ['affine', '固定＋变量'],
  ['fixed', '固定用量'], ['manual', '手动确认'], ['piecewise', '分段曲线']
]
export const ingredientRoles = [['main', '主料'], ['secondary', '辅料'], ['seasoning', '调味料'], ['liquid', '水 / 汤汁'], ['other', '其他']]
export function editableIngredient(value = {}) {
  return { ...value, name: value.name || '', quantity: value.quantity || '', unit: value.unit || '',
    role: value.role || 'main', scaling: { mode: 'auto', exponent: 0.8, fixed_fraction: 0.3, points: [], note: '', ...value.scaling },
    curveText: (value.scaling?.points || []).map(p => `${p.ratio} | ${p.factor}`).join('\n') }
}
export function savedIngredient(value) {
  const { curveText, amount, ...ingredient } = value
  const scaling = { ...ingredient.scaling, exponent: Number(ingredient.scaling.exponent), fixed_fraction: Number(ingredient.scaling.fixed_fraction) }
  if (!Number.isFinite(scaling.exponent) || scaling.exponent < 0.1 || scaling.exponent > 2) throw new Error('指数需为 0.1–2。')
  if (!Number.isFinite(scaling.fixed_fraction) || scaling.fixed_fraction < 0 || scaling.fixed_fraction > 1) throw new Error('固定占比需为 0–1。')
  if (scaling.mode === 'piecewise') {
    scaling.points = String(curveText || '').split('\n').filter(line => line.trim()).map(line => {
      const parts = line.split('|').map(item => item.trim())
      if (parts.length !== 2 || parts.some(item => item === '' || !Number.isFinite(Number(item)))) throw new Error('分段曲线每行填写：份数倍率 | 用量倍率。')
      return { ratio: Number(parts[0]), factor: Number(parts[1]) }
    })
    if (scaling.points.length < 2 || scaling.points.length > 12 || !scaling.points.some(p => p.ratio === 1 && p.factor === 1) ||
        scaling.points.some((p, i, points) => p.ratio <= 0 || p.ratio > 20 || p.factor < 0 || p.factor > 40 ||
          (i > 0 && (p.ratio <= points[i - 1].ratio || p.factor < points[i - 1].factor)))) {
      throw new Error('分段曲线需有 2–12 个递增节点，并包含 1 | 1；用量倍率不能下降。')
    }
  }
  // Reparse edited quantity on the server; never retain stale numeric metadata.
  return { ...ingredient, name: ingredient.name.trim(), quantity: String(ingredient.quantity).trim(), unit: ingredient.unit.trim(), scaling }
}
