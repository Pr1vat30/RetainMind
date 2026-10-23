"""Pytest configuration and automatic test isolation fixtures."""

from __future__ import annotations

import asyncio
from pathlib import Path
import httpx
import pytest


@pytest.fixture(autouse=True)
def isolate_test_sandbox(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """Executes each test inside a dedicated temporary sandbox directory.

    All artifacts produced during tests (e.g. session_state.json, uploads/,
    data/courses/, examination_plan.json) are written strictly inside tmp_path
    and discarded automatically by pytest after the test finishes.
    """
    monkeypatch.chdir(tmp_path)
    yield


class WrappedResponse:
    def __init__(self, resp: httpx.Response):
        self._resp = resp
        self.status = resp.status_code
        self.status_code = resp.status_code
        self.headers = resp.headers

    async def json(self):
        return self._resp.json()

    async def text(self):
        return self._resp.text

    @property
    def content_type(self):
        return self.headers.get("content-type", "")


class WrappedClient:
    def __init__(self, client: httpx.AsyncClient):
        self._client = client

    def _convert_data(self, kwargs: dict) -> dict:
        data = kwargs.get("data")
        if data is not None and hasattr(data, "_fields"):
            form_data = {}
            files = {}
            for params, headers, value in data._fields:
                name = params.get("name")
                filename = params.get("filename")
                if filename:
                    ctype = headers.get("Content-Type", "application/octet-stream")
                    files[name] = (filename, value, ctype)
                else:
                    form_data[name] = value
            kwargs = dict(kwargs)
            kwargs["data"] = form_data
            if files:
                kwargs["files"] = files
        return kwargs

    async def get(self, url: str, **kwargs):
        r = await self._client.get(url, **kwargs)
        return WrappedResponse(r)

    async def post(self, url: str, **kwargs):
        kwargs = self._convert_data(kwargs)
        r = await self._client.post(url, **kwargs)
        return WrappedResponse(r)

    async def delete(self, url: str, **kwargs):
        kwargs = self._convert_data(kwargs)
        r = await self._client.delete(url, **kwargs)
        return WrappedResponse(r)

    async def options(self, url: str, **kwargs):
        r = await self._client.options(url, **kwargs)
        return WrappedResponse(r)

    async def patch(self, url: str, **kwargs):
        kwargs = self._convert_data(kwargs)
        r = await self._client.patch(url, **kwargs)
        return WrappedResponse(r)

    async def close(self):
        await self._client.aclose()


@pytest.fixture
async def aiohttp_client():
    """Provides an ASGI test client compatible with existing aiohttp test patterns."""
    clients = []

    async def _create_client(app):
        transport = httpx.ASGITransport(app=app)
        raw_client = httpx.AsyncClient(transport=transport, base_url="http://test")
        client = WrappedClient(raw_client)
        clients.append(client)
        return client

    yield _create_client

    for client in clients:
        await client.close()
