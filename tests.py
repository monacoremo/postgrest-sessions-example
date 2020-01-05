'''
Integration tests for the PostgREST sessions example.

'''

import requests
import pytest
import os
import time


BASE_URL = os.environ.get('EXAMPLEAPP_URI', 'http://localhost:3000/')


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

    assert resp.status_code == 400


def test_login_wrong_password(alice_account, alice_email):
    'Logins with wrong passwords should fail.'
    resp = requests.post(f'{BASE_URL}rpc/login', json={
        'email': alice_email,
        'password': 'wrong_alicesecret',
    })

    assert resp.status_code == 400


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
    assert len(resp.json()) > 0
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


def test_create_todo_anonymous(alice_session):
    'Anonymous users should not be able to create todo items.'
    resp = alice_session.post(f'{BASE_URL}todos', json={
        'user_id': 1,
        'description': 'Test todo',
    })

    assert resp.status_code == 401
