"""RetainMind REST, WebRTC & WebSocket API Server for Flutter & Client Interfaces.

Powered by Pipecat:
1. Default Flutter voice path: WebRTC audio via SmallWebRTCTransport (/api/offer).
2. Fallback bidirectional raw PCM WebSocket audio streaming via
   FastAPIWebsocketTransport (/ws, /ws/{course_id}).
3. Full REST API for examination session lifecycle, telemetry, BKT mastery, courses, and syllabus.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
from pathlib import Path
from typing import Any

from fastapi import (
    FastAPI,
    HTTPException,
    Request,
    Response,
    UploadFile,
    WebSocket,
    WebSocketDisconnect,
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pipecat.transports.base_transport import TransportParams
from pipecat.transports.smallwebrtc.connection import SmallWebRTCConnection
from pipecat.transports.smallwebrtc.request_handler import (
    IceCandidate,
    SmallWebRTCPatchRequest,
    SmallWebRTCRequest,
    SmallWebRTCRequestHandler,
)
from pipecat.transports.smallwebrtc.transport import SmallWebRTCTransport
from pipecat.transports.websocket.fastapi import (
    FastAPIWebsocketParams,
    FastAPIWebsocketTransport,
)

from agent import create_examiner_pipeline
from assessment.courses import CourseManager
from assessment.service import SessionService
from config import config
from pcm_serializer import FlutterPcmSerializer

logger = logging.getLogger("agent.api")


def _create_pipecat_websocket_params(
    pipeline_mode: str | None = None,
) -> FastAPIWebsocketParams:
    """Use Gemini-native PCM rates on the Flutter websocket audio path."""
    resolved_mode = pipeline_mode or config.pipeline_mode
    return FastAPIWebsocketParams(
        audio_in_enabled=True,
        audio_out_enabled=True,
        audio_out_10ms_chunks=2,
        audio_in_sample_rate=16000,
        audio_out_sample_rate=24000
        if resolved_mode == "gemini_live"
        else config.audio_sample_rate,
        serializer=FlutterPcmSerializer(),
    )


def _cors_headers() -> dict[str, str]:
    return {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS, DELETE, PATCH",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
    }


def create_app() -> FastAPI:
    """Builds and configures the FastAPI application with Pipecat WebRTC, WebSocket, and REST endpoints."""
    app = FastAPI(
        title="RetainMind Pipecat Voice Agent API",
        version="0.2.0",
        description="Unified Pipecat WebRTC, WebSocket & REST API for Oral Examination",
    )

    @app.middleware("http")
    async def add_cors_headers(request: Request, call_next):
        if request.method == "OPTIONS":
            return Response(status_code=204, headers=_cors_headers())
        response = await call_next(request)
        for k, v in _cors_headers().items():
            response.headers[k] = v
        return response

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.options("/{full_path:path}")
    async def options_handler(full_path: str):
        return Response(status_code=204, headers=_cors_headers())

    # Initialize SmallWebRTCRequestHandler for peer-to-peer WebRTC connections
    # Keep client/server ICE configuration aligned for WebRTC peers outside
    # the same local network as well as local development sessions.
    webrtc_handler = SmallWebRTCRequestHandler(
        ice_servers=list(config.webrtc_stun_servers)
    )

    # -------------------------------------------------------------------------
    # Health & Diagnostics
    # -------------------------------------------------------------------------
    @app.get("/")
    @app.get("/health")
    async def handle_health():
        return {
            "status": "healthy",
            "service": "RetainMind Pipecat Voice Agent API",
            "webrtc_mode": config.webrtc_mode,
            "pipeline_mode": config.pipeline_mode,
            "transports": ["smallwebrtc", "websocket"],
        }

    # -------------------------------------------------------------------------
    # Pipecat WebRTC Signaling Endpoints (SmallWebRTCTransport)
    # -------------------------------------------------------------------------
    @app.post("/api/offer")
    @app.post("/api/session/webrtc")
    async def handle_webrtc_offer(request: Request):
        """Negotiate local WebRTC peer-to-peer connection for audio streaming."""
        try:
            body = await request.json()
        except Exception:
            raise HTTPException(
                status_code=400, detail="Invalid JSON body in WebRTC offer request"
            )

        sdp = body.get("sdp")
        req_type = body.get("type", "offer")
        pc_id = body.get("pc_id")
        restart_pc = body.get("restart_pc", False)
        course_id = body.get("course_id") or CourseManager.get_active_course_id()

        if not sdp:
            raise HTTPException(status_code=400, detail="Missing required 'sdp' field")

        webrtc_req = SmallWebRTCRequest(
            sdp=sdp,
            type=req_type,
            pc_id=pc_id,
            restart_pc=restart_pc,
            request_data={"course_id": course_id},
        )

        async def _connection_callback(conn: SmallWebRTCConnection):
            logger.info(
                "Initializing SmallWebRTCTransport for peer %s (course: %s)",
                conn.pc_id,
                course_id,
            )
            transport = SmallWebRTCTransport(
                webrtc_connection=conn,
                params=TransportParams(
                    audio_in_enabled=True,
                    audio_out_enabled=True,
                ),
            )
            task, _agent, runner = await create_examiner_pipeline(
                transport=transport,
                course_id=course_id,
                is_direct_test=(course_id == "direct_test"),
            )
            asyncio.create_task(runner.run(task))

        try:
            answer = await webrtc_handler.handle_web_request(
                webrtc_req, _connection_callback
            )
            return JSONResponse(content=answer, headers=_cors_headers())
        except Exception as e:
            logger.exception("Error handling WebRTC offer: %s", e)
            raise HTTPException(status_code=500, detail=str(e))

    @app.patch("/api/offer")
    async def handle_webrtc_patch(request: Request):
        """Receive trickle ICE candidates for SmallWebRTC."""
        try:
            body = await request.json()
            candidates = [
                IceCandidate(
                    candidate=c.get("candidate", ""),
                    sdp_mid=c.get("sdpMid") or c.get("sdp_mid"),
                    sdp_mline_index=c.get("sdpMLineIndex") or c.get("sdp_mline_index"),
                )
                for c in body.get("candidates", [])
            ]
            patch_req = SmallWebRTCPatchRequest(
                pc_id=body["pc_id"],
                candidates=candidates,
            )
            await webrtc_handler.handle_patch_request(patch_req)
            return JSONResponse(content={"status": "ok"}, headers=_cors_headers())
        except Exception as e:
            logger.warning("Error processing ICE patch: %s", e)
            return JSONResponse(
                content={"status": "ignored", "error": str(e)}, status_code=200
            )

    # -------------------------------------------------------------------------
    # Pipecat WebSocket Endpoint (custom Flutter PCM protocol)
    # -------------------------------------------------------------------------
    @app.websocket("/ws")
    @app.websocket("/ws/{course_id}")
    @app.websocket("/ws/test/{course_id}")
    async def handle_websocket_endpoint(
        websocket: WebSocket, course_id: str | None = None
    ):
        """Bidirectional raw PCM audio streaming endpoint for Flutter and custom clients."""
        await websocket.accept()
        resolved_course_id = course_id or CourseManager.get_active_course_id()
        logger.info(
            "WebSocket client connected to Pipecat session for course: %s",
            resolved_course_id,
        )

        try:
            transport = FastAPIWebsocketTransport(
                websocket=websocket,
                params=_create_pipecat_websocket_params(),
            )
            task, _agent, runner = await create_examiner_pipeline(
                transport=transport,
                course_id=resolved_course_id,
                is_direct_test=(resolved_course_id == "direct_test"),
            )
            await runner.run(task)
        except WebSocketDisconnect:
            logger.info(
                "WebSocket client disconnected for course: %s", resolved_course_id
            )
        except Exception as e:
            logger.exception("Error in WebSocket voice session: %s", e)

    # -------------------------------------------------------------------------
    # Token / Session Discovery Endpoints (Backward-compatible with Flutter clients)
    # -------------------------------------------------------------------------
    @app.post("/api/token")
    async def handle_get_token(request: Request):
        """Returns session connection details and endpoints for WebRTC & WebSocket."""
        try:
            body = await request.json()
        except Exception:
            body = {}

        room_name = body.get("room_name") or "oral-exam-room"
        identity = body.get("participant_identity") or "student_default"
        name = body.get("participant_name") or "Studente"
        course_id = body.get("course_id")
        if course_id and course_id != "direct_test":
            CourseManager.set_active_course(course_id)

        req_host = request.headers.get("Host", "localhost:8000")
        base_url = f"http://{req_host}"
        ws_url = f"ws://{req_host}/ws/{course_id or 'default'}"

        return JSONResponse(
            status_code=201,
            content={
                "server_url": base_url,
                "participant_token": "pipecat_session_token",
                "room_name": room_name,
                "participant_identity": identity,
                "participant_name": name,
                "course_id": course_id,
                "webrtc_endpoint": "/api/offer",
                "websocket_endpoint": ws_url,
                "transport": "pipecat",
            },
            headers=_cors_headers(),
        )

    @app.get("/api/session/warmup")
    @app.post("/api/session/warmup")
    async def handle_session_warmup(request: Request):
        """Prewarm session state and course discovery."""
        try:
            body = await request.json()
        except Exception:
            body = {}

        CourseManager.ensure_directories()
        course_id = (
            body.get("course_id")
            or request.query_params.get("course_id")
            or CourseManager.get_active_course_id()
        )
        if course_id:
            CourseManager.set_active_course(course_id)

        req_host = request.headers.get("Host", "localhost:8000")
        return {
            "server_url": f"http://{req_host}",
            "participant_token": "pipecat_prewarmed_token",
            "room_name": f"oral-exam-{course_id or 'default'}-prewarm",
            "participant_identity": "student_default",
            "participant_name": "Studente",
            "is_prewarmed": True,
            "course_id": course_id,
            "webrtc_endpoint": "/api/offer",
            "websocket_endpoint": f"ws://{req_host}/ws/{course_id or 'default'}",
        }

    # -------------------------------------------------------------------------
    # Session State, Telemetry, and Control
    # -------------------------------------------------------------------------
    @app.get("/api/session/status")
    async def handle_session_status(
        course_id: str | None = None, id: str | None = None
    ):
        target_course = course_id or id or CourseManager.get_active_course_id()
        if target_course:
            cdir = CourseManager.get_course_dir(target_course)
            service = SessionService(
                state_file_path=cdir / "state.json",
                plan_file_path=cdir / "plan.json",
                events_file_path=cdir / "events.jsonl",
            )
        else:
            service = SessionService()
        status_data = service.get_status()
        if target_course:
            status_data["course_id"] = target_course
        return status_data

    @app.get("/api/session/transcript")
    async def handle_session_transcript(
        course_id: str | None = None,
        id: str | None = None,
        iteration: int | None = None,
    ):
        target_course = course_id or id or CourseManager.get_active_course_id()
        if target_course:
            cdir = CourseManager.get_course_dir(target_course)
            service = SessionService(
                state_file_path=cdir / "state.json",
                plan_file_path=cdir / "plan.json",
                events_file_path=cdir / "events.jsonl",
                course_id=target_course,
            )
        else:
            service = SessionService()
        transcript = service.get_conversation_transcript(
            iteration=iteration, course_id=target_course
        )
        return {
            "total_turns": len(transcript),
            "iteration": iteration,
            "course_id": target_course,
            "turns": transcript,
        }

    @app.post("/api/session/pause")
    async def handle_session_pause(request: Request):
        try:
            body = await request.json()
        except Exception:
            body = {}
        target_course = (
            body.get("course_id")
            or request.query_params.get("course_id")
            or request.query_params.get("id")
            or CourseManager.get_active_course_id()
        )
        if target_course:
            cdir = CourseManager.get_course_dir(target_course)
            service = SessionService(
                state_file_path=cdir / "state.json",
                plan_file_path=cdir / "plan.json",
                events_file_path=cdir / "events.jsonl",
                course_id=target_course,
            )
        else:
            service = SessionService()
        reason = body.get("reason", "Richiesta da client")
        result = await service.pause(reason=reason)
        return result

    @app.post("/api/session/resume")
    async def handle_session_resume(request: Request):
        try:
            body = await request.json()
        except Exception:
            body = {}
        target_course = (
            body.get("course_id")
            or request.query_params.get("course_id")
            or request.query_params.get("id")
        )
        if target_course:
            CourseManager.set_active_course(target_course)
            cdir = CourseManager.get_course_dir(target_course)
            service = SessionService(
                state_file_path=cdir / "state.json",
                plan_file_path=cdir / "plan.json",
                events_file_path=cdir / "events.jsonl",
            )
        else:
            service = SessionService()
        try:
            result = await service.resume()
            return result
        except FileNotFoundError as e:
            raise HTTPException(status_code=404, detail=str(e))
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))

    @app.post("/api/session/repeat")
    async def handle_session_repeat(request: Request):
        try:
            body = await request.json()
        except Exception:
            body = {}
        target_course = (
            body.get("course_id")
            or request.query_params.get("course_id")
            or request.query_params.get("id")
        )
        if target_course:
            CourseManager.set_active_course(target_course)
            cdir = CourseManager.get_course_dir(target_course)
            service = SessionService(
                state_file_path=cdir / "state.json",
                plan_file_path=cdir / "plan.json",
                events_file_path=cdir / "events.jsonl",
            )
        else:
            service = SessionService()
        adapt = body.get("adapt", True)
        return await service.repeat(adapt=adapt)

    @app.get("/api/session/report")
    async def handle_session_report(
        course_id: str | None = None, id: str | None = None
    ):
        target_course = course_id or id or CourseManager.get_active_course_id()
        if target_course:
            cdir = CourseManager.get_course_dir(target_course)
            service = SessionService(
                state_file_path=cdir / "state.json",
                plan_file_path=cdir / "plan.json",
                events_file_path=cdir / "events.jsonl",
            )
        else:
            service = SessionService()
        return await service.get_diagnostic_report()

    @app.get("/api/session/history")
    async def handle_session_history(
        course_id: str | None = None, id: str | None = None
    ):
        target_course = course_id or id
        all_history = CourseManager.get_discussions_history()
        if target_course:
            filtered = [
                h
                for h in all_history
                if h.get("id") == target_course or h.get("course_id") == target_course
            ]
            if filtered:
                return {"history": filtered}
        return {"history": all_history}

    @app.get("/api/session/compare")
    async def handle_session_compare(
        course_id: str | None = None, id: str | None = None
    ):
        target_course = course_id or id or CourseManager.get_active_course_id()
        if target_course:
            cdir = CourseManager.get_course_dir(target_course)
            service = SessionService(
                state_file_path=cdir / "state.json",
                plan_file_path=cdir / "plan.json",
                events_file_path=cdir / "events.jsonl",
                course_id=target_course,
            )
        else:
            service = SessionService()
        return await service.compare()

    @app.post("/api/session/new")
    async def handle_session_new(request: Request):
        try:
            body = await request.json()
        except Exception:
            body = {}
        target_course = (
            body.get("course_id")
            or request.query_params.get("course_id")
            or request.query_params.get("id")
        )
        if target_course:
            CourseManager.set_active_course(target_course)
            cdir = CourseManager.get_course_dir(target_course)
            service = SessionService(
                state_file_path=cdir / "state.json",
                plan_file_path=cdir / "plan.json",
                events_file_path=cdir / "events.jsonl",
            )
        else:
            service = SessionService()
            target_course = CourseManager.get_active_course_id()
        return await service.start_new_discussion(course_id=target_course)

    @app.delete("/api/session/history/{iteration}")
    @app.post("/api/session/delete")
    async def handle_session_delete(request: Request, iteration: str | None = None):
        it_param = iteration or request.query_params.get("iteration")
        if not it_param:
            try:
                body = await request.json()
                it_param = str(
                    body.get("iteration")
                    or body.get("course_id")
                    or body.get("id")
                    or ""
                )
            except Exception:
                pass
        if not it_param:
            raise HTTPException(
                status_code=400, detail="Parametro iteration o course_id non valido"
            )

        service = SessionService()
        return service.delete_iteration(it_param)

    @app.post("/api/session/reset")
    async def handle_session_reset(request: Request):
        try:
            body = await request.json()
        except Exception:
            body = {}
        delete_plan = body.get("delete_plan", True)
        service = SessionService()
        return service.reset_all(delete_plan=delete_plan)

    # -------------------------------------------------------------------------
    # Course Management & Syllabus
    # -------------------------------------------------------------------------
    @app.get("/api/courses")
    async def handle_courses_list():
        courses = CourseManager.list_courses()
        active_id = CourseManager.get_active_course_id()
        return {"active_course_id": active_id, "courses": courses}

    @app.post("/api/courses/activate")
    async def handle_course_activate(request: Request):
        try:
            body = await request.json()
        except Exception:
            body = {}
        course_id = body.get("course_id") or body.get("id")
        if not course_id:
            raise HTTPException(status_code=400, detail="Parametro course_id mancante")
        CourseManager.set_active_course(course_id)
        return {"success": True, "active_course_id": course_id}

    @app.post("/api/courses/generate-from-topic")
    async def handle_generate_from_topic(request: Request):
        try:
            body = await request.json()
        except Exception:
            body = {}

        topic = str(body.get("topic") or "").strip()
        title = str(body.get("title") or "").strip() or None
        level = str(body.get("level") or "intermedio").strip().lower()
        if level not in {"base", "intermedio", "avanzato"}:
            level = "intermedio"
        try:
            duration_minutes = int(body.get("duration_minutes", 20))
        except (TypeError, ValueError):
            duration_minutes = 20
        duration_minutes = max(10, min(duration_minutes, 60))

        if not topic:
            raise HTTPException(
                status_code=400, detail="Parametro 'topic' mancante o vuoto."
            )

        try:
            from orchestrator.gemini_orchestrator import GeminiOrchestrator

            orchestrator = GeminiOrchestrator()
            resolved_title = title or topic
            course_id = CourseManager.slugify(resolved_title)
            course_dir = CourseManager.get_course_dir(course_id)
            course_plan_path = course_dir / "plan.json"

            (
                plan,
                _final_title,
                summary_md,
            ) = await orchestrator.generate_plan_from_topic(
                topic=topic,
                title=title,
                plan_output_file=course_plan_path,
                level=level,
                duration_minutes=duration_minutes,
            )

            from assessment.knowledge import register_course_stores

            register_course_stores(
                course_id, orchestrator.graph_store, orchestrator.vector_store
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
            from assessment import PedagogicalState, SessionStatus

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

            return JSONResponse(
                status_code=201,
                content={
                    "success": True,
                    "course_id": course_id,
                    "title": plan.title,
                    "total_concepts": len(plan.concept_order),
                    "concepts": concepts,
                    "generated_from_topic": True,
                    "material_preview": summary_md,
                    "message": f"Sessione su '{plan.title}' generata con successo dall'IA.",
                },
                headers=_cors_headers(),
            )
        except Exception as e:
            logger.exception("Failed to generate course from topic: %s", e)
            raise HTTPException(status_code=500, detail=f"Errore generazione: {e}")

    @app.get("/api/plan")
    async def handle_plan(course_id: str | None = None, id: str | None = None):
        target_course = course_id or id
        plan_path = None
        if target_course:
            course_plan = CourseManager.get_course_dir(target_course) / "plan.json"
            if course_plan.exists():
                plan_path = course_plan

        if not plan_path or not plan_path.exists():
            active_id = CourseManager.get_active_course_id()
            if active_id:
                course_dir = CourseManager.get_course_dir(active_id)
                if (course_dir / "plan.json").exists():
                    plan_path = course_dir / "plan.json"

        if (not plan_path or not plan_path.exists()) and (
            CourseManager.DATA_DIR / "examination_plan.json"
        ).exists():
            plan_path = CourseManager.DATA_DIR / "examination_plan.json"

        if not plan_path or not plan_path.exists():
            return {"has_plan": False, "message": "Nessun piano didattico trovato."}

        try:
            data = json.loads(plan_path.read_text(encoding="utf-8"))
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

            return {
                "has_plan": True,
                "title": data.get("title", "Esame Orale"),
                "total_concepts": len(concept_list),
                "concept_order": data.get("concept_order", []),
                "concepts": concept_list,
            }
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))

    @app.post("/api/documents/upload")
    async def handle_document_upload(request: Request):
        """Upload document (PDF, TXT, MD) and generate topologically sequenced syllabus."""
        uploads_dir = Path("uploads")
        uploads_dir.mkdir(exist_ok=True)

        file_path = None
        title = "Nuova Discussione d'Esame"

        content_type = request.headers.get("content-type", "")
        if "multipart" in content_type:
            form = await request.form()
            title_field = form.get("title")
            if title_field:
                title = str(title_field).strip()
            upload_file = form.get("file") or form.get("document")
            if upload_file is not None and hasattr(upload_file, "read"):
                filename = (
                    getattr(upload_file, "filename", "uploaded_doc.txt")
                    or "uploaded_doc.txt"
                )
                safe_name = re.sub(r"[^a-zA-Z0-9_.-]", "_", filename)
                dest = uploads_dir / safe_name
                contents = await upload_file.read()
                dest.write_bytes(contents)
                file_path = dest
        else:
            try:
                body = await request.json()
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
            raise HTTPException(
                status_code=400, detail="Nessun file o contenuto valido fornito"
            )

        try:
            from orchestrator.gemini_orchestrator import GeminiOrchestrator

            course_id = CourseManager.slugify(title or file_path.stem)
            course_dir = CourseManager.get_course_dir(course_id)
            course_plan_path = course_dir / "plan.json"

            orchestrator = GeminiOrchestrator()
            plan = await orchestrator.ingest_document_and_plan(
                file_path=file_path,
                title=title,
                plan_output_file=course_plan_path,
            )

            from assessment.knowledge import register_course_stores

            register_course_stores(
                course_id, orchestrator.graph_store, orchestrator.vector_store
            )

            CourseManager.create_or_update_course(
                course_id=course_id,
                title=title,
                filename=file_path.name,
                file_path=str(file_path),
                plan_dict=plan.model_dump(),
            )

            service = SessionService(
                plan_file_path=course_plan_path,
                state_file_path=course_dir / "state.json",
            )
            manager = service._load_manager()
            from assessment import PedagogicalState, SessionStatus

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

            return JSONResponse(
                status_code=201,
                content={
                    "success": True,
                    "course_id": course_id,
                    "title": plan.title,
                    "total_concepts": len(plan.concept_order),
                    "concepts": concepts,
                    "message": f"Documento '{file_path.name}' analizzato con successo.",
                },
                headers=_cors_headers(),
            )
        except Exception as e:
            logger.exception("Failed to ingest document: %s", e)
            raise HTTPException(status_code=500, detail=f"Errore: {e}")

    return app


# Module-level FastAPI instance for ASGI runners (uvicorn src.api:app)
app = create_app()

if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("PORT", os.getenv("API_PORT", "8000")))
    host = os.getenv("HOST", "0.0.0.0")
    print(f"🚀 Avvio RetainMind Pipecat API Server su http://{host}:{port}")
    uvicorn.run("api:app", host=host, port=port, reload=True)
