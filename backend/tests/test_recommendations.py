import json

import httpx
import pytest
from fastapi.testclient import TestClient
from service.app import app
from service.config import get_settings
from service.database import ImportJob, RecipeRow
from service.recommendations import MenuRequest, generate_menu, parse_menu
from service.deepseek import AIError

@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv('COOK_DATABASE_URL', f'sqlite+aiosqlite:///{tmp_path}/menu.db')
    monkeypatch.setenv('COOK_ALLOW_DEVELOPMENT_LOGIN', 'true')
    monkeypatch.setenv('COOK_DEEPSEEK_API_KEY', 'fake-key')
    get_settings.cache_clear()
    with TestClient(app) as value:
        yield value
    get_settings.cache_clear()


def mock_deepseek(monkeypatch, dishes):
    requests = []
    def respond(request):
        requests.append(request)
        return httpx.Response(200, json={'choices': [{'finish_reason': 'stop',
            'message': {'content': json.dumps({'dishes': dishes}, ensure_ascii=False)}}],
            'usage': {'prompt_tokens': 12, 'completion_tokens': 8}})
    real_client = httpx.AsyncClient
    monkeypatch.setattr('service.recommendations.httpx.AsyncClient',
                        lambda **kwargs: real_client(transport=httpx.MockTransport(respond), **kwargs))
    return requests


def dish(name):
    return {'name': name, 'reason': '适合今天吃', 'estimated_minutes': 9, 'effort': 'low'}


@pytest.mark.parametrize('mode,count,minutes,effort', [
    ('quick', 1, 10, 'low'), ('everyday', 2, 30, 'medium'), ('feast', 3, 60, 'high')])
def test_all_modes_have_consistent_defaults(mode, count, minutes, effort):
    request = MenuRequest(mode=mode)
    assert (request.dish_count, request.time_minutes, request.effort) == (count, minutes, effort)


def test_ambiguous_saved_names_are_not_arbitrarily_matched():
    response = parse_menu(json.dumps({'dishes': [dish('番茄炒蛋')]}), MenuRequest(mode='quick'),
                          [{'id': 'a', 'name': '番茄炒蛋'}, {'id': 'b', 'name': '番茄炒蛋'}])
    assert response.dishes[0].matched_recipe_id is None


def test_provider_protocol_and_parser_without_database(monkeypatch):
    from pydantic import SecretStr
    from types import SimpleNamespace
    import asyncio
    requests = mock_deepseek(monkeypatch, [dish('  番茄炒蛋  ')])
    settings = SimpleNamespace(deepseek_api_key=SecretStr('fake'),
        deepseek_base_url='https://api.deepseek.com', deepseek_model='deepseek-flash')
    payload = MenuRequest(mode='quick')
    content, usage = asyncio.run(generate_menu(settings, payload, []))
    result = parse_menu(content, payload, [{'id': 'owned-id', 'name': '番茄炒蛋'}])
    assert result.dishes[0].matched_recipe_id == 'owned-id'
    assert result.dishes[0].name == '番茄炒蛋'
    assert usage['prompt_tokens'] == 12
    assert requests[0].url.path == '/chat/completions'
    assert '菜谱结构化解析器' not in json.loads(requests[0].read())['messages'][0]['content']
    with pytest.raises(AIError):
        parse_menu(json.dumps({'dishes': [dish('番茄炒蛋'), dish('番茄炒蛋')]}),
                   MenuRequest(mode='everyday'), [])


def test_menu_calls_deepseek_and_only_returns_names(client, monkeypatch):
    requests = mock_deepseek(monkeypatch, [dish('  番茄炒蛋  ')])
    result = client.post('/api/v1/recommendations/menu', json={'mode': 'quick'})
    assert result.status_code == 200, result.text
    assert result.json() == {'mode': 'quick', 'warnings': [], 'dishes': [
        {'name': '番茄炒蛋', 'reason': '适合今天吃', 'estimated_minutes': 9,
         'effort': 'low', 'matched_recipe_id': None}]}
    sent = json.loads(requests[0].read())
    brief = json.loads(sent['messages'][1]['content'])
    assert (brief['servings'], brief['dish_count'], brief['time_minutes']) == (2, 1, 10)
    assert '菜谱结构化解析器' not in sent['messages'][0]['content']
    assert client.get('/api/v1/recipes').json() == []
    assert client.get('/api/v1/ai/status').json()['input_tokens'] == 12
    assert client.get('/api/v1/ai/status').json()['daily_used'] == 1


def test_override_exclusions_and_malformed_result(client, monkeypatch):
    requests = mock_deepseek(monkeypatch, [dish('鱼香肉丝'), dish('鱼香肉丝')])
    payload = {'mode': 'feast', 'dish_count': 2, 'servings': 4,
               'time_minutes': 45, 'effort': 'medium', 'exclude_names': ['宫保鸡丁']}
    result = client.post('/api/v1/recommendations/menu', json=payload)
    assert result.status_code == 502
    brief = json.loads(json.loads(requests[0].read())['messages'][1]['content'])
    assert brief['dish_count'] == 2 and brief['servings'] == 4
    assert brief['exclude_names'] == ['宫保鸡丁']
    assert client.get('/api/v1/ai/status').json()['input_tokens'] == 12
    assert client.get('/api/v1/recipes').json() == []


def test_input_bounds_and_quota(client, monkeypatch):
    mock_deepseek(monkeypatch, [dish('番茄炒蛋')])
    assert client.post('/api/v1/recommendations/menu', json={
        'mode': 'quick', 'dish_count': 7}).status_code == 422
    assert client.post('/api/v1/recommendations/menu', json={
        'mode': 'quick', 'exclude_names': ['x' * 81]}).status_code == 422
    assert client.post('/api/v1/recommendations/menu', json={'mode': 'quick'}).status_code == 200
    assert client.post('/api/v1/recommendations/menu', json={'mode': 'quick'}).status_code == 200
    assert client.post('/api/v1/recommendations/menu', json={'mode': 'quick'}).status_code == 429


def test_owned_recipe_matching_and_accounting_job_not_imported(client, monkeypatch):
    # Add a foreign user's similarly named recipe; only the owner's recipe may match.
    from service.database import User
    import asyncio
    async def seed():
        async with app.state.sessions() as db:
            db.add(User(id='other-user', name='Other'))
            await db.flush()
            db.add(RecipeRow(id='foreign', user_id='other-user', document={'name': '番茄炒蛋'}))
            await db.commit()
    asyncio.run(seed())
    mock_deepseek(monkeypatch, [dish('番茄炒蛋')])
    response = client.post('/api/v1/recommendations/menu', json={'mode': 'quick'})
    assert response.status_code == 200
    assert response.json()['dishes'][0]['matched_recipe_id'] is None
    async def jobs():
        async with app.state.sessions() as db:
            from sqlalchemy import select
            return (await db.scalars(select(ImportJob))).all()
    records = asyncio.run(jobs())
    assert len(records) == 1
    assert records[0].status == 'completed'
    assert records[0].payload == {'kind': 'recommendation'}
    assert records[0].result is None
    assert app.state.import_worker.queue.empty()


def test_unconfigured_api_never_claims_recommendation(client, monkeypatch):
    from pydantic import SecretStr
    monkeypatch.setattr(app.state.settings, 'deepseek_api_key', SecretStr(''))
    result = client.post('/api/v1/recommendations/menu', json={'mode': 'quick'})
    assert result.status_code == 503
    assert result.json()['detail'] == '尚未配置 DeepSeek API。'


def saved_recipe(recipe_id, name, confirmed=True):
    return {'recipe_id': recipe_id, 'name': name, 'confirmed': confirmed,
            'tasks': [{'id': recipe_id + '-task', 'recipe_id': recipe_id,
                       'name': '煮熟', 'duration_seconds': 60}]}


def test_ingredients_are_sent_and_bounded(client, monkeypatch):
    requests = mock_deepseek(monkeypatch, [dish('番茄炒蛋')])
    response = client.post('/api/v1/recommendations/menu', json={
        'mode': 'quick', 'ingredients': [' 番茄 ', '鸡蛋']})
    assert response.status_code == 200, response.text
    brief = json.loads(json.loads(requests[0].read())['messages'][1]['content'])
    assert brief['ingredients'] == ['番茄', '鸡蛋']
    assert client.post('/api/v1/recommendations/menu', json={
        'mode': 'quick', 'ingredients': ['x' * 41]}).status_code == 422
    assert client.post('/api/v1/recommendations/menu', json={
        'mode': 'quick', 'ingredients': ['x'] * 31}).status_code == 422


def test_resolve_reuses_owned_recipes_and_requires_choice(client, monkeypatch):
    for recipe_id, name, confirmed in [('one', '番茄炒蛋', True),
                                       ('two', '鱼香肉丝', True),
                                       ('three', '鱼香肉丝', False),
                                       ('four', '蒸南瓜', False)]:
        assert client.post('/api/v1/recipes', json=saved_recipe(recipe_id, name, confirmed)).status_code == 201
    monkeypatch.setattr(app.state.import_worker.queue, 'put_nowait',
                        lambda _: pytest.fail('local matches must not import'))
    result = client.post('/api/v1/recommendations/resolve', json={
        'names': ['番茄炒蛋', '鱼香肉丝', '蒸南瓜']})
    assert result.status_code == 200, result.text
    items = result.json()['items']
    assert items[0] == {'name': '番茄炒蛋', 'status': 'matched', 'recipe_id': 'one'}
    assert items[1]['status'] == 'needs_choice'
    assert {item['recipe_id'] for item in items[1]['candidates']} == {'two', 'three'}
    assert items[2] == {'name': '蒸南瓜', 'status': 'needs_review', 'recipe_id': 'four'}
    choice = client.post('/api/v1/recommendations/resolve', json={
        'names': ['鱼香肉丝'], 'selected_recipe_ids': {'鱼香肉丝': 'three'}})
    assert choice.json()['items'][0]['status'] == 'needs_review'
    assert choice.json()['items'][0]['recipe_id'] == 'three'
    assert client.get('/api/v1/ai/status').json()['daily_used'] == 0


def test_resolve_normalization_and_foreign_selection_is_failure(client, monkeypatch):
    import asyncio
    from service.database import User
    async def seed():
        async with app.state.sessions() as db:
            db.add(User(id='foreign-user', name='Foreign'))
            await db.flush()
            db.add(RecipeRow(id='foreign-recipe', user_id='foreign-user',
                             document={'name': '番茄炒蛋', 'confirmed': True}))
            await db.commit()
    asyncio.run(seed())
    assert client.post('/api/v1/recipes', json=saved_recipe('mine', 'ＡＢＣ  菜')).status_code == 201
    monkeypatch.setattr(app.state.import_worker.queue, 'put_nowait',
                        lambda _: pytest.fail('invalid selection must not import'))
    result = client.post('/api/v1/recommendations/resolve', json={
        'names': ['ABC 菜'], 'selected_recipe_ids': {'ABC 菜': 'mine'}})
    assert result.json()['items'][0]['status'] == 'matched'
    denied = client.post('/api/v1/recommendations/resolve', json={
        'names': ['番茄炒蛋'], 'selected_recipe_ids': {'番茄炒蛋': 'foreign-recipe'}})
    assert denied.json()['items'][0]['status'] == 'failed'
    assert client.get('/api/v1/ai/status').json()['daily_used'] == 0


def test_resolve_import_cache_and_completed_draft(client, monkeypatch):
    import asyncio
    ids = []
    monkeypatch.setattr(app.state.import_worker.queue, 'put_nowait', ids.append)
    payload = {'names': ['番茄炒蛋']}
    first = client.post('/api/v1/recommendations/resolve', json=payload)
    assert first.status_code == 200, first.text
    item = first.json()['items'][0]
    assert item['status'] == 'import_pending'
    assert ids == [item['job_id']]
    again = client.post('/api/v1/recommendations/resolve', json=payload).json()['items'][0]
    assert again['job_id'] == item['job_id']
    assert ids == [item['job_id']]
    assert client.get('/api/v1/ai/status').json()['daily_used'] == 1
    async def complete():
        async with app.state.sessions() as db:
            job = await db.get(ImportJob, item['job_id'])
            job.status = 'completed'
            job.result = saved_recipe('draft-id', '番茄炒蛋', False)
            job.payload = {'parser_version': 2}
            await db.commit()
    asyncio.run(complete())
    completed = client.post('/api/v1/recommendations/resolve', json=payload).json()['items'][0]
    assert completed['status'] == 'import_pending'
    assert completed['job_id'] == item['job_id']
    job = client.get('/api/v1/import-jobs/' + item['job_id']).json()
    assert job['status'] == 'completed' and job['recipe']['confirmed'] is False
    assert client.get('/api/v1/recipes').json() == []


def test_resolve_preserves_successes_when_quota_exhausted(client, monkeypatch):
    ids = []
    monkeypatch.setattr(app.state.import_worker.queue, 'put_nowait', ids.append)
    result = client.post('/api/v1/recommendations/resolve', json={
        'names': ['番茄炒蛋', '鱼香肉丝', '蒸南瓜']})
    assert result.status_code == 200, result.text
    items = result.json()['items']
    assert [item['status'] for item in items] == ['import_pending', 'import_pending', 'failed']
    assert len(ids) == 2
    assert client.get('/api/v1/ai/status').json()['daily_used'] == 2
    retry = client.post('/api/v1/recommendations/resolve', json={
        'names': ['番茄炒蛋', '鱼香肉丝', '蒸南瓜']}).json()['items']
    assert [item['status'] for item in retry] == ['import_pending', 'import_pending', 'failed']
    assert [item['job_id'] for item in retry[:2]] == ids
    assert client.get('/api/v1/ai/status').json()['daily_used'] == 2


def test_resolve_keeps_local_match_when_api_missing(client, monkeypatch):
    from pydantic import SecretStr
    assert client.post('/api/v1/recipes', json=saved_recipe('local', '蒸南瓜')).status_code == 201
    monkeypatch.setattr(app.state.settings, 'deepseek_api_key', SecretStr(''))
    result = client.post('/api/v1/recommendations/resolve', json={
        'names': ['蒸南瓜', '番茄炒蛋']})
    assert result.status_code == 200
    assert [item['status'] for item in result.json()['items']] == ['matched', 'failed']
    assert client.get('/api/v1/ai/status').json()['daily_used'] == 0


def test_concurrent_resolve_of_normalized_name_only_enqueues_once(client, monkeypatch):
    from concurrent.futures import ThreadPoolExecutor
    queued = []
    monkeypatch.setattr(app.state.import_worker.queue, 'put_nowait', queued.append)
    with ThreadPoolExecutor(max_workers=3) as executor:
        responses = list(executor.map(lambda name: client.post('/api/v1/recommendations/resolve',
            json={'names': [name]}), ['ABC 菜', 'ＡＢＣ  菜', 'abc 菜']))
    assert all(response.status_code == 200 for response in responses)
    ids = {response.json()['items'][0]['job_id'] for response in responses}
    assert len(ids) == 1 and len(queued) == 1
    assert client.get('/api/v1/ai/status').json()['daily_used'] == 1
