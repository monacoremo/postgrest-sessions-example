'''
Integration tests for the PostgREST sessions full stack example.

'''

import os
import subprocess
import time

import requests
import pytest


BASE_URL = os.environ.get('FULLSTACK_URI', 'http://localhost:9000/')


def test_register():
    'Registering as an anonymous user should succeed.'
    session = requests.Session()
    resp = session.post(f'{BASE_URL}api/rpc/register', json={
        'email': f'registrationtest-{time.time()}@test.org',
        'name': 'Registration Test',
        'password': 'registrationsecret',
    })

    assert resp.status_code == 200
    assert resp.cookies.get('session_token')
