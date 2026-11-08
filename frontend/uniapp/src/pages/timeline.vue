<script setup>
import { ref, computed } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import { storage } from '../lib/storage.js'
import { createSession } from '../lib/session.js'
import { uid, formatSeconds, go, toast } from '../utils.js'
import MealIngredients from '../components/MealIngredients.vue'

const snapshot = ref(null)
const rows = computed(() => (snapshot.value?.plan?.tasks || []).slice().sort((a, b) => a.start_seconds - b.start_seconds))
const templates = computed(() => Object.fromEntries((snapshot.value?.request?.tasks || []).map(t => [t.id, t])))
onShow(() => { snapshot.value = storage.get('latest_plan') })

async function start() {
  if (!snapshot.value) return
  const active = storage.get('active_session')
  if (active && !Object.values(active.document?.states || {}).every(s => s.status === 'completed')) {
    const result = await uni.showModal({ title: '已有烹饪会话', content: '开始新计划会替换本机当前会话。请先完成或恢复原会话。', showCancel: false })
    if (result) go('execute')
    return
  }
  try {
    const document = createSession(snapshot.value, uid())
    storage.set('active_session', { document, version: 0, mutation: uid() })
    go('execute')
  } catch (e) { toast(e.message || '无法开始计划。') }
}
</script>

<template>
  <view class="page">
    <text class="title">烹饪时间线</text>
    <view v-if="!snapshot" class="card muted">还没有保存的计划，请先生成烹饪计划。</view>
    <template v-else>
      <text class="subtitle">共 {{ rows.length }} 步。按时间线执行，设备自动步骤会继续计时。</text>
      <MealIngredients :snapshots="snapshot.recipe_snapshots" />
      <view v-for="row in rows" :key="row.task_id" class="card">
        <view class="row"><text class="muted">{{ snapshot.recipes?.[templates[row.task_id]?.recipe_id] || '' }}</text></view>
        <text class="step">{{ templates[row.task_id]?.name || row.name }}</text>
        <text v-if="templates[row.task_id]?.notes" class="muted">{{ templates[row.task_id].notes }}</text>
        <text class="muted">预计 {{ formatSeconds((row.end_seconds || 0) - row.start_seconds) }}</text>
      </view>
      <button class="primary" @click="start">开始烹饪</button>
    </template>
  </view>
</template>

<style scoped>
.step { display: block; font-size: 31rpx; font-weight: 650; margin: 12rpx 0; }
</style>
