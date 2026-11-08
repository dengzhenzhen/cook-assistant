<script setup>
import { ref, computed } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import { api, auth } from '../lib/client.js'
import { storage, selected } from '../lib/storage.js'
import { flushEdits, pendingEdits } from '../lib/outbox.js'
import { cachedRecipes, cacheRecipes, overlayPending } from '../catalog-cache.js'
import { errorText, go, tab } from '../utils.js'
import MealIngredients from '../components/MealIngredients.vue'

const recipes = ref([])
const chosen = ref([])
const kitchen = ref(null)
const useTarget = ref(false)
const date = ref('')
const time = ref('')
const generating = ref(false)
const error = ref('')
const servings = ref({})
const previews = ref({})
const previewing = ref(false)
let previewSequence = 0
const chosenRecipes = computed(() => recipes.value.filter(r => chosen.value.includes(r.recipe_id)))

onShow(async () => {
  if (!auth.value) { go('login'); return }
  recipes.value = overlayPending(cachedRecipes(), pendingEdits())
  kitchen.value = storage.get('kitchen')
  chosen.value = selected.get()
  servings.value = storage.get('meal_servings') || {}
  previews.value = {}
  const next = new Date(Date.now() + 3600000)
  date.value = `${next.getFullYear()}-${String(next.getMonth() + 1).padStart(2, '0')}-${String(next.getDate()).padStart(2, '0')}`
  time.value = `${String(next.getHours()).padStart(2, '0')}:${String(next.getMinutes()).padStart(2, '0')}`
  try {
    kitchen.value = await api.kitchen(); storage.set('kitchen', kitchen.value)
    recipes.value = overlayPending(await api.recipes(), pendingEdits()); cacheRecipes(recipes.value)
  } catch (e) { if (!auth.value) go('login'); else error.value = errorText(e) }
})

function portion(recipe) { return servings.value[recipe.recipe_id] ?? recipe.servings }
function changePortion(recipe, event) {
  const value = Number(event.detail.value)
  servings.value = { ...servings.value, [recipe.recipe_id]: value }
  storage.set('meal_servings', servings.value)
  previews.value = {}
  previewSequence++
}
function portionSelection() {
  const values = Object.fromEntries(chosenRecipes.value.map(recipe => [recipe.recipe_id, Number(portion(recipe))]))
  if (Object.values(values).some(value => !Number.isInteger(value) || value < 1 || value > 20)) throw new Error('本餐份数需为 1–20 的整数。')
  return values
}
async function preview() {
  if (previewing.value) return
  previewing.value = true; error.value = ''
  const sequence = ++previewSequence
  try {
    const values = portionSelection()
    await flushEdits()
    if (pendingEdits().length) throw new Error('请先联网同步菜谱修改或处理冲突，再预览本餐用量。')
    const results = await Promise.all(chosenRecipes.value.map(recipe => api.scaleRecipe(recipe.recipe_id, values[recipe.recipe_id])))
    if (sequence === previewSequence) previews.value = Object.fromEntries(results.map(result => [result.recipe_id, result]))
  } catch (e) { error.value = errorText(e) }
  finally { previewing.value = false }
}

async function generate() {
  if (generating.value || !chosenRecipes.value.length || !kitchen.value) return
  generating.value = true; error.value = ''
  try {
    await flushEdits()
    if (pendingEdits().length) throw new Error('本机有未同步的菜谱或厨房修改，请先联网同步或处理冲突。')
    const target = useTarget.value ? new Date(`${date.value}T${time.value}:00`).toISOString() : null
    const recipeIds = chosenRecipes.value.map(r => r.recipe_id)
    const constraints = storage.get('meal_constraints')
    const sameMenu = constraints?.recipe_ids?.length === recipeIds.length && recipeIds.every(id => constraints.recipe_ids.includes(id))
    const preferences = sameMenu ? { mode: constraints.mode, time_minutes: constraints.time_minutes, effort: constraints.effort } : null
    const snapshot = await api.plan(recipeIds, kitchen.value.kitchen_id, target, portionSelection(), preferences)
    storage.set('latest_plan', snapshot)
    go('timeline')
  } catch (e) { error.value = errorText(e) }
  finally { generating.value = false }
}
</script>

<template>
  <view class="page">
    <text class="title">今晚的饭，安排一下</text>
    <text class="subtitle">选择菜谱和厨房设备，生成可执行的烹饪计划。</text>
    <view v-if="!chosenRecipes.length" class="card muted" @click="tab('recipes')">还没选菜，去菜谱页挑几道吧 ›</view>
    <view v-for="recipe in chosenRecipes" :key="recipe.recipe_id" class="card">
      <view class="row"><text>{{ recipe.name }}</text><text class="muted">原配方 {{ recipe.servings }} 人份 · {{ recipe.tasks?.length }} 步</text></view>
      <label class="field">本餐份数<input :value="portion(recipe)" class="input" type="number" @input="changePortion(recipe, $event)" /></label>
    </view>
    <template v-if="chosenRecipes.length">
      <button class="secondary" :disabled="previewing" @click="preview">{{ previewing ? '正在换算…' : '预览本餐食材用量' }}</button>
      <text class="subtitle">按每种食材自己的曲线换算；时长、火候及锅具容量仍需核对。步骤中的数字不自动改写。</text>
      <MealIngredients :snapshots="previews" />
    </template>
    <view class="card row" @click="go('kitchen')"><text>我的厨房</text><text class="muted">{{ kitchen ? `${kitchen.cook_count} 人 · ${kitchen.capacities?.burner || 0} 个灶眼` : '读取中' }} ›</text></view>
    <view class="card"><view class="row"><text>指定开饭时间</text><switch :checked="useTarget" color="#c45230" @change="useTarget = $event.detail.value" /></view><text class="muted">不指定时按尽快完成安排。</text>
      <view v-if="useTarget" class="row time-picker"><picker mode="date" :value="date" @change="date = $event.detail.value"><text class="chip">{{ date }}</text></picker><picker mode="time" :value="time" @change="time = $event.detail.value"><text class="chip">{{ time }}</text></picker></view>
    </view>
    <text v-if="error" class="error">{{ error }}</text>
    <button class="primary" :disabled="generating || !chosenRecipes.length || !kitchen" @click="generate">{{ generating ? '正在安排锅灶和时间…' : '生成烹饪计划' }}</button>
    <button class="secondary" @click="go('execute')">继续烹饪 / 恢复会话</button>
    <button class="secondary" @click="go('timeline')">查看上次计划</button>
  </view>
</template>

<style scoped>
.time-picker { justify-content: flex-start; margin-top: 18rpx; }
</style>
