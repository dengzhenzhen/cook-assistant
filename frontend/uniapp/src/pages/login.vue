<script setup>
import { ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import { api, auth } from '../lib/client.js'
import { errorText, tab } from '../utils.js'

const email = ref('')
const password = ref('')
const registering = ref(false)
const busy = ref(false)
const error = ref('')

onShow(() => { if (auth.value) tab('recipes') })

async function submit() {
  if (busy.value) return
  busy.value = true
  error.value = ''
  try {
    if (registering.value) await api.register(email.value.trim(), password.value)
    else await api.login(email.value.trim(), password.value)
    tab('recipes')
  } catch (e) { error.value = errorText(e) }
  finally { busy.value = false }
}
</script>

<template>
  <view class="page login">
    <text class="eyebrow">开饭 · KAIFAN</text>
    <text class="title">{{ registering ? '创建开饭账号' : '欢迎回来' }}</text>
    <text class="subtitle">从想吃的一道菜开始，安排好每一步。</text>
    <view class="card form">
      <label class="field">邮箱<input v-model="email" class="input" type="text" placeholder="name@example.com" /></label>
      <label class="field">密码<input v-model="password" class="input" type="password" placeholder="至少 8 位" /></label>
      <text v-if="error" class="error">{{ error }}</text>
      <button class="primary" :disabled="busy" @click="submit">{{ busy ? '请稍候…' : registering ? '注册并登录' : '登录' }}</button>
      <button class="secondary" @click="registering = !registering">{{ registering ? '已有账号？去登录' : '没有账号？创建账号' }}</button>
    </view>
    <text class="muted">账号密码仅发送到你的开饭服务端。</text>
  </view>
</template>

<style scoped>
.login { padding-top: 100rpx; }
.eyebrow { color: #bc5634; letter-spacing: 4rpx; font-size: 24rpx; }
.form { margin-top: 50rpx; }
</style>
