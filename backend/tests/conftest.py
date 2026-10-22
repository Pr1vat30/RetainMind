"""Pytest configuration and automatic test isolation fixtures."""

from __future__ import annotations

from pathlib import Path
import pytest


@pytest.fixture(autouse=True)
def isolate_test_sandbox(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """Executes each test inside a dedicated temporary sandbox directory.

    All artifacts produced during tests (e.g. session_state.json, uploads/,
    data/courses/, examination_plan.json) are written strictly inside tmp_path
    and discarded automatically by pytest after the test finishes.

    This ensures that the user's real application history, courses, uploads,
    and session state in the workspace are NEVER touched, overwritten, or deleted.
    """
    monkeypatch.chdir(tmp_path)
    yield


@pytest.fixture
async def aiohttp_client():
    """Provides a TestClient for testing aiohttp applications without requiring pytest-aiohttp."""
    from aiohttp.test_utils import TestClient, TestServer

    clients = []

    async def _create_client(app):
        client = TestClient(TestServer(app))
        await client.start_server()
        clients.append(client)
        return client

    yield _create_client

    for client in clients:
        await client.close()

