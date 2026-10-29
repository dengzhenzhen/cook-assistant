"""CP-SAT scheduler with lexicographic objectives and immutable execution facts."""
from collections import defaultdict
from ortools.sat.python import cp_model
from .models import Allocation, Plan, Request, ScheduledTask


class SchedulingError(ValueError):
    pass


def generate_plan(request: Request, *, time_limit_seconds: float = 10) -> Plan:
    if time_limit_seconds <= 0:
        raise ValueError("time_limit_seconds must be positive")
    model = cp_model.CpModel()
    states = {s.task_id: s for s in request.execution}
    horizon = max(request.now_seconds, request.target_finish_seconds or 0) + sum(
        t.duration_seconds for t in request.tasks
    ) + sum(s.remaining_seconds or 0 for s in request.execution) + 1
    starts, ends = {}, {}
    pools = defaultdict(list)
    allocations = []

    def occupy(resource, quantity, start, end, label):
        capacity = request.cook_count if resource == "cook" else request.capacities.get(resource, 0)
        if quantity > capacity:
            raise SchedulingError(f"insufficient resource {resource}: need {quantity}, available {capacity}")
        size = model.new_int_var(0, horizon, f"size:{label}")
        interval = model.new_interval_var(start, size, end, label)
        pools[resource].append((interval, quantity))
        allocations.append((resource, quantity, start, end))

    for task in request.tasks:
        start = starts[task.id] = model.new_int_var(0, horizon, f"start:{task.id}")
        end = ends[task.id] = model.new_int_var(0, horizon, f"end:{task.id}")
        state = states.get(task.id)
        if state:
            model.add(start == state.actual_start)
            model.add(end == (state.actual_end if state.actual_end is not None else
                              request.now_seconds + state.remaining_seconds))
        else:
            model.add(start >= request.now_seconds)
            model.add(end == start + task.duration_seconds)
        # Conservative prototype: intermittent work occupies a cook throughout.
        if task.attention_type != "passive":
            occupy("cook", 1, start, end, f"cook:{task.id}")
        for resource, quantity in task.resources.items():
            occupy(resource, quantity, start, end, f"{resource}:{task.id}")
    for task in request.tasks:
        for dep in task.dependencies:
            model.add(starts[task.id] >= ends[dep])
    finish = model.new_int_var(0, horizon, "finish")
    model.add_max_equality(finish, list(ends.values()))
    target = request.target_finish_seconds
    meal = model.new_int_var(0, horizon, "meal")
    model.add_max_equality(meal, [finish, target or 0])
    for i, hold in enumerate(request.holds):
        occupy(hold.resource, hold.quantity, starts[hold.start_task],
               ends[hold.end_task] if hold.end_task else meal, f"hold:{i}")
    for resource, items in pools.items():
        model.add_cumulative([i for i, _ in items], [q for _, q in items],
                             request.cook_count if resource == "cook" else request.capacities[resource])
    target = request.target_finish_seconds
    late = model.new_int_var(0, horizon, "lateness")
    model.add_max_equality(late, [0, finish - target] if target is not None else [0])
    excesses = []
    for recipe, tolerance in request.max_holding_seconds.items():
        ready = model.new_int_var(0, horizon, f"ready:{recipe}")
        model.add_max_equality(ready, [ends[t.id] for t in request.tasks if t.recipe_id == recipe])
        excess = model.new_int_var(0, horizon, f"holding:{recipe}")
        model.add_max_equality(excess, [0, meal - ready - tolerance])
        excesses.append(excess)
    first = model.new_int_var(0, horizon, "first")
    model.add_min_equality(first, list(starts.values()))
    solver = cp_model.CpSolver()
    solver.parameters.max_time_in_seconds = time_limit_seconds
    solver.parameters.num_search_workers = 1
    optimal = True
    # Never claim lower-priority optimality if a higher-priority stage timed out.
    for objective in (late, sum(excesses), finish - first, finish):
        model.minimize(objective)
        status = solver.solve(model)
        if status not in (cp_model.OPTIMAL, cp_model.FEASIBLE):
            raise SchedulingError("infeasible resource/execution constraints" if status == cp_model.INFEASIBLE
                                  else "solver could not find a plan within the time limit")
        if status != cp_model.OPTIMAL:
            optimal = False
            break
        model.add(objective == solver.value(objective))
    tasks = [ScheduledTask(task_id=t.id, recipe_id=t.recipe_id, name=t.name, notes=t.notes,
                           start_seconds=solver.value(starts[t.id]), end_seconds=solver.value(ends[t.id]),
                           status=("completed" if states[t.id].actual_end is not None else "running")
                           if t.id in states else "pending") for t in request.tasks]
    warnings = []
    if any(t.attention_type == "intermittent" for t in request.tasks):
        warnings.append("间歇关注任务按全程占用一名厨师建模；明火任务仍需看管。")
    return Plan(tasks=sorted(tasks, key=lambda t: (t.start_seconds, t.task_id)),
                allocations=[Allocation(resource=r, quantity=q, start_seconds=solver.value(s),
                                        end_seconds=solver.value(e)) for r, q, s, e in allocations],
                finish_seconds=solver.value(finish), lateness_seconds=solver.value(late),
                holding_excess_seconds=sum(solver.value(e) for e in excesses),
                optimal=optimal, warnings=warnings)
