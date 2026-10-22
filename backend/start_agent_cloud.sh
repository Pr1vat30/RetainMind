#!/bin/bash
# Avvia l'agente collegato al server LiveKit Cloud
echo "☁️ Avvio Voice Agent collegato a LiveKit CLOUD..."
LIVEKIT_MODE=cloud uv run python src/agent.py dev
