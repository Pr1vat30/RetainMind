import pytest
from pipecat.frames.frames import LLMContextFrame
from types import SimpleNamespace

from agent import _queue_opening_greeting


@pytest.mark.asyncio
async def test_opening_greeting_initializes_gemini_context_and_runs_immediately():
    queued = []

    async def queue_frames(frames):
        queued.extend(frames)

    greeting = "Buongiorno! Benvenuto alla simulazione. Sei pronto?"
    await _queue_opening_greeting(SimpleNamespace(queue_frames=queue_frames), greeting)

    assert len(queued) == 1
    assert isinstance(queued[0], LLMContextFrame)
    assert queued[0].context.messages[0]["role"] == "user"
    assert greeting in queued[0].context.messages[0]["content"]
    assert "pronunciando ad alta voce" in queued[0].context.messages[0]["content"]


@pytest.mark.asyncio
async def test_opening_greeting_propagates_queue_failures():
    async def queue_frames(_frames):
        raise RuntimeError("pipeline is not ready")

    with pytest.raises(RuntimeError, match="pipeline is not ready"):
        await _queue_opening_greeting(
            SimpleNamespace(queue_frames=queue_frames),
            "Buongiorno!",
        )
