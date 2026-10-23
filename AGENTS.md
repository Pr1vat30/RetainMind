# AGENTS.md

This backend is a FastAPI application with Pipecat voice pipelines. The Flutter client communicates with the API over REST and audio over WebSocket PCM; SmallWebRTC signaling is also available. See `../README.md` and `README.md` for setup and architecture.

## Project structure

This Python project uses `uv` for dependency management, server startup, and tests. Application code lives in `src/`. `src/api.py` is the unified FastAPI entrypoint; `src/agent.py` builds the Pipecat pipeline used by API-managed voice sessions.

Keep the existing separation between API/session management, voice processing, assessment, planning, and RAG ingestion. Check the implementation and configuration before documenting behavior: some providers and persistent stores are optional, and in-memory implementations are used by default in some paths.

Maintain formatting with Ruff when needed (`uv run ruff format` and `uv run ruff check`).

## Pipecat and provider documentation

Pipecat and model-provider APIs evolve. When changing transport or provider integrations, consult the relevant official Pipecat/provider documentation and verify assumptions against the versions pinned in `pyproject.toml` and `uv.lock`. The active client protocol is defined by `src/pcm_serializer.py` and the WebSocket routes in `src/api.py`.

## Voice pipeline and session behavior

The default `AGENT_PIPELINE_MODE` is `cascaded` (STT → LLM → TTS); `gemini_live` selects the native Gemini Live path. Keep the Flutter audio format, sample rates, interruption handling, and Pipecat frame flow aligned across client and server. Session state, plan expectations, retrieval context, assessment, and opening greetings must continue to use the same active course/session.

Prefer focused processors and explicit session functions over putting unrelated lifecycle behavior into a single prompt. Preserve graceful handling of provider failures and disconnects.

## Testing

Add or update focused tests for behavior changes when appropriate. Existing tests are under `tests/`; run them with `uv run pytest`. Ruff can be used for formatting and linting. Avoid tests that require live provider credentials or microphone hardware unless the test is explicitly designed as an integration test.

## Local development

Run the unified API and Pipecat server from this directory with `./start_api_server.sh`. `./start_agent_cloud.sh` is a compatibility alias to the same server; run only one of them at a time. Configure required provider keys in `.env` or `.env.local` (`.env.local` takes precedence).
