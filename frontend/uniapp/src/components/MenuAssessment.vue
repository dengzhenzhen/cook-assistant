<script setup>
defineProps({ assessment: { type: Object, default: null } })
</script>

<template>
  <view v-if="assessment" class="card">
    <text class="section">本餐时间与工作量核对</text>
    <text class="subtitle">按完整步骤及当前厨房排程：约 {{ assessment.estimated_total_minutes }} 分钟；操作及看管约 {{ assessment.estimated_work_minutes }} 人分钟。</text>
    <text class="muted">工作量按需操作 / 看管的步骤时长累计，是保守参考；多人并行时可与整餐时间不同。</text>
    <text v-for="warning in assessment.warnings" :key="warning" class="error">{{ warning }}</text>
    <text v-if="assessment.within_time_target && assessment.within_work_target" class="subtitle">当前基准排程在目标范围内，实际仍需核对份量、火力与熟度。</text>
  </view>
</template>
