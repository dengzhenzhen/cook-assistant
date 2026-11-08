<script setup>
import { ref, computed } from 'vue'
import { onShow, onHide, onUnload } from '@dcloudio/uni-app'
import { api, auth } from '../lib/client.js'
import { storage } from '../lib/storage.js'
import { createSession, tick, startTask, startNext, completeTask, readyToStart, elapsed, finished, needsWatching, buildReplan, applyReplan, automatic } from '../lib/session.js'
import { uid, errorText, formatSeconds, go, tab, toast } from '../utils.js'
import MealIngredients from '../components/MealIngredients.vue'

const record = ref(null)
const now = ref(Date.now())
const message = ref('')
const conflict = ref(null)
const replanning = ref(false)
const syncing = ref(false)
const restoring = ref(false)
let timer = null
let lastSync = 0

const session = computed(() => record.value?.document || null)
const tasks = computed(() => session.value?.snapshot?.request?.tasks || [])
const planRows = computed(() => session.value?.snapshot?.plan?.tasks || [])
const running = computed(() => tasks.value.filter(t => session.value?.states?.[t.id]?.status === 'running'))
const upcoming = computed(() => planRows.value.filter(row => !session.value?.states?.[row.task_id]).map(row => ({ ...row, task: tasks.value.find(t => t.id === row.task_id) })).filter(row => row.task))
const completed = computed(() => tasks.value.filter(t => session.value?.states?.[t.id]?.status === 'completed').length)

function save() {
  if (!record.value) return
  record.value.mutation = uid()
  storage.set('active_session', JSON.parse(JSON.stringify(record.value)))
}

async function sync() {
  if (!session.value || syncing.value || conflict.value) return
  syncing.value = true
  const pending = record.value.mutation
  try {
    if (pending) {
      const result = await api.syncSession(session.value, record.value.version || 0, pending)
      record.value.version = result.version
      if (record.value.mutation === pending) record.value.mutation = null
      storage.set('active_session', JSON.parse(JSON.stringify(record.value)))
    } else if (record.value.version) {
      const remote = await api.getSession(session.value.id)
      if (remote.version > record.value.version && !record.value.mutation) {
        record.value = { document: remote.document, version: remote.version, mutation: null }
        storage.set('active_session', JSON.parse(JSON.stringify(record.value)))
      }
    }
    message.value = '进度已同步'
  } catch (e) {
    if (e.status === 409) { conflict.value = e.conflict || e.data?.detail || {}; message.value = '云端进度已改变，本机进度已保留。' }
    else message.value = '进度已保存在本机，联网后可重试同步。'
  } finally { syncing.value = false }
}

async function replan() {
  if (!session.value || replanning.value || finished(session.value)) return
  replanning.value = true
  try {
    const result = await api.recalculate(buildReplan(session.value))
    applyReplan(session.value, result)
    save()
    await sync()
  } catch (e) { message.value = `重新排程失败，当前进度仍保留：${errorText(e)}` }
  finally { replanning.value = false }
}

async function update() {
  now.value = Date.now()
  if (!session.value) return
  const changed = tick(session.value, new Date(now.value))
  if (changed) { save(); await sync(); if (!finished(session.value)) await replan() }
  if (now.value - lastSync > 10000) { lastSync = now.value; await sync() }
}

function beginTimer() { if (timer) clearInterval(timer); timer = setInterval(update, 1000) }
function stopTimer() { if (timer) clearInterval(timer); timer = null }
onShow(async () => {
  if (!auth.value) { go('login'); return }
  record.value = storage.get('active_session')
  if (session.value) { await update(); beginTimer(); await sync() }
})
onHide(() => {
  stopTimer()
  if (session.value && !finished(session.value) && !session.value.paused) {
    session.value.paused = true
    save()
  }
})
onUnload(stopTimer)

async function start(id) {
  if (!session.value || !startTask(session.value, id, new Date(), false)) return
  save(); await sync(); await replan()
}
async function complete(task, direct = false) {
  const state = session.value?.states?.[task.id]
  if (!state) return
  const due = state.started + task.duration_seconds
  if (!direct && elapsed(session.value) < due) {
    const answer = await uni.showModal({ title: '提前完成', content: '预计时间还没到。确认食物已经完成并继续？' })
    if (!answer.confirm) return
  }
  if (!completeTask(session.value, task.id)) return
  save(); await sync(); await replan()
}
async function resume() {
  if (!session.value) return
  session.value.resting = false
  startNext(session.value)
  tick(session.value)
  save(); await sync(); await replan()
}
async function togglePause() {
  if (!session.value) return
  session.value.paused = !session.value.paused
  save(); await sync()
  if (!session.value.paused) await replan()
}
async function restore() {
  restoring.value = true
  try {
    const rows = await api.listSessions()
    if (!rows.length) { toast('暂无云端会话'); return }
    const answer = await uni.showActionSheet({ itemList: rows.map(row => `${row.document?.started_at || row.session_id}`) })
    const picked = rows[answer.tapIndex]
    if (!picked) return
    record.value = { document: picked.document, version: picked.version, mutation: null }
    conflict.value = null
    storage.set('active_session', JSON.parse(JSON.stringify(record.value)))
    await update(); beginTimer()
  } catch (e) { if (!String(e?.errMsg || '').includes('cancel')) toast(errorText(e)) }
  finally { restoring.value = false }
}
async function resolveConflict(mode) {
  if (mode === 'cloud') {
    try {
      const remote = await api.getSession(session.value.id)
      record.value = { document: remote.document, version: remote.version, mutation: null }
      storage.set('active_session', JSON.parse(JSON.stringify(record.value)))
      conflict.value = null; message.value = '已恢复云端进度'
    } catch (e) { toast(errorText(e)) }
  } else {
    record.value.document.id = uid()
    record.value.version = 0
    conflict.value = null
    save()
    await sync()
  }
}
async function finishAndExit() {
  if (!session.value || !finished(session.value)) return
  try {
    storage.set(`history:${session.value.id}`, JSON.parse(JSON.stringify(record.value)))
    stopTimer()
    tab('recipes')
  } catch (e) { toast(`保存进度失败：${errorText(e)}`) }
}
function remaining(task) {
  const state = session.value?.states?.[task.id]
  return formatSeconds(state ? state.started + task.duration_seconds - elapsed(session.value, new Date(now.value)) : 0)
}
function ready(id) { return session.value && readyToStart(session.value, id, new Date(now.value)) }
function recipeName(task) { return session.value?.snapshot?.recipes?.[task.recipe_id] || '' }
</script>

<template>
  <view class="page">
    <text class="title">正在烹饪</text>
    <view v-if="!session" class="card"><text class="subtitle">本机没有正在执行的计划。</text><button class="secondary" :disabled="restoring" @click="restore">恢复云端会话</button><button class="secondary" @click="go('timeline')">查看上次计划</button></view>
    <template v-else>
      <text class="subtitle">已完成 {{ completed }} / {{ tasks.length }} 步 · {{ session.paused ? '已暂停' : session.resting ? '正在休息' : '按计划进行' }}</text>
      <MealIngredients :snapshots="session.snapshot.recipe_snapshots" />
      <text v-if="needsWatching(session)" class="error">明火或手动步骤正在进行，请留意锅灶。</text>
      <view v-if="conflict" class="card"><text class="error">{{ message }}</text><button class="secondary" @click="resolveConflict('cloud')">恢复云端进度</button><button class="secondary" @click="resolveConflict('separate')">保留本机为独立会话</button></view>
      <text v-else-if="message" class="muted">{{ message }}</text>
      <view v-if="finished(session)" class="card"><text class="section">开饭啦！</text><text class="subtitle">全部步骤已完成。</text><button class="primary" @click="finishAndExit">完成并返回菜谱</button></view>
      <template v-else>
        <view v-if="session.resting" class="card"><text class="section">稍作休息</text><text class="subtitle">返回后可继续安排下一步。设备运行会按时间更新。</text><button class="primary" :disabled="session.paused" @click="resume">继续做下一步</button></view>
        <text class="section">正在进行</text>
        <view v-for="task in running" :key="task.id" class="card">
          <view class="row"><text class="step-name">{{ task.name }}</text><text class="muted">{{ recipeName(task) }}</text></view>
          <text v-if="task.notes" class="subtitle">{{ task.notes }}</text>
          <text class="timer">{{ remaining(task) }}</text>
          <text class="muted">{{ automatic(session, task) ? '设备自动运行，结束后 60 秒自动确认' : '请完成操作后手动确认' }}</text>
          <button class="primary" @click="complete(task)" @longpress="complete(task, true)">确认完成（长按直接完成）</button>
        </view>
        <view v-if="!running.length" class="card muted">当前没有运行中的步骤。</view>
        <text class="section">接下来</text>
        <view v-for="row in upcoming" :key="row.task_id" class="card">
          <view class="row"><text class="step-name">{{ row.task.name }}</text><text class="muted">计划 {{ formatSeconds(row.start_seconds) }}</text></view>
          <text v-if="row.task.notes" class="subtitle">{{ row.task.notes }}</text>
          <button v-if="ready(row.task_id) && !session.resting" class="secondary" @click="start(row.task_id)">开始这一步</button>
        </view>
        <button class="secondary" @click="togglePause">{{ session.paused ? '恢复安排新步骤' : '暂停安排新步骤' }}</button>
        <button class="secondary" :disabled="replanning" @click="replan">{{ replanning ? '正在重新安排…' : '重新安排剩余步骤' }}</button>
      </template>
      <button class="secondary" @click="sync">立即同步进度</button>
      <text class="muted">小程序退到后台时不保证系统提醒；返回页面会根据实际时间恢复计时。</text>
    </template>
  </view>
</template>

<style scoped>
.step-name { font-size: 30rpx; font-weight: 650; }
.timer { display: block; font-size: 50rpx; margin: 20rpx 0; color: #bd5231; font-weight: 700; }
</style>
