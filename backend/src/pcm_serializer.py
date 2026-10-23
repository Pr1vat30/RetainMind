"""Lossless PCM WebSocket protocol for the RetainMind Flutter client."""

import base64
import json

from loguru import logger

from pipecat.frames.frames import (
    AudioRawFrame,
    Frame,
    InputAudioRawFrame,
    InterruptionFrame,
    OutputTransportMessageFrame,
    OutputTransportMessageUrgentFrame,
)
from pipecat.processors.frame_processor import FrameProcessorSetup
from pipecat.serializers.base_serializer import FrameSerializer


class FlutterPcmSerializer(FrameSerializer):
    """Serialize raw PCM16 frames without telephony μ-law conversion."""

    async def setup(self, setup: FrameProcessorSetup):
        self._input_sample_rate = setup.audio_in_sample_rate

    async def deserialize(self, data: str | bytes) -> Frame | None:
        try:
            message = json.loads(data)
        except (json.JSONDecodeError, UnicodeDecodeError, TypeError):
            logger.warning("Flutter PCM websocket received invalid JSON")
            return None

        if message.get("event") != "audio":
            return None

        audio = message.get("audio") or {}
        if audio.get("encoding") != "pcm_s16le":
            logger.warning("Flutter PCM websocket received unsupported encoding")
            return None

        try:
            pcm = base64.b64decode(audio["payload"], validate=True)
            sample_rate = int(audio.get("sampleRate") or self._input_sample_rate)
            channels = int(audio.get("channels") or 1)
        except (KeyError, ValueError, TypeError):
            logger.warning("Flutter PCM websocket received invalid audio payload")
            return None

        if not pcm or len(pcm) % (2 * channels):
            logger.warning("Flutter PCM websocket received an incomplete PCM frame")
            return None

        return InputAudioRawFrame(
            audio=pcm,
            num_channels=channels,
            sample_rate=sample_rate,
        )

    async def serialize(self, frame: Frame) -> str | None:
        if self.should_ignore_frame(frame):
            return None

        if isinstance(frame, InterruptionFrame):
            return json.dumps({"event": "clear"})

        if isinstance(frame, AudioRawFrame):
            return json.dumps(
                {
                    "event": "audio",
                    "audio": {
                        "encoding": "pcm_s16le",
                        "sampleRate": frame.sample_rate,
                        "channels": frame.num_channels,
                        "payload": base64.b64encode(frame.audio).decode("ascii"),
                    },
                }
            )

        if isinstance(
            frame, (OutputTransportMessageFrame, OutputTransportMessageUrgentFrame)
        ):
            return json.dumps(frame.message)

        return None
