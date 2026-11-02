import time
import pytest
from fastapi.testclient import TestClient
from service.app import app
from service.config import get_settings


def recipe():
    return {'recipe_id':'test-recipe','name':'煮米饭','tasks':[
        {'id':'wash','recipe_id':'test-recipe','name':'洗米','notes':'按刻度加水。','duration_seconds':30},
        {'id':'cook','recipe_id':'test-recipe','name':'电饭煲煮饭','duration_seconds':600,
         'dependencies':['wash'],'attention_type':'passive','resources':{'rice_cooker':1}}]}


@pytest.fixture
def client(tmp_path,monkeypatch):
    monkeypatch.setenv('COOK_DATABASE_URL',f'sqlite+aiosqlite:///{tmp_path}/test.db')
    monkeypatch.setenv('COOK_ALLOW_DEVELOPMENT_LOGIN','true')
    monkeypatch.setenv('COOK_DEEPSEEK_API_KEY','test-key-not-real')
    get_settings.cache_clear()
    with TestClient(app) as c: yield c
    get_settings.cache_clear()


def test_recipe_kitchen_and_plan_persist_across_requests(client):
    assert client.post('/api/v1/recipes',json=recipe()).status_code==201
    assert client.get('/api/v1/recipes').json()[0]['tasks'][0]['notes']=='按刻度加水。'
    kitchen=client.get('/api/v1/kitchens/default').json()
    kitchen['capacities']['oven']=0
    assert client.put('/api/v1/kitchens/'+kitchen['kitchen_id'],json=kitchen).status_code==200
    assert client.get('/api/v1/kitchens/default').json()['capacities']['oven']==0
    from datetime import datetime,timedelta,timezone
    response=client.post('/api/v1/plans/from-recipes',json={'recipe_ids':['test-recipe'],
        'kitchen_id':kitchen['kitchen_id'],'target_finish_time':(datetime.now(timezone.utc)+timedelta(hours=1)).isoformat()})
    assert response.status_code==200,response.text
    assert response.json()['plan']['allocations']
    assert client.delete('/api/v1/recipes/test-recipe').status_code==204
    assert client.get('/api/v1/recipes/test-recipe').status_code==404


def test_validation_rejects_bad_dependency_and_draft_planning(client):
    data=recipe();data['tasks'][0]['dependencies']=['cook']
    assert client.post('/api/v1/recipes',json=data).status_code==422
    data=recipe();data['confirmed']=False
    assert client.post('/api/v1/recipes',json=data).status_code==201
    kitchen=client.get('/api/v1/kitchens/default').json()
    from datetime import datetime,timedelta,timezone
    response=client.post('/api/v1/plans/from-recipes',json={'recipe_ids':['test-recipe'],
        'kitchen_id':kitchen['kitchen_id'],'target_finish_time':(datetime.now(timezone.utc)+timedelta(hours=1)).isoformat()})
    assert response.status_code==422


def test_async_import_cache_and_usage(client,monkeypatch):
    import json
    async def fake_complete(*args):
        data=recipe();data.pop('recipe_id');data.pop('confirmed',None)
        return json.dumps(data),{'prompt_tokens':100,'completion_tokens':200}
    monkeypatch.setattr('service.imports.complete',fake_complete)
    response=client.post('/api/v1/recipes/import/text',json={'text':'大米洗净后，电饭煲煮熟。'})
    assert response.status_code==202,response.text
    job_id=response.json()['job_id']
    for _ in range(100):
        job=client.get('/api/v1/import-jobs/'+job_id).json()
        if job['status'] in ('completed','failed'): break
        time.sleep(.01)
    assert job['status']=='completed',job
    assert job['recipe']['confirmed'] is False
    assert job['recipe']['tasks'][0]['recipe_id']==job['recipe']['recipe_id']
    again=client.post('/api/v1/recipes/import/text',json={'text':'大米洗净后，电饭煲煮熟。'}).json()
    assert again['job_id']==job_id
    status=client.get('/api/v1/ai/status').json()
    assert status['daily_used']==1 and status['input_tokens']==100
    assert 'test-key-not-real' not in str(status)


def test_quota_does_not_disable_manual_recipe_creation(client,monkeypatch):
    monkeypatch.setenv('COOK_AI_DAILY_LIMIT','0');get_settings.cache_clear()
    app.state.settings=get_settings()
    response=client.post('/api/v1/recipes/import/text',json={'text':'鸡蛋煎熟后加盐。'})
    assert response.status_code==429
    assert client.post('/api/v1/recipes',json=recipe()).status_code==201


def test_recipe_survives_application_restart(tmp_path,monkeypatch):
    monkeypatch.setenv('COOK_DATABASE_URL',f'sqlite+aiosqlite:///{tmp_path}/persistent.db')
    monkeypatch.setenv('COOK_ALLOW_DEVELOPMENT_LOGIN','true')
    get_settings.cache_clear()
    with TestClient(app) as c: assert c.post('/api/v1/recipes',json=recipe()).status_code==201
    with TestClient(app) as c: assert c.get('/api/v1/recipes/test-recipe').json()['name']=='煮米饭'
    get_settings.cache_clear()


def test_invalid_ai_structure_gets_only_one_repair_and_records_both_calls(client,monkeypatch):
    import json
    calls=[]
    async def fake_complete(settings,text,images=None):
        calls.append(text)
        value=recipe();value.pop('recipe_id')
        if len(calls)==1:value['tasks'][0]['dependencies']=['missing']
        return json.dumps(value),{'prompt_tokens':10,'completion_tokens':20}
    monkeypatch.setattr('service.imports.complete',fake_complete)
    job=client.post('/api/v1/recipes/import/text',json={'text':'洗米后电饭煲煮熟，测试修正。'}).json()
    for _ in range(100):
        result=client.get('/api/v1/import-jobs/'+job['job_id']).json()
        if result['status'] in ('completed','failed'):break
        time.sleep(.01)
    assert result['status']=='completed',result
    assert len(calls)==2
    usage=client.get('/api/v1/ai/status').json()
    assert usage['input_tokens']==20 and usage['daily_used']==1


def test_name_only_import_searches_then_parses_recipe(client,monkeypatch):
    import json
    calls=[]
    async def fake_complete(settings,text,images=None):
        calls.append(('complete',text))
        if len(calls)==1:
            return json.dumps({'name_only':True,'name':'番茄炒蛋'}),{'prompt_tokens':5,'completion_tokens':5}
        value=recipe();value.pop('recipe_id');value['name']='番茄炒蛋'
        return json.dumps(value),{'prompt_tokens':10,'completion_tokens':20}
    async def fake_search(settings,name):
        calls.append(('search',name))
        return '番茄炒蛋：鸡蛋打散，番茄切块，炒熟。'
    monkeypatch.setattr('service.imports.complete',fake_complete)
    monkeypatch.setattr('service.imports.search_recipe',fake_search)
    job=client.post('/api/v1/recipes/import/text',json={'text':'番茄炒蛋'}).json()
    for _ in range(100):
        result=client.get('/api/v1/import-jobs/'+job['job_id']).json()
        if result['status'] in ('completed','failed'):break
        time.sleep(.01)
    assert result['status']=='completed',result
    assert result['recipe']['name']=='番茄炒蛋'
    assert [call[0] for call in calls]==['complete','search','complete']
    assert '番茄炒蛋：鸡蛋打散' in calls[2][1]
    assert client.get('/api/v1/ai/status').json()['input_tokens']==15


def test_name_only_import_fails_without_search_results(client,monkeypatch):
    from service.deepseek import AIError
    calls=[]
    async def fake_complete(settings,text,images=None):
        calls.append(text)
        return '{"name_only":true,"name":"不存在的菜"}',{'prompt_tokens':5}
    async def fake_search(settings,name):
        raise AIError('未搜索到这道菜的可用菜谱，请输入食材和做法后重试。')
    monkeypatch.setattr('service.imports.complete',fake_complete)
    monkeypatch.setattr('service.imports.search_recipe',fake_search)
    job=client.post('/api/v1/recipes/import/text',json={'text':'不存在的菜'}).json()
    for _ in range(100):
        result=client.get('/api/v1/import-jobs/'+job['job_id']).json()
        if result['status'] in ('completed','failed'):break
        time.sleep(.01)
    assert result['status']=='failed'
    assert '未搜索到' in result['error']
    assert len(calls)==1


def test_text_import_accepts_short_dish_names_but_rejects_whitespace(client,monkeypatch):
    from service.deepseek import AIError
    async def fake_complete(settings,text,images=None):
        return '{"name_only":true,"name":"米饭"}',{'prompt_tokens':1}
    async def fake_search(settings,name):
        raise AIError('未搜索到这道菜的可用菜谱，请输入食材和做法后重试。')
    monkeypatch.setattr('service.imports.complete',fake_complete)
    monkeypatch.setattr('service.imports.search_recipe',fake_search)
    assert client.post('/api/v1/recipes/import/text',json={'text':'米饭'}).status_code==202
    assert client.post('/api/v1/recipes/import/text',json={'text':'   '}).status_code==422


def test_search_recipe_uses_deepseek_search_endpoint(monkeypatch):
    import asyncio
    import httpx
    from pydantic import SecretStr
    from types import SimpleNamespace
    from service.deepseek import search_recipe
    requests=[]
    def respond(request):
        requests.append(request)
        return httpx.Response(200,json={'results':[{'title':'做法','url':'https://example.com/recipe',
            'content':'食材：鸡蛋、番茄；步骤：切、炒。'}]})
    original_client=httpx.AsyncClient
    monkeypatch.setattr('service.deepseek.httpx.AsyncClient',
        lambda **kwargs:original_client(transport=httpx.MockTransport(respond),**kwargs))
    settings=SimpleNamespace(deepseek_api_key=SecretStr('test-key'),deepseek_base_url='https://api.deepseek.com')
    material=asyncio.run(search_recipe(settings,'番茄炒蛋'))
    assert requests[0].url.path=='/v1/tools/search'
    assert requests[0].read().decode().find('"need_content":true')>=0
    assert '食材：鸡蛋、番茄' in material


def test_numeric_ingredient_quantity_is_preserved_as_text():
    import json
    from service.deepseek import parse_result
    value=recipe();value.pop('recipe_id');value['ingredients']=[{'name':'大米','quantity':200,'unit':'g'}]
    assert parse_result(json.dumps(value),'text').ingredients[0].quantity=='200'


def test_ai_resource_holds_do_not_double_count_task_demands():
    import json
    from service.deepseek import parse_result
    from cook_scheduler import Request,generate_plan
    value=recipe();value.pop('recipe_id')
    value['holds']=[{'resource':'rice_cooker','quantity':1,'start_task':'wash','end_task':'cook'}]
    result=parse_result(json.dumps(value),'text')
    assert result.tasks[1].resources=={}
    plan=generate_plan(Request(tasks=result.tasks,holds=result.holds,capacities={'rice_cooker':1}))
    assert plan.finish_seconds==630


def test_ai_normalization_retains_additional_resource_demand():
    import json
    from service.deepseek import parse_result
    value=recipe();value.pop('recipe_id');value['tasks'][1]['resources']['rice_cooker']=2
    value['holds']=[{'resource':'rice_cooker','quantity':1,'start_task':'wash','end_task':'cook'}]
    result=parse_result(json.dumps(value),'text')
    assert result.tasks[1].resources=={'rice_cooker':1}


def test_canonical_ai_cache_does_not_subtract_held_resources_twice():
    import json
    from types import SimpleNamespace
    from service.deepseek import parse_result
    from service.api.ai import job_view
    value=recipe();value.pop('recipe_id');value['tasks'][1]['resources']['rice_cooker']=2
    value['holds']=[{'resource':'rice_cooker','quantity':1,'start_task':'wash','end_task':'cook'}]
    normalized=parse_result(json.dumps(value),'text')
    job=SimpleNamespace(id='job',status='completed',result=normalized.model_dump(),error=None,payload={'parser_version':2})
    assert job_view(job)['recipe']['tasks'][1]['resources']=={'rice_cooker':1}


@pytest.mark.parametrize('include_null', [False, True])
def test_plan_without_target_time(client, include_null):
    assert client.post('/api/v1/recipes', json=recipe()).status_code == 201
    kitchen = client.get('/api/v1/kitchens/default').json()
    payload = {'recipe_ids': ['test-recipe'], 'kitchen_id': kitchen['kitchen_id']}
    if include_null:
        payload['target_finish_time'] = None
    result = client.post('/api/v1/plans/from-recipes', json=payload)
    assert result.status_code == 200, result.text
    assert result.json()['request']['target_finish_seconds'] is None
    assert result.json()['plan']['lateness_seconds'] == 0
    assert min(t['start_seconds'] for t in result.json()['plan']['tasks']) == 0


def test_plan_reports_missing_oven_without_target(client):
    data = recipe()
    data['tasks'][0]['resources'] = {'oven': 1}
    assert client.post('/api/v1/recipes', json=data).status_code == 201
    kitchen = client.get('/api/v1/kitchens/default').json()
    result = client.post('/api/v1/plans/from-recipes', json={
        'recipe_ids': ['test-recipe'], 'kitchen_id': kitchen['kitchen_id']})
    assert result.status_code == 409
    assert result.json()['detail'] == 'insufficient resource oven: need 1, available 0'
