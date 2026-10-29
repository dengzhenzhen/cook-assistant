/* Pure execution helpers, shared by the UI controller and dependency-free tests. */
(function (root) {
  'use strict';

  const tasksById = session => new Map(session.request.tasks.map(task => [task.id, task]));
  const isRunning = entry => entry.actual_end === undefined;
  const running = session => session.execution.filter(isRunning);
  const confirmationSeconds = session => session.confirmation_seconds ?? 60;
  const confirmationDeadline = (session, entry) => entry.estimated_end + confirmationSeconds(session);

  function readyTasks(session, now) {
    const templates = tasksById(session);
    const started = new Set(session.execution.map(entry => entry.task_id));
    const completed = new Set(session.execution.filter(entry => !isRunning(entry)).map(entry => entry.task_id));
    return session.plan.tasks.filter(row => !started.has(row.task_id) && row.start_seconds <= now &&
      templates.get(row.task_id).dependencies.every(id => completed.has(id)));
  }

  function nextTask(session) {
    const templates = tasksById(session);
    const started = new Set(session.execution.map(entry => entry.task_id));
    const completed = new Set(session.execution.filter(entry => !isRunning(entry)).map(entry => entry.task_id));
    return session.plan.tasks.find(row => !started.has(row.task_id) &&
      templates.get(row.task_id).dependencies.every(id => completed.has(id)));
  }

  const APPLIANCES = new Set(['rice_cooker', 'oven', 'microwave', 'air_fryer']);

  function isApplianceTask(session, task) {
    if (task.attention_type !== 'passive' || task.resources?.burner) return false;
    const templates = tasksById(session);
    function ancestors(id, seen = new Set()) {
      for (const dependency of templates.get(id)?.dependencies || []) {
        if (!seen.has(dependency)) { seen.add(dependency); ancestors(dependency, seen); }
      }
      return seen;
    }
    const holds = (session.request.holds || []).filter(hold =>
      (hold.start_task === task.id || ancestors(task.id).has(hold.start_task)) &&
      (!hold.end_task || hold.end_task === task.id || ancestors(hold.end_task).has(task.id)));
    if (holds.some(hold => hold.resource === 'burner')) return false;
    return Object.keys(task.resources || {}).some(key => APPLIANCES.has(key)) ||
      holds.some(hold => APPLIANCES.has(hold.resource));
  }

  function canAutoConfirm(session, entry) {
    return !entry.auto_confirm_cancelled && isApplianceTask(session, tasksById(session).get(entry.task_id));
  }

  function dueConfirmations(session, now) {
    return running(session).filter(entry => canAutoConfirm(session, entry) &&
      confirmationDeadline(session, entry) <= now);
  }

  function requestAt(session, now) {
    const request = JSON.parse(JSON.stringify(session.request));
    request.now_seconds = now;
    request.execution = session.execution.map(entry => isRunning(entry) ? {
      task_id: entry.task_id,
      actual_start: entry.actual_start,
      // Keep people/equipment reserved during the confirmation grace period.
      remaining_seconds: Math.max(60, confirmationDeadline(session, entry) - now),
    } : {
      task_id: entry.task_id,
      actual_start: entry.actual_start,
      actual_end: entry.actual_end,
    });
    return request;
  }

  function startTask(session, id, now) {
    if (session.execution.some(entry => entry.task_id === id)) throw new Error('这一步已经开始。');
    if (!readyTasks(session, now).some(row => row.task_id === id)) throw new Error('这一步尚未满足计划时间或前置依赖。');
    const task = tasksById(session).get(id);
    session.execution.push({task_id: id, actual_start: now, estimated_end: now + task.duration_seconds});
    return task;
  }

  const helpers = {tasksById, isRunning, running, confirmationSeconds, confirmationDeadline,
    readyTasks, nextTask, requestAt, startTask, isApplianceTask, canAutoConfirm, dueConfirmations};
  root.CookExecution = helpers;
  if (typeof module !== 'undefined' && module.exports) module.exports = helpers;
})(globalThis);
