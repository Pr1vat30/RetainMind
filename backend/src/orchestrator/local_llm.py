"""Local zero-quota LLM provider orchestrating pedagogical examination turns.

Executes student turn assessment directly through SessionAssessmentManager and streams
prepared pedagogical spoken directives to the Pipecat voice synthesizer.
"""

from __future__ import annotations

import logging
import re
from typing import Any

from pipecat.frames.frames import (
    Frame,
    LLMContextFrame,
    LLMFullResponseEndFrame,
    LLMFullResponseStartFrame,
    LLMTextFrame,
)
from pipecat.processors.frame_processor import FrameDirection, FrameProcessor

from assessment.state import SessionAssessmentManager

logger = logging.getLogger("orchestrator.local_llm")


def _concise_reference(context: Any) -> str:
    """Extract a short course-grounded explanation for clarification in local mode."""
    reference = (
        getattr(context, "ideal_answer", "")
        or getattr(context.current_concept, "summary", "")
        or next((chunk.text for chunk in context.ground_truth_chunks if chunk.text), "")
    )
    sentences = re.split(r"(?<=[.!?])\s+", reference.strip())
    concise = " ".join(sentences[:2]).strip()
    if len(concise) > 360:
        concise = concise[:357].rsplit(" ", 1)[0] + "…"
    return concise


def _extract_text(content: Any) -> str:
    """Safely extracts plain text from varied ChatContent representations."""
    if not content:
        return ""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, str):
                parts.append(item)
            elif hasattr(item, "text"):
                parts.append(str(item.text))
            elif isinstance(item, dict) and "text" in item:
                parts.append(str(item["text"]))
        return " ".join(parts).strip()
    return str(content).strip()


class LocalOrchestratedLLMService(FrameProcessor):
    """Local, quota-free LLM processor that executes pedagogical evaluation logic

    and delivers prepared prompts directly into the Pipecat pipeline (TTS).
    """

    def __init__(self, assessment_manager: SessionAssessmentManager) -> None:
        super().__init__()
        self.assessment_manager = assessment_manager

    async def process_frame(self, frame: Frame, direction: FrameDirection) -> None:
        await super().process_frame(frame, direction)

        if isinstance(frame, LLMContextFrame):
            # Extract last user message from LLMContext
            context = frame.context
            last_student_msg = ""
            if hasattr(context, "messages") and context.messages:
                for msg in context.messages:
                    role = getattr(msg, "role", None) or (
                        msg.get("role") if isinstance(msg, dict) else None
                    )
                    content = getattr(msg, "content", "") or (
                        msg.get("content", "") if isinstance(msg, dict) else ""
                    )
                    text = _extract_text(content)
                    if role in ("user", "student") and text:
                        last_student_msg = text

            if not last_student_msg:
                spoken_text = "Dimmi pure, ti ascolto."
            else:
                (
                    examiner_ctx,
                    turn_state,
                ) = await self.assessment_manager.process_student_turn(
                    student_transcript=last_student_msg
                )
                if turn_state.graph_relation_followed == "SESSION_TOPIC_CLARIFICATION":
                    explanation = _concise_reference(examiner_ctx)
                    plan = self.assessment_manager.examination_plan
                    plan_item = (
                        plan.items.get(turn_state.assessed_concept_id) if plan else None
                    )
                    question = (
                        plan_item.planned_question.main_question
                        if plan_item
                        else f"Mi parli di {examiner_ctx.concept_name}."
                    )
                    spoken_text = (
                        f"Certo. {explanation} Ora riprendiamo: {question}"
                        if explanation
                        else f"Certo, restiamo sul materiale del corso. {question}"
                    )
                else:
                    spoken_text = examiner_ctx.pedagogical_directive or (
                        f"Continuiamo con l'argomento {examiner_ctx.current_concept.name}."
                    )

            logger.info(
                "LocalOrchestratedLLMService: Delivering spoken text: %s", spoken_text
            )

            await self.push_frame(LLMFullResponseStartFrame())
            await self.push_frame(LLMTextFrame(spoken_text))
            await self.push_frame(LLMFullResponseEndFrame())
        else:
            await self.push_frame(frame, direction)


# Backward compatibility alias
LocalOrchestratedLLM = LocalOrchestratedLLMService
