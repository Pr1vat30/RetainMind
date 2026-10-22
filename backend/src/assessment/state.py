"""Session assessment and pedagogical state management.

Tracks real-time student mastery, manages examination plan progression,
orchestrates spaced-repetition retry for deferred concepts, and handles
session persistence and resumption.
"""

from __future__ import annotations

import asyncio
import json
import logging
import re
import time
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any

from assessment.bkt import BayesianKnowledgeTracing
from assessment.evaluator import ResponseEvaluator
from assessment.fsm import OralExaminerFSM
from config import config
from planning.models import ExaminationPlan, PlanItemStatus
from rag.graph_store import BaseGraphStore
from rag.hybrid_retriever import HybridRAGRetriever
from rag.models import (
    ConceptNode,
    EvaluationDetail,
    EvaluationResultType,
    ExaminerContext,
    PedagogicalState,
    TurnAssessmentState,
)
from rag.vector_store import BaseVectorStore

logger = logging.getLogger("agent.assessment.state")


class SessionStatus(str, Enum):
    """Lifecycle state of the examination session."""

    ACTIVE = "ACTIVE"
    PAUSED = "PAUSED"
    COMPLETED = "COMPLETED"


# Words indicating student readiness to begin the oral examination
AFFIRMATIVE_READINESS_WORDS: frozenset[str] = frozenset(
    {
        "sì",
        "si",
        "pronto",
        "pronta",
        "procediamo",
        "procedi",
        "avanti",
        "iniziamo",
        "partiamo",
        "possiamo",
        "ok",
        "okay",
        "va bene",
        "certamente",
        "certo",
        "quando vuoi",
        "vai",
        "yes",
    }
)

SILENCE_AND_NOISE_TOKENS: frozenset[str] = frozenset(
    {
        "-",
        "—",
        "–",
        "--",
        "---",
        ".",
        "..",
        "...",
        "....",
        "?",
        "!",
        ",",
        "_",
        "silenzio",
        "[silenzio]",
        "(silenzio)",
        "silence",
        "[silence]",
        "(silence)",
        "none",
        "null",
        "<noise>",
        "<silence>",
    }
)


def is_silence_or_noise(text: str) -> bool:
    """Returns True if the utterance is silence, noise, or a placeholder marker like '-'."""
    if not text:
        return True
    clean = text.strip()
    if clean.lower() in SILENCE_AND_NOISE_TOKENS:
        return True
    if clean.lower().startswith("<noise>") or clean.lower().startswith("<silence>"):
        return True
    stripped = re.sub(r"[\s\.\-_–—,;:!?~`'\"\[\]\(\)]", "", clean)
    if not stripped:
        return True
    return False


# Phrases signaling student's request to skip or change question
SKIP_REQUEST_PHRASES: frozenset[str] = frozenset(
    {
        "fai un'altra domanda",
        "fai un altra domanda",
        "cambia domanda",
        "cambiamo domanda",
        "passa alla prossima",
        "prossima domanda",
        "salta",
        "passa avanti",
        "cambia argomento",
        "non la so",
        "non lo so, passa",
        "un'altra domanda",
        "un altra domanda",
    }
)

# Patterns and phrases explicitly signaling student's request to pause or stop the session
EXPLICIT_PAUSE_PATTERNS: tuple[str, ...] = (
    r"\b(facciamo\s+una\s+)?pausa\b",
    r"\bfermiamoci(\s+qui)?\b",
    r"\bvoglio\s+(fermarmi|fare\s+una\s+pausa)\b",
    r"\bmettiamo\s+in\s+pausa\b",
    r"\b(possiamo\s+fare\s+una\s+)?pausa\b",
    r"\bsalva\s+e\s+(riprendiamo|continuiamo)\b",
    r"\briprendiamo\s+dopo\b",
    r"\bsospendiamo(\s+l['']esame)?\b",
    r"\bstop\s+(all['']esame|esame)\b",
    r"\bferma\s+(l['']esame|l\s+esame|tutto)\b",
)

EXPLICIT_PAUSE_COMMANDS: frozenset[str] = frozenset(
    {
        "pausa",
        "stop",
        "fermati",
        "facciamo una pausa",
        "fermiamoci qui",
        "ci fermiamo",
        "mettiamo in pausa",
        "sospendiamo",
        "salva e riprendiamo",
        "riprendiamo dopo",
        "voglio fermarmi",
        "ferma esame",
    }
)

# Words that indicate technical, algorithmic, or explanatory context where "stop" or "pausa" is NOT a pause command
TECHNICAL_NON_PAUSE_TERMS: frozenset[str] = frozenset(
    {
        "early",
        "stopping",
        "bootstrap",
        "criterio",
        "condizione",
        "regola",
        "algoritmo",
        "overfitting",
        "modello",
        "funzione",
        "pesi",
        "epoche",
        "loss",
        "gradiente",
        "discesa",
        "conduce",
        "convergenza",
    }
)


def is_explicit_pause_request(text: str) -> bool:
    """Determine whether an utterance is an explicit command to pause the examination."""
    clean = text.lower().strip()
    words = set(re.findall(r"\b\w+\b", clean))
    if not words:
        return False

    # If technical terms related to ML/algorithms are mentioned, this is an answer, not a pause command
    if TECHNICAL_NON_PAUSE_TERMS.intersection(words):
        return False

    # Exact short command
    if clean in EXPLICIT_PAUSE_COMMANDS:
        return True

    # If the student spoke a substantial answer (> 6 words), don't trigger pause
    if len(words) <= 6:
        for pat in EXPLICIT_PAUSE_PATTERNS:
            if re.search(pat, clean):
                return True

    return False


# Phrases signaling student's request to resume a paused session
RESUME_REQUEST_PHRASES: frozenset[str] = frozenset(
    {
        "riprendiamo",
        "continuiamo",
        "sono tornato",
        "ripartiamo",
        "riprendi",
        "continua da dove eravamo",
        "proseguiamo",
        "possiamo riprendere",
        "sono pronto a riprendere",
    }
)

# Phrases signaling student's request to repeat / retake the oral examination
REPEAT_REQUEST_PHRASES: frozenset[str] = frozenset(
    {
        "ripetiamo l'esame",
        "voglio ripetere",
        "ricominciamo l'esame",
        "nuovo tentativo",
        "rifacciamo l'interrogazione",
        "ricomincia da capo",
        "ripeti esame",
        "ripetiamo da capo",
        "rifare l'esame",
        "ripetere l'esame",
    }
)


class SessionAssessmentManager:
    """Manages the real-time and persistent state for an adaptive oral examination session."""

    def __init__(
        self,
        graph_store: BaseGraphStore,
        vector_store: BaseVectorStore,
        retriever: HybridRAGRetriever | None = None,
        bkt_engine: BayesianKnowledgeTracing | None = None,
        fsm_engine: OralExaminerFSM | None = None,
        evaluator: ResponseEvaluator | None = None,
        examination_plan: ExaminationPlan | None = None,
        student_id: str = "student_default",
        state_file_path: str | Path | None = None,
        events_file_path: str | Path | None = None,
        execution_mode: str = "local",
    ) -> None:
        self.graph_store = graph_store
        self.vector_store = vector_store
        self.retriever = retriever or HybridRAGRetriever(graph_store, vector_store)
        self.bkt = bkt_engine or BayesianKnowledgeTracing(graph_store)
        self.fsm = fsm_engine or OralExaminerFSM()
        self.evaluator = evaluator or ResponseEvaluator()
        self.examination_plan = examination_plan
        self.student_id = student_id
        self.state_file_path = Path(state_file_path) if state_file_path else None
        self.events_file_path = Path(events_file_path) if events_file_path else None
        self.execution_mode = execution_mode  # "console" | "local" | "cloud"
        self.events: list[dict[str, Any]] = []

        # Session tracking state
        self.status: SessionStatus = SessionStatus.ACTIVE
        self.current_iteration: int = 1
        self.iterations_history: list[dict[str, Any]] = []
        self.paused_concept_id: str | None = None
        self.current_concept_id: str | None = None
        self.current_pedagogical_state: PedagogicalState = PedagogicalState.EXPLORATION
        self.consecutive_failures: int = 0
        self.history: list[dict[str, Any]] = []
        self.last_turn_assessment: TurnAssessmentState | None = None
        self.last_ai_directive: str = ""
        self._last_context: ExaminerContext | None = None
        self._last_processed_transcript: str = ""
        self._last_processed_ts: float = 0.0
        self._turn_lock: asyncio.Lock | None = None
        self._all_concepts_cache: list[ConceptNode] | None = None

        if self.examination_plan and self.examination_plan.current_item:
            self.current_concept_id = self.examination_plan.current_item.concept_id

    def record_event(
        self, event_type: str, data: dict[str, Any] | None = None
    ) -> dict[str, Any]:
        """Records an auditable structured event across Console CLI, Local Server, or Cloud."""
        event = {
            "timestamp": datetime.now().isoformat(),
            "execution_mode": self.execution_mode,
            "student_id": self.student_id,
            "iteration": self.current_iteration,
            "concept_id": self.current_concept_id,
            "event_type": event_type,
            "data": data or {},
        }
        self.events.append(event)

        logger.info(
            "📌 [EVENT:%s][%s] (Concept: %s, Iteration: %d) %s",
            self.execution_mode.upper(),
            event_type,
            self.current_concept_id or "NONE",
            self.current_iteration,
            json.dumps(data or {}, ensure_ascii=False),
        )

        if self.events_file_path:
            try:
                self.events_file_path.parent.mkdir(parents=True, exist_ok=True)
                with open(self.events_file_path, "a", encoding="utf-8") as f:
                    f.write(json.dumps(event, ensure_ascii=False) + "\n")
            except Exception as err:
                logger.warning(
                    "Could not append to events log %s: %s",
                    self.events_file_path,
                    err,
                )

        return event

    def _get_lock(self) -> asyncio.Lock:
        """Lazily initialize the async lock within the running event loop."""
        if self._turn_lock is None:
            import asyncio

            self._turn_lock = asyncio.Lock()
        return self._turn_lock

    async def _get_all_concepts_cached(self) -> list[ConceptNode]:
        """Returns course concepts with in-memory caching to eliminate duplicate full graph scans."""
        if self._all_concepts_cache is None:
            self._all_concepts_cache = await self.graph_store.get_all_concepts()
        return self._all_concepts_cache

    def set_examination_plan(self, plan: ExaminationPlan) -> None:
        """Attach or update the examination plan."""
        self.examination_plan = plan
        if plan.current_item:
            self.current_concept_id = plan.current_item.concept_id
            if plan.current_item.status == PlanItemStatus.PENDING:
                plan.current_item.status = PlanItemStatus.IN_PROGRESS

    async def initialize_session(self) -> ExaminerContext:
        """Initializes the session by setting the active concept and context."""
        if self.examination_plan and self.examination_plan.current_item:
            self.current_concept_id = self.examination_plan.current_item.concept_id
            if self.examination_plan.current_item.status == PlanItemStatus.PENDING:
                self.examination_plan.current_item.status = PlanItemStatus.IN_PROGRESS
        else:
            entry_concept = await self.retriever.get_root_or_entry_concept()
            self.current_concept_id = (
                entry_concept.id if entry_concept else "general_introduction"
            )

        self.current_pedagogical_state = PedagogicalState.EXPLORATION
        self.consecutive_failures = 0

        context = await self.retriever.retrieve_context_for_concept(
            concept_id=self.current_concept_id,
            pedagogical_state=self.current_pedagogical_state,
        )

        self.record_event(
            "SESSION_INITIALIZED",
            {
                "entry_concept": self.current_concept_id,
                "plan_active": bool(self.examination_plan),
                "plan_progress": (
                    self.examination_plan.progress_percentage
                    if self.examination_plan
                    else 0.0
                ),
            },
        )
        return context

    async def process_student_turn(
        self,
        student_transcript: str,
        pause_duration: float = 0.0,
    ) -> tuple[ExaminerContext, TurnAssessmentState]:
        """Evaluates student's answer, updates BKT & plan state, and retrieves grounded context."""
        async with self._get_lock():
            clean_text = student_transcript.strip()
            if (clean_text.startswith("['") and clean_text.endswith("']")) or (
                clean_text.startswith('["') and clean_text.endswith('"]')
            ):
                clean_text = clean_text[2:-2].strip()

            # Ignore noise, empty utterances, or silence placeholders like '-' without advancing the exam or recording history
            if is_silence_or_noise(clean_text):
                logger.info("Ignoring silence/noise utterance ('%s') without recording turn", clean_text)
                if self._last_context and self.last_turn_assessment:
                    return self._last_context, self.last_turn_assessment
                if not self.current_concept_id:
                    init_ctx = await self.initialize_session()
                    return init_ctx, TurnAssessmentState(
                        assessed_concept_id=self.current_concept_id or "general",
                        evaluation_result=EvaluationResultType.HESITANT,
                    )
                current_concept = await self.graph_store.get_concept(self.current_concept_id)
                c_name = current_concept.name if current_concept else self.current_concept_id
                wait_ctx = ExaminerContext(
                    concept_id=self.current_concept_id,
                    concept_name=c_name,
                    pedagogical_state=self.current_pedagogical_state,
                    pedagogical_directive=self.last_ai_directive or f"Mi parli di {c_name}.",
                    ground_truth_chunks=[],
                    metadata={"silence": True},
                )
                return wait_ctx, TurnAssessmentState(
                    assessed_concept_id=self.current_concept_id,
                    evaluation_result=EvaluationResultType.HESITANT,
                )

            now_ts = time.time()
            # Deduplication: ignore identical transcript received within 2.0s debounce window
            if (
                clean_text.lower() == self._last_processed_transcript.lower()
                and (now_ts - self._last_processed_ts) < 2.0
                and self._last_context
                and self.last_turn_assessment
            ):
                logger.warning(
                    "Duplicate student turn ignored ('%s' received within %.2fs)",
                    clean_text,
                    now_ts - self._last_processed_ts,
                )
                return self._last_context, self.last_turn_assessment

            # 0. Early Intent Check (0ms): Pause, Resume, or Repeat Examination
            msg_lower = clean_text.lower().strip()

            if is_explicit_pause_request(clean_text):
                logger.info("Explicit pause request detected from student: '%s'", clean_text)
                return await self.pause_session()

            is_repeat_request = any(
                phrase in msg_lower for phrase in REPEAT_REQUEST_PHRASES
            )
            if is_repeat_request:
                return await self.restart_examination(adapt_from_previous=True)

            if self.status == SessionStatus.PAUSED:
                is_resume_request = any(
                    phrase in msg_lower for phrase in RESUME_REQUEST_PHRASES
                ) or bool(
                    set(re.findall(r"\w+", msg_lower)).intersection(
                        AFFIRMATIVE_READINESS_WORDS
                    )
                )
                if is_resume_request:
                    return await self.resume_session()

            if not self.current_concept_id:
                await self.initialize_session()

            concept_id = self.current_concept_id or "general_introduction"
            current_concept = await self.graph_store.get_concept(concept_id)
            if not current_concept:
                current_concept = ConceptNode(
                    id=concept_id,
                    name=concept_id.replace("_", " ").title(),
                    summary="Target topic.",
                )

            # Retrieve ontological neighborhood and ground-truth chunks concurrently in parallel
            (
                prereqs,
                causal_targets,
                contrasting,
                multi_hop,
                all_concepts,
                gt_chunks,
            ) = await asyncio.gather(
                self.graph_store.get_prerequisites(concept_id),
                self.graph_store.get_causal_targets(concept_id),
                self.graph_store.get_contrasting_concepts(concept_id),
                self.graph_store.get_multi_hop_neighbors(concept_id, max_hops=2),
                self._get_all_concepts_cached(),
                self.vector_store.search(
                    query=f"{current_concept.name} {current_concept.summary}",
                    limit=3,
                    concept_id_filter=current_concept.id,
                ),
            )

            # Check if student is confirming readiness (initial opening Turn 0 or session resumption)
            words = set(re.findall(r"\w+", msg_lower))
            is_initial_turn = len(self.history) == 0
            is_last_turn_resumption = bool(
                self.history
                and (
                    self.history[-1].get("evaluation") in ("RESUMED", "READINESS_CONFIRMED")
                    or "[session_resumed]" in str(self.history[-1].get("transcript", "")).lower()
                )
            )
            is_ai_asking_readiness = bool(
                self.last_ai_directive
                and ("pronto" in self.last_ai_directive.lower() or "iniziamo" in self.last_ai_directive.lower())
            )

            is_affirmative_readiness = (
                len(words) <= 6
                and bool(words.intersection(AFFIRMATIVE_READINESS_WORDS))
                and (is_initial_turn or is_last_turn_resumption or is_ai_asking_readiness)
            )
            is_explicit_resume_cmd = (
                clean_text.lower() in RESUME_REQUEST_PHRASES
                or any(phrase in msg_lower for phrase in RESUME_REQUEST_PHRASES)
            )

            if is_affirmative_readiness or is_explicit_resume_cmd:
                curr_item = (
                    self.examination_plan.items.get(concept_id)
                    if self.examination_plan and concept_id in self.examination_plan.items
                    else (self.examination_plan.current_item if self.examination_plan else None)
                )
                curr_q = (
                    curr_item.planned_question.main_question
                    if curr_item and hasattr(curr_item, "planned_question") and hasattr(curr_item.planned_question, "main_question")
                    else f"Mi parli dei concetti fondamentali relativi a {current_concept.name}."
                )
                spoken_directive = (
                    f"Perfetto, iniziamo subito! {curr_q}"
                    if is_initial_turn
                    else f"Perfetto, riprendiamo! {curr_q}"
                )

                new_context = ExaminerContext(
                    current_concept=current_concept,
                    pedagogical_state=PedagogicalState.EXPLORATION,
                    ground_truth_chunks=gt_chunks,
                    prerequisites=prereqs,
                    causal_targets=causal_targets,
                    contrasting_concepts=contrasting,
                    multi_hop_concepts=multi_hop,
                    all_graph_concepts=all_concepts,
                    pedagogical_directive=spoken_directive,
                )
                turn_assessment = TurnAssessmentState(
                    assessed_concept_id=concept_id,
                    evaluation_result=EvaluationResultType.ACCURATE,
                    mastery_delta=0.0,
                    next_target_node=concept_id,
                    graph_relation_followed="PLAN_START" if is_initial_turn else "PLAN_RESUME",
                    uncertainty_signals={
                        "pause_duration": pause_duration,
                        "filler_words": 0,
                    },
                )

                if config.verbose_requests:
                    logger.info(
                        "\n"
                        + "═" * 70
                        + "\n"
                        + f"🚀 [STUDENT CONFIRMED READINESS ({'INITIAL' if is_initial_turn else 'RESUMPTION'}) -> LAUNCHING QUESTION]\n"
                        + f"   • Concept: {concept_id} ({current_concept.name})\n"
                        + f'   • Spoken Question: "{spoken_directive}"\n'
                        + "═" * 70
                    )

                self.history.append(
                    {
                        "turn": len(self.history) + 1,
                        "concept_id": concept_id,
                        "concept_name": current_concept.name,
                        "transcript": clean_text,
                        "student_transcript": clean_text,
                        "student_response": clean_text,
                        "ai_question": f"Sei pronto a iniziare l'esame su {current_concept.name}?",
                        "evaluation": "READINESS_CONFIRMED",
                        "directive": spoken_directive,
                    }
                )
                self.record_event(
                    "STUDENT_READINESS_CONFIRMED",
                    {
                        "student_transcript": clean_text,
                        "first_planned_concept": concept_id,
                        "spoken_question": spoken_directive,
                    },
                )
                self.last_ai_directive = spoken_directive
                self._last_processed_transcript = clean_text
                self._last_processed_ts = now_ts
                self._last_context = new_context
                self.last_turn_assessment = turn_assessment
                return new_context, turn_assessment

            # 1. Evaluate student's response
            eval_detail: EvaluationDetail = self.evaluator.evaluate_response(
                student_response=clean_text,
                target_concept=current_concept,
                ground_truth=gt_chunks,
                contrasting_concepts=contrasting,
                pause_duration=pause_duration,
            )

        # 2. Bayesian Knowledge Tracing & Graph Mastery Update
        _, mastery_delta = await self.bkt.update_concept_mastery(
            concept_id=concept_id,
            evaluation=eval_detail.evaluation_result,
        )

        # 3. Decision Logic: Plan-driven OR FSM-driven
        plan_item = (
            self.examination_plan.items.get(concept_id)
            if self.examination_plan
            else None
        )

        is_skip_request = any(phrase in msg_lower for phrase in SKIP_REQUEST_PHRASES)

        if is_skip_request and plan_item:
            self.examination_plan.defer_concept(concept_id)
            next_item = self.examination_plan.advance_to_next()
            if next_item:
                next_concept_id = next_item.concept_id
                next_state = PedagogicalState.EXPLORATION
                relation_followed = "PLAN_SKIP_NEXT"
                spoken_directive = f"Nessun problema, passiamo ad un altro argomento. {next_item.planned_question.main_question}"
            else:
                next_concept_id = concept_id
                next_state = PedagogicalState.SYNTHESIS
                relation_followed = "PLAN_COMPLETED"
                spoken_directive = "Abbiamo completato tutti gli argomenti previsti nel piano d'esame. Ottimo lavoro!"
        elif plan_item:
            plan_item.current_attempt += 1
            plan_item.attempts_log.append(
                {
                    "attempt": plan_item.current_attempt,
                    "response": student_transcript,
                    "evaluation": eval_detail.evaluation_result.value,
                    "reasoning": eval_detail.reasoning,
                }
            )

            is_success = eval_detail.evaluation_result in (
                EvaluationResultType.ACCURATE,
                EvaluationResultType.MEMORIZED,
            )
            max_attempts = plan_item.planned_question.max_attempts

            if is_success:
                plan_item.status = PlanItemStatus.MASTERED
                self.consecutive_failures = 0

                # Check if any deferred concept is ready for spaced-repetition retry
                ready_deferred_id = self.examination_plan.on_correct_answer()
                if ready_deferred_id and self.examination_plan.items.get(
                    ready_deferred_id
                ):
                    next_concept_id = ready_deferred_id
                    next_state = PedagogicalState.SCAFFOLDING
                    relation_followed = "PLAN_DEFERRED_RETRY"
                else:
                    next_item = self.examination_plan.advance_to_next()
                    if next_item:
                        next_concept_id = next_item.concept_id
                        next_state = PedagogicalState.EXPLORATION
                        relation_followed = "PLAN_NEXT"
                    else:
                        next_concept_id = concept_id
                        next_state = PedagogicalState.EXPLORATION
                        relation_followed = "PLAN_COMPLETED"
            else:
                self.consecutive_failures += 1
                if plan_item.current_attempt < max_attempts:
                    # Deliver targeted scaffolding / narrowing without advancing
                    next_concept_id = concept_id
                    if eval_detail.evaluation_result == EvaluationResultType.VAGUE:
                        next_state = PedagogicalState.CAUSAL_NARROWING
                        relation_followed = "PLAN_NARROWING"
                    elif (
                        eval_detail.evaluation_result
                        == EvaluationResultType.MISCONCEPTION
                    ):
                        next_state = PedagogicalState.CONCEPTUAL_COLLISION
                        relation_followed = "PLAN_COLLISION"
                    else:
                        next_state = PedagogicalState.SCAFFOLDING
                        relation_followed = "PLAN_SCAFFOLD"
                else:
                    # Max attempts reached on this concept: Defer to cyclic queue and switch to a different question
                    self.examination_plan.defer_concept(
                        concept_id=concept_id, required_correct_answers=2
                    )
                    next_item = self.examination_plan.advance_to_next()
                    if next_item:
                        next_concept_id = next_item.concept_id
                        next_state = PedagogicalState.EXPLORATION
                        relation_followed = "PLAN_NEXT_AFTER_FAIL"
                    else:
                        next_concept_id = concept_id
                        next_state = PedagogicalState.EXPLORATION
                        relation_followed = "PLAN_COMPLETED"
        else:
            # Fallback to dynamic FSM
            if eval_detail.evaluation_result in (
                EvaluationResultType.HESITANT,
                EvaluationResultType.VAGUE,
                EvaluationResultType.MISCONCEPTION,
            ):
                self.consecutive_failures += 1
            else:
                self.consecutive_failures = 0

            next_state, next_concept_id, relation_followed = (
                self.fsm.determine_next_transition(
                    current_concept=current_concept,
                    evaluation=eval_detail.evaluation_result,
                    consecutive_failures=self.consecutive_failures,
                    prerequisites=prereqs,
                    causal_targets=causal_targets,
                    contrasting_concepts=contrasting,
                    multi_hop_neighbors=multi_hop,
                    all_concepts=all_concepts,
                )
            )

        # 4. Build structured internal state
        turn_assessment = TurnAssessmentState(
            assessed_concept_id=concept_id,
            evaluation_result=eval_detail.evaluation_result,
            mastery_delta=round(mastery_delta, 4),
            next_target_node=next_concept_id,
            graph_relation_followed=relation_followed,
        )
        self.last_turn_assessment = turn_assessment

        now_iso = datetime.now().isoformat()
        current_ai_question = self.last_ai_directive or (
            plan_item.planned_question.main_question
            if plan_item
            else f"Mi parli di {current_concept.name}."
        )

        # 5. Record full conversation turn history
        self.history.append(
            {
                "turn": len(self.history) + 1,
                "timestamp": now_iso,
                "iteration": self.current_iteration,
                "concept_id": concept_id,
                "concept_name": current_concept.name,
                "ai_question": current_ai_question,
                "student_transcript": student_transcript,
                "student_response": student_transcript,
                "evaluated_concept": concept_id,
                "evaluation_result": eval_detail.evaluation_result.value,
                "evaluation": eval_detail.evaluation_result.value,
                "confidence": eval_detail.confidence,
                "reasoning": eval_detail.reasoning,
                "missing_concepts": eval_detail.missing_concepts,
                "mastery_delta": mastery_delta,
                "next_concept": next_concept_id,
                "next_concept_id": next_concept_id,
                "next_state": next_state.value,
                "pedagogical_state": next_state.value,
                "relation_followed": relation_followed,
                "plan_progress": (
                    self.examination_plan.progress_percentage
                    if self.examination_plan
                    else None
                ),
            }
        )

        self.current_concept_id = next_concept_id
        self.current_pedagogical_state = next_state

        # 6. Retrieve next context
        new_context = await self.retriever.retrieve_context_for_concept(
            concept_id=next_concept_id,
            pedagogical_state=next_state,
            evaluation_detail=eval_detail,
        )

        # Inject planned questions if available
        if (
            self.examination_plan
            and self.examination_plan.items.get(next_concept_id)
            and relation_followed.startswith("PLAN_")
        ):
            target_plan_item = self.examination_plan.items[next_concept_id]
            q_spec = target_plan_item.planned_question
            if relation_followed in ("PLAN_SCAFFOLD", "PLAN_NARROWING"):
                if eval_detail.covered_aspects:
                    covered_str = ", ".join(eval_detail.covered_aspects[:3])
                    uncovered_str = (
                        ", ".join(eval_detail.uncovered_aspects[:3])
                        if eval_detail.uncovered_aspects
                        else "il funzionamento dettagliato"
                    )
                    new_context.pedagogical_directive = (
                        f"Lo studente ha accennato parzialmente a: '{covered_str}', ma mancano aspetti chiave su: '{uncovered_str}'. "
                        f"Riconosci con garbo ciò che ha detto (es. 'Esatto, hai accennato a {covered_str}...') "
                        f"e fagli una domanda guida mirata per aiutarlo a spiegare '{uncovered_str}' in relazione a {target_plan_item.concept_name}."
                    )
                elif (
                    relation_followed == "PLAN_NARROWING" and q_spec.narrowing_questions
                ):
                    narrow_idx = max(0, target_plan_item.current_attempt - 1) % len(q_spec.narrowing_questions)
                    new_context.pedagogical_directive = q_spec.narrowing_questions[narrow_idx]
                elif q_spec.scaffolding_hints:
                    hint_idx = max(0, target_plan_item.current_attempt - 1) % len(q_spec.scaffolding_hints)
                    new_context.pedagogical_directive = (
                        f"Prova a riflettere su questo indizio: {q_spec.scaffolding_hints[hint_idx]}"
                    )
                else:
                    new_context.pedagogical_directive = f"Prova a partire dalla definizione di base di {target_plan_item.concept_name}."
            elif (
                relation_followed == "PLAN_COLLISION"
                and q_spec.collision_check_questions
            ):
                coll_idx = max(0, target_plan_item.current_attempt - 1) % len(q_spec.collision_check_questions)
                new_context.pedagogical_directive = q_spec.collision_check_questions[coll_idx]
            elif relation_followed == "PLAN_DEFERRED_RETRY":
                retry_hint = (
                    q_spec.scaffolding_hints[0]
                    if q_spec.scaffolding_hints
                    else q_spec.main_question
                )
                new_context.pedagogical_directive = f"Molto bene! Ora che abbiamo chiarito questi aspetti, torniamo un attimo indietro su {target_plan_item.concept_name}: {retry_hint}"
            elif relation_followed == "PLAN_NEXT":
                new_context.pedagogical_directive = (
                    f"Molto bene. {q_spec.main_question}"
                )
            elif relation_followed == "PLAN_NEXT_AFTER_FAIL":
                new_context.pedagogical_directive = f"Nessun problema, lasciamo da parte questo argomento per ora. Passiamo ad altro: {q_spec.main_question}"
            elif relation_followed == "PLAN_COMPLETED":
                new_context.pedagogical_directive = "Abbiamo completato tutti gli argomenti previsti nel piano d'esame. Ottimo lavoro!"

        # Anti-repetition guard: prevent saying the exact same sentence two turns in a row
        if (
            self.last_ai_directive
            and new_context.pedagogical_directive.strip().lower()
            == self.last_ai_directive.strip().lower()
        ):
            c_label = current_concept.name if current_concept else concept_id
            logger.info("Consecutive identical directive detected. Varying prompt for %s", c_label)
            new_context.pedagogical_directive = (
                f"Per aiutarti ad approfondire {c_label}, prova a farmi un esempio concreto o spiegami la sua utilità applicativa."
            )

        plan_info = ""
        if self.examination_plan:
            total_items = len(self.examination_plan.concept_order)
            curr_idx = self.examination_plan.current_index + 1
            curr_item = self.examination_plan.items.get(concept_id)
            status_str = curr_item.status.value if curr_item else "IN_PROGRESS"
            deferred_ids = [d.concept_id for d in self.examination_plan.deferred_queue]
            plan_info = (
                f"📋 [PIANO D'ESAME & VERIFICA PROGRESSO]\n"
                f"   • Passo Attivo: [{curr_idx}/{total_items}] - {concept_id} ({current_concept.name})\n"
                f"   • Stato Concetto: {status_str} | Progresso Totale: {self.examination_plan.progress_percentage}%\n"
                f"   • Coda di Rinvio Ciclica: {deferred_ids if deferred_ids else 'Nessun argomento in sospeso'}\n\n"
            )

        if config.verbose_requests:
            logger.info(
                "\n"
                + "═" * 70
                + "\n"
                + plan_info
                + "📥 [STUDENT TRANSCRIPT RECEIVED]\n"
                + f'   • Text: "{student_transcript}"\n'
                + f"   • Pause Duration: {pause_duration:.2f}s | Fillers: {eval_detail.filler_word_count}\n\n"
                + "🧠 [EVALUATION & UNCERTAINTY]\n"
                + f"   • Assessed Concept: {concept_id} ({current_concept.name})\n"
                + f"   • Result: {eval_detail.evaluation_result.value} (Confidence: {eval_detail.confidence * 100:.0f}%)\n"
                + f"   • Reasoning: {eval_detail.reasoning}\n"
                + f"   • Missing Concepts: {eval_detail.missing_concepts}\n\n"
                + "📊 [KNOWLEDGE TRACING & MASTERY DELTA]\n"
                + f"   • Mastery Delta: {mastery_delta:+.2f}\n"
                + f"   • Next Pedagogical State: {next_state.value}\n"
                + f"   • Relation / Action: {relation_followed}\n"
                + f"   • Next Target Concept: {next_concept_id}\n\n"
                + "📤 [DIRECTIVE & PROMPT FOR EXAMINER]\n"
                + f"   • Spoken Directive: {new_context.pedagogical_directive}\n"
                + "═" * 70
            )
        else:
            logger.info(
                "Turn processed: Concept=%s, Result=%s, Next=%s (%s via %s)",
                concept_id,
                eval_detail.evaluation_result.value,
                next_concept_id,
                next_state.value,
                relation_followed,
            )

        self.last_ai_directive = new_context.pedagogical_directive
        self._last_processed_transcript = clean_text
        self._last_processed_ts = now_ts
        self._last_context = new_context
        self.last_turn_assessment = turn_assessment

        self.record_event(
            "TURN_EVALUATED",
            {
                "turn": len(self.history),
                "assessed_concept": concept_id,
                "student_transcript": clean_text,
                "evaluation_result": eval_detail.evaluation_result.value,
                "confidence": eval_detail.confidence,
                "reasoning": eval_detail.reasoning,
                "mastery_delta": round(mastery_delta, 4),
                "next_concept": next_concept_id,
                "next_pedagogical_state": next_state.value,
                "relation_followed": relation_followed,
                "spoken_directive": new_context.pedagogical_directive,
            },
        )

        # Offload disk persistence to background worker thread so the voice reply is returned immediately
        snapshot = self.to_dict()
        try:
            loop = asyncio.get_running_loop()
            loop.create_task(
                asyncio.to_thread(
                    self.save_session_state, self.state_file_path, snapshot
                )
            )
        except RuntimeError:
            self.save_session_state(self.state_file_path, snapshot)

        return new_context, turn_assessment

    async def pause_session(
        self, reason: str = ""
    ) -> tuple[ExaminerContext, TurnAssessmentState]:
        """Pauses the oral examination and persists current state to disk."""
        self.status = SessionStatus.PAUSED
        concept_id = self.current_concept_id or "general_introduction"
        current_concept = await self.graph_store.get_concept(concept_id)
        concept_name = current_concept.name if current_concept else concept_id

        spoken_directive = (
            f"Certamente! Ho messo in pausa l'esame e salvato i tuoi progressi al concetto '{concept_name}'. "
            "Quando vorrai riprendere, basterà dirmelo e ripartiremo esattamente da qui. A presto!"
        )

        turn_assessment = TurnAssessmentState(
            assessed_concept_id=concept_id,
            evaluation_result=EvaluationResultType.ACCURATE,
            mastery_delta=0.0,
            next_target_node=concept_id,
            graph_relation_followed="SESSION_PAUSE",
        )

        new_context = ExaminerContext(
            current_concept=current_concept
            or ConceptNode(id=concept_id, name=concept_name),
            pedagogical_state=self.current_pedagogical_state,
            pedagogical_directive=spoken_directive,
        )

        self.history.append(
            {
                "turn": len(self.history) + 1,
                "concept_id": concept_id,
                "transcript": "[SESSION_PAUSED]",
                "evaluation": "PAUSED",
                "directive": spoken_directive,
            }
        )

        self.record_event(
            "SESSION_PAUSED",
            {
                "paused_concept_id": concept_id,
                "reason": reason,
                "spoken_directive": spoken_directive,
            },
        )

        self.save_session_state(self.state_file_path)
        self._last_context = new_context
        self.last_turn_assessment = turn_assessment
        logger.info(
            "Session PAUSED at concept %s (Iteration %d)",
            concept_id,
            self.current_iteration,
        )
        return new_context, turn_assessment

    async def resume_session(
        self,
    ) -> tuple[ExaminerContext, TurnAssessmentState]:
        """Resumes a paused examination session from the exact concept and planned question."""
        self.status = SessionStatus.ACTIVE
        concept_id = self.current_concept_id or "general_introduction"
        current_concept = await self.graph_store.get_concept(concept_id)
        if not current_concept:
            current_concept = ConceptNode(
                id=concept_id,
                name=concept_id.replace("_", " ").title(),
                summary="Target topic.",
            )

        # Retrieve active question from plan if available
        plan_item = (
            self.examination_plan.items.get(concept_id)
            if self.examination_plan
            else None
        )
        if plan_item:
            q_text = plan_item.planned_question.main_question
        else:
            q_text = f"Riprendiamo da dove eravamo rimasti: mi parli dei concetti di {current_concept.name}."

        spoken_directive = (
            f"Bentornato! Riprendiamo l'esame esattamente da dove eravamo rimasti. "
            f"Stavamo affrontando '{current_concept.name}': {q_text}"
        )

        new_context = await self.retriever.retrieve_context_for_concept(
            concept_id=concept_id,
            pedagogical_state=self.current_pedagogical_state,
        )
        new_context.pedagogical_directive = spoken_directive

        turn_assessment = TurnAssessmentState(
            assessed_concept_id=concept_id,
            evaluation_result=EvaluationResultType.ACCURATE,
            mastery_delta=0.0,
            next_target_node=concept_id,
            graph_relation_followed="SESSION_RESUME",
        )

        self.history.append(
            {
                "turn": len(self.history) + 1,
                "concept_id": concept_id,
                "transcript": "[SESSION_RESUMED]",
                "evaluation": "RESUMED",
                "directive": spoken_directive,
            }
        )

        self.record_event(
            "SESSION_RESUMED",
            {
                "resumed_concept_id": concept_id,
                "spoken_directive": spoken_directive,
            },
        )

        self.save_session_state(self.state_file_path)
        self._last_context = new_context
        self.last_turn_assessment = turn_assessment
        logger.info(
            "Session RESUMED at concept %s (Iteration %d)",
            concept_id,
            self.current_iteration,
        )
        return new_context, turn_assessment

    async def restart_examination(
        self, adapt_from_previous: bool = True
    ) -> tuple[ExaminerContext, TurnAssessmentState]:
        """Restarts the oral examination for a new iteration, dynamically adapting to previous performance."""
        # 1. Archive current iteration (conservata nello storico anche se self.history non ha scambi)
        had_exchanges = bool(self.history and len(self.history) > 0)
        previous_turns = list(self.history)

        all_concepts = await self.graph_store.get_all_concepts()
        avg_m = (
            sum(c.mastery_score for c in all_concepts) / len(all_concepts)
            if all_concepts and had_exchanges
            else 0.0
        )
        mastered = (
            [c.name for c in all_concepts if c.mastery_score >= 0.80]
            if had_exchanges
            else []
        )
        weak = (
            [
                c.name
                for c in all_concepts
                if c.mastery_score < 0.45 or c.mistake_count > 0
            ]
            if had_exchanges
            else []
        )

        plan_title = (
            self.examination_plan.title
            if self.examination_plan
            else f"Discussione #{self.current_iteration}"
        )
        plan_concepts = []
        if self.examination_plan:
            for cid in self.examination_plan.concept_order:
                if cid in self.examination_plan.items:
                    it_obj = self.examination_plan.items[cid]
                    plan_concepts.append(
                        {
                            "concept_id": cid,
                            "concept_name": it_obj.concept_name,
                            "difficulty": getattr(it_obj, "difficulty", 1.0),
                            "main_question": (
                                it_obj.planned_question.main_question
                                if hasattr(it_obj, "planned_question")
                                and hasattr(it_obj.planned_question, "main_question")
                                else ""
                            ),
                        }
                    )

        last_ts = (
            previous_turns[-1].get("timestamp", datetime.now().isoformat())
            if previous_turns
            else datetime.now().isoformat()
        )

        self.iterations_history.append(
            {
                "iteration": self.current_iteration,
                "title": plan_title,
                "plan_title": plan_title,
                "concepts": plan_concepts,
                "average_mastery": round(avg_m, 2),
                "mastered_concepts": mastered,
                "weak_concepts": weak,
                "history": previous_turns,
                "timestamp": last_ts,
            }
        )
        self.current_iteration += 1

        # 2. Reset active conversation state and knowledge graph mastery for a clean discussion
        self.status = SessionStatus.ACTIVE
        self.history = []
        self.consecutive_failures = 0
        self.current_pedagogical_state = PedagogicalState.EXPLORATION

        # Reset concept mastery in knowledge graph to default baseline so each discussion starts fresh
        for c in all_concepts:
            try:
                await self.graph_store.update_mastery(
                    concept_id=c.id,
                    mastery_score=0.10,
                    hesitation_delta=0,
                    mistake_delta=0,
                )
            except Exception as err:
                logger.warning("Could not reset concept mastery for %s: %s", c.id, err)

        # 3. Dynamic Plan Adaptation: Reset items and adjust questions/priority based on weaknesses
        if self.examination_plan:
            for item in self.examination_plan.items.values():
                item.status = PlanItemStatus.PENDING
                item.current_attempt = 0

            # If adapting, prioritize concepts that were weak or had mistakes
            if adapt_from_previous and weak:
                weak_cids = [
                    c.id
                    for c in all_concepts
                    if c.mastery_score < 0.45 or c.mistake_count > 0
                ]
                for cid in weak_cids:
                    if cid in self.examination_plan.items:
                        item = self.examination_plan.items[cid]
                        if item.planned_question.narrowing_questions:
                            item.planned_question.main_question = (
                                f"Nel precedente tentativo abbiamo notato qualche dubbio su {item.concept_name}. "
                                f"{item.planned_question.narrowing_questions[0]}"
                            )

            self.examination_plan.current_index = 0
            self.examination_plan.deferred_queue = []
            self.examination_plan.is_completed = False
            if self.examination_plan.concept_order:
                self.current_concept_id = self.examination_plan.concept_order[0]
                if self.examination_plan.current_item:
                    self.examination_plan.current_item.status = (
                        PlanItemStatus.IN_PROGRESS
                    )

        first_item = (
            self.examination_plan.current_item if self.examination_plan else None
        )
        first_q = (
            first_item.planned_question.main_question
            if first_item
            else "Mi parli dei concetti fondamentali del corso."
        )

        # 4. Spoken Directive personalizzata:
        # Se c'erano stati scambi, saluta con bentornato e recap degli argomenti.
        # Se non ci sono stati scambi, inizia da zero come conversazione ex novo.
        if adapt_from_previous and had_exchanges:
            unique_topics = list(
                dict.fromkeys(
                    t.get("concept_name") or t.get("concept_id", "")
                    for t in previous_turns
                    if t.get("concept_name") or t.get("concept_id")
                )
            )[:2]
            topics_clause = (
                f" affrontato {', '.join(unique_topics)}"
                if unique_topics
                else " iniziato il programma d'esame"
            )
            iter_label = (
                f" (Iterazione {self.current_iteration})"
                if self.current_iteration > 1
                else ""
            )
            spoken_directive = (
                f"Bentornato alla simulazione di {plan_title}{iter_label}! "
                f"La scorsa volta abbiamo{topics_clause}. Sei pronto a continuare? {first_q}"
            )
        else:
            spoken_directive = (
                f"Buongiorno! Benvenuto alla simulazione di {plan_title}. "
                "Iniziamo con il primo argomento del documento. Sei pronto?"
            )

        concept_id = self.current_concept_id or "general_introduction"

        new_context = await self.retriever.retrieve_context_for_concept(
            concept_id=concept_id,
            pedagogical_state=self.current_pedagogical_state,
        )
        new_context.pedagogical_directive = spoken_directive

        turn_assessment = TurnAssessmentState(
            assessed_concept_id=concept_id,
            evaluation_result=EvaluationResultType.ACCURATE,
            mastery_delta=0.0,
            next_target_node=concept_id,
            graph_relation_followed="SESSION_RESTART",
        )

        self.record_event(
            "SESSION_RESTARTED",
            {
                "new_iteration": self.current_iteration,
                "first_concept_id": self.current_concept_id,
                "weak_concepts": weak,
                "spoken_directive": spoken_directive,
            },
        )

        self.save_session_state(self.state_file_path)
        self._last_context = new_context
        self.last_turn_assessment = turn_assessment
        logger.info(
            "Session RESTARTED (New Iteration %d) with %d archived previous iterations.",
            self.current_iteration,
            len(self.iterations_history),
        )
        return new_context, turn_assessment

    def to_dict(self) -> dict[str, Any]:
        """Serialize session state for persistence and resumption."""
        return {
            "student_id": self.student_id,
            "execution_mode": self.execution_mode,
            "status": self.status.value,
            "current_iteration": self.current_iteration,
            "paused_concept_id": self.paused_concept_id,
            "current_concept_id": self.current_concept_id,
            "current_pedagogical_state": self.current_pedagogical_state.value,
            "consecutive_failures": self.consecutive_failures,
            "history": self.history,
            "iterations_history": self.iterations_history,
            "events": self.events[-100:],
            "examination_plan": (
                self.examination_plan.model_dump() if self.examination_plan else None
            ),
        }

    def save_session_state(
        self,
        file_path: str | Path | None = None,
        snapshot_dict: dict[str, Any] | None = None,
    ) -> None:
        """Persist session state to a JSON file. If file_path is None, operates in-memory."""
        target_path = Path(file_path) if file_path else self.state_file_path
        if target_path is None:
            return
        data = snapshot_dict if snapshot_dict is not None else self.to_dict()
        target_path.parent.mkdir(parents=True, exist_ok=True)
        target_path.write_text(json.dumps(data, indent=2), encoding="utf-8")
        logger.info("Saved session assessment state to %s", target_path)

        # Synchronize with CourseManager to keep course-scoped state and sessions directory updated
        try:
            from assessment.courses import CourseManager

            CourseManager.sync_from_manager(self, snapshot_dict=data)
        except Exception as sync_err:
            logger.debug("CourseManager sync skipped/failed: %s", sync_err)

    def load_session_state(self, file_path: str | Path) -> None:
        """Restore session state from a JSON file."""
        path = Path(file_path)
        if not path.exists():
            raise FileNotFoundError(f"State file not found at: {path}")
        data = json.loads(path.read_text(encoding="utf-8"))
        self.student_id = data.get("student_id", self.student_id)
        self.execution_mode = data.get("execution_mode", self.execution_mode)
        self.status = SessionStatus(data.get("status", "ACTIVE"))
        self.current_iteration = data.get("current_iteration", 1)
        self.paused_concept_id = data.get("paused_concept_id")
        self.current_concept_id = data.get("current_concept_id")
        state_val = data.get("current_pedagogical_state", "EXPLORATION")
        self.current_pedagogical_state = PedagogicalState(state_val)
        self.consecutive_failures = data.get("consecutive_failures", 0)
        self.history = data.get("history", [])
        self.iterations_history = data.get("iterations_history", [])
        self.events = data.get("events", [])
        if data.get("examination_plan"):
            self.examination_plan = ExaminationPlan.model_validate(
                data["examination_plan"]
            )
        logger.info(
            "Restored session assessment state from %s (Iteration %d, Status %s, Mode %s)",
            path,
            self.current_iteration,
            self.status.value,
            self.execution_mode,
        )
