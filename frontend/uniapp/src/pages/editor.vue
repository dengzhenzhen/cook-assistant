<script setup>
import { ref } from 'vue'
import { onLoad } from '@dcloudio/uni-app'
import { api } from '../lib/client.js'
import { storage } from '../lib/storage.js'
import { queueEdit, flushEdits, pendingEdits } from '../lib/outbox.js'
import { cachedRecipes, cacheRecipes } from '../catalog-cache.js'
import { newRecipe, newTask, resourceNames, errorText, tab, toast } from '../utils.js'
import { editableIngredient, savedIngredient, scalingModes, ingredientRoles } from '../lib/ingredients.js'

const draft = ref(null)
const base = ref(null)
const error = ref('')
const saving = ref(false)

onLoad(async options => {
  const id = options.id
  if (!id) { draft.value = newRecipe(); return }
  const cachedDraft = storage.get(`draft:${id}`)
  if (cachedDraft) { draft.value = cachedDraft; ingredientsFromDraft(); return }
  const cached = cachedRecipes().find(r => r.recipe_id === id)
  if (cached) { base.value = JSON.parse(JSON.stringify(cached)); draft.value = JSON.parse(JSON.stringify(cached)) }
  try {
    const remote = await api.getRecipe(id)
    base.value = remote
    draft.value = JSON.parse(JSON.stringify(remote))
  } catch (e) { if (!draft.value) error.value = errorText(e) }
  const pending = pendingEdits().find(row => row.kind === 'recipe' && row.document.recipe_id === id)
  if (pending) { base.value = pending.base; draft.value = JSON.parse(JSON.stringify(pending.document)) }
  if (draft.value) ingredientsFromDraft()
})

function ingredientsFromDraft() {
  draft.value.ingredients = (draft.value.ingredients || []).map(editableIngredient)
}
function addIngredient() { draft.value.ingredients.push(editableIngredient()) }
function chooseRule(ingredient, event) { ingredient.scaling.mode = scalingModes[Number(event.detail.value)][0] }
function chooseRole(ingredient, event) { ingredient.role = ingredientRoles[Number(event.detail.value)][0] }
function ruleLabel(ingredient) { return scalingModes.find(option => option[0] === ingredient.scaling.mode)?.[1] || '自动参考' }
function roleLabel(ingredient) { return ingredientRoles.find(option => option[0] === ingredient.role)?.[1] || '主料' }
function addTask() { draft.value.tasks.push(newTask(draft.value.recipe_id)) }
function removeTask(index) {
  const task = draft.value.tasks[index]
  if (draft.value.tasks.length === 1) { toast('至少保留一个步骤'); return }
  if ((draft.value.holds || []).some(h => h.start_task === task.id || h.end_task === task.id)) { toast('该步骤被厨具持续占用引用，不能删除'); return }
  draft.value.tasks.splice(index, 1)
  draft.value.tasks.forEach(t => { t.dependencies = (t.dependencies || []).filter(id => id !== task.id) })
}
function toggleDep(task, id) {
  const values = task.dependencies || []
  task.dependencies = values.includes(id) ? values.filter(item => item !== id) : [...values, id]
}
function toggleResource(task, key) {
  const resources = { ...(task.resources || {}) }
  if (resources[key]) delete resources[key]
  else resources[key] = 1
  task.resources = resources
}
async function save() {
  if (saving.value) return
  const value = draft.value
  if (!value.name?.trim()) { error.value = '请填写菜名。'; return }
  if (Number(value.servings) < 1 || Number(value.servings) > 20) { error.value = '份数需为 1–20。'; return }
  let ingredients
  try { ingredients = value.ingredients.map(savedIngredient) }
  catch (e) { error.value = e.message; return }
  if (ingredients.some(i => !i.name)) { error.value = '食材名称不能为空。'; return }
  for (const task of value.tasks) {
    task.duration_seconds = Number(task.duration_seconds)
    if (!task.name?.trim() || !Number.isInteger(task.duration_seconds) || task.duration_seconds < 1 || task.duration_seconds > 86400) {
      error.value = '每个步骤需填写名称和 1–86400 秒时长。'; return
    }
  }
  value.servings = Number(value.servings)
  value.confirmed = true
  error.value = ''
  saving.value = true
  try {
    const saved = { ...value, ingredients }
    queueEdit('recipe', base.value, JSON.parse(JSON.stringify(saved)))
    const rows = cachedRecipes()
    cacheRecipes([saved, ...rows.filter(r => r.recipe_id !== value.recipe_id)])
    storage.remove(`draft:${value.recipe_id}`)
    try { await flushEdits() } catch (e) { toast(`已保存到本机，联网后再同步：${errorText(e)}`) }
    if (pendingEdits().some(row => row.document.recipe_id === value.recipe_id && row.status === 'conflict')) {
      error.value = '云端菜谱已变更。本机草稿已保留，请在“我的”里处理同步冲突。'
      return
    }
    tab('recipes')
  } catch (e) { error.value = errorText(e) }
  finally { saving.value = false }
}
</script>

<template>
  <view class="page" v-if="draft">
    <text class="title">{{ draft.confirmed === false ? '确认识别结果' : '编辑菜谱' }}</text>
    <text v-if="draft.confirmed === false" class="subtitle">请核对 AI 识别的食材、时长、依赖和资源后保存。</text>
    <label class="field">菜名<input v-model="draft.name" class="input" maxlength="80" /></label>
    <label class="field">原配方份数<input v-model="draft.servings" class="input" type="number" /></label>
    <text class="section">结构化食材与换算规则</text>
    <text class="subtitle">每种材料可采用不同曲线。自动规则是参考值，水量、盐度与锅底油请按实际配方确认。</text>
    <view v-for="(ingredient, index) in draft.ingredients" :key="index" class="card">
      <view class="row"><text>食材 {{ index + 1 }}</text><text class="danger" @click="draft.ingredients.splice(index, 1)">删除</text></view>
      <label class="field">名称<input v-model="ingredient.name" class="input" maxlength="100" placeholder="例如：生抽" /></label>
      <view class="row"><label class="field ingredient-field">原用量<input v-model="ingredient.quantity" class="input" maxlength="80" placeholder="10、1/2、2–3、适量" /></label><label class="field ingredient-field">单位<input v-model="ingredient.unit" class="input" maxlength="30" placeholder="g、ml、个" /></label></view>
      <view class="row"><picker :range="ingredientRoles.map(option => option[1])" @change="chooseRole(ingredient, $event)"><text class="chip">{{ roleLabel(ingredient) }} ›</text></picker><picker :range="scalingModes.map(option => option[1])" @change="chooseRule(ingredient, $event)"><text class="chip">{{ ruleLabel(ingredient) }} ›</text></picker></view>
      <label v-if="ingredient.scaling.mode === 'power'" class="field">指数（1 为按比例；小于 1 表示增量较缓）<input v-model="ingredient.scaling.exponent" class="input" type="digit" /></label>
      <label v-if="ingredient.scaling.mode === 'affine'" class="field">固定占比（0–1，剩余部分按比例）<input v-model="ingredient.scaling.fixed_fraction" class="input" type="digit" /></label>
      <label v-if="ingredient.scaling.mode === 'piecewise'" class="field">分段节点：份数倍率 | 用量倍率<textarea v-model="ingredient.curveText" class="textarea" placeholder="0.5 | 0.7&#10;1 | 1&#10;2 | 1.6" /></label>
      <label class="field">配方依据 / 提醒<input v-model="ingredient.scaling.note" class="input" maxlength="300" placeholder="例如：锅底油不随人数完全增加" /></label>
    </view>
    <button class="secondary" @click="addIngredient">＋ 增加食材</button>
    <text class="section">烹饪步骤</text>
    <view v-for="(task, index) in draft.tasks" :key="task.id" class="card">
      <view class="row"><text class="section">步骤 {{ index + 1 }}</text><text class="danger" @click="removeTask(index)">删除</text></view>
      <label class="field">操作名称<input v-model="task.name" class="input" placeholder="例如：切番茄" /></label>
      <label class="field">备注<textarea v-model="task.notes" class="textarea" maxlength="4000" placeholder="火候、翻炒时间与调味时机" /></label>
      <label class="field">预计时长（秒）<input v-model="task.duration_seconds" class="input" type="number" /></label>
      <text class="muted">关注方式</text>
      <view><text v-for="option in [['active','持续操作'],['intermittent','间歇看管'],['passive','设备自动']]" :key="option[0]" class="chip" :class="{ active: task.attention_type === option[0] }" @click="task.attention_type = option[0]">{{ option[1] }}</text></view>
      <text class="muted label">前置步骤</text>
      <view><text v-for="other in draft.tasks.filter(t => t.id !== task.id)" :key="other.id" class="chip" :class="{ active: task.dependencies?.includes(other.id) }" @click="toggleDep(task, other.id)">{{ other.name || '未命名步骤' }}</text><text v-if="draft.tasks.length === 1" class="muted">可独立开始</text></view>
      <text class="muted label">本步骤占用厨具</text>
      <view><text v-for="(name, key) in resourceNames" :key="key" class="chip" :class="{ active: task.resources?.[key] }" @click="toggleResource(task, key)">{{ name }}</text></view>
    </view>
    <button class="secondary" @click="addTask">＋ 增加步骤</button>
    <text v-if="draft.holds?.length" class="muted">已保留 AI 识别到的跨步骤厨具占用。</text>
    <text v-if="error" class="error">{{ error }}</text>
    <button class="primary" :disabled="saving" @click="save">{{ saving ? '正在保存…' : '确认内容并保存' }}</button>
  </view>
  <view v-else class="page"><text class="muted">{{ error || '正在加载菜谱…' }}</text></view>
</template>

<style scoped>
.label { display: block; margin-top: 20rpx; }
.ingredient-field { flex: 1; min-width: 0; }
</style>
