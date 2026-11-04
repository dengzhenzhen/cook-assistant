<script>
export default { onLaunch() {} }
</script>

<style>
page { background: #f7f5ef; color: #263328; font-family: -apple-system, BlinkMacSystemFont, 'PingFang SC', sans-serif; }
button { border-radius: 14rpx; }
button::after { border: none; }
.page { padding: 32rpx; padding-bottom: 130rpx; }
.title { font-size: 48rpx; font-weight: 700; margin: 10rpx 0 26rpx; display: block; }
.subtitle { font-size: 26rpx; color: #74806d; line-height: 1.6; display: block; }
.card { display: block; background: #fffefa; border: 1rpx solid #e4e4d8; border-radius: 24rpx; padding: 26rpx; margin: 20rpx 0; }
.field { display: block; margin: 22rpx 0; font-size: 25rpx; }
.input, .textarea { display: block; width: 100%; box-sizing: border-box; margin-top: 10rpx; background: #fffefa; border: 1rpx solid #d9ddcf; border-radius: 14rpx; padding: 20rpx; font-size: 28rpx; }
.input { height: 96rpx; min-height: 96rpx; padding: 0 20rpx; line-height: 1.5; }
.textarea { height: 240rpx; min-height: 240rpx; line-height: 1.6; }
.primary { background: #c45230; color: white; margin-top: 24rpx; }
.secondary { background: #e8eee3; color: #34573b; margin-top: 18rpx; }
.danger { color: #b33927; }
.muted { color: #788475; font-size: 24rpx; }
.row { display: flex; align-items: center; justify-content: space-between; gap: 16rpx; }
.chip { padding: 8rpx 18rpx; border-radius: 30rpx; background: #edf1e9; color: #4c6548; margin: 8rpx 8rpx 0 0; display: inline-block; font-size: 23rpx; }
.chip.active { background: #4e704d; color: white; }
.section { font-size: 34rpx; font-weight: 650; margin: 34rpx 0 15rpx; display: block; }
.error { color: #ad3d2b; font-size: 25rpx; margin: 14rpx 0; display: block; }
.bottom-space { height: 100rpx; }
</style>
