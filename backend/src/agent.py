"""LiveKit Voice AI Agent Entrypoint for Oral Examination & Study Assistance.

Supports dual operational architectures:
1. Gemini Live API: End-to-end multimodal speech-to-speech with Google RealtimeModel,
   neural noise cancellation (ai_coustics QUAIL_VF_S), and realtime function calling
   for pedagogical steering (`evaluate_and_advance`, `get_exam_progress`, `get_session_summary`).
2. Cascaded Voice Pipeline: Deepgram Nova-3 STT -> Local/Inference LLM -> ElevenLabs Turbo v2.5 TTS
   with turn detector and preemptive audio synthesis.
"""

import asyncio
import logging
import re
import shutil
from datetime import datetime
from pathlib import Path

from livekit.agents import (
    Agent,
    AgentServer,
    AgentSession,
    JobContext,
    RunContext,
    TurnHandlingOptions,
    cli,
    function_tool,
    inference,
    llm,
    room_io,
)
from google.genai import types
from livekit.plugins import ai_coustics, deepgram, elevenlabs, google, openai

from assessment import (
    PedagogicalState,
    SessionAssessmentManager,
    SessionReportGenerator,
    SessionStatus,
    is_silence_or_noise,
)
from config import config
from orchestrator import LocalOrchestratedLLM
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


def extract_custom_vocabulary(plan, max_terms: int = 100) -> list[str]:
    """Extract domain terms, technical concepts, and keywords from the examination plan for Gemini 3.8 Live biasing."""
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


class OralExaminerAgent(Agent):
    """Voice AI Oral Examiner with Hybrid RAG & Knowledge Tracing."""

    def __init__(
        self,
        assessment_manager: SessionAssessmentManager | None = None,
        examiner_llm: llm.LLM | llm.RealtimeModel | None = None,
        instructions: str | None = None,
    ) -> None:
        self.assessment_manager = assessment_manager or SessionAssessmentManager(
            graph_store=create_graph_store("memory"),
            vector_store=create_vector_store("memory"),
        )
        self.last_assistant_ts: float = 0.0
        self.last_spoken_directive: str = ""
        final_instructions = instructions or ORAL_EXAMINER_SYSTEM_INSTRUCTIONS

        if examiner_llm is not None:
            chosen_llm = examiner_llm
        elif config.pipeline_mode == "gemini_live":
            vocab = extract_custom_vocabulary(self.assessment_manager.examination_plan)
            chosen_llm = google.realtime.RealtimeModel(
                model=config.gemini_live_model,
                voice=config.gemini_voice,
                api_key=config.google_api_key or None,
                instructions=final_instructions,
                temperature=0.3,
                input_audio_transcription=(
                    types.AudioTranscriptionConfig(custom_vocabulary=vocab)
                    if vocab
                    else types.AudioTranscriptionConfig()
                ),
                output_audio_transcription=types.AudioTranscriptionConfig(),
                tool_behavior=types.Behavior.BLOCKING,
                tool_response_scheduling=types.FunctionResponseScheduling.WHEN_IDLE,
                context_window_compression=types.ContextWindowCompressionConfig(
                    sliding_window=types.SlidingWindow()
                ),
            )
        elif config.openai_api_key:
            chosen_llm = openai.LLM(
                model="gpt-4o-mini",
                api_key=config.openai_api_key,
            )
        else:
            chosen_llm = LocalOrchestratedLLM(
                assessment_manager=self.assessment_manager
            )

        super().__init__(
            llm=chosen_llm,
            instructions=final_instructions,
        )

    @function_tool
    async def evaluate_and_advance(
        self, context: RunContext, student_response: str
    ) -> str:
        """Evaluate the student's answer, update the knowledge graph & Bayesian mastery,
        and retrieve the next ground-truth context and pedagogical directive.

        **Invocation Condition:** Invoke this tool immediately every time the student provides
        an answer, partial response, hesitation, or request to change question during the examination loop.

        Args:
            student_response: The exact transcript of what the student said.
        """
        try:
            if is_silence_or_noise(student_response):
                logger.info("evaluate_and_advance: ignoring silence/noise utterance ('%s')", student_response)
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
                f"Se lo studente ha chiesto di cambiare o se ha fallito dopo l'indizio, passa direttamente alla nuova domanda inclusa nella direttiva.{anti_repeat_note}"
            )
        except Exception as err:
            logger.exception("Error in evaluate_and_advance: %s", err)
            return (
                "status: error\n"
                "retryable: false\n"
                "message: Continua l'interrogazione verificando i concetti chiave del corso."
            )

    @function_tool
    async def get_exam_progress(self, context: RunContext) -> str:
        """Get the current progress percentage and status of the examination plan.

        **Invocation Condition:** Invoke this tool *only if* the student explicitly asks about
        their progress, remaining questions, or how the exam is proceeding.
        """
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

    @function_tool
    async def get_session_summary(self, context: RunContext) -> str:
        """Generate the student's performance report and Root Cause Analysis.

        **Invocation Condition:** Invoke this tool when the examination is completed or
        when the student explicitly requests a final grade, recap, or diagnostic review.
        """
        try:
            report_gen = SessionReportGenerator(self.assessment_manager.graph_store)
            rep = await report_gen.generate_diagnostic_report(
                self.assessment_manager.history,
                self.assessment_manager.iterations_history,
            )
            spoken = rep.get("spoken_summary", "Sessione completata con successo.")
            return (
                f"status: ok\n"
                f"retryable: false\n"
                f"{spoken}"
            )
        except Exception as err:
            logger.exception("Error generating session summary: %s", err)
            return (
                "status: error\n"
                "retryable: false\n"
                "message: Riepilogo della sessione completato."
            )

    @function_tool
    async def pause_session(self, context: RunContext, reason: str = "") -> str:
        """Pause the oral examination session and persist all progress to disk.

        **CRITICAL INVOCATION CONDITION:** Invoke this tool ONLY AND EXCLUSIVELY if the student explicitly
        commands to pause, take a break, or stop the exam (e.g., 'pausa', 'fermiamoci qui', 'facciamo una pausa', 'voglio fermarmi').
        NEVER invoke this tool during normal student answers, technical discussions (e.g., early stopping, bootstrap, criteria),
        hesitations, thinking pauses, silence, or regular questions!
        """
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

    @function_tool
    async def resume_session(self, context: RunContext) -> str:
        """Resume a paused oral examination session from the exact topic and question.

        **Invocation Condition:** Invoke this tool when the student expresses readiness to resume
        a previously paused exam session (e.g., 'riprendiamo', 'sono pronto a continuare').
        """
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

    @function_tool
    async def repeat_examination(self, context: RunContext) -> str:
        """Restart the oral examination as a new iteration, dynamically adapting to previous attempts.

        **Invocation Condition:** Invoke this tool when the student asks to repeat, retake, or restart
        the examination (e.g., 'ripetiamo l'esame', 'voglio fare un altro tentativo', 'ricominciamo').
        """
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

    @function_tool
    async def get_exam_history_and_comparison(self, context: RunContext) -> str:
        """Compare the student's current performance with previous exam iterations and show historical evolution.

        **Invocation Condition:** Invoke this tool when the student asks about their progress over time,
        historical comparisons, or how they improved compared to previous attempts.
        """
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
            return (
                f"status: ok\n"
                f"retryable: false\n"
                f"{spoken}"
            )
        except Exception as err:
            logger.exception("Error comparing exam iterations: %s", err)
            return (
                "status: error\n"
                "retryable: false\n"
                "message: Confronto con le iterazioni precedenti completato."
            )

    @function_tool
    async def get_conversation_transcript(self, context: RunContext) -> str:
        """Retrieve the formatted full transcript of the questions and answers from the current examination.

        **Invocation Condition:** Invoke this tool when the student asks to review what has been said,
        recap previous questions/answers, or check the dialogue transcript.
        """
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
            return (
                f"status: ok\n"
                f"retryable: false\n"
                + "\n".join(summary_lines)
            )
        except Exception as err:
            logger.exception("Error retrieving transcript: %s", err)
            return (
                "status: error\n"
                "retryable: false\n"
                "message: Impossibile recuperare la trascrizione al momento."
            )


server = AgentServer()


async def on_session_end(ctx: JobContext) -> None:
    """Invoked when the voice session ends to record telemetry and session summary."""
    try:
        report = ctx.make_session_report()
        report_dict = report.to_dict()
        logger.info(
            "Session ended for room %s: %d conversation events logged.",
            ctx.room.name,
            len(report_dict.get("events", [])),
        )
    except Exception as err:
        logger.warning(
            "Could not generate final session report for room %s: %s",
            ctx.room.name,
            err,
        )


@server.rtc_session(agent_name=config.agent_name, on_session_end=on_session_end)
async def my_agent(ctx: JobContext):
    # Contextual structured logging setup
    ctx.log_context_fields = {
        "room": ctx.room.name,
        "agent": config.agent_name,
        "pipeline_mode": config.pipeline_mode,
    }
    logger.info(
        "Initializing oral examination voice session for room %s (Mode: %s)",
        ctx.room.name,
        config.pipeline_mode,
    )
    execution_mode = "cloud"

    # Resolve target course_id from LiveKit room name or active course
    from assessment.courses import CourseManager
    CourseManager.ensure_directories()

    course_id = None
    if getattr(ctx, "job", None) and getattr(ctx.job, "metadata", None):
        course_id = ctx.job.metadata.strip() or None

    if not course_id and getattr(ctx.room, "metadata", None):
        course_id = ctx.room.metadata.strip() or None

    if not course_id and ctx.room.name:
        match = re.match(r"^oral-exam-(.+)-(\d+)$", ctx.room.name)
        if match and match.group(1) != "room" and not match.group(1).isdigit():
            course_id = match.group(1)
        elif ctx.room.name.startswith("oral-exam-") and ctx.room.name not in ("oral-exam", "oral-exam-room"):
            candidate = ctx.room.name[len("oral-exam-"):]
            if candidate and not candidate.isdigit():
                course_id = candidate

    if not course_id:
        course_id = CourseManager.get_active_course_id()

    logger.info("Voice session for room %s bound to course: %s", ctx.room.name, course_id)
    CourseManager.set_active_course(course_id)

    course_dir = CourseManager.get_course_dir(course_id)
    state_path = course_dir / "state.json"
    plan_path = course_dir / "plan.json"
    events_path = course_dir / "events.jsonl"

    if not plan_path.exists() and (CourseManager.DATA_DIR / "examination_plan.json").exists():
        plan_path = CourseManager.DATA_DIR / "examination_plan.json"
    if not state_path.exists() and (CourseManager.DATA_DIR / "session_state.json").exists():
        state_path = CourseManager.DATA_DIR / "session_state.json"

    # Register graceful shutdown callback
    async def on_shutdown():
        logger.info(
            "Shutdown initiated for room %s (course %s). Saving session resources.",
            ctx.room.name,
            course_id,
        )
        try:
            assessment_manager.record_event(
                "SESSION_SHUTDOWN", {"room": ctx.room.name, "mode": execution_mode, "course_id": course_id}
            )
            # When interrupted or disconnected, keep session as PAUSED so it can be resumed
            # seamlessly without spawning duplicate sessions or losing ongoing turns!
            if assessment_manager.status != SessionStatus.COMPLETED:
                assessment_manager.status = SessionStatus.PAUSED

            target_save = course_dir / "state.json"
            assessment_manager.save_session_state(target_save)

            logger.info(
                "Persisted paused state on shutdown for course %s: %d conversation turns saved.",
                course_id,
                len(assessment_manager.history),
            )
        except Exception as e:
            logger.warning("Could not persist session state on shutdown: %s", e)

    ctx.add_shutdown_callback(on_shutdown)

    # Load active Examination Plan if available
    plan_title = "esame orale"
    plan = None
    if plan_path.exists():
        try:
            from planning import ExaminationPlanner

            plan = ExaminationPlanner.load_plan_from_file(plan_path)
            plan_title = plan.title
            logger.info("Loaded active ExaminationPlan for %s: %s", course_id, plan_title)
        except Exception as err:
            logger.warning("Could not load examination plan from %s: %s", plan_path, err)

    # Initialize Graph & Vector stores for SessionAssessmentManager
    g_store = create_graph_store(
        "neo4j" if config.neo4j_uri != "bolt://localhost:7687" else "memory"
    )
    v_store = create_vector_store(
        "qdrant" if config.qdrant_url != "http://localhost:6333" else "memory"
    )
    assessment_manager = SessionAssessmentManager(
        graph_store=g_store,
        vector_store=v_store,
        examination_plan=plan,
        state_file_path=state_path,
        events_file_path=events_path,
        execution_mode=execution_mode,
    )

    # Check for existing session state for this document
    is_resumed_session = False

    if state_path.exists():
        try:
            assessment_manager.load_session_state(state_path)
            # True resumption only when there are existing conversation turns
            if assessment_manager.history or assessment_manager.iterations_history:
                is_resumed_session = True
                assessment_manager.status = SessionStatus.ACTIVE
                logger.info(
                    "Resuming active discussion for course %s, concept %s with %d existing turns",
                    course_id,
                    assessment_manager.current_concept_id,
                    len(assessment_manager.history),
                )
        except Exception as err:
            logger.warning("Could not restore existing session state from %s: %s", state_path, err)

    # For brand-new documents or fully reset sessions, initialize starting state
    if not is_resumed_session:
        logger.info(
            "Initializing single discussion state for document: %s in room: %s",
            plan_title,
            ctx.room.name,
        )
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

    curr_cid = assessment_manager.current_concept_id
    if curr_cid and plan and curr_cid in plan.items:
        first_item = plan.items[curr_cid]
    else:
        first_item = plan.current_item if plan else None

    first_q = (
        first_item.planned_question.main_question
        if first_item and hasattr(first_item, "planned_question") and hasattr(first_item.planned_question, "main_question")
        else "Mi parli dei concetti fondamentali del corso."
    )

    if is_resumed_session and assessment_manager.current_concept_id:
        curr_c = assessment_manager.current_concept_id.replace("_", " ").title()
        greeting = (
            f"Bentornato alla discussione su {plan_title}! "
            f"Eravamo rimasti all'argomento '{curr_c}'. Sei pronto a riprendere?"
        )
    else:
        greeting = (
            f"Buongiorno! Benvenuto alla simulazione di {plan_title}. "
            "Iniziamo con il primo argomento del documento. Sei pronto?"
        )

    plan_topics_summary = ""
    if plan and plan.concept_order:
        plan_topics_summary = ", ".join(
            f"'{plan.items[cid].concept_name}'"
            for cid in plan.concept_order[:12]
            if cid in plan.items
        )

    if is_resumed_session:
        opening_rule = (
            f"1. **Fase di Ripresa (One-time element):**\n"
            f'   All\'avvio della connessione saluta e chiedi conferma per riprendere dicendo unicamente: "{greeting}"\n'
            f"   Aspetta che lo studente ti risponda confermando di voler procedere (es. 'Sì', 'Procediamo', 'Sono pronto', 'Iniziamo').\n"
            f"   Non appena conferma, invoca IMMEDIATAMENTE `evaluate_and_advance` con la sua conferma.\n"
            f"   Pronuncia la domanda restituita nella DIRETTIVA PEDAGOGICA UNA SOLA VOLTA. NON anticipare la domanda prima della risposta dello strumento né ripeterla mai due volte!\n"
        )
    else:
        opening_rule = (
            f"1. **Fase di Apertura (One-time element):**\n"
            f'   All\'avvio della sessione saluta e chiedi se lo studente è pronto dicendo unicamente: "{greeting}"\n'
            f"   Aspetta che lo studente ti risponda confermando di voler procedere (es. 'Sì', 'Procediamo', 'Sono pronto', 'Iniziamo').\n"
            f"   Non appena conferma, invoca IMMEDIATAMENTE `evaluate_and_advance` con la sua conferma.\n"
            f"   Pronuncia la prima domanda restituita nella DIRETTIVA PEDAGOGICA UNA SOLA VOLTA. NON anticipare la domanda prima della risposta dello strumento né ripeterla mai due volte!\n"
        )

    instructions = (
        f"**Persona:**\n"
        f"Sei la Docente Universitaria titolare del corso di '{plan_title}'. "
        f"Conduci l'esame orale simulato con tono autorevole, empatico, chiaro, calmo e naturale, ESCLUSIVAMENTE sui contenuti del corso.\n"
        f"RESPOND IN ITALIAN. YOU MUST RESPOND UNMISTAKABLY IN ITALIAN.\n\n"
        f"**Costanza Vocale e Timbro (FONDAMENTALE):**\n"
        f"- Mantieni SEMPRE rigorosamente la stessa identica voce, timbro, altezza (pitch), cadenza e volume durante tutta la discussione, sia all'avvio sia quando riprendi una sessione interrotta.\n"
        f"- Il tuo tono deve rimanere immutato: pacato, professionale, accademico, naturale ed empatico da docente universitaria.\n"
        f"- Non alterare MAI il tono di voce o la prosodia tra l'apertura e la ripresa o tra una domanda e l'altra.\n\n"
        f"**Conversational Rules:**\n"
        f"{opening_rule}"
        f"2. **Fase di Interrogazione (Conversational loop):**\n"
        f"   - Ad ogni turno, invoca IMMEDIATAMENTE `evaluate_and_advance` con la risposta esatta pronunciata dallo studente.\n"
        f"   - Formula la tua risposta vocale allo studente basandoti sulla 'DIRETTIVA PEDAGOGICA' restituita dallo strumento.\n"
        f"   - **ADAPTIVE SCAFFOLDING (Guida Personalizzata sulle Lacune):**\n"
        f"     * Se lo studente è in difficoltà ma ha accennato a qualcosa di corretto: NON usare formule fisse né ripetere la domanda generale. Riconosci ciò che ha detto di buono e fagli una domanda guida mirata specificamente sulla parte che gli manca per completare il concetto.\n"
        f"     * Se lo studente NON riesce a dare alcuna risposta o dichiara di non sapere nulla: fornisci un indizio generale o procedi con garbo all'argomento successivo previsto dal piano.\n"
        f"     * Se lo studente chiede esplicitamente di cambiare domanda: passa immediatamente al nuovo argomento senza insistere.\n\n"
        f"**Tool Invocations & Protocol Rules (Gemini 3.8 Live Conventions):**\n"
        f"- Non eseguire MAI più di due chiamate consecutive a strumenti senza parlare ad alta voce allo studente.\n"
        f"- Quando ricevi la risposta da uno strumento (status: ok), formula ed esprimi IMMEDIATAMENTE ad alta voce la 'DIRETTIVA PEDAGOGICA' per mantenere il dialogo naturale.\n"
        f"- Non invocare mai due volte lo stesso strumento per il medesimo input dello studente.\n"
        f"- Invoca `evaluate_and_advance(student_response=...)` ad ogni risposta dello studente per sincronizzarti con il piano d'esame.\n"
        f"- Invoca `pause_session()` SOLO ED ESCLUSIVAMENTE se lo studente comanda esplicitamente di fermare l'esame o fare una pausa (es. 'facciamo una pausa', 'fermiamoci qui', 'voglio fermarmi'). NON invocarlo MAI se lo studente parla di argomenti tecnici (es. early stopping, bootstrap), se esita o se tace!\n"
        f"- Invoca `resume_session()` se lo studente riprende la sessione sospesa.\n"
        f"- Invoca `repeat_examination()` se lo studente chiede di ripetere l'esame da capo.\n"
        f"- Invoca `get_exam_history_and_comparison()` se lo studente chiede il confronto con la prova precedente o lo storico.\n"
        f"- Invoca `get_exam_progress()` se lo studente chiede a che punto si trova o quanti argomenti mancano.\n"
        f"- Invoca `get_session_summary()` a fine esame o su richiesta di recap finale.\n\n"
        f"**Programma del Corso (Sequenza Didattica):**\n"
        f"{plan_topics_summary}\n\n"
        f"**Guardrails:**\n"
        f"- ZERO ALLUCINAZIONI: Domande e verifiche devono riguardare esclusivamente il programma d'esame.\n"
        f"- FORMATO VOCALE: Rispondi in testo semplice. Non usare MAI markdown, asterischi, elenchi puntati o emoji.\n"
        f"- REGOLA ASSOLUTA CONTRO LE RIPETIZIONI (ZERO RIPETIZIONI):\n"
        f"  * Non ripetere MAI la stessa identica domanda o direttiva due volte di seguito.\n"
        f"  * Non porre mai la stessa domanda due volte nello stesso turno (né prima né dopo la chiamata allo strumento).\n"
        f"  * Se hai già fatto una domanda, attendi la risposta dello studente o formula un indizio differente senza duplicare la frase precedente.\n"
        f"- GESTIONE DEL SILENZIO:\n"
        f"  * Se lo studente tace o riflette in silenzio, non ripetergli la domanda a raffica. Lasciagli qualche secondo per pensare con calma.\n"
        f"- REGOLA CRITICA ZERO PAUSE ACCIDENTALI:\n"
        f"  * Non mettere MAI in pausa la sessione a meno che lo studente non lo chieda con comandi espliciti e inequivocabili di interruzione.\n"
    )

    # Configure session based on pipeline mode
    if config.pipeline_mode == "gemini_live":
        custom_vocab = extract_custom_vocabulary(plan)
        logger.info(
            "Starting Gemini 3.8 Live speech-to-speech session with model %s, voice %s, custom_vocab terms: %d",
            config.gemini_live_model,
            config.gemini_voice,
            len(custom_vocab),
        )
        realtime_model = google.realtime.RealtimeModel(
            model=config.gemini_live_model,
            voice=config.gemini_voice,
            api_key=config.google_api_key or None,
            instructions=instructions,
            temperature=0.3,
            input_audio_transcription=(
                types.AudioTranscriptionConfig(custom_vocabulary=custom_vocab)
                if custom_vocab
                else types.AudioTranscriptionConfig()
            ),
            output_audio_transcription=types.AudioTranscriptionConfig(),
            tool_behavior=types.Behavior.BLOCKING,
            tool_response_scheduling=types.FunctionResponseScheduling.WHEN_IDLE,
            context_window_compression=types.ContextWindowCompressionConfig(
                sliding_window=types.SlidingWindow()
            ),
        )
        session = AgentSession(llm=realtime_model)
        agent_instance = OralExaminerAgent(
            assessment_manager=assessment_manager,
            examiner_llm=realtime_model,
            instructions=instructions,
        )
    else:
        # Configure TTS instance: uses direct ElevenLabs plugin if custom API key is present, otherwise LiveKit Inference
        if config.eleven_api_key:
            logger.info(
                "Using ElevenLabs plugin for custom voice ID: %s", config.tts_voice
            )
            tts_instance = elevenlabs.TTS(
                voice_id=config.tts_voice,
                model="eleven_turbo_v2_5",
                api_key=config.eleven_api_key,
                language=config.tts_language,
                voice_settings=elevenlabs.VoiceSettings(
                    stability=0.85,
                    similarity_boost=0.90,
                    style=0.0,
                    use_speaker_boost=True,
                ),
            )
        else:
            tts_instance = inference.TTS(
                model=config.tts_primary_model,
                voice=config.tts_voice,
                language=config.tts_language,
                extra_kwargs={
                    "stability": 0.85,
                    "similarity_boost": 0.90,
                    "style": 0.0,
                    "use_speaker_boost": True,
                    "apply_language_text_normalization": True,
                },
            )

        # Configure STT instance: direct Deepgram plugin if API key present, else LiveKit Inference
        if config.deepgram_api_key:
            logger.info("Using Deepgram plugin directly for STT")
            stt_instance = deepgram.STT(
                api_key=config.deepgram_api_key,
                language=config.stt_language,
                endpointing=200,
                interim_results=False,
            )
        else:
            stt_instance = inference.STT(
                model=config.stt_primary_model,
                language=config.stt_language,
                extra_kwargs={
                    "no_delay": True,
                    "endpointing": 200,
                    "interim_results": False,
                },
                fallback=[{"model": config.stt_fallback_model}],
            )

        # High-performance, tuned cascaded STT->LLM->TTS pipeline for oral exam pacing
        session = AgentSession(
            stt=stt_instance,
            tts=tts_instance,
            turn_handling=TurnHandlingOptions(
                # Multimodal acoustic & semantic turn detector
                turn_detection=inference.TurnDetector(),
                endpointing={
                    "mode": "dynamic",
                    "min_delay": 0.65,
                    "max_delay": 2.5,
                },
                interruption={
                    "mode": "adaptive",
                    "min_duration": 0.25,
                    "resume_false_interruption": False,
                },
                preemptive_generation={
                    "enabled": True,
                    "preemptive_tts": True,
                },
                expressive=True,
            ),
        )
        agent_instance = OralExaminerAgent(
            assessment_manager=assessment_manager,
            instructions=instructions,
        )

    # Track conversation timestamps to measure student thinking latency
    agent_instance.last_assistant_ts = asyncio.get_event_loop().time()

    @session.on("conversation_item_added")
    def _on_conversation_item_added(event) -> None:
        now = asyncio.get_event_loop().time()
        item = getattr(event, "item", event)
        role = getattr(item, "role", None)
        if role == "assistant":
            agent_instance.last_assistant_ts = now

    # Start session: for Gemini Live, native cloud-side noise cancellation and AEC are used.
    # We avoid local CPU neural enhancement (ai_coustics) to eliminate latency and audio stuttering.
    room_options = room_io.RoomOptions()
    if config.pipeline_mode != "gemini_live":
        room_options = room_io.RoomOptions(
            audio_input=room_io.AudioInputOptions(
                noise_cancellation=ai_coustics.audio_enhancement(
                    model=ai_coustics.EnhancerModel.QUAIL_VF_S
                ),
            ),
        )

    # Join the room and connect to the user
    await ctx.connect()

    # Start voice agent session on the connected room
    await session.start(
        agent=agent_instance,
        room=ctx.room,
        room_options=room_options,
    )

    # Wait for the student participant to connect before speaking
    try:
        participant = await ctx.wait_for_participant()
        logger.info(
            "Student participant connected: %s (%s)",
            participant.identity,
            participant.name,
        )
    except Exception as e:
        logger.warning("Error waiting for participant: %s", e)

    # Persist initial session state asynchronously in background thread so greeting is not blocked
    def _save_state_bg():
        try:
            target_save = course_dir / "state.json"
            assessment_manager.save_session_state(target_save)
        except Exception as err:
            logger.warning("Could not save initial session state in background: %s", err)

    asyncio.create_task(asyncio.to_thread(_save_state_bg))

    # Opening greeting: allow 400ms for mobile WebRTC track subscription & audio session stabilization
    assessment_manager.last_ai_directive = greeting
    logger.info("Speaking opening greeting with minimum latency: %s", greeting)
    if config.pipeline_mode == "gemini_live":
        await asyncio.sleep(0.4)
        greeting_instruction = (
            f'Saluta lo studente pronunciando ad alta voce con tono pacato, accademico e naturale unicamente ed esattamente: "{greeting}"'
        )
        session.generate_reply(
            instructions=greeting_instruction,
        )
    else:
        await session.say(greeting)


if __name__ == "__main__":
    cli.run_app(server)
