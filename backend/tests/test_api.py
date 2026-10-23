import json
import pytest
from aiohttp import web
from aiohttp.test_utils import AioHTTPTestCase, unittest_run_loop

from api import create_app
from config import config


@pytest.mark.asyncio
async def test_api_health_endpoint(aiohttp_client):
    app = create_app()
    client = await aiohttp_client(app)
    resp = await client.get("/health")
    assert resp.status == 200
    data = await resp.json()
    assert data["status"] == "healthy"
    assert "livekit_mode" in data
    assert resp.headers.get("Access-Control-Allow-Origin") == "*"


@pytest.mark.asyncio
async def test_api_token_endpoint(aiohttp_client):
    app = create_app()
    client = await aiohttp_client(app)
    payload = {
        "room_name": "test-exam-room",
        "participant_identity": "student_123",
        "participant_name": "Mario Rossi",
    }
    resp = await client.post("/api/token", json=payload)
    assert resp.status == 201
    data = await resp.json()
    assert data["room_name"] == "test-exam-room"
    assert data["participant_identity"] == "student_123"
    assert "participant_token" in data
    assert len(data["participant_token"]) > 20
    assert "server_url" in data
    assert resp.headers.get("Access-Control-Allow-Origin") == "*"


@pytest.mark.asyncio
async def test_api_get_token_alias(aiohttp_client):
    """Verifies that standard LiveKit /getToken endpoint works identically."""
    app = create_app()
    client = await aiohttp_client(app)
    resp = await client.post("/getToken", json={"room_name": "alias-room"})
    assert resp.status == 201
    data = await resp.json()
    assert data["room_name"] == "alias-room"
    assert "participant_token" in data


@pytest.mark.asyncio
async def test_api_cors_options(aiohttp_client):
    app = create_app()
    client = await aiohttp_client(app)
    resp = await client.options("/api/token")
    assert resp.status == 204
    assert resp.headers.get("Access-Control-Allow-Origin") == "*"
    assert "POST" in resp.headers.get("Access-Control-Allow-Methods", "")


@pytest.mark.asyncio
async def test_api_session_status_and_transcript(aiohttp_client):
    app = create_app()
    client = await aiohttp_client(app)

    # Status
    resp = await client.get("/api/session/status")
    assert resp.status == 200
    status_data = await resp.json()
    assert "has_active_session" in status_data

    # Transcript
    resp_tr = await client.get("/api/session/transcript")
    assert resp_tr.status == 200
    tr_data = await resp_tr.json()
    assert "turns" in tr_data


@pytest.mark.asyncio
async def test_api_document_upload_json(aiohttp_client, monkeypatch):
    from rag.ingestion.extractor import KnowledgeExtractor
    from rag.models import ConceptNode

    def mock_extract(*args, **kwargs):
        c = ConceptNode(
            id="dolo_e_colpa",
            name="Dolo e Colpa",
            summary="Definizione di dolo e colpa in diritto penale.",
            prerequisites=[],
            contrasts_with=[],
            properties={"difficulty": "MEDIUM"},
        )
        return [c], [], []

    monkeypatch.setattr(KnowledgeExtractor, "extract_with_llm", mock_extract)

    app = create_app()
    client = await aiohttp_client(app)

    payload = {
        "title": "Diritto Penale",
        "content": "# Fondamenti di Diritto Penale\nIl reato e l'elemento soggettivo.\n## Dolo e Colpa\nDefinizione di dolo.",
        "filename": "appunti_penale.md",
    }
    resp = await client.post("/api/documents/upload", json=payload)
    assert resp.status == 201
    data = await resp.json()
    assert data["success"] is True
    assert "title" in data
    assert "concepts" in data


@pytest.mark.asyncio
async def test_api_document_upload_multipart(aiohttp_client, monkeypatch):
    from aiohttp import FormData
    from rag.ingestion.extractor import KnowledgeExtractor
    from rag.models import ConceptNode

    def mock_extract(*args, **kwargs):
        c = ConceptNode(
            id="deadlock",
            name="Deadlock",
            summary="Condizioni di Coffman e gestione deadlock.",
            prerequisites=[],
            contrasts_with=[],
            properties={"difficulty": "MEDIUM"},
        )
        return [c], [], []

    monkeypatch.setattr(KnowledgeExtractor, "extract_with_llm", mock_extract)

    app = create_app()
    client = await aiohttp_client(app)

    data = FormData()
    data.add_field("title", "Sistemi Operativi")
    data.add_field(
        "file",
        b"# Sistemi Operativi\nGestione processi e thread.\n## Deadlock\nCondizioni di Coffman.",
        filename="sistemi_operativi.txt",
        content_type="text/plain",
    )

    resp = await client.post("/api/documents/upload", data=data)
    assert resp.status == 201
    res_json = await resp.json()
    assert res_json["success"] is True
    assert res_json["title"] == "Sistemi Operativi"
    assert "total_concepts" in res_json

    # Verify history is completely clean and has no phantom completed conversations
    resp_hist = await client.get("/api/session/history")
    assert resp_hist.status == 200
    hist_json = await resp_hist.json()
    # No completed phantom iteration should exist after uploading a document!
    completed = [h for h in hist_json.get("history", []) if h.get("status") == "COMPLETED"]
    assert len(completed) == 0


@pytest.mark.asyncio
async def test_api_session_new_and_delete(aiohttp_client):
    app = create_app()
    client = await aiohttp_client(app)

    # 1. Start a new isolated discussion
    resp_new = await client.post("/api/session/new")
    assert resp_new.status == 200
    new_data = await resp_new.json()
    assert new_data["success"] is True
    assert "room_name" in new_data
    assert "oral-exam-" in new_data["room_name"]
    it_num = new_data["iteration"]

    # 2. Delete the iteration from the server
    resp_del = await client.delete(f"/api/session/history/{it_num}")
    assert resp_del.status == 200
    del_data = await resp_del.json()
    assert del_data["success"] is True

    # 3. Reset all sessions on the server
    resp_reset = await client.post("/api/session/reset", json={"delete_plan": False})
    assert resp_reset.status == 200
    reset_data = await resp_reset.json()
    assert reset_data["success"] is True


@pytest.mark.asyncio
async def test_api_courses_and_separation(aiohttp_client, monkeypatch, tmp_path):
    """Verifies that courses and sessions are strictly separated in dedicated folders."""
    from rag.ingestion.extractor import KnowledgeExtractor
    from rag.models import ConceptNode, ConceptStatus
    from pathlib import Path

    def mock_extract(*args, **kwargs):
        c = ConceptNode(
            id="query_optimization",
            name="Ottimizzazione delle Query",
            summary="Sintesi",
            status=ConceptStatus.UNTESTED,
            mastery_score=0.5,
            properties={"main_question": "Come funziona l'optimizer?"},
        )
        return [c], [], []

    monkeypatch.setattr(KnowledgeExtractor, "extract_with_llm", mock_extract)

    app = create_app()
    client = await aiohttp_client(app)

    # 1. Upload new course
    payload = {
        "title": "Basi di Dati NoSQL",
        "content": "# NoSQL\nSistemi distribuiti e sharding.",
        "filename": "nosql_guide.md",
    }
    resp = await client.post("/api/documents/upload", json=payload)
    assert resp.status == 201
    data = await resp.json()
    assert data["success"] is True
    course_id = data["course_id"]
    assert "nosql" in course_id

    # 2. Verify dedicated course directory structure
    course_dir = Path("data/courses") / course_id
    assert course_dir.exists()
    assert (course_dir / "plan.json").exists()
    assert (course_dir / "metadata.json").exists()
    assert (course_dir / "sessions").exists()

    # 3. Check /api/courses listing
    resp_courses = await client.get("/api/courses")
    assert resp_courses.status == 200
    courses_data = await resp_courses.json()
    assert courses_data["active_course_id"] == course_id
    assert any(c["id"] == course_id for c in courses_data["courses"])


@pytest.mark.asyncio
async def test_api_interrupt_and_resume_updates_single_item(aiohttp_client, monkeypatch):
    """Verifies that interrupting and resuming conversation does NOT create new session items,
    and that the document item is updated in place.
    """
    from rag.ingestion.extractor import KnowledgeExtractor
    from rag.models import ConceptNode, ConceptStatus

    def mock_extract(*args, **kwargs):
        c = ConceptNode(
            id="c1",
            name="Algoritmi Greedy",
            summary="Definizione Greedy",
            status=ConceptStatus.UNTESTED,
            properties={"main_question": "Cosa è un algoritmo greedy?"},
        )
        return [c], [], []

    monkeypatch.setattr(KnowledgeExtractor, "extract_with_llm", mock_extract)

    app = create_app()
    client = await aiohttp_client(app)

    # 1. Upload document
    resp = await client.post(
        "/api/documents/upload",
        json={"title": "Algoritmi Avanzati", "content": "Contenuto Greedy", "filename": "greedy.md"},
    )
    assert resp.status == 201
    doc_data = await resp.json()
    course_id = doc_data["course_id"]

    # History has exactly 1 item for this document
    resp_hist = await client.get("/api/session/history")
    hist_data = await resp_hist.json()
    doc_items = [h for h in hist_data["history"] if h["id"] == course_id]
    assert len(doc_items) == 1
    assert doc_items[0]["turns_completed"] == 0

    # 2. Simulate conversation turn
    from assessment.service import SessionService
    service = SessionService()
    manager = service._load_manager()
    manager.history.append({
        "turn": 1,
        "role": "student",
        "student_response": "Un algoritmo greedy fa scelte localmente ottimali.",
        "ai_question": "Cosa è un algoritmo greedy?",
        "evaluation_result": "ACCURATE",
        "concept_name": "Algoritmi Greedy",
        "timestamp": "2026-10-21T13:00:00",
    })
    manager.save_session_state("session_state.json")

    # 3. User interrupts (pauses)
    resp_pause = await client.post("/api/session/pause", json={"reason": "Pausa"})
    assert resp_pause.status == 200

    # History still has ONLY 1 item for this document, and status is PAUSED
    resp_hist2 = await client.get("/api/session/history")
    hist_data2 = await resp_hist2.json()
    doc_items2 = [h for h in hist_data2["history"] if h["id"] == course_id]
    assert len(doc_items2) == 1
    assert doc_items2[0]["turns_completed"] >= 1
    assert doc_items2[0]["status"] == "PAUSED"

    # 4. User resumes
    resp_resume = await client.post("/api/session/resume")
    assert resp_resume.status == 200

    # 5. Add another turn
    manager2 = service._load_manager()
    manager2.history.append({
        "turn": len(manager2.history) + 1,
        "role": "student",
        "student_response": "Un esempio è Kruskal.",
        "ai_question": "Fammi un esempio.",
        "evaluation_result": "ACCURATE",
        "concept_name": "Algoritmi Greedy",
        "timestamp": "2026-10-21T13:05:00",
    })
    manager2.save_session_state("session_state.json")

    # History MUST STILL HAVE EXACTLY 1 ITEM!
    resp_hist3 = await client.get("/api/session/history")
    hist_data3 = await resp_hist3.json()
    doc_items3 = [h for h in hist_data3["history"] if h["id"] == course_id]
    assert len(doc_items3) == 1
    assert doc_items3[0]["turns_completed"] >= 2
    assert doc_items3[0]["status"] == "ACTIVE"


@pytest.mark.asyncio
async def test_api_generate_from_topic(aiohttp_client, monkeypatch):
    """Verifies that an entire exam can be generated purely from a topic without file upload."""
    from rag.ingestion.extractor import KnowledgeExtractor
    from pathlib import Path

    def mock_extract_from_topic(topic, **kwargs):
        return {
            "course_title": f"Corso di {topic}",
            "course_summary_markdown": f"# {topic}\n\nSintesi dettagliata su {topic}.",
            "concepts": [
                {
                    "id": "concetto_introduttivo",
                    "name": "Concetto Introduttivo",
                    "summary": "Introduzione alla materia.",
                    "ideal_answer": "Spiegazione approfondita del concetto.",
                    "expected_key_points": ["Punto 1", "Punto 2"],
                    "main_question": "Quali sono i fondamenti?",
                    "narrowing_questions": ["Qual è il dettaglio operativo?"],
                    "scaffolding_hints": ["Rifletti sui presupposti."],
                    "stress_test_questions": ["Come si applica in pratica?"],
                    "collision_check_questions": ["Cosa lo distingue da altre nozioni?"],
                    "difficulty": "EASY",
                    "prerequisites": [],
                    "contrasts_with": [],
                    "causal_targets": [],
                }
            ],
        }

    monkeypatch.setattr(KnowledgeExtractor, "extract_from_topic", mock_extract_from_topic)

    app = create_app()
    client = await aiohttp_client(app)

    # 1. Test missing topic returns 400
    resp_bad = await client.post("/api/courses/generate-from-topic", json={"topic": ""})
    assert resp_bad.status == 400

    # 2. Generate valid topic
    resp = await client.post(
        "/api/courses/generate-from-topic",
        json={"topic": "Diritto Costituzionale: Il Parlamento", "title": "Diritto Costituzionale"},
    )
    assert resp.status == 201
    data = await resp.json()
    assert data["success"] is True
    assert "diritto_costituzionale" in data["course_id"]
    assert data["total_concepts"] == 1
    assert data["concepts"][0]["concept_name"] == "Concetto Introduttivo"

    # 3. Verify directory and state
    course_dir = Path("data/courses") / data["course_id"]
    assert course_dir.exists()
    assert (course_dir / "plan.json").exists()
    assert (course_dir / "state.json").exists()
    assert (course_dir / "material.md").exists()


@pytest.mark.asyncio
async def test_api_session_warmup_endpoint(aiohttp_client):
    """Verifies that /api/session/warmup issues a prewarmed token with dispatch configuration."""
    app = create_app()
    client = await aiohttp_client(app)

    # 1. Warmup via POST
    resp = await client.post("/api/session/warmup", json={"course_id": "test_course"})
    assert resp.status == 200
    data = await resp.json()
    assert data["is_prewarmed"] is True
    assert "participant_token" in data
    assert "room_name" in data
    assert "oral-exam-test_course-prewarm" in data["room_name"]

    # 2. Warmup via GET
    resp_get = await client.get("/api/session/warmup?course_id=test_course")
    assert resp_get.status == 200
    data_get = await resp_get.json()
    assert data_get["is_prewarmed"] is True
    assert "participant_token" in data_get





