<script setup>
import { computed, ref } from 'vue'
const props = defineProps({ snapshots: { type: Object, default: () => ({}) } })
const expanded = ref(false)
const recipes = computed(() => Object.values(props.snapshots || {}))
</script>

<template>
  <view v-if="recipes.length" class="card">
    <view class="row" @click="expanded = !expanded"><text>本餐食材清单</text><text class="chip">{{ expanded ? '收起' : '展开' }}</text></view>
    <template v-if="expanded">
      <view v-for="recipe in recipes" :key="recipe.recipe_id">
        <text class="section">{{ recipe.name }} · {{ recipe.target_servings }} 人份</text>
        <text class="muted">基准 {{ recipe.base_servings }} 人份，本餐用量已独立保存。</text>
        <view v-for="(ingredient, index) in recipe.ingredients" :key="index" class="ingredient">
          <view class="row"><text>{{ ingredient.name }}</text><text>{{ ingredient.quantity || '待确认' }} {{ ingredient.unit }}</text></view>
          <text v-for="warning in ingredient.warnings" :key="warning" class="muted">{{ warning }}</text>
        </view>
        <text v-for="warning in recipe.warnings" :key="warning" class="muted">{{ warning }}</text>
      </view>
    </template>
  </view>
</template>

<style scoped>
.ingredient { margin: 18rpx 0; }
.muted { display: block; line-height: 1.6; }
</style>
