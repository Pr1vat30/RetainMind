"""Local zero-quota LLM provider orchestrating pedagogical examination turns.

Executes student turn assessment directly through SessionAssessmentManager and streams
prepared pedagogical spoken directives to the LiveKit voice synthesizer.
"""

from __future__ import annotations

import logging
import uuid
from typing import Any

from livekit.agents import llm
from livekit.agents.llm.chat_context import ChatContext
from livekit.agents.llm.llm import ChatChunk, ChoiceDelta, LLMStream
from livekit.agents.llm.tool_context import Tool
from livekit.agents.types import DEFAULT_API_CONNECT_OPTIONS, APIConnectOptions

from assessment.state import SessionAssessmentManager

logger = logging.getLogger("orchestrator.local_llm")


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


class LocalOrchestratedLLMStream(LLMStream):
    """Executes the examination turn locally and streams the prepared spoken prompt directly."""

    def __init__(
        self,
        llm_instance: LocalOrchestratedLLM,
        *,
        chat_ctx: ChatContext,
        tools: list[Tool],
        conn_options: APIConnectOptions,
    ) -> None:
        super().__init__(
            llm_instance,
            chat_ctx=chat_ctx,
            tools=tools,
            conn_options=conn_options,
        )
        self._llm_instance = llm_instance

    async def _run(self) -> None:
        # 1. Safely retrieve messages from chat context
        if callable(getattr(self._chat_ctx, "messages", None)):
            all_messages = self._chat_ctx.messages()
        elif hasattr(self._chat_ctx, "items"):
            all_messages = self._chat_ctx.items
        else:
            all_messages = []

        last_student_msg = ""
        user_msgs_count = 0
        for msg in all_messages:
            role = getattr(msg, "role", None)
            content = getattr(msg, "content", "")
            text = _extract_text(content)
            if role == "user" and text:
                last_student_msg = text
                user_msgs_count += 1

        manager: SessionAssessmentManager = self._llm_instance.assessment_manager
        if not last_student_msg:
            spoken_text = "Dimmi pure, ti ascolto."
        else:
            (
                examiner_ctx,
                _turn_state,
            ) = await manager.process_student_turn(student_transcript=last_student_msg)
            spoken_text = examiner_ctx.pedagogical_directive or (
                f"Continuiamo con l'argomento {examiner_ctx.current_concept.name}."
            )

        logger.info("LocalOrchestratedLLM: Delivering spoken text: %s", spoken_text)

        # 4. Stream response chunk directly to LiveKit TTS
        chunk = ChatChunk(
            id=f"chunk_{uuid.uuid4().hex[:8]}",
            delta=ChoiceDelta(role="assistant", content=spoken_text),
        )
        self._event_ch.send_nowait(chunk)


class LocalOrchestratedLLM(llm.LLM):
    """Local, quota-free LLM provider that executes Gemini/local pedagogical logic

    and delivers prepared prompts directly to LiveKit Voice Assistant.
    """

    def __init__(self, assessment_manager: SessionAssessmentManager) -> None:
        super().__init__()
        self.assessment_manager = assessment_manager

    def chat(
        self,
        *,
        chat_ctx: ChatContext,
        tools: list[Tool] | None = None,
        conn_options: APIConnectOptions = DEFAULT_API_CONNECT_OPTIONS,
        **kwargs: Any,
    ) -> LLMStream:
        return LocalOrchestratedLLMStream(
            self,
            chat_ctx=chat_ctx,
            tools=tools or [],
            conn_options=conn_options,
        )
