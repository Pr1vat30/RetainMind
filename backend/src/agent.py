"""Pipecat Voice AI Agent for Oral Examination & Socratic Study Assistance.

Supports:
1. WebRTC streaming via SmallWebRTCTransport (peer-to-peer without media server).
2. WebSocket streaming via FastAPIWebsocketTransport with the Flutter PCM protocol.
3. Gemini Live Multimodal Speech-to-Speech (Google GenAI Realtime).
4. Cascaded Voice Pipeline: Silero VAD -> Deepgram STT -> LLM -> ElevenLabs TTS.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
from pathlib import Path
from typing import Any

from google.genai import types
from pipecat.adapters.schemas.function_schema import FunctionSchema
from pipecat.audio.vad.silero import SileroVADAnalyzer
from pipecat.frames.frames import (
    EndFrame,
    LLMContextFrame,
    TextFrame,
)
from pipecat.pipeline.pipeline import Pipeline
from pipecat.pipeline.runner import PipelineRunner
from pipecat.pipeline.task import PipelineParams, PipelineTask
from pipecat.processors.aggregators.llm_context import LLMContext
from pipecat.processors.aggregators.llm_response_universal import (
    LLMContextAggregatorPair,
)
from pipecat.services.deepgram.stt import DeepgramSTTService
from pipecat.services.elevenlabs.tts import ElevenLabsTTSService
from pipecat.services.google.gemini_live.llm import (
    GeminiLiveLLMService,
    GeminiVADParams,
)
from pipecat.services.llm_service import FunctionCallParams
from pipecat.services.openai.llm import OpenAILLMService
from pipecat.transports.base_transport import BaseTransport, TransportParams

from assessment import (
    PedagogicalState,
    SessionAssessmentManager,
    SessionReportGenerator,
    SessionStatus,
    is_silence_or_noise,
)
from config import config
from orchestrator.local_llm import LocalOrchestratedLLMService
from planning.models import PlanItemStatus
from prompts import (
    ORAL_EXAMINER_SYSTEM_INSTRUCTIONS,
    build_examiner_turn_prompt,
)
from rag import create_graph_store, create_vector_store
from utils import enable_api_request_logging

if config.verbose_requests:
    enable_api_request_logging()

logger = logging.getLogger("agent")


async def _queue_opening_greeting(task: PipelineTask, greeting: str) -> None:
    """Seed Gemini's initial context with a prompt that makes it speak first."""
    prompt = (
        "Lo studente si è appena collegato alla sessione. "
        "Avvia subito la conversazione pronunciando ad alta voce, in italiano, "
        f"esattamente questo saluto e nient'altro: {greeting}"
    )
    # Gemini Live ignores audio until it has processed an initial context.
    # The context frame is retained if it arrives before the network session
    # is ready, then Gemini's service seeds the prompt and starts generation.
    await task.queue_frames(
        [
            LLMContextFrame(
                context=LLMContext(messages=[{"role": "user", "content": prompt}])
            )
        ]
    )


def extract_custom_vocabulary(plan, max_terms: int = 100) -> list[str]:
    """Extract domain terms, technical concepts, and keywords from the examination plan for Gemini Live biasing."""
    terms: set[str] = set()
    if not plan:
        return []
    if getattr(plan, "title", None):
        terms.add(plan.title.strip())
    if hasattr(plan, "concept_order") and plan.concept_order:
        for cid in plan.concept_order:
            if hasattr(plan, "items") and cid in plan.items:
                item = plan.items[cid]
                if getattr(item, "concept_name", None):
                    terms.add(item.concept_name.strip())
            clean_cid = cid.replace("_", " ").title().strip()
            terms.add(clean_cid)
    result = [t for t in terms if t and len(t) > 2]
    return sorted(result)[:max_terms]


class OralExaminerAgent:
    """Voice AI Oral Examiner with Hybrid RAG & Knowledge Tracing for Pipecat."""

    def __init__(
        self,
        assessment_manager: SessionAssessmentManager | None = None,
        examiner_llm: Any = None,
        instructions: str | None = None,
    ) -> None:
        self.assessment_manager = assessment_manager or SessionAssessmentManager(
            graph_store=create_graph_store("memory"),
            vector_store=create_vector_store("memory"),
        )
        self.examiner_llm = examiner_llm
        self.last_assistant_ts: float = 0.0
        self.last_spoken_directive: str = ""
        self.instructions = instructions or ORAL_EXAMINER_SYSTEM_INSTRUCTIONS

    async def evaluate_and_advance(
        self, context: Any = None, student_response: str = ""
    ) -> str:
        """Evaluate the student's answer, update the knowledge graph & Bayesian mastery,
        and retrieve the next ground-truth context and pedagogical directive."""
        try:
            if is_silence_or_noise(student_response):
                logger.info(
                    "evaluate_and_advance: ignoring silence/noise utterance ('%s')",
                    student_response,
                )
                return (
                    "status: ok\n"
                    "retryable: false\n"
                    "message: Lo studente è in attesa o sta riflettendo in silenzio. "
                    "Non ripetere la domanda precedente e attendi con calma che formuli la sua risposta."
                )

            now = asyncio.get_event_loop().time()
            pause_sec = (
                max(0.0, round(now - self.last_assistant_ts, 2))
                if self.last_assistant_ts > 0
                else 0.0
            )
            (
                examiner_ctx,
                turn_state,
            ) = await self.assessment_manager.process_student_turn(
                student_transcript=student_response,
                pause_duration=pause_sec,
            )
            prompt_context = build_examiner_turn_prompt(examiner_ctx)
            logger.info(
                "Evaluated turn for concept %s -> %s (Next: %s via %s)",
                turn_state.assessed_concept_id,
                turn_state.evaluation_result.value,
                turn_state.next_target_node,
                turn_state.graph_relation_followed,
            )

            pedagogical_directive = examiner_ctx.pedagogical_directive.strip()
            anti_repeat_note = ""
            if (
                self.last_spoken_directive
                and pedagogical_directive.lower() == self.last_spoken_directive.lower()
            ):
                anti_repeat_note = (
                    "\n\n[REGOLA ANTI-RIPETIZIONE ASSOLUTA]: "
                    "Hai già pronunciato questa stessa domanda/direttiva al turno precedente. "
                    "NON ripeterla con le stesse identiche parole! Varia la formulazione, poni una domanda su un caso concreto "
                    f"oppure chiedi un esempio pratico correlato a {examiner_ctx.concept_name}."
                )
            self.last_spoken_directive = pedagogical_directive

            return (
                f"status: ok\n"
                f"retryable: false\n"
                f"Evaluation: {turn_state.evaluation_result.value}.\n"
                f"Prossimo Argomento Target: {turn_state.next_target_node}.\n"
                f"DIRETTIVA PEDAGOGICA (DA PRONUNCIARE ALLO STUDENTE):\n"
                f"{pedagogical_directive}\n\n"
                f"CONTESTO DAL DOCUMENTO:\n{prompt_context}\n\n"
                f"REGOLE: Esprimi la direttiva pedagogica con tono naturale ed empatico da professore. "
                f"Non ripetere la stessa identica domanda precedente. "
                f"Se la direttiva chiede allo studente se vuole riprovare o cambiare argomento, pronuncia la domanda e attendi la sua scelta; non cambiare argomento senza una conferma chiara. "
                f"Se lo studente chiede esplicitamente di saltare l'argomento, segui la nuova domanda inclusa nella direttiva.{anti_repeat_note}"
            )
        except Exception as err:
            logger.exception("Error in evaluate_and_advance: %s", err)
            return (
                "status: error\n"
                "retryable: false\n"
                "message: Continua l'interrogazione verificando i concetti chiave del corso."
            )

    async def get_exam_progress(self, context: Any = None) -> str:
        """Get the current progress percentage and status of the examination plan."""
        plan = self.assessment_manager.examination_plan
        if not plan:
            return (
                "status: ok\n"
                "retryable: false\n"
                "message: Nessun piano d'esame formale attivo. Interrogazione in modalità esplorativa continua."
            )
        return (
            f"status: ok\n"
            f"retryable: false\n"
            f"Progresso esame: {plan.progress_percentage}%. "
            f"Concetto corrente: {self.assessment_manager.current_concept_id} "
            f"({plan.current_index + 1} di {len(plan.concept_order)} argomenti)."
        )

    async def get_session_summary(self, context: Any = None) -> str:
        """Generate the student's performance report and Root Cause Analysis."""
        try:
            report_gen = SessionReportGenerator(self.assessment_manager.graph_store)
            rep = await report_gen.generate_diagnostic_report(
                self.assessment_manager.history,
                self.assessment_manager.iterations_history,
            )
            spoken = rep.get("spoken_summary", "Sessione completata con successo.")
            return f"status: ok\nretryable: false\n{spoken}"
        except Exception as err:
            logger.exception("Error generating session summary: %s", err)
            return (
                "status: error\n"
                "retryable: false\n"
                "message: Riepilogo della sessione completato."
            )

    async def pause_session(self, context: Any = None, reason: str = "") -> str:
        """Pause the oral examination session and persist all progress to disk."""
        try:
            examiner_ctx, _ = await self.assessment_manager.pause_session(reason=reason)
            return (
                f"status: ok\n"
                f"retryable: false\n"
                f"DIRETTIVA PEDAGOGICA (DA PRONUNCIARE ALLO STUDENTE):\n"
                f"{examiner_ctx.pedagogical_directive}"
            )
        except Exception as err:
            logger.exception("Error pausing session: %s", err)
            return (
                "status: error\n"
                "retryable: false\n"
                "message: Sessione messa in pausa con successo."
            )

    async def resume_session(self, context: Any = None) -> str:
        """Resume a paused oral examination session from the exact topic and question."""
        try:
            examiner_ctx, _ = await self.assessment_manager.resume_session()
            prompt_context = build_examiner_turn_prompt(examiner_ctx)
            return (
                f"status: ok\n"
                f"retryable: false\n"
                f"DIRETTIVA PEDAGOGICA (DA PRONUNCIARE ALLO STUDENTE):\n"
                f"{examiner_ctx.pedagogical_directive}\n\n"
                f"CONTESTO DAL DOCUMENTO:\n{prompt_context}"
            )
        except Exception as err:
            logger.exception("Error resuming session: %s", err)
            return (
                "status: error\n"
                "retryable: false\n"
                "message: Bentornato! Riprendiamo l'esame dal punto in cui lo avevamo interrotto."
            )

    async def repeat_examination(self, context: Any = None) -> str:
        """Restart the oral examination as a new iteration, dynamically adapting to previous attempts."""
        try:
            examiner_ctx, _ = await self.assessment_manager.restart_examination(
                adapt_from_previous=True
            )
            prompt_context = build_examiner_turn_prompt(examiner_ctx)
            return (
                f"status: ok\n"
                f"retryable: false\n"
                f"DIRETTIVA PEDAGOGICA (DA PRONUNCIARE ALLO STUDENTE):\n"
                f"{examiner_ctx.pedagogical_directive}\n\n"
                f"CONTESTO DAL DOCUMENTO:\n{prompt_context}"
            )
        except Exception as err:
            logger.exception("Error restarting examination: %s", err)
            return (
                "status: error\n"
                "retryable: false\n"
                "message: Avviamo una nuova sessione d'esame. Sei pronto a ricominciare?"
            )

    async def get_exam_history_and_comparison(self, context: Any = None) -> str:
        """Compare the student's current performance with previous exam iterations."""
        try:
            report_gen = SessionReportGenerator(self.assessment_manager.graph_store)
            comp = await report_gen.compare_iterations(
                current_history=self.assessment_manager.history,
                iterations_history=self.assessment_manager.iterations_history,
            )
            spoken = comp.get(
                "spoken_comparison",
                "Non ci sono iterazioni precedenti sufficienti per un confronto.",
            )
            return f"status: ok\nretryable: false\n{spoken}"
        except Exception as err:
            logger.exception("Error comparing exam iterations: %s", err)
            return (
                "status: error\n"
                "retryable: false\n"
                "message: Confronto con le iterazioni precedenti completato."
            )

    async def get_conversation_transcript(self, context: Any = None) -> str:
        """Retrieve the formatted full transcript of current examination."""
        try:
            turns = self.assessment_manager.history
            if not turns:
                return (
                    "status: ok\n"
                    "retryable: false\n"
                    "message: Nessuno scambio registrato finora."
                )
            recent = turns[-5:]
            summary_lines = []
            for t in recent:
                t_num = t.get("turn", "?")
                q = t.get("ai_question", "")[:80]
                a = t.get("student_transcript", "")[:80]
                res = t.get("evaluation", "N/A")
                summary_lines.append(f"Turno {t_num} [{res}]: D: {q} | R: {a}")
            return f"status: ok\nretryable: false\n" + "\n".join(summary_lines)
        except Exception as err:
            logger.exception("Error retrieving transcript: %s", err)
            return (
                "status: error\n"
                "retryable: false\n"
                "message: Impossibile recuperare la trascrizione al momento."
            )

    def get_tools_schema(self) -> list[FunctionSchema]:
        """Convert agent methods into Pipecat FunctionSchema tools for function calling."""

        async def _eval_handler(params: FunctionCallParams):
            args = params.arguments or {}
            resp = await self.evaluate_and_advance(
                context=params.context,
                student_response=str(args.get("student_response", "")),
            )
            await params.result_callback(resp)

        async def _progress_handler(params: FunctionCallParams):
            resp = await self.get_exam_progress(context=params.context)
            await params.result_callback(resp)

        async def _summary_handler(params: FunctionCallParams):
            resp = await self.get_session_summary(context=params.context)
            await params.result_callback(resp)

        async def _pause_handler(params: FunctionCallParams):
            args = params.arguments or {}
            resp = await self.pause_session(
                context=params.context,
                reason=str(args.get("reason", "")),
            )
            await params.result_callback(resp)

        async def _resume_handler(params: FunctionCallParams):
            resp = await self.resume_session(context=params.context)
            await params.result_callback(resp)

        async def _repeat_handler(params: FunctionCallParams):
            resp = await self.repeat_examination(context=params.context)
            await params.result_callback(resp)

        async def _history_handler(params: FunctionCallParams):
            resp = await self.get_exam_history_and_comparison(context=params.context)
            await params.result_callback(resp)

        async def _transcript_handler(params: FunctionCallParams):
            resp = await self.get_conversation_transcript(context=params.context)
            await params.result_callback(resp)

        return [
            FunctionSchema(
                name="evaluate_and_advance",
                description="Evaluate the student's answer and advance the pedagogical graph.",
                properties={
                    "student_response": {
                        "type": "string",
                        "description": "Exact transcript of what the student said.",
                    }
                },
                required=["student_response"],
                handler=_eval_handler,
            ),
            FunctionSchema(
                name="get_exam_progress",
                description="Get current percentage progress in the syllabus.",
                properties={},
                required=[],
                handler=_progress_handler,
            ),
            FunctionSchema(
                name="get_session_summary",
                description="Generate diagnostic review and grade summary.",
                properties={},
                required=[],
                handler=_summary_handler,
            ),
            FunctionSchema(
                name="pause_session",
                description="Pause the examination session when student commands it.",
                properties={
                    "reason": {
                        "type": "string",
                        "description": "Reason for pausing.",
                    }
                },
                required=[],
                handler=_pause_handler,
            ),
            FunctionSchema(
                name="resume_session",
                description="Resume a paused examination session.",
                properties={},
                required=[],
                handler=_resume_handler,
            ),
            FunctionSchema(
                name="repeat_examination",
                description="Restart the examination as a new attempt.",
                properties={},
                required=[],
                handler=_repeat_handler,
            ),
            FunctionSchema(
                name="get_exam_history_and_comparison",
                description="Compare student performance across iterations.",
                properties={},
                required=[],
                handler=_history_handler,
            ),
            FunctionSchema(
                name="get_conversation_transcript",
                description="Retrieve formatted conversation history.",
                properties={},
                required=[],
                handler=_transcript_handler,
            ),
        ]


async def create_examiner_pipeline(
    transport: BaseTransport,
    course_id: str | None = None,
    is_direct_test: bool = False,
) -> tuple[PipelineTask, OralExaminerAgent, PipelineRunner]:
    """Factory creating a complete Pipecat real-time audio pipeline."""
    from assessment.courses import CourseManager

    CourseManager.ensure_directories()
    if not course_id:
        course_id = CourseManager.get_active_course_id()
    if not course_id:
        existing = CourseManager.list_courses()
        if existing:
            course_id = existing[0]["id"]

    CourseManager.set_active_course(course_id)
    course_dir = CourseManager.get_course_dir(course_id)
    state_path = course_dir / "state.json"
    plan_path = course_dir / "plan.json"
    events_path = course_dir / "events.jsonl"

    if (
        not plan_path.exists()
        and (CourseManager.DATA_DIR / "examination_plan.json").exists()
        and CourseManager.get_active_course_id() == course_id
    ):
        plan_path = CourseManager.DATA_DIR / "examination_plan.json"
    elif (
        not plan_path.exists()
        and Path("examination_plan.json").exists()
        and CourseManager.get_active_course_id() == course_id
    ):
        plan_path = Path("examination_plan.json")

    # Load examination plan if present
    plan = None
    plan_title = "esame orale"
    if plan_path.exists():
        try:
            from planning import ExaminationPlanner

            plan = ExaminationPlanner.load_plan_from_file(plan_path)
            plan_title = plan.title
        except Exception as err:
            logger.warning("Could not load examination plan: %s", err)

    # Reuse the stores populated during plan generation, or restore course
    # knowledge from disk when the API/agent process has restarted.
    from assessment.knowledge import load_course_stores

    material_path = course_dir / "material.md"
    if not material_path.exists():
        metadata_path = course_dir / "metadata.json"
        if metadata_path.exists():
            try:
                material_path = Path(
                    json.loads(metadata_path.read_text(encoding="utf-8")).get(
                        "file_path", ""
                    )
                )
            except (OSError, ValueError, TypeError):
                logger.warning(
                    "Could not resolve saved material for course %s", course_id
                )
    g_store, v_store = await load_course_stores(
        course_id, plan=plan, material_path=material_path
    )

    assessment_manager = SessionAssessmentManager(
        graph_store=g_store,
        vector_store=v_store,
        examination_plan=plan,
        state_file_path=state_path,
        events_file_path=events_path,
        execution_mode="pipecat",
        course_id=course_id,
    )

    is_resumed_session = False
    if state_path.exists():
        try:
            assessment_manager.load_session_state(state_path)
            if assessment_manager.history or assessment_manager.iterations_history:
                is_resumed_session = True
                assessment_manager.status = SessionStatus.ACTIVE
        except Exception as err:
            logger.warning("Could not restore session state: %s", err)

    if not is_resumed_session:
        assessment_manager.current_iteration = 1
        assessment_manager.history = []
        assessment_manager.consecutive_failures = 0
        assessment_manager.status = SessionStatus.ACTIVE
        assessment_manager.current_pedagogical_state = PedagogicalState.EXPLORATION

        if plan and plan.concept_order:
            assessment_manager.current_concept_id = plan.concept_order[0]
            plan.current_index = 0
            plan.is_completed = False
            plan.deferred_queue = []
            for item in plan.items.values():
                item.status = PlanItemStatus.PENDING
                item.current_attempt = 0
            if assessment_manager.current_concept_id in plan.items:
                plan.items[
                    assessment_manager.current_concept_id
                ].status = PlanItemStatus.IN_PROGRESS

    if is_resumed_session and assessment_manager.current_concept_id:
        curr_c = assessment_manager.current_concept_id.replace("_", " ").title()
        greeting = (
            f"Bentornato alla discussione su {plan_title}! "
            f"Eravamo rimasti all'argomento '{curr_c}'. Sei pronto a riprendere?"
        )
        opening_rule = (
            f"1. **Fase di Ripresa (One-time element):**\n"
            f'   All\'avvio della connessione saluta dicendo unicamente: "{greeting}"\n'
            f"   Aspetta che lo studente ti risponda confermando di voler procedere.\n"
            f"   Non appena conferma, invoca IMMEDIATAMENTE `evaluate_and_advance` con la sua conferma.\n"
        )
    else:
        greeting = (
            f"Buongiorno! Benvenuto alla simulazione di {plan_title}. "
            "Iniziamo con il primo argomento del documento. Sei pronto?"
        )
        opening_rule = (
            f"1. **Fase di Apertura (One-time element):**\n"
            f'   All\'avvio della sessione saluta dicendo unicamente: "{greeting}"\n'
            f"   Aspetta che lo studente ti risponda confermando di voler procedere.\n"
            f"   Non appena conferma, invoca IMMEDIATAMENTE `evaluate_and_advance` con la sua conferma.\n"
        )

    plan_topics_summary = ""
    if plan and plan.concept_order:
        plan_topics_summary = ", ".join(
            f"'{plan.items[cid].concept_name}'"
            for cid in plan.concept_order[:12]
            if cid in plan.items
        )

    instructions = (
        f"**Persona:**\n"
        f"Sei la Docente Universitaria titolare del corso di '{plan_title}'. "
        f"Conduci l'esame orale simulato con tono autorevole, empatico, chiaro, calmo e naturale, ESCLUSIVAMENTE sui contenuti del corso.\n"
        f"RESPOND IN ITALIAN. YOU MUST RESPOND UNMISTAKABLY IN ITALIAN.\n\n"
        f"**Conversational Rules:**\n"
        f"{opening_rule}"
        f"2. **Fase di Interrogazione:**\n"
        f"   - Ad ogni turno, invoca IMMEDIATAMENTE `evaluate_and_advance` con la risposta dello studente.\n"
        f"   - Formula la tua risposta vocale basandoti sulla 'DIRETTIVA PEDAGOGICA' restituita dallo strumento.\n\n"
        f"**Programma del Corso:**\n"
        f"{plan_topics_summary}\n\n"
        f"**Guardrails:**\n"
        f"- Rispondi in testo semplice senza markdown né asterischi.\n"
        f"- ZERO RIPETIZIONI: Non ripetere la stessa domanda due volte di seguito.\n"
    )

    agent_instance = OralExaminerAgent(
        assessment_manager=assessment_manager,
        instructions=instructions,
    )
    tools = agent_instance.get_tools_schema()

    # Build Pipeline based on operational mode
    is_gemini_live = config.pipeline_mode == "gemini_live"

    if is_gemini_live:
        gemini_model = (
            config.gemini_live_model
            if "/" in config.gemini_live_model
            else f"models/{config.gemini_live_model}"
        )
        if "gemini-3.8-live" in gemini_model:
            # Fallback or standard Pipecat model identifier
            gemini_model = "models/gemini-3.8-live"

        llm_service = GeminiLiveLLMService(
            api_key=config.google_api_key or os.getenv("GEMINI_API_KEY", ""),
            settings=GeminiLiveLLMService.Settings(
                model=gemini_model,
                voice=config.gemini_voice,
                language="it-IT",
                system_instruction=instructions,
                # Gemini's default end-of-speech wait is relatively long.
                # 500 ms reduces turn latency while preserving natural pauses.
                vad=GeminiVADParams(silence_duration_ms=500),
            ),
            tools=tools,
        )
        pipeline = Pipeline(
            [
                transport.input(),
                llm_service,
                transport.output(),
            ]
        )
    else:
        # Cascaded STT -> LLM -> TTS pipeline
        vad = SileroVADAnalyzer()

        stt_service = DeepgramSTTService(
            api_key=config.deepgram_api_key or "test_key",
            settings=DeepgramSTTService.Settings(
                language=config.stt_language
                if config.stt_language != "multi"
                else "it",
            ),
        )

        context = LLMContext()
        user_agg, asst_agg = LLMContextAggregatorPair(context)

        if config.openai_api_key:
            llm_proc = OpenAILLMService(
                api_key=config.openai_api_key,
                settings=OpenAILLMService.Settings(
                    model="gpt-4o-mini",
                    system_instruction=instructions,
                ),
                tools=tools,
            )
        else:
            llm_proc = LocalOrchestratedLLMService(
                assessment_manager=assessment_manager
            )

        tts_service = ElevenLabsTTSService(
            api_key=config.eleven_api_key or "test_key",
            settings=ElevenLabsTTSService.Settings(
                voice=config.tts_voice,
                model="eleven_turbo_v2_5",
            ),
        )

        pipeline = Pipeline(
            [
                transport.input(),
                vad,
                stt_service,
                user_agg,
                llm_proc,
                tts_service,
                transport.output(),
                asst_agg,
            ]
        )

    task = PipelineTask(
        pipeline,
        params=PipelineParams(
            allow_interruptions=True,
            enable_metrics=True,
        ),
    )

    runner = PipelineRunner()

    @transport.event_handler("on_client_connected")
    async def on_client_connected(transport, client):
        logger.info("Student connected to Pipecat session for course %s", course_id)
        assessment_manager.last_ai_directive = greeting
        if is_gemini_live:

            async def queue_greeting_after_gemini_connects():
                try:
                    await _queue_opening_greeting(task, greeting)
                    logger.info("Queued opening greeting for course %s", course_id)
                except Exception as e:
                    logger.warning("Error queuing opening greeting frame: %s", e)

            # Do not block transport.start(): the Gemini processor receives
            # StartFrame only after the client's on-connected callback returns.
            asyncio.create_task(queue_greeting_after_gemini_connects())
        else:
            try:
                await task.queue_frames([TextFrame(text=greeting)])
            except Exception as e:
                logger.warning("Error queuing opening greeting frame: %s", e)

    @transport.event_handler("on_client_disconnected")
    async def on_client_disconnected(transport, client):
        logger.info(
            "Student disconnected from Pipecat session for course %s", course_id
        )
        try:
            assessment_manager.record_event(
                "SESSION_SHUTDOWN", {"mode": "pipecat", "course_id": course_id}
            )
            if assessment_manager.status != SessionStatus.COMPLETED:
                assessment_manager.status = SessionStatus.PAUSED
            target_save = course_dir / "state.json"
            assessment_manager.save_session_state(target_save)
            logger.info("Saved paused session state on disconnect for %s", course_id)
        except Exception as e:
            logger.warning("Error saving session state on disconnect: %s", e)
        await task.cancel()

    return task, agent_instance, runner


async def run_examiner_pipeline(
    transport: BaseTransport,
    course_id: str | None = None,
    is_direct_test: bool = False,
) -> None:
    """Run an examiner session pipeline until client disconnects or completion."""
    task, _agent, runner = await create_examiner_pipeline(
        transport=transport,
        course_id=course_id,
        is_direct_test=is_direct_test,
    )
    await runner.run(task)
