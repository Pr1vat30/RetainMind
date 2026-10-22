"""RetainMind REST & Token API Server for Flutter & Client Interfaces.

Provides HTTP/REST endpoints for:
1. LiveKit Room Access Token generation (JWT) for mobile/desktop Flutter clients.
2. Examination session lifecycle and telemetry inspection via `SessionService`
   (status, live transcript, pause, resume, repeat with dynamic adaptation, diagnostic report).
3. Examination plan / syllabus discovery.
"""

from __future__ import annotations

import json
import logging
import re
from pathlib import Path
from typing import Any

from aiohttp import web
from livekit import api

from assessment.service import SessionService
from assessment.state import PedagogicalState, SessionStatus
from config import config

logger = logging.getLogger("agent.api")


def _cors_headers() -> dict[str, str]:
    """CORS headers allowing Flutter Web, Desktop, and Mobile clients."""
    return {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
    }


def _json_response(data: Any, status: int = 200) -> web.Response:
    return web.json_response(data, status=status, headers=_cors_headers())


async def handle_options(request: web.Request) -> web.Response:
    """Preflight CORS handler."""
    return web.Response(status=204, headers=_cors_headers())


async def handle_health(request: web.Request) -> web.Response:
    """Healthcheck endpoint."""
    return _json_response(
        {
            "status": "healthy",
            "service": "RetainMind Voice Agent API",
            "livekit_mode": config.livekit_mode,
            "livekit_url": config.livekit_url,
            "pipeline_mode": config.pipeline_mode,
        }
    )


async def handle_get_token(request: web.Request) -> web.Response:
    """Generate a LiveKit Access Token for a student joining the oral exam room.

    Supports both standard LiveKit endpoint schema (`/getToken`) and `/api/token`.
    """
    try:
        body = await request.json() if request.can_read_body else {}
    except Exception:
        body = {}

    room_name = body.get("room_name") or "oral-exam-room"
    identity = body.get("participant_identity") or "student_default"
    name = body.get("participant_name") or "Studente"
    course_id = body.get("course_id")
    if course_id:
        from assessment.courses import CourseManager

        CourseManager.set_active_course(course_id)

    # Resolve connection URL for client (handle localhost vs LAN/host translation)
    server_url = config.livekit_url
    if "127.0.0.1" in server_url or "localhost" in server_url:
        req_host = request.headers.get("Host", "").split(":")[0]
        if req_host and req_host not in ("127.0.0.1", "localhost", "0.0.0.0"):
            server_url = server_url.replace("127.0.0.1", req_host).replace(
                "localhost", req_host
            )

    # Create AccessToken with VideoGrants and Agent Dispatch configuration
    token_builder = (
        api.AccessToken(config.livekit_api_key, config.livekit_api_secret)
        .with_identity(identity)
        .with_name(name)
        .with_grants(
            api.VideoGrants(
                room_join=True,
                room=room_name,
                can_publish=True,
                can_subscribe=True,
            )
        )
    )

    if config.agent_name:
        token_builder = token_builder.with_room_config(
            api.RoomConfiguration(
                agents=[api.RoomAgentDispatch(agent_name=config.agent_name, metadata=course_id or "")]
            )
        )
    if course_id:
        token_builder = token_builder.with_metadata(course_id)

    participant_token = token_builder.to_jwt()

    return _json_response(
        {
            "server_url": server_url,
            "participant_token": participant_token,
            "room_name": room_name,
            "participant_identity": identity,
            "participant_name": name,
        },
        status=201,
    )


async def handle_session_status(request: web.Request) -> web.Response:
    """Returns current active examination session status and BKT progress."""
    from assessment.courses import CourseManager

    course_id = request.query.get("course_id") or request.query.get("id")
    if course_id:
        cdir = CourseManager.get_course_dir(course_id)
        service = SessionService(
            state_file_path=cdir / "state.json",
            plan_file_path=cdir / "plan.json",
            events_file_path=cdir / "events.jsonl",
        )
    else:
        service = SessionService()
    status_data = service.get_status()
    return _json_response(status_data)


async def handle_session_transcript(request: web.Request) -> web.Response:
    """Returns chronological conversation transcript turns for live subtitles and study review."""
    service = SessionService()
    it_param = request.query.get("iteration")
    course_id = request.query.get("course_id") or request.query.get("id")
    iteration = int(it_param) if it_param and it_param.isdigit() else None
    transcript = service.get_conversation_transcript(iteration=iteration, course_id=course_id)
    return _json_response(
        {
            "total_turns": len(transcript),
            "iteration": iteration,
            "course_id": course_id,
            "turns": transcript,
        }
    )


async def handle_session_pause(request: web.Request) -> web.Response:
    """Pauses the active examination session."""
    service = SessionService()
    try:
        body = await request.json() if request.can_read_body else {}
    except Exception:
        body = {}
    reason = body.get("reason", "Richiesta da app Flutter")
    result = await service.pause(reason=reason)
    return _json_response(result)


async def handle_session_resume(request: web.Request) -> web.Response:
    """Resumes a paused examination session."""
    from assessment.courses import CourseManager

    try:
        body = await request.json() if request.can_read_body else {}
    except Exception:
        body = {}
    course_id = body.get("course_id") or request.query.get("course_id") or request.query.get("id")
    if course_id:
        CourseManager.set_active_course(course_id)
        cdir = CourseManager.get_course_dir(course_id)
        service = SessionService(
            state_file_path=cdir / "state.json",
            plan_file_path=cdir / "plan.json",
            events_file_path=cdir / "events.jsonl",
        )
    else:
        service = SessionService()

    try:
        result = await service.resume()
        return _json_response(result)
    except FileNotFoundError as e:
        return _json_response({"error": str(e)}, status=404)
    except Exception as e:
        return _json_response({"error": str(e)}, status=500)


async def handle_session_repeat(request: web.Request) -> web.Response:
    """Restarts the examination as a new iteration with dynamic pedagogical adaptation."""
    from assessment.courses import CourseManager

    try:
        body = await request.json() if request.can_read_body else {}
    except Exception:
        body = {}
    course_id = body.get("course_id") or request.query.get("course_id") or request.query.get("id")
    if course_id:
        CourseManager.set_active_course(course_id)
        cdir = CourseManager.get_course_dir(course_id)
        service = SessionService(
            state_file_path=cdir / "state.json",
            plan_file_path=cdir / "plan.json",
            events_file_path=cdir / "events.jsonl",
        )
    else:
        service = SessionService()

    adapt = body.get("adapt", True)
    result = await service.repeat(adapt=adapt)
    return _json_response(result)


async def handle_session_report(request: web.Request) -> web.Response:
    """Generates and returns the post-exam diagnostic report and RCA."""
    from assessment.courses import CourseManager

    course_id = request.query.get("course_id") or request.query.get("id")
    if not course_id:
        course_id = CourseManager.get_active_course_id()

    if course_id:
        cdir = CourseManager.get_course_dir(course_id)
        service = SessionService(
            state_file_path=cdir / "state.json",
            plan_file_path=cdir / "plan.json",
            events_file_path=cdir / "events.jsonl",
        )
    else:
        service = SessionService()

    report = await service.get_diagnostic_report()
    return _json_response(report)


async def handle_session_history(request: web.Request) -> web.Response:
    """Returns history across all iterations."""
    service = SessionService()
    history = service.get_history()
    return _json_response({"history": history})


async def handle_session_compare(request: web.Request) -> web.Response:
    """Compares current iteration with previous iteration performance."""
    service = SessionService()
    comp = await service.compare()
    return _json_response(comp)


async def handle_plan(request: web.Request) -> web.Response:
    """Returns the course examination plan syllabus."""
    from assessment.courses import CourseManager

    course_id = request.query.get("course_id") or request.query.get("id")
    plan_path = None
    if course_id:
        course_plan = CourseManager.get_course_dir(course_id) / "plan.json"
        if course_plan.exists():
            plan_path = course_plan

    if not plan_path or not plan_path.exists():
        active_id = CourseManager.get_active_course_id()
        if active_id:
            course_dir = CourseManager.get_course_dir(active_id)
            if (course_dir / "plan.json").exists():
                plan_path = course_dir / "plan.json"

    if (not plan_path or not plan_path.exists()) and (CourseManager.DATA_DIR / "examination_plan.json").exists():
        plan_path = CourseManager.DATA_DIR / "examination_plan.json"

    if not plan_path.exists():
        return _json_response(
            {"has_plan": False, "message": "Nessun piano didattico trovato."},
            status=404,
        )

    try:
        data = json.loads(plan_path.read_text(encoding="utf-8"))
        # Sanitize items for frontend consumption
        concept_list = []
        for cid in data.get("concept_order", []):
            item = data.get("items", {}).get(cid, {})
            concept_list.append(
                {
                    "concept_id": cid,
                    "concept_name": item.get("concept_name", cid),
                    "difficulty": item.get("difficulty", 1.0),
                    "prerequisites": item.get("prerequisites", []),
                    "main_question": item.get("planned_question", {}).get(
                        "main_question", ""
                    ),
                }
            )

        return _json_response(
            {
                "has_plan": True,
                "title": data.get("title", "Esame Orale"),
                "total_concepts": len(concept_list),
                "concept_order": data.get("concept_order", []),
                "concepts": concept_list,
            }
        )
    except Exception as e:
        return _json_response({"error": str(e)}, status=500)


async def handle_session_new(request: web.Request) -> web.Response:
    """Starts a completely fresh, isolated discussion on the current or specified examination plan."""
    from assessment.courses import CourseManager

    try:
        body = await request.json() if request.can_read_body else {}
    except Exception:
        body = {}
    course_id = body.get("course_id") or request.query.get("course_id") or request.query.get("id")
    if course_id:
        CourseManager.set_active_course(course_id)
        cdir = CourseManager.get_course_dir(course_id)
        service = SessionService(
            state_file_path=cdir / "state.json",
            plan_file_path=cdir / "plan.json",
            events_file_path=cdir / "events.jsonl",
        )
    else:
        service = SessionService()
        course_id = CourseManager.get_active_course_id()

    result = await service.start_new_discussion(course_id=course_id)
    return _json_response(result)


async def handle_session_delete(request: web.Request) -> web.Response:
    """Deletes a specific discussion iteration or course document from the server."""
    it_param = request.match_info.get("iteration") or request.query.get("iteration")
    if not it_param:
        try:
            body = await request.json() if request.can_read_body else {}
            it_param = str(
                body.get("iteration")
                or body.get("course_id")
                or body.get("id")
                or ""
            )
        except Exception:
            pass

    if not it_param:
        return _json_response({"error": "Parametro iteration o course_id non valido"}, status=400)

    service = SessionService()
    result = service.delete_iteration(it_param)
    return _json_response(result)


async def handle_session_reset(request: web.Request) -> web.Response:
    """Resets all session states, history, events, and removes examination plan."""
    service = SessionService()
    try:
        body = await request.json() if request.can_read_body else {}
    except Exception:
        body = {}
    delete_plan = body.get("delete_plan", True)
    result = service.reset_all(delete_plan=delete_plan)
    return _json_response(result)


async def handle_document_upload(request: web.Request) -> web.Response:
    """Handles document upload (PDF, TXT, MD or JSON text), generates a new examination
    plan, and resets session state for a new oral discussion.
    """
    uploads_dir = Path("uploads")
    uploads_dir.mkdir(exist_ok=True)

    file_path = None
    title = "Nuova Discussione d'Esame"

    content_type = request.content_type
    if "multipart" in content_type:
        reader = await request.multipart()
        field = await reader.next()
        while field is not None:
            if field.name == "title":
                title_val = (await field.read(decode=True)).decode("utf-8").strip()
                if title_val:
                    title = title_val
            elif field.name in ("file", "document"):
                filename = field.filename or "uploaded_doc.txt"
                safe_name = re.sub(r"[^a-zA-Z0-9_.-]", "_", filename)
                dest = uploads_dir / safe_name
                with dest.open("wb") as f:
                    while True:
                        chunk = await field.read_chunk()
                        if not chunk:
                            break
                        f.write(chunk)
                file_path = dest
            field = await reader.next()
    else:
        try:
            body = await request.json() if request.can_read_body else {}
        except Exception:
            body = {}
        title = body.get("title", title)
        text = body.get("content") or body.get("text") or ""
        filename = body.get("filename", "notes.md")
        if text:
            dest = uploads_dir / filename
            dest.write_text(text, encoding="utf-8")
            file_path = dest

    if not file_path or not file_path.exists():
        return _json_response(
            {"error": "Nessun file o contenuto valido fornito"}, status=400
        )

    try:
        from assessment.courses import CourseManager
        from orchestrator.gemini_orchestrator import GeminiOrchestrator

        # 1. Determine clean course ID and prepare course directory
        course_id = CourseManager.slugify(title or file_path.stem)
        course_dir = CourseManager.get_course_dir(course_id)
        course_plan_path = course_dir / "plan.json"

        # 2. Extract ontology & build topologically ordered plan via Gemini
        orchestrator = GeminiOrchestrator()
        plan = await orchestrator.ingest_document_and_plan(
            file_path=file_path,
            title=title,
            plan_output_file=course_plan_path,
        )

        # 3. Register course in CourseManager & mirror plan to root
        CourseManager.create_or_update_course(
            course_id=course_id,
            title=title,
            filename=file_path.name,
            file_path=str(file_path),
            plan_dict=plan.model_dump(),
        )

        # 4. Initialize completely fresh, isolated session state for this course
        service = SessionService(
            plan_file_path=course_plan_path,
            state_file_path=course_dir / "state.json",
        )
        manager = service._load_manager()
        manager.status = SessionStatus.ACTIVE
        manager.current_iteration = 1
        manager.history = []
        manager.iterations_history = []
        manager.consecutive_failures = 0
        manager.current_pedagogical_state = PedagogicalState.EXPLORATION
        manager.examination_plan = plan
        manager.current_concept_id = (
            plan.concept_order[0] if plan.concept_order else None
        )
        manager.save_session_state(course_dir / "state.json")

        concepts = [
            {
                "concept_id": cid,
                "concept_name": plan.items[cid].concept_name,
                "main_question": plan.items[cid].planned_question.main_question,
            }
            for cid in plan.concept_order
            if cid in plan.items
        ]

        return _json_response(
            {
                "success": True,
                "course_id": course_id,
                "title": plan.title,
                "total_concepts": len(plan.concept_order),
                "concepts": concepts,
                "message": f"Documento '{file_path.name}' analizzato con successo. Generati {len(concepts)} argomenti nella cartella corso '{course_id}'.",
            },
            status=201,
        )
    except Exception as e:
        logger.exception("Failed to ingest document: %s", e)
        return _json_response(
            {"error": f"Errore durante l'elaborazione del documento: {e!s}"},
            status=500,
        )


async def handle_courses_list(request: web.Request) -> web.Response:
    """Returns all available courses and the active course identifier."""
    from assessment.courses import CourseManager

    courses = CourseManager.list_courses()
    active_id = CourseManager.get_active_course_id()
    return _json_response({"active_course_id": active_id, "courses": courses})


async def handle_generate_from_topic(request: web.Request) -> web.Response:
    """Generates an entire examination curriculum, syllabus, and plan directly from a user-specified topic."""
    try:
        body = await request.json() if request.can_read_body else {}
    except Exception:
        body = {}

    topic = str(body.get("topic") or "").strip()
    title = str(body.get("title") or "").strip() or None

    if not topic:
        return _json_response({"error": "Parametro 'topic' mancante o vuoto."}, status=400)

    try:
        from assessment.courses import CourseManager
        from orchestrator.gemini_orchestrator import GeminiOrchestrator

        orchestrator = GeminiOrchestrator()

        resolved_title = title or topic
        course_id = CourseManager.slugify(resolved_title)
        course_dir = CourseManager.get_course_dir(course_id)
        course_plan_path = course_dir / "plan.json"

        plan, final_title, summary_md = await orchestrator.generate_plan_from_topic(
            topic=topic,
            title=title,
            plan_output_file=course_plan_path,
        )

        material_file = course_dir / "material.md"
        material_file.write_text(summary_md, encoding="utf-8")

        CourseManager.create_or_update_course(
            course_id=course_id,
            title=plan.title,
            filename="argomento_ia.md",
            file_path=str(material_file),
            plan_dict=plan.model_dump(),
        )

        service = SessionService(
            plan_file_path=course_plan_path,
            state_file_path=course_dir / "state.json",
        )
        manager = service._load_manager()
        manager.status = SessionStatus.ACTIVE
        manager.current_iteration = 1
        manager.history = []
        manager.iterations_history = []
        manager.consecutive_failures = 0
        manager.current_pedagogical_state = PedagogicalState.EXPLORATION
        manager.examination_plan = plan
        manager.current_concept_id = (
            plan.concept_order[0] if plan.concept_order else None
        )
        manager.save_session_state(course_dir / "state.json")

        concepts = [
            {
                "concept_id": cid,
                "concept_name": plan.items[cid].concept_name,
                "main_question": plan.items[cid].planned_question.main_question,
            }
            for cid in plan.concept_order
            if cid in plan.items
        ]

        return _json_response(
            {
                "success": True,
                "course_id": course_id,
                "title": plan.title,
                "total_concepts": len(plan.concept_order),
                "concepts": concepts,
                "message": f"Sessione su '{plan.title}' generata con successo dall'IA.",
            },
            status=201,
        )
    except Exception as e:
        logger.exception("Failed to generate course from topic: %s", e)
        return _json_response(
            {"error": f"Errore durante la generazione dell'esame da argomento: {e!s}"},
            status=500,
        )


async def handle_course_activate(request: web.Request) -> web.Response:
    """Switches the active course."""
    from assessment.courses import CourseManager

    try:
        body = await request.json() if request.can_read_body else {}
    except Exception:
        body = {}
    course_id = body.get("course_id") or body.get("id")
    if not course_id:
        return _json_response({"error": "Parametro course_id mancante"}, status=400)

    CourseManager.set_active_course(course_id)
    return _json_response({"success": True, "active_course_id": course_id})


def create_app() -> web.Application:
    """Builds and returns the aiohttp Application with all registered routes."""
    app = web.Application()

    # Preflight OPTIONS
    app.router.add_route("OPTIONS", "/{tail:.*}", handle_options)

    # Routes
    app.router.add_get("/", handle_health)
    app.router.add_get("/health", handle_health)

    # LiveKit Token Endpoints (support both /getToken and /api/token)
    app.router.add_post("/getToken", handle_get_token)
    app.router.add_post("/api/token", handle_get_token)

    # Session & Telemetry Endpoints
    app.router.add_get("/api/session/status", handle_session_status)
    app.router.add_get("/api/session/transcript", handle_session_transcript)
    app.router.add_post("/api/session/pause", handle_session_pause)
    app.router.add_post("/api/session/resume", handle_session_resume)
    app.router.add_post("/api/session/repeat", handle_session_repeat)
    app.router.add_post("/api/session/new", handle_session_new)
    app.router.add_delete("/api/session/history/{iteration}", handle_session_delete)
    app.router.add_post("/api/session/delete", handle_session_delete)
    app.router.add_post("/api/session/reset", handle_session_reset)
    app.router.add_get("/api/session/report", handle_session_report)
    app.router.add_get("/api/session/history", handle_session_history)
    app.router.add_get("/api/session/compare", handle_session_compare)

    # Courses Endpoints
    app.router.add_get("/api/courses", handle_courses_list)
    app.router.add_post("/api/courses/activate", handle_course_activate)
    app.router.add_post("/api/courses/generate-from-topic", handle_generate_from_topic)

    # Examination Plan
    app.router.add_get("/api/plan", handle_plan)
    app.router.add_post("/api/documents/upload", handle_document_upload)

    return app


if __name__ == "__main__":
    import os

    port = int(os.getenv("PORT", os.getenv("API_PORT", "8000")))
    host = os.getenv("HOST", "0.0.0.0")
    print(f"🚀 Avvio RetainMind REST & Token API Server su http://{host}:{port}")
    print(f"📡 LiveKit Mode: {config.livekit_mode} ({config.livekit_url})")
    app = create_app()
    web.run_app(app, host=host, port=port)
