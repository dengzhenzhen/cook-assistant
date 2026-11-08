<script setup>
import { ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import { api, auth } from '../lib/client.js'
import { storage, selected, getAccount } from '../lib/storage.js'
import { editDish, menuRequest, menuSettings, normalizeDishes, settingsForMode } from '../lib/menu.js'
import { errorText, go, tab, toast } from '../utils.js'

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

function save() {
  if (!getAccount()) return
  storage.set('menu_draft', { settings: settings.value, dishes: dishes.value, warnings: warnings.value })
}

onShow(() => {
  if (!auth.value) { go('login'); return }
  const draft = storage.get('menu_draft')
  settings.value = menuSettings(draft?.settings || {})
  dishes.value = normalizeDishes(draft?.dishes)
  warnings.value = Array.isArray(draft?.warnings) ? draft.warnings : []
  chosen.value = selected.get()
  error.value = ''
})

function setMode(mode) { settings.value = settingsForMode(mode, settings.value); save() }
function changeCount(delta) { settings.value = menuSettings({ ...settings.value, dish_count: settings.value.dish_count + delta }); save() }
function changeServings(delta) { settings.value = menuSettings({ ...settings.value, servings: settings.value.servings + delta }); save() }
function setTime(value) { settings.value = menuSettings({ ...settings.value, time_minutes: value }); save() }
function setEffort(value) { settings.value = menuSettings({ ...settings.value, effort: value }); save() }

function changeName(index, event) {
  dishes.value = editDish(dishes.value, index, event.detail.value)
  save()
}
function tidyDishes() { dishes.value = normalizeDishes(dishes.value); save() }
function addDish() {
  if (dishes.value.length >= 6) return
  dishes.value = [...dishes.value, { name: '', reason: '', estimated_minutes: null, effort: null }]
  save()
}
function removeDish(index) { dishes.value = dishes.value.filter((_, position) => position !== index); save() }

async function generate() {
  if (generating.value) return
  tidyDishes()
  const account = getAccount()
  const request = menuRequest(settings.value, dishes.value)
  generating.value = true
  error.value = ''
  try {
    const result = await api.recommendMenu(request)
    if (getAccount() !== account) return
    dishes.value = normalizeDishes(result.dishes, settings.value.dish_count)
    warnings.value = Array.isArray(result.warnings) ? result.warnings : []
    save()
  } catch (cause) {
    if (getAccount() !== account) return
    error.value = errorText(cause)
  } finally { generating.value = false }
}

function chooseDish(dish) {
  if (!dish.matched_recipe_id) return
  selected.set([...selected.get(), dish.matched_recipe_id])
  storage.set('meal_servings', { ...(storage.get('meal_servings') || {}), [dish.matched_recipe_id]: settings.value.servings })
  chosen.value = selected.get()
  toast('已加入做饭计划')
}
</script>

<template>
  <view class="page">
    <text class="title">今天吃什么？</text>
    <text class="subtitle">选个节奏，先凑一桌菜单。菜谱和时间仍需确认。</text>

    <view class="card">
      <text class="section first-section">想吃哪种？</text>
      <view class="choices"><text v-for="mode in modes" :key="mode.value" class="chip" :class="{ active: settings.mode === mode.value }" @click="setMode(mode.value)">{{ mode.label }}</text></view>
      <view class="stepper row"><text>几人吃</text><view class="stepper-controls"><button class="small" :disabled="settings.servings <= 1" @click="changeServings(-1)">−</button><text>{{ settings.servings }} 人</text><button class="small" :disabled="settings.servings >= 20" @click="changeServings(1)">＋</button></view></view>
      <view class="stepper row"><text>几道菜</text><view class="stepper-controls"><button class="small" :disabled="settings.dish_count <= 1" @click="changeCount(-1)">−</button><text>{{ settings.dish_count }} 道</text><button class="small" :disabled="settings.dish_count >= 6" @click="changeCount(1)">＋</button></view></view>
      <view class="field"><text>希望多久做好</text><view class="choices"><text v-for="minutes in [10, 30, 60]" :key="minutes" class="chip" :class="{ active: settings.time_minutes === minutes }" @click="setTime(minutes)">{{ minutes }} 分钟</text></view><view class="custom-time"><input class="input time-input" type="number" :value="settings.time_minutes" @change="setTime($event.detail.value)" /><text class="muted">分钟，可自定 1–240</text></view></view>
      <view class="field"><text>愿意花多少功夫</text><view class="choices"><text v-for="option in effortOptions" :key="option.value" class="chip" :class="{ active: settings.effort === option.value }" @click="setEffort(option.value)">{{ option.label }}</text></view></view>
    </view>

    <button class="primary" :disabled="generating" @click="generate">{{ generating ? '正在搭配菜单…' : dishes.length ? '换一批' : '推荐一桌菜' }}</button>
    <text v-if="error" class="error">{{ error }}。菜单草稿已保留，可重试。</text>
    <text v-for="(warning, index) in warnings" :key="index" class="muted warning">{{ warning }}</text>

    <view v-if="dishes.length" class="menu-section">
      <text class="section">菜单草稿</text>
      <text class="muted">可修改菜名。理由和时间是估计，完整菜谱后验证。</text>
      <view v-for="(dish, index) in dishes" :key="index" class="card dish">
        <view class="row"><text class="dish-number">{{ index + 1 }}.</text><input class="input dish-input" :value="dish.name" maxlength="80" placeholder="输入菜名" @input="changeName(index, $event)" @blur="tidyDishes" /><text class="remove" @click="removeDish(index)">移除</text></view>
        <text v-if="dish.reason" class="reason">{{ dish.reason }}</text>
        <text v-if="dish.estimated_minutes" class="muted estimate">约 {{ dish.estimated_minutes }} 分钟 · 估计，完整菜谱后验证</text>
        <view class="dish-actions"><button v-if="dish.matched_recipe_id" class="secondary inline-button" :disabled="chosen.includes(dish.matched_recipe_id)" @click="chooseDish(dish)">{{ chosen.includes(dish.matched_recipe_id) ? '已加入计划' : '加入做饭计划' }}</button><button v-else class="secondary inline-button" @click="go('import')">暂无菜谱 · 去导入</button></view>
      </view>
      <button v-if="dishes.length < 6" class="secondary" @click="addDish">＋ 加一道菜</button>
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
</style>
