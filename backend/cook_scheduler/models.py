"""Validated, serializable scheduling boundary. Times are seconds from session origin."""
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, model_validator


class Model(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Task(Model):
    id: str = Field(min_length=1)
    recipe_id: str
    name: str
    notes: str = Field(default="", max_length=4000)
    duration_seconds: int = Field(gt=0)
    dependencies: list[str] = Field(default_factory=list)
    attention_type: Literal["active", "passive", "intermittent"] = "active"
    resources: dict[str, int] = Field(default_factory=dict)


class ResourceHold(Model):
    """Acquire at start_task.start; release at end_task.end or meal time."""
    resource: str
    quantity: int = Field(default=1, gt=0)
    start_task: str
    end_task: str | None = None


class Execution(Model):
    task_id: str
    actual_start: int = Field(ge=0)
    actual_end: int | None = Field(default=None, ge=0)
    remaining_seconds: int | None = Field(default=None, gt=0)


class Request(Model):
    tasks: list[Task] = Field(min_length=1)
    capacities: dict[str, int] = Field(default_factory=dict)
    cook_count: int = Field(default=1, ge=1)
    holds: list[ResourceHold] = Field(default_factory=list)
    # Soft maximum holding time per recipe, measured from its last task to meal.
    max_holding_seconds: dict[str, int] = Field(default_factory=dict)
    target_finish_seconds: int | None = Field(default=None, ge=0)
    now_seconds: int = Field(default=0, ge=0)
    execution: list[Execution] = Field(default_factory=list)

    @model_validator(mode="after")
    def validate_graph(self):
        tasks = {t.id: t for t in self.tasks}
        if len(tasks) != len(self.tasks):
            raise ValueError("duplicate task ID; IDs must be unique across recipes")
        visited, visiting = set(), set()

        def visit(key):
            if key not in tasks:
                raise ValueError(f"unknown dependency: {key}")
            if key in visiting:
                raise ValueError("cyclic task dependencies")
            if key in visited:
                return
            visiting.add(key)
            for dep in tasks[key].dependencies:
                visit(dep)
            visiting.remove(key)
            visited.add(key)

        for key in tasks:
            visit(key)
        if any(v < 0 for v in self.capacities.values()):
            raise ValueError("resource capacity cannot be negative")
        for task in self.tasks:
            if any(v <= 0 for v in task.resources.values()):
                raise ValueError("resource demand must be positive")
            if "cook" in task.resources:
                raise ValueError("cook is reserved; use attention_type and cook_count")
        for hold in self.holds:
            if hold.resource == "cook":
                raise ValueError("cook is reserved")
            if hold.start_task not in tasks or (hold.end_task and hold.end_task not in tasks):
                raise ValueError("unknown resource hold endpoint")
        if any(v < 0 for v in self.max_holding_seconds.values()):
            raise ValueError("holding tolerance cannot be negative")
        if set(self.max_holding_seconds) - {t.recipe_id for t in self.tasks}:
            raise ValueError("unknown recipe in holding policy")
        states = {e.task_id: e for e in self.execution}
        if len(states) != len(self.execution) or set(states) - tasks.keys():
            raise ValueError("duplicate or unknown execution task")
        for state in self.execution:
            if state.actual_start > self.now_seconds:
                raise ValueError("actual start is in the future")
            if state.actual_end is None:
                if state.remaining_seconds is None:
                    raise ValueError("running task requires remaining_seconds")
            elif not state.actual_start <= state.actual_end <= self.now_seconds:
                raise ValueError("invalid actual end")
            for dep in tasks[state.task_id].dependencies:
                previous = states.get(dep)
                if previous is None or previous.actual_end is None or previous.actual_end > state.actual_start:
                    raise ValueError("started task has unfinished dependency")
        return self


class ScheduledTask(Model):
    task_id: str
    recipe_id: str
    name: str
    notes: str = ""
    start_seconds: int
    end_seconds: int
    status: Literal["pending", "running", "completed"]


class Allocation(Model):
    resource: str
    quantity: int
    start_seconds: int
    end_seconds: int


class Plan(Model):
    tasks: list[ScheduledTask]
    allocations: list[Allocation]
    finish_seconds: int
    lateness_seconds: int
    holding_excess_seconds: int
    optimal: bool
    warnings: list[str]
