"""Tests for Pipecat WebRTC transport endpoints."""

from starlette.testclient import TestClient

from api import create_app


def test_webrtc_offer_endpoint_validation():
    app = create_app()
    client = TestClient(app)

    # Empty payload
    resp = client.post("/api/offer", json={})
    assert resp.status_code == 400
    assert "Missing required 'sdp' field" in resp.json()["detail"]


def test_health_reports_smallwebrtc_only():
    app = create_app()
    client = TestClient(app)

    resp = client.get("/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["transports"] == ["smallwebrtc"]


def test_token_returns_webrtc_endpoint_only():
    app = create_app()
    client = TestClient(app)

    resp = client.post("/api/token", json={"course_id": "classificazione"})
    assert resp.status_code == 201
    data = resp.json()
    assert data["webrtc_endpoint"] == "/api/offer"
    assert "websocket_endpoint" not in data
