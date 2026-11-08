from datetime import datetime, timedelta, timezone
from test_catalog import client


def save_dish(client, key, seconds=360, attention='active'):
    response = client.post('/api/v1/recipes', json={
        'recipe_id': key, 'name': key, 'servings': 2,
        'ingredients': [{'name': '鸡蛋', 'quantity': '2', 'unit': '个'}],
        'tasks': [{'id': f'task-{key}', 'recipe_id': key, 'name': '做菜',
                   'duration_seconds': seconds, 'attention_type': attention, 'resources': {'wok': 1}}]})
    assert response.status_code == 201, response.text


def test_ten_minute_target_checked_against_whole_menu_and_shared_equipment(client):
    save_dish(client, 'first')
    save_dish(client, 'second')
    kitchen = client.get('/api/v1/kitchens/default').json()
    result = client.post('/api/v1/plans/from-recipes', json={
        'recipe_ids': ['first', 'second'], 'kitchen_id': kitchen['kitchen_id'],
        'meal_preferences': {'mode': 'quick', 'time_minutes': 10, 'effort': 'low'}})
    assert result.status_code == 200, result.text
    assessment = result.json()['menu_assessment']
    assert assessment['estimated_total_minutes'] == 12
    assert assessment['estimated_work_minutes'] == 12
    assert not assessment['within_time_target'] and not assessment['within_work_target']
    assert len(assessment['warnings']) == 2


def test_future_dinner_target_does_not_count_idle_time_as_cooking_work(client):
    save_dish(client, 'first', 360, 'passive')
    kitchen = client.get('/api/v1/kitchens/default').json()
    result = client.post('/api/v1/plans/from-recipes', json={
        'recipe_ids': ['first'], 'kitchen_id': kitchen['kitchen_id'],
        'target_finish_time': (datetime.now(timezone.utc) + timedelta(hours=2)).isoformat(),
        'servings_by_recipe': {'first': 4},
        'meal_preferences': {'mode': 'quick', 'time_minutes': 10, 'effort': 'low'}})
    assert result.status_code == 200, result.text
    assessment = result.json()['menu_assessment']
    assert assessment['estimated_total_minutes'] == 6
    assert assessment['estimated_work_minutes'] == 0
    assert assessment['within_time_target'] and assessment['within_work_target']
    assert assessment['portions_changed'] and assessment['warnings']


def test_existing_plan_request_does_not_gain_unrequested_menu_restrictions(client):
    save_dish(client, 'first')
    kitchen = client.get('/api/v1/kitchens/default').json()
    result = client.post('/api/v1/plans/from-recipes', json={
        'recipe_ids': ['first'], 'kitchen_id': kitchen['kitchen_id']})
    assert result.status_code == 200
    assert result.json()['menu_assessment'] is None
