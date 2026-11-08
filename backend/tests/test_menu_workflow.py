"""Real persistence/import-worker/scheduler path with only the teacher mocked."""
import json
import time
from test_catalog import client


def test_recommend_edit_reuse_import_review_and_plan(client, monkeypatch):
    calls = []
    async def recommend(settings, request, library):
        assert request.ingredients == ['鸡蛋', '番茄', '西兰花']
        assert library[0]['name'] == '番茄炒蛋'
        return json.dumps({'dishes': [
            {'name': '番茄炒蛋', 'reason': '有现成菜谱', 'estimated_minutes': 6, 'effort': 'low'},
            {'name': '蒜蓉西兰花', 'reason': '已有西兰花', 'estimated_minutes': 6, 'effort': 'low'},
        ]}, ensure_ascii=False), {'prompt_tokens': 5, 'completion_tokens': 5}
    async def complete(settings, text, images=None):
        calls.append(text)
        if len(calls) == 1:
            assert text == '清炒西兰花'
            return '{"name_only":true,"name":"清炒西兰花"}', {'prompt_tokens': 2}
        return json.dumps({
            'name': '清炒西兰花', 'servings': 2,
            'ingredients': [{'name': '西兰花', 'quantity': '300', 'unit': 'g'},
                            {'name': '盐', 'quantity': '2', 'unit': 'g'}],
            'tasks': [{'id': 'fry', 'recipe_id': 'recipe', 'name': '炒制',
                       'duration_seconds': 360, 'resources': {'wok': 1}}]
        }, ensure_ascii=False), {'prompt_tokens': 3}
    async def search(settings, name):
        assert name == '清炒西兰花'
        return '西兰花300克，盐2克，清炒至熟。'
    monkeypatch.setattr('service.api.recommendations.generate_menu', recommend)
    monkeypatch.setattr('service.imports.complete', complete)
    monkeypatch.setattr('service.imports.search_recipe', search)
    saved = {'recipe_id': 'saved', 'name': '番茄炒蛋', 'servings': 2,
             'ingredients': [{'name': '番茄', 'quantity': '300', 'unit': 'g'}],
             'tasks': [{'id': 'saved-task', 'recipe_id': 'saved', 'name': '炒制',
                        'duration_seconds': 360, 'resources': {'wok': 1}}]}
    assert client.post('/api/v1/recipes', json=saved).status_code == 201
    menu = client.post('/api/v1/recommendations/menu', json={'mode': 'quick', 'dish_count': 2,
        'ingredients': ['鸡蛋', '番茄', '西兰花']})
    assert menu.status_code == 200, menu.text
    assert menu.json()['dishes'][0]['matched_recipe_id'] == 'saved'
    # User changes the second name before confirming: only the edited name imports.
    resolve = client.post('/api/v1/recommendations/resolve', json={'names': ['番茄炒蛋', '清炒西兰花']})
    assert resolve.status_code == 200, resolve.text
    items = resolve.json()['items']
    assert items[0]['status'] == 'matched'
    assert items[1]['status'] == 'import_pending'
    for _ in range(150):
        job = client.get('/api/v1/import-jobs/' + items[1]['job_id']).json()
        if job['status'] in ('completed', 'failed'): break
        time.sleep(0.01)
    assert job['status'] == 'completed', job
    assert job['recipe']['confirmed'] is False
    assert len(client.get('/api/v1/recipes').json()) == 1
    kitchen = client.get('/api/v1/kitchens/default').json()
    draft = job['recipe']
    draft['confirmed'] = True
    saved_draft = client.post('/api/v1/sync/edit', json={'kind': 'recipe', 'base': None, 'document': draft})
    assert saved_draft.status_code == 200, saved_draft.text
    final = client.post('/api/v1/recommendations/resolve', json={'names': ['番茄炒蛋', '清炒西兰花']}).json()['items']
    assert [item['status'] for item in final] == ['matched', 'matched']
    assert len(calls) == 2
    assert client.get('/api/v1/ai/status').json()['daily_used'] == 2
    ids = [item['recipe_id'] for item in final]
    plan = client.post('/api/v1/plans/from-recipes', json={
        'recipe_ids': ids, 'kitchen_id': kitchen['kitchen_id'], 'servings_by_recipe': {key: 4 for key in ids},
        'meal_preferences': {'mode': 'quick', 'time_minutes': 10, 'effort': 'low'}})
    assert plan.status_code == 200, plan.text
    result = plan.json()
    assert result['recipe_snapshots'][draft['recipe_id']]['ingredients'][1]['quantity'] == '3.48'
    assert not result['menu_assessment']['within_time_target']
    assert result['menu_assessment']['estimated_total_minutes'] == 12
    assert result['menu_assessment']['warnings']
