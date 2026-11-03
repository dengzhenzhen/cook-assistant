const clone = value => JSON.parse(JSON.stringify(value))
const secondsAt = (session, now) => Math.max(0, Math.floor((new Date(now).getTime() - Date.parse(session.origin)) / 1000))
const tasksOf = session => session.snapshot.request.tasks
const taskOf = (session, id) => tasksOf(session).find(task => task.id === id)
const rowsOf = session => session.snapshot.plan.tasks

export function createSession(snapshot, id, now = new Date()) {
  const first = Math.min(...snapshot.plan.tasks.map(row => row.start_seconds))
  const timed = snapshot.request.target_finish_seconds != null
  return { id, snapshot: clone(snapshot), origin: timed ? snapshot.origin : new Date(new Date(now).getTime() - first * 1000).toISOString(),
    started_at: new Date(now).toISOString(), states: {}, auto_seconds: 60, paused: false, resting: false, clock_version: 2 }
}
export function elapsed(session, now = new Date()) { return secondsAt(session, now) }
export function finished(session) { return tasksOf(session).every(task => session.states[task.id]?.status === 'completed') }
export function upcoming(session) { return rowsOf(session).filter(row => !session.states[row.task_id]).sort((a, b) => a.start_seconds - b.start_seconds) }
export function needsWatching(session) {
  return tasksOf(session).some(task => session.states[task.id]?.status === 'running' && (task.attention_type !== 'passive' || task.resources?.burner)) ||
    (session.snapshot.request.holds || []).some(hold => hold.resource === 'burner' && session.states[hold.start_task] && !(hold.end_task && session.states[hold.end_task]?.status === 'completed'))
}
export function automatic(session, task) {
  if (task.attention_type !== 'passive') return false
  const ids = new Set()
  const visit = id => { if (ids.has(id)) return; ids.add(id); (taskOf(session, id)?.dependencies || []).forEach(visit) }
  visit(task.id)
  const resources = new Set(Object.keys(task.resources || {}))
  for (const hold of session.snapshot.request.holds || []) {
    if (ids.has(hold.start_task) && !(hold.end_task && hold.end_task !== task.id && ids.has(hold.end_task))) resources.add(hold.resource)
  }
  return resources.size > 0 && [...resources].every(resource => ['rice_cooker', 'oven', 'microwave', 'air_fryer'].includes(resource))
}
export function canStart(session, candidate) {
  const demand = {}
  const add = (key, count) => { demand[key] = (demand[key] || 0) + count }
  for (const task of tasksOf(session)) {
    if (session.states[task.id]?.status !== 'running' && task.id !== candidate.id) continue
    Object.entries(task.resources || {}).forEach(([key, count]) => add(key, count))
    if (task.attention_type !== 'passive') add('cook', 1)
  }
  for (const hold of session.snapshot.request.holds || []) {
    if ((session.states[hold.start_task] || hold.start_task === candidate.id) && !(hold.end_task && session.states[hold.end_task]?.status === 'completed')) add(hold.resource, hold.quantity || 1)
  }
  const capacities = { ...session.snapshot.request.capacities, cook: session.snapshot.request.cook_count || 1 }
  return Object.entries(demand).every(([key, count]) => count <= (capacities[key] || 0))
}
function dependenciesDone(session, task) { return (task.dependencies || []).every(id => session.states[id]?.status === 'completed') }
export function readyToStart(session, id, now = new Date(), allowEarly = false) {
  if (session.paused || session.states[id]) return false
  const row = rowsOf(session).find(row => row.task_id === id)
  const task = taskOf(session, id)
  return Boolean(row && task && (allowEarly || row.start_seconds <= elapsed(session, now)) && dependenciesDone(session, task) && canStart(session, task))
}
export function startTask(session, id, now = new Date(), allowEarly = false) {
  if (!readyToStart(session, id, now, allowEarly)) return false
  session.resting = false
  session.states[id] = { status: 'running', started: elapsed(session, now) }
  return true
}
export function startNext(session, now = new Date(), afterTask = null) {
  if (session.paused || (session.resting && !afterTask)) return false
  const previous = taskOf(session, afterTask)
  for (const row of rowsOf(session)) {
    const task = taskOf(session, row.task_id)
    if (!task || session.states[task.id]) continue
    const handoff = previous && task.recipe_id === previous.recipe_id && task.attention_type === 'passive' && (task.dependencies || []).includes(afterTask)
    if (session.snapshot.request.target_finish_seconds != null && elapsed(session, now) < row.start_seconds && !handoff) continue
    if (dependenciesDone(session, task) && canStart(session, task)) {
      session.resting = false
      session.states[task.id] = { status: 'running', started: elapsed(session, now) }
      return true
    }
  }
  return false
}
export function completeTask(session, id, now = new Date(), advance = true) {
  const state = session.states[id]
  if (!state || state.status !== 'running') return false
  state.status = 'completed'
  state.ended = Math.max(state.started, elapsed(session, now))
  if (advance) startNext(session, now, id)
  enterRest(session)
  return true
}
export function enterRest(session) {
  if (finished(session) || tasksOf(session).some(task => session.states[task.id]?.status === 'running' && task.attention_type !== 'passive') || tasksOf(session).every(task => session.states[task.id]) || session.resting) return false
  session.resting = true
  return true
}
export function tick(session, now = new Date()) {
  const seconds = elapsed(session, now)
  let changed = false
  for (const task of tasksOf(session)) {
    const state = session.states[task.id]
    if (state?.status === 'running' && automatic(session, task) && seconds >= state.started + task.duration_seconds + (session.auto_seconds ?? 60)) {
      state.status = 'completed'
      state.ended = state.started + task.duration_seconds + (session.auto_seconds ?? 60)
      changed = true
    }
  }
  if (session.paused || session.resting) return changed
  if (changed) startNext(session, now)
  for (const row of rowsOf(session)) {
    const task = taskOf(session, row.task_id)
    if (task && !session.states[task.id] && seconds >= row.start_seconds && dependenciesDone(session, task) && canStart(session, task)) {
      session.states[task.id] = { status: 'running', started: seconds }
      changed = true
    }
  }
  return enterRest(session) || changed
}
export function buildReplan(session, now = new Date()) {
  const request = clone(session.snapshot.request)
  request.now_seconds = elapsed(session, now)
  request.execution = Object.entries(session.states).map(([task_id, state]) => ({ task_id, actual_start: state.started,
    actual_end: state.status === 'completed' ? state.ended : null,
    remaining_seconds: state.status === 'running' ? Math.min(86400, Math.max(1, (taskOf(session, task_id)?.duration_seconds || 1) - (request.now_seconds - state.started))) : null }))
  return request
}
export function applyReplan(session, plan) { session.snapshot.plan = clone(plan); session.needs_replan = false; return session }
