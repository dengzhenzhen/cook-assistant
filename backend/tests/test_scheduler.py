import pytest
from pydantic import ValidationError
from cook_scheduler import Request, SchedulingError, generate_plan


def task(id, duration=10, **kwargs):
    return dict(id=id, recipe_id=id.split('_')[0], name=id, duration_seconds=duration, **kwargs)


def schedule(tasks, **kwargs):
    return generate_plan(Request(tasks=tasks, **kwargs))


def times(plan):
    return {t.task_id: (t.start_seconds, t.end_seconds) for t in plan.tasks}


def test_dag_parallel_branches():
    p = schedule([task('tomato'), task('egg'), task('mix', dependencies=['egg']),
                  task('fry', dependencies=['tomato', 'mix'])], cook_count=2)
    t = times(p)
    assert p.finish_seconds == 30
    assert t['tomato'][0] < t['mix'][1]
    assert t['fry'][0] >= max(t['tomato'][1], t['mix'][1])


@pytest.mark.parametrize('tasks', [
    [task('a', dependencies=['b']), task('b', dependencies=['a'])],
    [task('a', dependencies=['missing'])], [task('a'), task('a')]])
def test_bad_graph(tasks):
    with pytest.raises(ValidationError):
        Request(tasks=tasks)


def test_cook_and_passive_parallelism():
    p = schedule([task('a'), task('b'), task('rice', 30, attention_type='passive')])
    assert p.finish_seconds == 30
    t = times(p)
    assert t['a'][1] <= t['b'][0] or t['b'][1] <= t['a'][0]


def test_pot_held_across_tasks():
    p = schedule([task('soup_heat', attention_type='passive'),
                  task('soup_pour', dependencies=['soup_heat']),
                  task('other', resources={'pot': 1})], capacities={'pot': 1}, cook_count=2,
                 holds=[dict(resource='pot', start_task='soup_heat', end_task='soup_pour')])
    t = times(p)
    assert t['other'][1] <= t['soup_heat'][0] or t['other'][0] >= t['soup_pour'][1]


def test_missing_resource():
    with pytest.raises(SchedulingError, match='insufficient resource'):
        schedule([task('fry', resources={'wok': 1})])


def test_deadline_and_freshness():
    p = schedule([task('salad', 10), task('rice', 40, attention_type='passive')],
                 target_finish_seconds=100, max_holding_seconds={'salad': 0})
    assert p.lateness_seconds == 0
    assert p.holding_excess_seconds == 0
    assert times(p)['salad'][1] == 100
    late = schedule([task('a', 50)], target_finish_seconds=20)
    assert late.lateness_seconds == 30


def test_recalculate_keeps_facts_and_running_resources():
    p = schedule([task('prep'), task('simmer', 20, dependencies=['prep'],
                                   attention_type='passive', resources={'pot': 1}),
                  task('other', resources={'pot': 1})], now_seconds=25,
                 capacities={'pot': 1}, execution=[
                     dict(task_id='prep', actual_start=0, actual_end=15),
                     dict(task_id='simmer', actual_start=15, remaining_seconds=30)])
    t = times(p)
    assert t['prep'] == (0, 15)
    assert t['simmer'] == (15, 55)
    assert t['other'][0] >= 55


def test_plate_held_until_meal():
    p = schedule([task('plate')], capacities={'plate': 1}, target_finish_seconds=100,
                 holds=[dict(resource='plate', start_task='plate')])
    a = next(a for a in p.allocations if a.resource == 'plate')
    assert a.end_seconds == 100


def test_inconsistent_execution_rejected():
    with pytest.raises(ValidationError, match='unfinished dependency'):
        Request(tasks=[task('a'), task('b', dependencies=['a'])], now_seconds=10,
                execution=[dict(task_id='b', actual_start=0, remaining_seconds=5)])


def test_intermediate_attention_reserves_cook():
    p = schedule([task('a', attention_type='intermittent'), task('b')])
    assert p.finish_seconds == 20
    assert p.warnings


def test_conflicting_actual_resources_infeasible():
    with pytest.raises(SchedulingError, match='infeasible'):
        schedule([task('a'), task('b')], now_seconds=5, execution=[
            dict(task_id='a', actual_start=0, remaining_seconds=5),
            dict(task_id='b', actual_start=0, remaining_seconds=5)])


def test_step_notes_are_preserved_without_affecting_scheduling():
    notes = "小火翻炒 30 秒，再转大火；出锅前放盐。"
    p = schedule([task('fry', notes=notes)])
    assert p.tasks[0].notes == notes
    assert p.tasks[0].end_seconds - p.tasks[0].start_seconds == 10
    assert schedule([task('legacy')]).tasks[0].notes == ""


def test_replan_early_long_cook_keeps_dinner_and_late_stir_fry():
    plan = schedule([
        task('stew_prep', 60),
        task('stew_long', 7200, attention_type='passive', dependencies=['stew_prep']),
        task('stew_plate', 60, dependencies=['stew_long']),
        task('veg_fry', 300, resources={'burner': 1}),
    ], target_finish_seconds=10800, now_seconds=60,
       capacities={'rice_cooker': 1, 'burner': 1},
       holds=[dict(resource='rice_cooker', start_task='stew_long', end_task='stew_plate')],
       max_holding_seconds={'stew': 600, 'veg': 0},
       execution=[dict(task_id='stew_prep', actual_start=0, actual_end=60),
                  dict(task_id='stew_long', actual_start=60, remaining_seconds=7200)])
    t = times(plan)
    assert t['stew_long'] == (60, 7260)
    assert t['veg_fry'] == (10500, 10800)
    assert t['stew_plate'][0] >= 10140
    assert plan.lateness_seconds == 0
    assert plan.holding_excess_seconds == 0
