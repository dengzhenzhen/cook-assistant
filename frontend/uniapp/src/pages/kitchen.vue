<script setup>
import { ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import { api, auth } from '../lib/client.js'
import { storage } from '../lib/storage.js'
import { queueEdit, flushEdits, pendingEdits } from '../lib/outbox.js'
import { resourceNames, errorText, toast } from '../utils.js'

const kitchen = ref(null)
const busy = ref(false)
const error = ref('')
const base = ref(null)

onShow(async () => {
  if (!auth.value) return
  kitchen.value = storage.get('kitchen')
  base.value = kitchen.value ? JSON.parse(JSON.stringify(kitchen.value)) : null
  try { const remote = await api.kitchen(); base.value = remote; kitchen.value = remote; storage.set('kitchen', remote); error.value = '' }
  catch (e) { error.value = errorText(e) }
  const pending = pendingEdits().find(row => row.kind === 'kitchen')
  if (pending) kitchen.value = JSON.parse(JSON.stringify(pending.document))
})

function adjust(key, delta) {
  const current = Number(kitchen.value.capacities[key] || 0)
  kitchen.value.capacities[key] = Math.max(0, Math.min(100, current + delta))
}

async function save() {
  busy.value = true
  try {
    kitchen.value.cook_count = Number(kitchen.value.cook_count)
    queueEdit('kitchen', base.value, JSON.parse(JSON.stringify(kitchen.value)))
    storage.set('kitchen', kitchen.value)
    try { await flushEdits() } catch (e) { toast(`已保存到本机，联网后再同步：${errorText(e)}`) }
    toast(pendingEdits().some(row => row.kind === 'kitchen') ? '厨房已保存到本机，等待同步' : '厨房已保存')
    uni.navigateBack()
  } catch (e) { error.value = errorText(e) }
  finally { busy.value = false }
}
</script>

<template>
  <view class="page">
    <text class="title">我的厨房</text>
    <text class="subtitle">设备数量会影响可并行的烹饪步骤。</text>
    <text v-if="error" class="error">{{ error }}</text>
    <view v-if="kitchen" class="card">
      <view class="row"><text>可操作人数</text><view class="counter"><text @click="kitchen.cook_count = Math.max(1, Number(kitchen.cook_count) - 1)">−</text><text>{{ kitchen.cook_count }}</text><text @click="kitchen.cook_count = Math.min(20, Number(kitchen.cook_count) + 1)">＋</text></view></view>
      <view v-for="(name, key) in resourceNames" :key="key" class="row equipment"><text>{{ name }}</text><view class="counter"><text @click="adjust(key, -1)">−</text><text>{{ kitchen.capacities[key] || 0 }}</text><text @click="adjust(key, 1)">＋</text></view></view>
    </view>
    <button v-if="kitchen" class="primary" :disabled="busy" @click="save">{{ busy ? '正在保存…' : '保存厨房配置' }}</button>
  </view>
</template>

<style scoped>
.equipment { padding-top: 26rpx; border-top: 1rpx solid #e6e7df; margin-top: 26rpx; }
.counter { display: flex; align-items: center; gap: 25rpx; }
.counter text:first-child, .counter text:last-child { font-size: 40rpx; color: #45674a; min-width: 42rpx; text-align: center; }
</style>
