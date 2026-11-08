from copy import deepcopy
from decimal import Decimal
import pytest
from pydantic import ValidationError
from service.schemas import Recipe, ScalingRule
from service.scaling import scale_recipe
from service.quantities import parse_amount
from test_catalog import client, recipe


@pytest.mark.parametrize('text,unit,kind,value,upper,canonical', [
    ('300', '克', 'exact', '300', None, 'g'),
    ('1/2', '个', 'exact', '0.5', None, '个'),
    ('半个', '', 'exact', '0.5', None, '个'),
    ('十二', '颗', 'exact', '12', None, '颗'),
    ('2–3g', '', 'range', '2', '3', 'g'),
    ('适量', '', 'to_taste', None, None, ''),
    ('一小把', '', 'unknown', None, None, '把'),
    ('NaN', 'g', 'unknown', None, None, 'g'),
    ('-2', 'g', 'unknown', None, None, 'g'),
    ('3-2', 'g', 'unknown', None, None, 'g'),
    ('1/0', 'g', 'unknown', None, None, 'g'),
    ('2ml', 'g', 'unknown', None, None, 'g'),
])
def test_quantity_parser_preserves_unknowns(text, unit, kind, value, upper, canonical):
    assert parse_amount(text, unit) == {'kind': kind, 'value': value, 'upper': upper, 'unit': canonical}


def portion_recipe():
    data = recipe()
    data['ingredients'] = [
        {'name': '鸡肉', 'quantity': '300', 'unit': 'g'},
        {'name': '盐', 'quantity': '2–3', 'unit': 'g'},
        {'name': '食用油', 'quantity': '10', 'unit': 'ml'},
        {'name': '水', 'quantity': '200', 'unit': 'ml'},
        {'name': '葱', 'quantity': '适量'},
    ]
    return Recipe.model_validate(data)


def test_each_ingredient_has_independent_curve_and_original_is_unchanged():
    original = portion_recipe()
    before = original.model_dump()
    result = scale_recipe(original, 4)
    meat, salt, oil, water, scallion = result['ingredients']
    assert meat['quantity'] == '600'
    assert Decimal(salt['amount']['value']) == Decimal(2) * (Decimal(2) ** Decimal('0.8'))
    assert salt['quantity'] != '4–6'
    assert oil['quantity'] == '17'  # 3ml fixed + 7ml * 2
    assert water['quantity'] == '200' and water['warnings']
    assert scallion['quantity'] == '适量' and scallion['warnings']
    assert original.model_dump() == before
    assert scale_recipe(original, 3) == scale_recipe(Recipe.model_validate(before), 3)
    assert result['warnings']


def test_explicit_recipe_rule_overrides_name_heuristic():
    data = portion_recipe().model_dump()
    data['ingredients'][1]['scaling'] = {'mode': 'linear'}
    assert scale_recipe(Recipe.model_validate(data), 4)['ingredients'][1]['quantity'] == '4–6'
    data['ingredients'][1]['scaling'] = {'mode': 'fixed'}
    assert scale_recipe(Recipe.model_validate(data), 4)['ingredients'][1]['quantity'] == '2–3'


def test_piecewise_interpolation_does_not_extrapolate():
    data = portion_recipe().model_dump()
    data['ingredients'][0]['scaling'] = {'mode': 'piecewise', 'points': [
        {'ratio': 0.5, 'factor': 0.7}, {'ratio': 1, 'factor': 1}, {'ratio': 2, 'factor': 1.6}]}
    value = Recipe.model_validate(data)
    assert scale_recipe(value, 2)['ingredients'][0]['quantity'] == '300'
    assert scale_recipe(value, 3)['ingredients'][0]['quantity'] == '390'
    outside = scale_recipe(value, 6)['ingredients'][0]
    assert outside['quantity'] == '300' and outside['factor'] is None and outside['warnings']


@pytest.mark.parametrize('points', [
    [{'ratio': 0.5, 'factor': 0.7}, {'ratio': 2, 'factor': 1.6}],
    [{'ratio': 1, 'factor': 1}, {'ratio': 1, 'factor': 2}],
    [{'ratio': 1, 'factor': 1}, {'ratio': 2, 'factor': 0.7}],
])
def test_invalid_curves_rejected(points):
    with pytest.raises(ValidationError): ScalingRule(mode='piecewise', points=points)


def test_scaled_plan_stores_immutable_ingredients_without_scaling_tasks(client):
    original = portion_recipe().model_dump()
    assert client.post('/api/v1/recipes', json=original).status_code == 201
    preview = client.post('/api/v1/recipes/test-recipe/scale', json={'target_servings': 4})
    assert preview.status_code == 200 and preview.json()['ingredients'][0]['quantity'] == '600'
    kitchen = client.get('/api/v1/kitchens/default').json()
    result = client.post('/api/v1/plans/from-recipes', json={
        'recipe_ids': ['test-recipe'], 'kitchen_id': kitchen['kitchen_id'], 'servings_by_recipe': {'test-recipe': 4}})
    assert result.status_code == 200, result.text
    snapshot = result.json()
    assert snapshot['recipe_snapshots']['test-recipe'] == preview.json()
    assert snapshot['request']['tasks'][1]['duration_seconds'] == 600
    changed = deepcopy(original)
    changed['ingredients'][0]['quantity'] = '400'
    assert client.put('/api/v1/recipes/test-recipe', json=changed).status_code == 200
    assert client.get('/api/v1/recipes/test-recipe').json()['ingredients'][0]['amount']['value'] == '400'
    assert snapshot['recipe_snapshots']['test-recipe']['ingredients'][0]['quantity'] == '600'
    assert client.get('/api/v1/recipes/test-recipe').json()['servings'] == 2
    assert client.post('/api/v1/plans/from-recipes', json={
        'recipe_ids': ['test-recipe'], 'kitchen_id': kitchen['kitchen_id'], 'servings_by_recipe': {'another-user': 2}}).status_code == 422
    assert client.post('/api/v1/recipes/test-recipe/scale', json={'target_servings': 0}).status_code == 422


def test_upgrade_default_fields_do_not_conflict_with_pre_upgrade_offline_base(client):
    import asyncio
    from service.database import RecipeRow
    from service.app import app
    raw = recipe()
    raw['ingredients'] = [{'name': '盐', 'quantity': '2', 'unit': 'g'}]

    async def insert_legacy():
        async with app.state.sessions() as db:
            db.add(RecipeRow(id=raw['recipe_id'], user_id='local-developer', document=raw))
            await db.commit()
    asyncio.run(insert_legacy())
    current = client.get('/api/v1/recipes/test-recipe').json()
    current['name'] = '离线改名'
    result = client.post('/api/v1/sync/edit', json={'kind': 'recipe', 'base': current | {'name': raw['name']}, 'document': current})
    assert result.status_code == 200, result.text
    stale = client.post('/api/v1/sync/edit', json={'kind': 'recipe', 'base': raw, 'document': current | {'name': '不能覆盖'}})
    assert stale.status_code == 409
