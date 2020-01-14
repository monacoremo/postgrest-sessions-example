'''
Integration tests for the PostgREST sessions example.

'''

import os
import subprocess
import time

import requests
import pytest


BASE_URL = os.environ.get('EXAMPLEAPP_URI', 'http://localhost:3000/')
DB_URI = os.environ.get('EXAMPLEAPP_TESTS_DB_URI')


@pytest.mark.skipif(DB_URI is None,
                    reason='$EXAMPLEAPP_TESTS_DB_URI required for running db tests')
def test_db():
    'Run tests that are defined in the database schema.'
    result = subprocess.run(
        ['psql', DB_URI, '-c', 'select tests.run();'],
        capture_output=True,
        check=True,
    )

    test_results = result.stdout.decode('utf-8').split('\n')

    for line in test_results:
        assert not line.strip().startswith('not ok')


@pytest.fixture(scope='session')
def alice_email():
    'Fixture for a user email.'
    return f'alice-{time.time()}@test.org'


@pytest.fixture(scope='session')
def alice_account(alice_email):
    'Fixture for a user account.'
    session = requests.Session()
    resp = session.post(f'{BASE_URL}rpc/register', json={
        'email': alice_email,
        'name': 'Alice',
        'password': 'alicesecret',
    })

    assert resp.status_code == 200


@pytest.fixture()
def alice_session(alice_email, alice_account):
    'Fixture for a logged in web session'
    session = requests.Session()
    resp = session.post(f'{BASE_URL}rpc/login', json={
        'email': alice_email,
        'password': 'alicesecret',
    })

    assert resp.status_code == 200

    return session


@pytest.fixture(scope='session')
def bob_email():
    'Fixture for a user email.'
    return f'bob-{time.time()}@test.org'


@pytest.fixture(scope='session')
def bob_account(bob_email):
    'Fixture for a user account.'
    session = requests.Session()
    resp = session.post(f'{BASE_URL}rpc/register', json={
        'email': bob_email,
        'name': 'Bob',
        'password': 'bobsecret',
    })

    assert resp.status_code == 200


@pytest.fixture()
def bob_session(bob_email, bob_account):
    'Fixture for a logged in web session'
    session = requests.Session()
    resp = session.post(f'{BASE_URL}rpc/login', json={
        'email': bob_email,
        'password': 'bobsecret',
    })

    assert resp.status_code == 200

    return session


def test_register():
    'Registering as an anonymous user should succeed.'
    session = requests.Session()
    resp = session.post(f'{BASE_URL}rpc/register', json={
        'email': f'registrationtest-{time.time()}@test.org',
        'name': 'Registration Test',
        'password': 'registrationsecret',
    })

    assert resp.status_code == 200
    assert resp.cookies.get('session_token')


def test_register_repeated(alice_session):
    'Registering when already logged in should not be allowed.'
    resp = alice_session.post(f'{BASE_URL}rpc/register', json={
        'email': f'registrationtest-{time.time()}@test.org',
        'name': 'Registration Test',
        'password': 'registrationsecret',
    })

    assert resp.status_code == 401
    assert resp.cookies.get('session_token') is None


def test_login(alice_account, alice_email):
    'Logging in with valid credentials should succeed.'
    session = requests.Session()
    resp = session.post(f'{BASE_URL}rpc/login', json={
        'email': alice_email,
        'password': 'alicesecret',
    })

    assert resp.status_code == 200
    assert resp.cookies.get('session_token')


def test_login_repeated(alice_email, alice_session):
    'A logged in user should not be able to log in again.'
    resp = alice_session.post(f'{BASE_URL}rpc/login', json={
        'email': alice_email,
        'password': 'alicesecret',
    })
    assert resp.status_code == 401


def test_login_wrong_email(alice_account, alice_email):
    'Logins with wrong emails should fail.'
    resp = requests.post(f'{BASE_URL}rpc/login', json={
        'email': 'wrong_' + alice_email,
        'password': 'alicesecret',
    })

    assert resp.status_code == 401


def test_login_wrong_password(alice_account, alice_email):
    'Logins with wrong passwords should fail.'
    resp = requests.post(f'{BASE_URL}rpc/login', json={
        'email': alice_email,
        'password': 'wrong_alicesecret',
    })

    assert resp.status_code == 401


def test_current_user(alice_session):
    'Logged in users should be able to access information on their own account.'
    resp = requests.get(f'{BASE_URL}rpc/current_user')
    assert resp.status_code == 401

    resp = alice_session.get(f'{BASE_URL}rpc/current_user')
    assert resp.status_code == 200
    assert resp.json()[0]['name'] == 'Alice'


def test_logout(alice_session):
    'Logging out should be possible for logged in users and change permissions.'
    resp = alice_session.get(f'{BASE_URL}rpc/current_user')
    assert resp.status_code == 200

    resp = alice_session.post(f'{BASE_URL}rpc/logout')
    assert resp.status_code == 200

    resp = alice_session.get(f'{BASE_URL}rpc/current_user')
    assert resp.status_code == 401

    resp = alice_session.post(f'{BASE_URL}rpc/logout')
    assert resp.status_code == 401


def test_refresh_session(alice_session):
    'Refreshing a session should succeed and set a new cookie.'
    resp = alice_session.post(f'{BASE_URL}rpc/refresh_session')

    assert resp.status_code == 200
    assert resp.cookies.get('session_token')


def test_users(alice_session):
    'Logged in users should be able to get a listing of users.'
    current_user = alice_session.get(f'{BASE_URL}rpc/current_user').json()[0]

    resp = alice_session.get(f'{BASE_URL}users')

    assert resp.status_code == 200
    assert current_user['user_id'] in (user['user_id'] for user in resp.json())


def test_create_todo(alice_session):
    'A user should be able to create todo items.'
    current_user = alice_session.get(f'{BASE_URL}rpc/current_user').json()[0]

    resp = alice_session.post(f'{BASE_URL}todos', json={
        'user_id': current_user['user_id'],
        'description': 'Test todo',
    }, headers={'Prefer': 'return=representation'})

    assert resp.status_code == 201
    assert resp.json()[0]['description'] == 'Test todo'


def test_todo_visibility(alice_session, bob_session):
    'A user should only be able to see his own and public todos.'
    current_user = alice_session.get(f'{BASE_URL}rpc/current_user').json()[0]

    todo_desc = f'Alice test todo {time.time()}'

    resp = alice_session.post(f'{BASE_URL}todos', json={
        'user_id': current_user['user_id'],
        'description': todo_desc,
    }, headers={'Prefer': 'return=representation'})
    assert resp.status_code == 201

    # Create a new todo item
    resp = alice_session.get(f'{BASE_URL}todos')
    assert todo_desc in (todo['description'] for todo in resp.json())

    # The todo item should not be visible for other users
    resp = bob_session.get(f'{BASE_URL}todos')
    assert todo_desc not in (todo['description'] for todo in resp.json())

    # Set all todo items from alice to be public
    resp = alice_session.patch(f'{BASE_URL}todos', json={'public': True})
    assert resp.status_code == 204

    # Other users should now be able to see it
    resp = bob_session.get(f'{BASE_URL}todos')
    assert todo_desc in (todo['description'] for todo in resp.json())


def test_create_todo_anonymous(alice_session):
    'Anonymous users should not be able to create todo items.'
    resp = alice_session.post(f'{BASE_URL}todos', json={
        'user_id': 1,
        'description': 'Test todo',
    })

    assert resp.status_code == 401
