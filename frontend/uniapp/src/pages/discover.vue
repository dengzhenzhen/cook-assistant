<script setup>
import { computed, ref } from 'vue'
import { onShow, onHide, onUnload } from '@dcloudio/uni-app'
import { api, auth } from '../lib/client.js'
import { storage, selected, getAccount } from '../lib/storage.js'
import { candidateSummary, cleanName, editDish, menuRequest, menuSettings, normalizeDishes, resolveRowsSafely, settingsForMode } from '../lib/menu.js'
import { errorText, go, tab, toast, uid } from '../utils.js'

const modes = [
  { value: 'quick', label: '10分钟快手菜' },
  { value: 'everyday', label: '普通一顿' },
  { value: 'feast', label: '吃顿好的' },
]
const effortOptions = [
  { value: 'low', label: '省事' },
  { value: 'medium', label: '适中' },
  { value: 'high', label: '愿意多花功夫' },
]
const settings = ref(menuSettings())
const dishes = ref([])
const warnings = ref([])
const chosen = ref([])
const generating = ref(false)
const error = ref('')
const ingredientsText = ref('')
const resolving = ref(false)
const busy = computed(() => generating.value || resolving.value)
let timer = null
let polling = false
let pageAccount = null
let visible = false

function withIds(rows) { return rows.map(dish => ({ ...dish, row_id: dish.row_id || uid() })) }
function stopPolling() { if (timer) clearInterval(timer); timer = null }

function save() {
  if (!pageAccount || getAccount() !== pageAccount) return
  storage.set('menu_draft', { settings: settings.value, ingredientsText: ingredientsText.value, dishes: dishes.value, warnings: warnings.value })
}

onShow(() => {
  stopPolling()
  visible = true
  if (!auth.value) { pageAccount = null; go('login'); return }
  pageAccount = getAccount()
  const draft = storage.get('menu_draft')
  settings.value = menuSettings(draft?.settings || {})
  ingredientsText.value = draft?.ingredientsText || ''
  dishes.value = withIds(normalizeDishes(draft?.dishes))
  warnings.value = Array.isArray(draft?.warnings) ? draft.warnings : []
  chosen.value = selected.get()
  error.value = ''
  startPolling()
  const reviewed = dishes.value.filter(dish => dish.resolution?.status === 'needs_review' && dish.review_opened && dish.resolution.recipe_id && !storage.get(`draft:${dish.resolution.recipe_id}`))
  if (reviewed.length) resolveRows(reviewed)
})
onHide(() => { visible = false; stopPolling() })
onUnload(() => { visible = false; stopPolling() })

function setMode(mode) { if (busy.value) return; settings.value = settingsForMode(mode, settings.value); save() }
function changeCount(delta) { if (busy.value) return; settings.value = menuSettings({ ...settings.value, dish_count: settings.value.dish_count + delta }); save() }
function changeServings(delta) { if (busy.value) return; settings.value = menuSettings({ ...settings.value, servings: settings.value.servings + delta }); save() }
function setTime(value) { if (busy.value) return; settings.value = menuSettings({ ...settings.value, time_minutes: value }); save() }
function setEffort(value) { if (busy.value) return; settings.value = menuSettings({ ...settings.value, effort: value }); save() }
function changeIngredients(event) { if (busy.value) return; ingredientsText.value = event.detail.value; save() }

function changeName(index, event) {
  if (busy.value) return
  dishes.value = editDish(dishes.value, index, event.detail.value)
  save()
}
function tidyDishes() { if (busy.value) return; dishes.value = withIds(normalizeDishes(dishes.value)); save() }
function addDish() {
  if (busy.value || dishes.value.length >= 6) return
  dishes.value = [...dishes.value, { row_id: uid(), name: '', reason: '', estimated_minutes: null, effort: null }]
  save()
}
function removeDish(index) { if (busy.value) return; dishes.value = dishes.value.filter((_, position) => position !== index); save() }

async function generate() {
  if (busy.value || getAccount() !== pageAccount) return
  tidyDishes()
  const account = getAccount()
  let request
  try { request = menuRequest(settings.value, dishes.value, ingredientsText.value) }
  catch (cause) { error.value = cause.message; return }
  generating.value = true
  error.value = ''
  try {
    const result = await api.recommendMenu(request)
    if (getAccount() !== account) return
    dishes.value = withIds(normalizeDishes(result.dishes, settings.value.dish_count))
    warnings.value = Array.isArray(result.warnings) ? result.warnings : []
    save()
  } catch (cause) {
    if (getAccount() !== account) return
    error.value = errorText(cause)
  } finally { generating.value = false }
}

function chooseDish(dish) {
  if (busy.value || getAccount() !== pageAccount) return
  const recipeId = dish.resolution?.status === 'matched' ? dish.resolution.recipe_id : dish.matched_recipe_id
  if (!recipeId) return
  selected.set([...selected.get(), recipeId])
  storage.set('meal_servings', { ...(storage.get('meal_servings') || {}), [recipeId]: settings.value.servings })
  storage.set('meal_constraints', { recipe_ids: selected.get(), time_minutes: settings.value.time_minutes, effort: settings.value.effort, mode: settings.value.mode })
  chosen.value = selected.get()
  toast('已加入做饭计划')
}

function chooseAll() {
  if (busy.value) return
  const ready = dishes.value.filter(dish => dish.resolution?.status === 'matched' || (!dish.resolution && dish.matched_recipe_id))
  for (const dish of ready) chooseDish(dish)
}

async function resolveRows(rows) {
  if (busy.value || !rows.length || getAccount() !== pageAccount) return
  const account = getAccount()
  const requested = rows.map(dish => ({ row_id: dish.row_id, name: cleanName(dish.name), choice_recipe_id: dish.choice_recipe_id }))
  const names = requested.map(dish => dish.name)
  if (names.some(name => !name)) { error.value = '请先填写每道菜的名称。'; return }
  resolving.value = true
  error.value = ''
  try {
    const updated = await resolveRowsSafely(api.resolveMenu, requested, () => dishes.value, () => getAccount() === account)
    if (!updated) return
    dishes.value = updated
    save()
    startPolling()
  } catch (cause) {
    if (getAccount() !== account) return
    error.value = `${errorText(cause)}。处理结果未确认，请手动重试；重试可能消耗 AI 配额。`
  } finally { resolving.value = false }
}

function confirmMenu() {
  if (busy.value) return
  tidyDishes()
  resolveRows(dishes.value.filter(dish => !dish.resolution))
}
function retryDish(dish) { if (!busy.value) resolveRows([dish]) }
function chooseCandidate(dish, recipeId) {
  if (busy.value) return
  dishes.value = dishes.value.map(row => row.row_id === dish.row_id ? { ...row, choice_recipe_id: recipeId } : row)
  save()
  resolveRows(dishes.value.filter(row => row.row_id === dish.row_id))
}
function reviewDish(dish) {
  if (busy.value) return
  const id = dish.resolution?.recipe_id
  if (!id) return
  dishes.value = dishes.value.map(row => row.row_id === dish.row_id ? { ...row, review_opened: true } : row)
  save()
  go('editor', `?id=${encodeURIComponent(id)}`)
}

async function pollJobs() {
  if (polling || getAccount() !== pageAccount) return
  polling = true
  const account = getAccount()
  try {
    for (const dish of dishes.value.filter(row => row.resolution?.status === 'import_pending')) {
      const { row_id, name } = dish
      const jobId = dish.resolution.job_id
      if (!jobId) continue
      try {
        const job = await api.importJob(jobId)
        if (getAccount() !== account) return
        const current = dishes.value.find(row => row.row_id === row_id && cleanName(row.name) === cleanName(name) && row.resolution?.job_id === jobId)
        if (!current) continue
        if (job.status === 'completed' && job.recipe?.recipe_id) {
          storage.set(`draft:${job.recipe.recipe_id}`, job.recipe)
          dishes.value = dishes.value.map(row => row.row_id === row_id ? { ...row, resolution: { status: 'needs_review', recipe_id: job.recipe.recipe_id } } : row)
          save()
          toast(`${name} 的菜谱草稿已生成，请审核保存`)
        } else if (job.status === 'failed') {
          dishes.value = dishes.value.map(row => row.row_id === row_id ? { ...row, resolution: { status: 'failed', error: job.error || '导入失败' } } : row)
          save()
        }
      } catch (cause) {
        if (getAccount() !== account) return
        error.value = `检查 ${name} 的导入进度失败：${errorText(cause)}`
      }
    }
  } finally {
    polling = false
    if (!dishes.value.some(dish => dish.resolution?.status === 'import_pending')) stopPolling()
  }
}
function startPolling() {
  stopPolling()
  if (!visible || !dishes.value.some(dish => dish.resolution?.status === 'import_pending')) return
  pollJobs()
  timer = setInterval(pollJobs, 2500)
}
</script>

<template>
  <view class="page">
    <text class="title">今天吃什么？</text>
    <text class="subtitle">选个节奏，先凑一桌菜单。菜谱和时间仍需确认。</text>

    <view class="card">
      <text class="section first-section">想吃哪种？</text>
      <view class="choices" :class="{ locked: busy }"><text v-for="mode in modes" :key="mode.value" class="chip" :class="{ active: settings.mode === mode.value }" @click="setMode(mode.value)">{{ mode.label }}</text></view>
      <view class="stepper row"><text>几人吃</text><view class="stepper-controls"><button class="small" :disabled="busy || settings.servings <= 1" @click="changeServings(-1)">−</button><text>{{ settings.servings }} 人</text><button class="small" :disabled="busy || settings.servings >= 20" @click="changeServings(1)">＋</button></view></view>
      <view class="stepper row"><text>几道菜</text><view class="stepper-controls"><button class="small" :disabled="busy || settings.dish_count <= 1" @click="changeCount(-1)">−</button><text>{{ settings.dish_count }} 道</text><button class="small" :disabled="busy || settings.dish_count >= 6" @click="changeCount(1)">＋</button></view></view>
      <view class="field"><text>希望多久做好</text><view class="choices" :class="{ locked: busy }"><text v-for="minutes in [10, 30, 60]" :key="minutes" class="chip" :class="{ active: settings.time_minutes === minutes }" @click="setTime(minutes)">{{ minutes }} 分钟</text></view><view class="custom-time"><input class="input time-input" type="number" :value="settings.time_minutes" :disabled="busy" @change="setTime($event.detail.value)" /><text class="muted">分钟，可自定 1–240</text></view></view>
      <view class="field"><text>愿意花多少功夫</text><view class="choices" :class="{ locked: busy }"><text v-for="option in effortOptions" :key="option.value" class="chip" :class="{ active: settings.effort === option.value }" @click="setEffort(option.value)">{{ option.label }}</text></view></view>
      <label class="field">手头已有食材（可选）<textarea class="textarea ingredients-input" :value="ingredientsText" :disabled="busy" maxlength="1300" placeholder="例如：番茄、鸡蛋、青椒；用逗号、顿号或换行分隔" @input="changeIngredients" /></label>
      <text class="muted">最多 30 项，每项最多 40 字。推荐会优先考虑这些食材。</text>
    </view>

    <button class="primary" :disabled="busy" @click="generate">{{ generating ? '正在搭配菜单…' : dishes.length ? '换一批' : '推荐一桌菜' }}</button>
    <text v-if="error" class="error">{{ error }}。菜单草稿已保留，可重试。</text>
    <text v-for="(warning, index) in warnings" :key="index" class="muted warning">{{ warning }}</text>

    <view v-if="dishes.length" class="menu-section">
      <text class="section">菜单草稿</text>
      <text class="muted">可修改菜名。理由和时间是估计，完整菜谱后验证。</text>
      <view v-for="(dish, index) in dishes" :key="dish.row_id" class="card dish">
        <view class="row"><text class="dish-number">{{ index + 1 }}.</text><input class="input dish-input" :value="dish.name" :disabled="busy" maxlength="80" placeholder="输入菜名" @input="changeName(index, $event)" @blur="tidyDishes" /><text class="remove" :class="{ locked: busy }" @click="removeDish(index)">移除</text></view>
        <text v-if="dish.reason" class="reason">{{ dish.reason }}</text>
        <text v-if="dish.estimated_minutes" class="muted estimate">约 {{ dish.estimated_minutes }} 分钟 · 估计，完整菜谱后验证</text>
        <view class="dish-actions">
          <button v-if="dish.resolution?.status === 'matched' || (!dish.resolution && dish.matched_recipe_id)" class="secondary inline-button" :disabled="busy || chosen.includes(dish.resolution?.recipe_id || dish.matched_recipe_id)" @click="chooseDish(dish)">{{ chosen.includes(dish.resolution?.recipe_id || dish.matched_recipe_id) ? '已加入计划' : '加入做饭计划' }}</button>
          <view v-if="dish.resolution?.status === 'needs_choice'"><text class="muted">找到相似菜谱，请选择一份：</text><view class="choices" :class="{ locked: busy }"><text v-for="candidate in dish.resolution.candidates || []" :key="candidate.recipe_id" class="chip" @click="chooseCandidate(dish, candidate.recipe_id)">{{ candidateSummary(candidate) }}</text></view></view>
          <button v-if="dish.resolution?.status === 'needs_review'" class="secondary inline-button" :disabled="busy" @click="reviewDish(dish)">审核菜谱并保存</button>
          <text v-if="dish.resolution?.status === 'import_pending'" class="muted">正在生成菜谱草稿…离开页面后可继续查看进度。</text>
          <view v-if="dish.resolution?.status === 'failed'"><text class="error">{{ dish.resolution.error || '处理失败' }}</text><button class="secondary inline-button" :disabled="busy" @click="retryDish(dish)">只重试这道菜</button></view>
        </view>
      </view>
      <button v-if="dishes.length < 6" class="secondary" :disabled="busy" @click="addDish">＋ 加一道菜</button>
      <button class="primary" :disabled="busy || !dishes.some(dish => !dish.resolution)" @click="confirmMenu">{{ resolving ? '正在检查并导入…' : '确认菜单，准备菜谱' }}</button>
      <button v-if="dishes.some(dish => dish.resolution?.status === 'matched' || (!dish.resolution && dish.matched_recipe_id))" class="secondary" :disabled="busy" @click="chooseAll">将可用菜谱加入做饭计划</button>
      <button v-if="chosen.length" class="secondary" @click="tab('plan')">查看做饭计划（已选 {{ chosen.length }} 道）</button>
    </view>
  </view>
</template>

<style scoped>
.first-section { margin-top: 0; }
.choices { display: flex; flex-wrap: wrap; }
.stepper { margin-top: 26rpx; min-height: 70rpx; font-size: 28rpx; }
.stepper-controls { display: flex; align-items: center; gap: 14rpx; }
.stepper-controls text { min-width: 78rpx; text-align: center; }
.small { width: 56rpx; height: 56rpx; line-height: 56rpx; padding: 0; margin: 0; font-size: 30rpx; background: #e8eee3; color: #34573b; }
.custom-time { display: flex; align-items: center; gap: 14rpx; margin-top: 12rpx; }
.time-input { width: 120rpx; height: 70rpx; min-height: 70rpx; margin: 0; }
.warning { display: block; margin-top: 14rpx; }
.menu-section { margin-top: 32rpx; }
.dish .row { justify-content: flex-start; }
.dish-number { font-weight: 650; }
.dish-input { flex: 1; width: 0; margin: 0; }
.remove { color: #ad3d2b; font-size: 24rpx; white-space: nowrap; }
.reason { display: block; margin-top: 16rpx; line-height: 1.5; font-size: 26rpx; }
.estimate { display: block; margin-top: 8rpx; }
.dish-actions { margin-top: 12rpx; }
.inline-button { display: inline-block; margin: 0; font-size: 24rpx; }
.ingredients-input { height: 150rpx; min-height: 150rpx; }
.locked { opacity: .55; }
</style>
