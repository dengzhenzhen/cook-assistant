<script setup>
import { ref } from 'vue'
import { onShow, onHide, onUnload } from '@dcloudio/uni-app'
import { api, auth } from '../lib/client.js'
import { storage } from '../lib/storage.js'
import { errorText, go, toast } from '../utils.js'

const text = ref('')
const jobId = ref('')
const status = ref('')
const busy = ref(false)
const error = ref('')
let timer = null
let polling = false

function stop() { if (timer) clearInterval(timer); timer = null }
async function poll() {
  if (!jobId.value || polling) return
  polling = true
  try {
    const job = await api.importJob(jobId.value)
    status.value = job.status
    if (job.status === 'completed') {
      stop()
      storage.set(`draft:${job.recipe.recipe_id}`, job.recipe)
      storage.remove('import_job')
      jobId.value = ''
      go('editor', `?id=${encodeURIComponent(job.recipe.recipe_id)}`)
    } else if (job.status === 'failed') {
      stop(); jobId.value = ''; storage.remove('import_job')
      error.value = job.error || '解析失败，请重试。'
    }
  } catch (e) { error.value = errorText(e); stop() }
  finally { polling = false }
}
function watch() { stop(); poll(); timer = setInterval(poll, 2000) }
onShow(() => { if (!auth.value) { go('login'); return }; jobId.value = storage.get('import_job') || ''; if (jobId.value) watch() })
onHide(stop)
onUnload(stop)

async function submit(image = false) {
  if (busy.value) return
  busy.value = true; error.value = ''
  try {
    let job
    if (image) {
      const choice = await uni.chooseImage({ count: 1, sizeType: ['compressed'], sourceType: ['album', 'camera'] })
      const imagePath = choice.tempFilePaths?.[0]
      if (!imagePath) return
      if (choice.tempFiles?.[0]?.size > 4 * 1024 * 1024) throw new Error('单张图片不能超过 4MB。')
      job = await api.importImage([imagePath])
    } else {
      if (!text.value.trim()) throw new Error('请输入菜名或菜谱文字。')
      job = await api.importText(text.value.trim())
    }
    jobId.value = job.job_id; status.value = job.status
    storage.set('import_job', jobId.value)
    watch()
  } catch (e) { error.value = errorText(e) }
  finally { busy.value = false }
}
</script>

<template>
  <view class="page">
    <text class="title">导入你的拿手菜</text>
    <text class="subtitle">输入菜名、粘贴做法，或选一张菜谱图片。确认结果后再保存。</text>
    <view v-if="jobId" class="card"><text class="section">{{ status === 'pending' ? '正在排队…' : '正在整理食材和步骤…' }}</text><button class="secondary" @click="poll">检查解析结果</button></view>
    <view v-else class="card">
      <label class="field">菜名或菜谱文字<textarea v-model="text" class="textarea" maxlength="20000" placeholder="例如：番茄炒蛋，或完整的食材和做法" /></label>
      <button class="primary" :disabled="busy" @click="submit(false)">{{ busy ? '正在提交…' : '解析文字菜谱' }}</button>
      <button class="secondary" :disabled="busy" @click="submit(true)">选择一张菜谱图片</button>
    </view>
    <text v-if="error" class="error">{{ error }}</text>
    <text class="muted">微信小程序每次支持导入一张图片。AI 草稿中的食材、时长和步骤需由你确认。</text>
  </view>
</template>
