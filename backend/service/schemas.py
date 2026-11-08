"""Versioned recipe and kitchen boundary, validated before persistence or scheduling."""
from datetime import datetime
from functools import lru_cache
from typing import Literal, Annotated
from uuid import uuid4
from pydantic import Field, model_validator
from decimal import Decimal, InvalidOperation
from .quantities import parse_amount
from cook_scheduler.models import Model, Request, Task, ResourceHold


def new_id():
    return str(uuid4())


class Amount(Model):
    kind: Literal['exact', 'range', 'to_taste', 'unknown'] = 'unknown'
    value: str | None = Field(default=None, max_length=80)
    upper: str | None = Field(default=None, max_length=80)
    unit: str = Field(default='', max_length=30)

    @model_validator(mode='after')
    def bounds(self):
        try:
            if self.kind in ('exact', 'range'):
                value = Decimal(self.value or '')
                if not value.is_finite() or not 0 <= value <= 1000000000: raise ValueError('invalid amount')
                if self.kind == 'range':
                    upper = Decimal(self.upper or '')
                    if not upper.is_finite() or not value <= upper <= 1000000000: raise ValueError('invalid range')
            elif self.value is not None or self.upper is not None:
                raise ValueError('unknown amounts cannot contain numbers')
            if self.kind == 'exact' and self.upper is not None: raise ValueError('exact amount has no upper')
        except InvalidOperation as exc:
            raise ValueError('invalid decimal amount') from exc
        return self


class ScalingPoint(Model):
    ratio: float = Field(gt=0, le=20, allow_inf_nan=False)
    factor: float = Field(ge=0, le=40, allow_inf_nan=False)


class ScalingRule(Model):
    mode: Literal['auto', 'linear', 'power', 'affine', 'fixed', 'manual', 'piecewise'] = 'auto'
    exponent: float = Field(default=0.8, ge=0.1, le=2, allow_inf_nan=False)
    fixed_fraction: float = Field(default=0.3, ge=0, le=1, allow_inf_nan=False)
    points: list[ScalingPoint] = Field(default_factory=list, max_length=12)
    note: str = Field(default='', max_length=300)

    @model_validator(mode='after')
    def curve(self):
        if self.mode == 'piecewise':
            if len(self.points) < 2 or not any(p.ratio == 1 and p.factor == 1 for p in self.points):
                raise ValueError('piecewise scaling requires a (1, 1) anchor')
            if any(a.ratio >= b.ratio or a.factor > b.factor for a, b in zip(self.points, self.points[1:])):
                raise ValueError('scaling points must have increasing ratios and nondecreasing factors')
        return self


class Ingredient(Model):
    name: str = Field(min_length=1, max_length=100)
    quantity: str = Field(default='', max_length=80)
    unit: str = Field(default='', max_length=30)
    amount: Amount | None = None
    role: Literal['main', 'secondary', 'seasoning', 'liquid', 'other'] = 'main'
    scaling: ScalingRule = Field(default_factory=ScalingRule)

    @model_validator(mode='before')
    @classmethod
    def parse_legacy(cls, data):
        # quantity/unit remain the editable source of truth. A client editing
        # only the legacy text must not accidentally retain stale parsed data.
        if isinstance(data, dict):
            data = {**data, 'amount': parse_amount(data.get('quantity', ''), data.get('unit', ''))}
        return data


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
    servings_by_recipe: dict[str, Annotated[int, Field(strict=True, ge=1, le=20)]] = Field(default_factory=dict, max_length=10)

    @model_validator(mode='after')
    def portion_selection(self):
        if set(self.servings_by_recipe) - set(self.recipe_ids):
            raise ValueError('servings may only refer to selected recipes')
        if any(not 1 <= servings <= 20 for servings in self.servings_by_recipe.values()):
            raise ValueError('servings must be between 1 and 20')
        return self


class ScaleRequest(Model):
    target_servings: int = Field(ge=1, le=20, strict=True)


class TextImport(Model):
    text: str = Field(min_length=1, max_length=20000)
