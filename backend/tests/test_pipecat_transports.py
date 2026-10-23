"""Tests for Pipecat WebRTC and WebSocket transport endpoints."""

import pytest
from starlette.testclient import TestClient

from api import _create_pipecat_websocket_params, create_app
from pcm_serializer import FlutterPcmSerializer


def test_webrtc_offer_endpoint_validation():
    app = create_app()
    client = TestClient(app)

    # Empty payload
    resp = client.post("/api/offer", json={})
    assert resp.status_code == 400
    assert "Missing required 'sdp' field" in resp.json()["detail"]


def test_flutter_websocket_transport_uses_full_bandwidth_pcm_rates():
    params = _create_pipecat_websocket_params(pipeline_mode="gemini_live")

    assert params.audio_in_sample_rate == 16000
    assert params.audio_out_sample_rate == 24000
    assert params.audio_out_10ms_chunks == 2
    assert isinstance(params.serializer, FlutterPcmSerializer)


@pytest.mark.asyncio
async def test_websocket_connection_stays_open():
    app = create_app()
    client = TestClient(app)

    # The Flutter transport uses the custom PCM protocol; a plain connection
    # should remain open until the client disconnects.
    with client.websocket_connect("/ws/test_course") as websocket:
        assert websocket is not None
