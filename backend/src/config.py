"""Configuration management for the Pipecat voice agent and RAG assessment pipeline.

Loads settings from `.env.local` (priority) or `.env` and provides a typed,
frozen dataclass with defaults for all pipeline modes (Gemini Live speech-to-speech,
cascaded STT->LLM->TTS, Neo4j, Qdrant, and Bayesian Knowledge Tracing).
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

# Load environment variables: .env.local takes precedence over .env
_backend_dir = Path(__file__).resolve().parent.parent
_env_local = _backend_dir / ".env.local"
_env = _backend_dir / ".env"
if _env_local.exists():
    load_dotenv(_env_local)
elif _env.exists():
    load_dotenv(_env)
else:
    load_dotenv()

# -----------------------------------------------------------------------------
# LiveKit Cloud Environment Resolution
# -----------------------------------------------------------------------------
livekit_env = "cloud"
if os.getenv("LIVEKIT_CLOUD_URL"):
    os.environ["LIVEKIT_URL"] = os.getenv("LIVEKIT_CLOUD_URL")
if os.getenv("LIVEKIT_CLOUD_API_KEY"):
    os.environ["LIVEKIT_API_KEY"] = os.getenv("LIVEKIT_CLOUD_API_KEY")
if os.getenv("LIVEKIT_CLOUD_API_SECRET"):
    os.environ["LIVEKIT_API_SECRET"] = os.getenv("LIVEKIT_CLOUD_API_SECRET")


@dataclass(frozen=True)
class VoiceAgentConfig:
    """Central configuration container for voice agents and backend services."""

    # -------------------------------------------------------------------------
    # LiveKit Server Mode (Cloud)
    # -------------------------------------------------------------------------
    livekit_mode: str = "cloud"
    livekit_url: str = os.getenv(
        "LIVEKIT_URL",
        os.getenv("LIVEKIT_CLOUD_URL", "wss://project-q-xfe1hcdq.livekit.cloud"),
    )
    livekit_api_key: str = os.getenv(
        "LIVEKIT_API_KEY",
        os.getenv("LIVEKIT_CLOUD_API_KEY", "test_devkey_cloud"),
    )
    livekit_api_secret: str = os.getenv(
        "LIVEKIT_API_SECRET",
        os.getenv("LIVEKIT_CLOUD_API_SECRET", "test_devsecret_cloud_32_bytes_long!"),
    )

    # -------------------------------------------------------------------------
    # Pipeline & Operational Modes
    # -------------------------------------------------------------------------
    # "gemini_live" = Bidirectional Speech-to-Speech via Google Realtime API
    # "cascaded"    = Sequential STT -> LLM -> TTS pipeline
    pipeline_mode: str = os.getenv("AGENT_PIPELINE_MODE", "cascaded")
    verbose_requests: bool = os.getenv("VERBOSE_REQUESTS", "true").lower() in (
        "true",
        "1",
        "yes",
    )

    # -------------------------------------------------------------------------
    # Pipecat & WebRTC / WebSocket Transport Configuration
    # -------------------------------------------------------------------------
    webrtc_mode: str = os.getenv(
        "WEBRTC_MODE", "smallwebrtc"
    )  # "smallwebrtc" | "livekit"
    webrtc_stun_servers: tuple[str, ...] = ("stun:stun.l.google.com:19302",)
    ws_sample_rate: int = int(os.getenv("WS_SAMPLE_RATE", "16000"))
    audio_sample_rate: int = int(os.getenv("AUDIO_SAMPLE_RATE", "24000"))

    # -------------------------------------------------------------------------
    # Google Gemini Live API Configuration
    # -------------------------------------------------------------------------
    gemini_live_model: str = os.getenv("GEMINI_LIVE_MODEL", "gemini-3.8-live")
    gemini_voice: str = os.getenv("GEMINI_VOICE", "Aoede")
    google_api_key: str = os.getenv("GOOGLE_API_KEY", "")
    plan_generation_model: str = os.getenv(
        "PLAN_GENERATION_MODEL", "gemini-3.5-flash-lite"
    )

    # -------------------------------------------------------------------------
    # Direct Provider API Keys
    # -------------------------------------------------------------------------
    openai_api_key: str = os.getenv("OPENAI_API_KEY", "")
    deepgram_api_key: str = os.getenv("DEEPGRAM_API_KEY", "")
    eleven_api_key: str = os.getenv(
        "ELEVEN_API_KEY", os.getenv("ELEVENLABS_API_KEY", "")
    )

    # -------------------------------------------------------------------------
    # Cascaded LLM Configuration
    # -------------------------------------------------------------------------
    llm_primary_model: str = os.getenv("AGENT_LLM_MODEL", "google/gemma-4-31b-it")
    llm_fallback_model: str = os.getenv(
        "AGENT_LLM_FALLBACK_MODEL", "openai/gpt-4.1-mini"
    )
    evaluator_model: str = os.getenv("AGENT_EVALUATOR_MODEL", "openai/gpt-4.1-mini")

    # -------------------------------------------------------------------------
    # Cascaded STT (Speech-to-Text) Configuration
    # -------------------------------------------------------------------------
    stt_primary_model: str = os.getenv("AGENT_STT_MODEL", "deepgram/nova-3")
    stt_language: str = os.getenv("AGENT_STT_LANGUAGE", "multi")
    stt_fallback_model: str = os.getenv(
        "AGENT_STT_FALLBACK_MODEL", "assemblyai/universal-3-5-pro"
    )

    # -------------------------------------------------------------------------
    # Cascaded TTS (Text-to-Speech) Configuration
    # -------------------------------------------------------------------------
    tts_primary_model: str = os.getenv(
        "AGENT_TTS_MODEL", "elevenlabs/eleven_turbo_v2_5"
    )
    tts_voice: str = os.getenv(
        "AGENT_TTS_VOICE",
        "Xb7hH8MSUJpSbSDYk0k2",  # Default: Alice (or your custom ElevenLabs Voice ID)
    )
    tts_language: str = os.getenv("AGENT_TTS_LANGUAGE", "it")
    tts_fallback_model: str = os.getenv("AGENT_TTS_FALLBACK_MODEL", "cartesia/sonic-3")
    tts_fallback_voice: str = os.getenv(
        "AGENT_TTS_FALLBACK_VOICE", "9626c31c-bec5-4cca-baa8-f8ba9e84c8bc"
    )

    # -------------------------------------------------------------------------
    # Agent Identity
    # -------------------------------------------------------------------------
    agent_name: str = os.getenv("LIVEKIT_AGENT_NAME", "study-examiner-agent")

    # -------------------------------------------------------------------------
    # Neo4j Graph Database Configuration
    # -------------------------------------------------------------------------
    neo4j_uri: str = os.getenv("NEO4J_URI", "bolt://localhost:7687")
    neo4j_user: str = os.getenv("NEO4J_USER", "neo4j")
    neo4j_password: str = os.getenv("NEO4J_PASSWORD", "password")
    neo4j_database: str = os.getenv("NEO4J_DATABASE", "neo4j")

    # -------------------------------------------------------------------------
    # Qdrant Vector Database Configuration
    # -------------------------------------------------------------------------
    qdrant_url: str = os.getenv("QDRANT_URL", "http://localhost:6333")
    qdrant_api_key: str = os.getenv("QDRANT_API_KEY", "")
    qdrant_collection: str = os.getenv("QDRANT_COLLECTION", "course_materials")

    # -------------------------------------------------------------------------
    # Dense Embedding Configuration
    # -------------------------------------------------------------------------
    embedding_provider: str = os.getenv(
        "EMBEDDING_PROVIDER", "mock"
    )  # "mock" | "openai" | "gemini"
    embedding_dimension: int = int(os.getenv("EMBEDDING_DIMENSION", "384"))

    # -------------------------------------------------------------------------
    # RAG & Bayesian Knowledge Tracing Hyperparameters
    # -------------------------------------------------------------------------
    rag_top_k_chunks: int = int(os.getenv("RAG_TOP_K_CHUNKS", "3"))
    bkt_init_mastery: float = float(os.getenv("BKT_INIT_MASTERY", "0.50"))
    bkt_accurate_gain: float = float(os.getenv("BKT_ACCURATE_GAIN", "0.35"))
    bkt_hesitation_decay: float = float(os.getenv("BKT_HESITATION_DECAY", "0.90"))
    bkt_mistake_decay: float = float(os.getenv("BKT_MISTAKE_DECAY", "0.60"))
    bkt_prerequisite_threshold: float = float(
        os.getenv("BKT_PREREQUISITE_THRESHOLD", "0.45")
    )
    max_scaffolding_attempts: int = int(os.getenv("MAX_SCAFFOLDING_ATTEMPTS", "2"))


# Global singleton configuration instance
config = VoiceAgentConfig()
