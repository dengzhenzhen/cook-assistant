// Only the login envelope is global. Every other key belongs to one account.
const PREFIX = 'kaifan:uniapp:'
let account = null
const memory = new Map()

function read(key) {
  if (typeof uni !== 'undefined' && uni.getStorageSync) return uni.getStorageSync(key)
  return memory.get(key)
}
function write(key, value) {
  if (typeof uni !== 'undefined' && uni.setStorageSync) uni.setStorageSync(key, value)
  else memory.set(key, value)
}
function erase(key) {
  if (typeof uni !== 'undefined' && uni.removeStorageSync) uni.removeStorageSync(key)
  else memory.delete(key)
}
export function setAccount(userId) { account = userId || null }
export function getAccount() { return account }
export function getGlobal(key, fallback = null) { return read(PREFIX + 'global:' + key) ?? fallback }
export function setGlobal(key, value) { write(PREFIX + 'global:' + key, value) }
export function removeGlobal(key) { erase(PREFIX + 'global:' + key) }
function scoped(key) { if (!account) throw new Error('请先登录。'); return PREFIX + account + ':' + key }
export function get(key, fallback = null) { return read(scoped(key)) ?? fallback }
export function set(key, value) { write(scoped(key), value); return value }
export function remove(key) { erase(scoped(key)) }
export const storage = { get, set, remove }
export const selected = {
  get: () => get('selected_recipe_ids', []),
  set: (ids) => set('selected_recipe_ids', [...new Set(ids)]),
  toggle(id) {
    const ids = new Set(this.get())
    ids.has(id) ? ids.delete(id) : ids.add(id)
    return this.set([...ids])
  },
  clear: () => remove('selected_recipe_ids'),
}
