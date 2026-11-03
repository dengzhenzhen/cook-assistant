<script setup>
import { ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import { api, auth } from '../lib/client.js'
import { selected, storage } from '../lib/storage.js'
import { pendingEdits, flushEdits, resolveEdit, discardEdit } from '../lib/outbox.js'
import { cachedRecipes, cacheRecipes } from '../catalog-cache.js'
import { errorText, go, tab, toast } from '../utils.js'

const status = ref(null)
const profile = ref(null)
const pending = ref([])
onShow(async () => {
  if (!auth.value) { go('login'); return }
  pending.value = pendingEdits()
  try { status.value = await api.aiStatus(); profile.value = await api.profile() }
  catch (e) { if (!auth.value) go('login'); else toast(errorText(e)) }
})

async function syncEdits() {
  try { await flushEdits(); pending.value = pendingEdits(); toast(pending.value.length ? '仍有未同步编辑' : '编辑已同步') }
  catch (e) { pending.value = pendingEdits(); toast(errorText(e)) }
}
async function resolve(index, keepLocal) {
  const edit = pending.value[index]
  if (!edit) return
  try {
    const remote = edit.kind === 'recipe' ? await api.getRecipe(edit.document.recipe_id) : await api.kitchen()
    if (keepLocal) { resolveEdit(index, remote, edit.document); await syncEdits() }
    else {
      discardEdit(index)
      if (edit.kind === 'recipe') cacheRecipes([remote, ...cachedRecipes().filter(r => r.recipe_id !== remote.recipe_id)])
      else storage.set('kitchen', remote)
      pending.value = pendingEdits(); toast('已采用云端版本')
    }
  } catch (e) { toast(errorText(e)) }
}

async function logout() {
  selected.clear()
  try { await api.logout() } catch (_) { /* local session is cleared by client */ }
  tab('recipes')
}
</script>

<template>
  <view class="page">
    <text class="title">我的开饭</text>
    <view class="card"><text class="section">{{ profile?.name || '我的账号' }}</text><text class="muted">{{ auth?.user_id || '' }}</text></view>
    <view class="card" @click="go('kitchen')"><view class="row"><text>我的厨房</text><text class="muted">配置厨具和人数 ›</text></view></view>
    <view class="card"><text class="section">AI 菜谱解析</text><text v-if="status" class="muted">今日已使用 {{ status.daily_used }} / {{ status.daily_limit }} 次 · {{ status.configured ? '已配置' : '未配置' }}</text><text v-else class="muted">暂无用量信息</text></view>
    <view class="card" @click="go('execute')"><view class="row"><text>恢复烹饪会话</text><text class="muted">查看本机或云端进度 ›</text></view></view>
    <view v-if="pending.length" class="card"><text class="section">待同步编辑 {{ pending.length }}</text><button class="secondary" @click="syncEdits">重试同步</button>
      <view v-for="(edit, index) in pending" :key="index" class="pending"><text>{{ edit.kind === 'recipe' ? edit.document.name : '厨房配置' }} · {{ edit.status === 'conflict' ? '云端冲突' : '等待同步' }}</text>
        <view v-if="edit.status === 'conflict'"><button class="secondary" @click="resolve(index, true)">保留本机并覆盖云端</button><button class="secondary" @click="resolve(index, false)">采用云端</button></view>
      </view>
    </view>
    <button class="secondary" @click="logout">退出登录</button>
  </view>
</template>

<style scoped>
.pending { padding: 20rpx 0; border-top: 1rpx solid #e6e7df; }
</style>
