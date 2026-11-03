<script setup>
import { ref, computed } from 'vue'
import { onShow, onPullDownRefresh } from '@dcloudio/uni-app'
import { api, auth } from '../lib/client.js'
import { selected } from '../lib/storage.js'
import { queueEdit, flushEdits } from '../lib/outbox.js'
import { pendingEdits } from '../lib/outbox.js'
import { cachedRecipes, cacheRecipes, overlayPending } from '../catalog-cache.js'
import { errorText, go, tab, toast } from '../utils.js'

const recipes = ref([])
const chosen = ref([])
const loading = ref(false)
const error = ref('')
const filter = ref('all')
const shown = computed(() => recipes.value.filter(r => filter.value === 'all' ||
  (filter.value === 'favorite' && r.favorite) || (filter.value === 'selected' && chosen.value.includes(r.recipe_id))))

async function load() {
  if (!auth.value) { go('login'); return }
  chosen.value = selected.get()
  recipes.value = overlayPending(cachedRecipes(), pendingEdits())
  loading.value = true
  try {
    recipes.value = overlayPending(await api.recipes(), pendingEdits())
    cacheRecipes(recipes.value)
    error.value = ''
  } catch (e) { if (!auth.value) { recipes.value = []; go('login') } else error.value = errorText(e) }
  finally { loading.value = false; uni.stopPullDownRefresh() }
}
onShow(load)
onPullDownRefresh(load)

function toggle(recipe) {
  selected.toggle(recipe.recipe_id)
  chosen.value = selected.get()
}

async function favorite(recipe) {
  const updated = { ...recipe, favorite: !recipe.favorite }
  try {
    queueEdit('recipe', recipe, updated)
    recipes.value = recipes.value.map(r => r.recipe_id === updated.recipe_id ? updated : r)
    cacheRecipes(recipes.value)
    try { await flushEdits() } catch (_) { toast('收藏已保存到本机，联网后同步。') }
  } catch (e) { toast(errorText(e)) }
}

function edit(recipe) { go('editor', `?id=${encodeURIComponent(recipe.recipe_id)}`) }
</script>

<template>
  <view class="page">
    <text class="title">今天想吃什么？</text>
    <text class="subtitle">收藏菜谱，挑几道菜，一起安排开饭。</text>
    <view class="actions"><button class="secondary" @click="go('import')">导入菜谱</button><button class="secondary" @click="go('editor')">手动创建</button></view>
    <view><text v-for="item in [['all','全部'],['favorite','收藏'],['selected','今晚想做']]" :key="item[0]" class="chip" :class="{ active: filter === item[0] }" @click="filter = item[0]">{{ item[1] }}</text></view>
    <text v-if="error" class="error">{{ error }}（已显示本地缓存）</text>
    <text v-if="loading && !recipes.length" class="muted">正在加载菜谱…</text>
    <view v-for="recipe in shown" :key="recipe.recipe_id" class="card recipe">
      <view class="row"><text class="recipe-name" @click="edit(recipe)">{{ recipe.name }}</text><text class="muted">{{ recipe.servings }} 人份 · {{ recipe.tasks?.length || 0 }} 步</text></view>
      <view class="row recipe-actions"><text class="chip" @click="favorite(recipe)">{{ recipe.favorite ? '♥ 已收藏' : '♡ 收藏' }}</text><text class="chip" :class="{ active: chosen.includes(recipe.recipe_id) }" @click="toggle(recipe)">{{ chosen.includes(recipe.recipe_id) ? '✓ 已选' : '+ 今晚做' }}</text><text class="chip" @click="edit(recipe)">编辑</text></view>
    </view>
    <view v-if="!shown.length && !loading" class="card muted">这里还没有菜谱，试试导入或手动创建。</view>
    <button v-if="chosen.length" class="primary" @click="tab('plan')">已选 {{ chosen.length }} 道 · 安排做饭</button>
  </view>
</template>

<style scoped>
.actions { display: flex; gap: 16rpx; margin: 28rpx 0; }
.actions button { flex: 1; margin: 0; }
.recipe-name { font-size: 32rpx; font-weight: 650; }
.recipe-actions { justify-content: flex-start; margin-top: 14rpx; }
</style>
