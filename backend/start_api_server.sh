#!/bin/bash
# Avvia il server unificato FastAPI + Pipecat (REST, WebRTC SmallWebRTC & WebSocket per Flutter)
echo "🚀 Avvio RetainMind Pipecat API Server su http://0.0.0.0:8000..."
uv run uvicorn src.api:app --host 0.0.0.0 --port 8000 --reload
