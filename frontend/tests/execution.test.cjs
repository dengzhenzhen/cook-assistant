const {test} = require('node:test');
const assert = require('node:assert/strict');
const E = require('../execution.js');

function session() {
  return {
    request: {tasks: [
      {id: 'wash', duration_seconds: 10, dependencies: [], attention_type: 'active'},
      {id: 'rice', duration_seconds: 30, dependencies: ['wash'], attention_type: 'passive'},
      {id: 'cut', duration_seconds: 20, dependencies: [], attention_type: 'active'},
    ]},
    plan: {tasks: [
      {task_id: 'wash', start_seconds: 0},
      {task_id: 'rice', start_seconds: 10},
      {task_id: 'cut', start_seconds: 10},
    ]},
    execution: [], confirmation_seconds: 60,
  };
}

test('a running appliance does not hide or block an eligible manual task', () => {
  const s = session();
  s.execution = [{task_id: 'wash', actual_start: 0, actual_end: 10}];
  E.startTask(s, 'rice', 10);
  assert.deepEqual(E.readyTasks(s, 10).map(t => t.task_id), ['cut']);
  E.startTask(s, 'cut', 10);
  assert.equal(E.running(s).length, 2);
});

test('starting tasks respects dependencies, start times, and duplicate actions', () => {
  const s = session();
  assert.throws(() => E.startTask(s, 'rice', 10));
  assert.throws(() => E.startTask(s, 'cut', 5));
  E.startTask(s, 'wash', 0);
  assert.throws(() => E.startTask(s, 'wash', 0));
});

test('confirmation deadline survives serializing, and extending cooking resets it', () => {
  const s = session();
  E.startTask(s, 'wash', 0);
  const restored = JSON.parse(JSON.stringify(s));
  assert.equal(E.confirmationDeadline(restored, restored.execution[0]), 70);
  restored.execution[0].estimated_end += 300;
  assert.equal(E.confirmationDeadline(restored, restored.execution[0]), 370);
  restored.confirmation_seconds = 120;
  assert.equal(E.confirmationDeadline(restored, restored.execution[0]), 430);
});

test('unconfirmed tasks retain equipment and completion facts remain immutable', () => {
  const s = session();
  s.execution = [{task_id: 'wash', actual_start: 0, actual_end: 10}];
  E.startTask(s, 'rice', 10);
  const request = E.requestAt(s, 30);
  assert.deepEqual(request.execution[0], {task_id: 'wash', actual_start: 0, actual_end: 10});
  assert.equal(request.execution[1].remaining_seconds, 70);
  assert.equal(E.requestAt(s, 1000).execution[1].remaining_seconds, 60);
  assert.equal(s.execution[1].estimated_end, 40);
});

test('only passive appliance tasks may auto-confirm, including devices held across steps', () => {
  const s = session();
  s.request.holds = [{resource: 'rice_cooker', start_task: 'wash'}];
  s.execution = [{task_id: 'wash', actual_start: 0, actual_end: 10}];
  E.startTask(s, 'rice', 10);
  const entry = s.execution[1];
  assert.equal(E.canAutoConfirm(s, entry), true);
  assert.equal(E.dueConfirmations(s, 99).length, 0);
  assert.deepEqual(E.dueConfirmations(s, 100).map(e => e.task_id), ['rice']);
  entry.auto_confirm_cancelled = true;
  assert.deepEqual(E.dueConfirmations(s, 1000), []);
});

test('manual, intermittent, flame, and generic passive waits never auto-confirm', () => {
  for (const [attention, resources] of [
    ['active', {rice_cooker: 1}], ['intermittent', {rice_cooker: 1}],
    ['passive', {burner: 1, rice_cooker: 1}], ['passive', {}],
  ]) {
    const s = session();
    s.request.tasks[0].attention_type = attention;
    s.request.tasks[0].resources = resources;
    E.startTask(s, 'wash', 0);
    assert.deepEqual(E.dueConfirmations(s, 1000), []);
  }
});

test('an unrelated appliance hold cannot make a passive flame task automatic', () => {
  const s = session();
  s.request.holds = [{resource: 'rice_cooker', start_task: 'cut'}];
  s.execution = [{task_id: 'wash', actual_start: 0, actual_end: 10}];
  E.startTask(s, 'rice', 10);
  assert.equal(E.canAutoConfirm(s, s.execution[1]), false);
  s.request.holds = [{resource: 'rice_cooker', start_task: 'wash'},
    {resource: 'burner', start_task: 'wash'}];
  assert.equal(E.canAutoConfirm(s, s.execution[1]), false);
});
