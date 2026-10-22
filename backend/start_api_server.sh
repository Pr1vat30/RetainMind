#!/bin/bash
# Avvia il server REST & Token API per client Flutter
echo "🚀 Avvio RetainMind REST & Token API Server (http://0.0.0.0:8000)..."
uv run python src/api.py
