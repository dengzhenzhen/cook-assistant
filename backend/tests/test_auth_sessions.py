import pytest
from fastapi.testclient import TestClient
from service.app import app
from service.config import get_settings


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv('COOK_DATABASE_URL', f'sqlite+aiosqlite:///{tmp_path}/auth.db')
    monkeypatch.setenv('COOK_ALLOW_DEVELOPMENT_LOGIN', 'false')
    monkeypatch.setenv('COOK_JWT_SECRET', 'test-secret-only-012345678901234567890123456789')
    get_settings.cache_clear()
    with TestClient(app) as client:
        yield client
    get_settings.cache_clear()


def account(client, email='cook@example.com'):
    r = client.post('/api/v1/auth/register', json={'email': email, 'password': 'safe-test-password'})
    assert r.status_code == 201, r.text
    return r.json()


def headers(tokens):
    return {'Authorization': 'Bearer ' + tokens['access_token']}


def test_auth_rotation_logout_and_isolation(client):
    assert client.get('/api/v1/recipes').status_code == 401
    tokens = account(client)
    assert client.get('/api/v1/profile', headers=headers(tokens)).json()['development_mode'] is False
    assert client.post('/api/v1/auth/login', json={'email': 'cook@example.com', 'password': 'bad-password'}).status_code == 401
    assert client.post('/api/v1/auth/register', json={'email': 'cook@example.com', 'password': 'safe-test-password'}).status_code == 409
    refreshed = client.post('/api/v1/auth/refresh', json={'refresh_token': tokens['refresh_token']})
    assert refreshed.status_code == 200
    assert client.post('/api/v1/auth/refresh', json={'refresh_token': tokens['refresh_token']}).status_code == 401
    fresh = refreshed.json()
    assert client.post('/api/v1/auth/logout', json={'refresh_token': fresh['refresh_token']}).status_code == 204
    assert client.post('/api/v1/auth/refresh', json={'refresh_token': fresh['refresh_token']}).status_code == 401
    kitchen = client.get('/api/v1/kitchens/default', headers=headers(tokens)).json()
    other = account(client, 'other@example.com')
    assert client.put('/api/v1/kitchens/'+kitchen['kitchen_id'], headers=headers(other), json=kitchen).status_code == 404


def test_offline_snapshot_retry_conflict_and_immutable_completed_facts(client):
    tokens = account(client)
    h = headers(tokens)
    doc = {'snapshot': {'request': {'tasks': [{'id': 'a', 'recipe_id': 'r', 'name': '洗米', 'duration_seconds': 1}]}},
           'origin': '2026-10-28T00:00:00Z', 'states': {'a': {'status': 'running', 'started': 0}}}
    payload = {'session_id': 's', 'base_version': 0, 'mutation_id': 'first', 'document': doc}
    assert client.put('/api/v1/sessions/s', headers=h, json=payload).json()['version'] == 1
    assert client.put('/api/v1/sessions/s', headers=h, json=payload).json()['version'] == 1
    payload['mutation_id'] = 'second'
    assert client.put('/api/v1/sessions/s', headers=h, json=payload).status_code == 409
    payload['base_version'] = 1
    doc['states']['a'] = {'status': 'completed', 'started': 0, 'ended': 2}
    assert client.put('/api/v1/sessions/s', headers=h, json=payload).json()['version'] == 2
    payload['base_version'] = 2; payload['mutation_id'] = 'third'; doc['states'] = {}
    assert client.put('/api/v1/sessions/s', headers=h, json=payload).status_code == 409
    other = account(client, 'other@example.com')
    assert client.get('/api/v1/sessions/s', headers=headers(other)).status_code == 404
    assert len(client.get('/api/v1/sessions', headers=h).json()) == 1


def test_offline_edit_is_idempotent_and_rejects_stale_base(client):
    h = headers(account(client))
    recipe = {'recipe_id': 'r', 'name': '米饭', 'tasks': [{'id': 'a', 'recipe_id': 'r', 'name': '洗米', 'duration_seconds': 10}]}
    edit = {'kind': 'recipe', 'base': None, 'document': recipe}
    response = client.post('/api/v1/sync/edit', headers=h, json=edit)
    assert response.status_code == 200, response.text
    canonical = response.json()['document']
    assert client.post('/api/v1/sync/edit', headers=h, json=edit).status_code == 200
    edit['document'] = {**canonical, 'name': '离线改名'}
    assert client.post('/api/v1/sync/edit', headers=h, json=edit).status_code == 409
    edit['base'] = canonical
    assert client.post('/api/v1/sync/edit', headers=h, json=edit).status_code == 200
