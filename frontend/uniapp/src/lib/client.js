import { getGlobal, setGlobal, removeGlobal, setAccount } from './storage.js'

export class ApiError extends Error {
  constructor(status, detail, data = null) {
    const message = typeof detail === 'string' ? detail : detail?.message || '请求失败，请稍后重试。'
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.data = data
    this.conflict = status === 409
  }
}

const saved = getGlobal('auth')
export const auth = { value: saved || null }
setAccount(saved?.user_id)
let refreshPromise = null
let baseUrl = (typeof import.meta !== 'undefined' && import.meta.env?.VITE_API_BASE_URL) || getGlobal('server', '') || ''
export function setBaseUrl(url) { baseUrl = String(url).replace(/\/$/, ''); setGlobal('server', baseUrl) }
export function getBaseUrl() { return baseUrl }

function transport(path, { method = 'GET', data, headers = {} } = {}) {
  return new Promise((resolve, reject) => {
    if (!baseUrl) return reject(new ApiError(0, '尚未配置后端地址 VITE_API_BASE_URL。'))
    if (typeof uni === 'undefined' || !uni.request) return reject(new Error('网络接口不可用。'))
    uni.request({
      url: baseUrl + path, method, data,
      header: { 'Content-Type': 'application/json', ...headers },
      success: resolve,
      fail: (cause) => reject(new ApiError(0, '网络不可用，请检查连接。', cause)),
    })
  })
}
function decode(response) {
  if (response.statusCode >= 200 && response.statusCode < 300) return response.data
  const detail = response.data?.detail || response.data?.message
  const explained = Array.isArray(detail) ? detail.map(item => item.msg || String(item)).join('；') : detail
  throw new ApiError(response.statusCode, explained || '请求失败，请稍后重试。', response.data)
}
function install(tokens) {
  auth.value = tokens
  setAccount(tokens?.user_id)
  if (tokens) setGlobal('auth', tokens)
  else removeGlobal('auth')
  return tokens
}
async function refresh(previous) {
  if (!refreshPromise) {
    refreshPromise = (async () => {
      try {
        const next = decode(await transport('/api/v1/auth/refresh', { method: 'POST', data: { refresh_token: previous.refresh_token } }))
        // Logout or account switching during the request must not resurrect tokens.
        if (auth.value === previous) install(next)
        return auth.value === next ? next : null
      } catch (error) {
        if (error.status === 401 && auth.value === previous) install(null)
        throw error
      } finally { refreshPromise = null }
    })()
  }
  return refreshPromise
}
export async function request(path, options = {}) {
  const { authRequired = true, ...config } = options
  const previous = auth.value
  if (authRequired && !previous) throw new ApiError(401, '请先登录。')
  const send = (tokens) => transport(path, { ...config, headers: tokens ? { Authorization: `Bearer ${tokens.access_token}`, ...config.headers } : config.headers })
  let response = await send(authRequired ? previous : null)
  if (authRequired && response.statusCode === 401 && previous?.refresh_token) {
    const next = auth.value !== previous ? auth.value : await refresh(previous)
    if (!next || next.user_id !== previous.user_id) throw new ApiError(401, '登录已失效，请重新登录。')
    response = await send(next) // A request is replayed at most once.
  }
  if (authRequired && auth.value?.user_id !== previous.user_id) throw new ApiError(401, '账号已切换，请重新打开页面。')
  return decode(response)
}

function encode(id) { return encodeURIComponent(id) }
export const api = {
  async register(email, password) { return install(await request('/api/v1/auth/register', { method: 'POST', data: { email, password }, authRequired: false })) },
  async login(email, password) { return install(await request('/api/v1/auth/login', { method: 'POST', data: { email, password }, authRequired: false })) },
  async logout() {
    const current = auth.value
    install(null)
    if (current?.refresh_token) {
      try { await request('/api/v1/auth/logout', { method: 'POST', data: { refresh_token: current.refresh_token }, authRequired: false }) } catch (_) { /* local logout is authoritative */ }
    }
  },
  profile: () => request('/api/v1/profile'),
  recipes: () => request('/api/v1/recipes'),
  getRecipe: (id) => request(`/api/v1/recipes/${encode(id)}`),
  saveRecipe: (recipe, existing = false) => request(existing ? `/api/v1/recipes/${encode(recipe.recipe_id)}` : '/api/v1/recipes', { method: existing ? 'PUT' : 'POST', data: recipe }),
  deleteRecipe: (id) => request(`/api/v1/recipes/${encode(id)}`, { method: 'DELETE' }),
  kitchen: () => request('/api/v1/kitchens/default'),
  saveKitchen: (kitchen) => request(`/api/v1/kitchens/${encode(kitchen.kitchen_id)}`, { method: 'PUT', data: kitchen }),
  aiStatus: () => request('/api/v1/ai/status'),
  importText: (text) => request('/api/v1/recipes/import/text', { method: 'POST', data: { text } }),
  importJob: (id) => request(`/api/v1/import-jobs/${encode(id)}`),
  async importImage(filePaths) {
    const paths = Array.isArray(filePaths) ? filePaths : [filePaths]
    const previous = auth.value
    if (!previous) throw new ApiError(401, '请先登录。')
    if (paths.length !== 1) throw new Error('每次请选择一张图片。')
    if (typeof uni === 'undefined' || !uni.uploadFile) throw new Error('图片上传不可用。')
    const upload = tokens => new Promise((resolve, reject) => {
      uni.uploadFile({ url: baseUrl + '/api/v1/recipes/import/image', filePath: paths[0], name: 'images',
        header: { Authorization: `Bearer ${tokens.access_token}` },
        success(result) {
          try { resolve({ statusCode: result.statusCode, data: JSON.parse(result.data || '{}') }) }
          catch (error) { reject(new ApiError(result.statusCode, '图片上传响应无效。', error)) }
        },
        fail(error) { reject(new ApiError(0, '图片上传失败，请检查连接。', error)) },
      })
    })
    let response = await upload(previous)
    if (response.statusCode === 401) {
      const next = auth.value !== previous ? auth.value : await refresh(previous)
      if (!next || next.user_id !== previous.user_id) throw new ApiError(401, '登录已失效，请重新登录。')
      response = await upload(next)
    }
    if (auth.value?.user_id !== previous.user_id) throw new ApiError(401, '账号已切换，请重新打开页面。')
    return decode(response)
  },
  plan: (recipeIds, kitchenId, targetFinishTime = null) => request('/api/v1/plans/from-recipes', { method: 'POST', data: { recipe_ids: recipeIds, kitchen_id: kitchenId, target_finish_time: targetFinishTime } }),
  recalculate: (scheduleRequest) => request('/api/v1/plans/recalculate', { method: 'POST', data: scheduleRequest }),
  listSessions: () => request('/api/v1/sessions'),
  getSession: (id) => request(`/api/v1/sessions/${encode(id)}`),
  syncSession: (session, baseVersion = 0, mutationId = cryptoId()) => request(`/api/v1/sessions/${encode(session.id || session.session_id)}`, { method: 'PUT', data: { session_id: session.id || session.session_id, base_version: baseVersion, mutation_id: mutationId, document: session } }),
  syncEdit: (edit) => request('/api/v1/sync/edit', { method: 'POST', data: edit }),
}
export function cryptoId() { return globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(36).slice(2)}` }
