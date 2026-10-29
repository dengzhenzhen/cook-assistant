"""Versioned recipe and kitchen boundary, validated before persistence or scheduling."""
from datetime import datetime
from functools import lru_cache
from typing import Literal
from uuid import uuid4
from pydantic import Field, model_validator
from cook_scheduler.models import Model, Request, Task, ResourceHold


def new_id():
    return str(uuid4())


class Ingredient(Model):
    name: str = Field(min_length=1, max_length=100)
    quantity: str = Field(default='', max_length=80)
    unit: str = Field(default='', max_length=30)


class Recipe(Model):
    schema_version: Literal['1.0'] = '1.0'
    recipe_id: str = Field(default_factory=new_id, min_length=1, max_length=80)
    name: str = Field(min_length=1, max_length=80)
    servings: int = Field(default=2, ge=1, le=20)
    ingredients: list[Ingredient] = Field(default_factory=list, max_length=100)
    tasks: list[Task] = Field(min_length=1, max_length=50)
    holds: list[ResourceHold] = Field(default_factory=list, max_length=100)
    max_holding_seconds: int = Field(default=300, ge=0, le=86400)
    favorite: bool = False
    confirmed: bool = True
    source_type: Literal['manual', 'text', 'image', 'url'] = 'manual'
    estimated_fields: list[str] = Field(default_factory=list)

    @model_validator(mode='after')
    def graph(self):
        if any(t.recipe_id != self.recipe_id for t in self.tasks):
            raise ValueError('task recipe_id must match recipe_id')
        if any(t.duration_seconds > 86400 for t in self.tasks):
            raise ValueError('task duration exceeds 24 hours')
        Request(tasks=self.tasks, holds=self.holds)
        tasks = {t.id: t for t in self.tasks}
        @lru_cache
        def ancestors(key):
            result = set()
            for dep in tasks[key].dependencies:
                result.add(dep)
                result.update(ancestors(dep))
            return result
        for hold in self.holds:
            if hold.end_task and hold.end_task != hold.start_task and hold.start_task not in ancestors(hold.end_task):
                raise ValueError('resource release must follow acquisition in the DAG')
        return self


DEFAULT_CAPACITIES = dict(burner=2,wok=1,pot=1,steamer=0,rice_cooker=1,air_fryer=0,
                          oven=0,microwave=1,board=1,knife=1,large_bowl=3,bowl=4,plate=4)


class Kitchen(Model):
    kitchen_id: str = Field(default_factory=new_id, max_length=80)
    name: str = Field(default='我的厨房', min_length=1, max_length=80)
    cook_count: int = Field(default=1, ge=1, le=20)
    capacities: dict[str, int] = Field(default_factory=lambda: DEFAULT_CAPACITIES.copy())

    @model_validator(mode='after')
    def quantities(self):
        if len(self.capacities)>100 or any(not 0<=n<=100 for n in self.capacities.values()):
            raise ValueError('resource quantities must be between 0 and 100')
        return self


class SavedPlanRequest(Model):
    recipe_ids: list[str] = Field(min_length=1, max_length=10)
    kitchen_id: str
    target_finish_time: datetime | None = None


class TextImport(Model):
    text: str = Field(min_length=5, max_length=20000)
