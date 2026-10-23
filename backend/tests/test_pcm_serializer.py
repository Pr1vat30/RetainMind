import base64
import json
import struct

import pytest
from pipecat.frames.frames import InputAudioRawFrame, OutputAudioRawFrame

from pcm_serializer import FlutterPcmSerializer


@pytest.mark.asyncio
async def test_flutter_pcm_serializer_preserves_input_pcm_without_lossy_conversion():
    pcm = struct.pack("<hhh", 1200, -2400, 3600)
    message = json.dumps(
        {
            "event": "audio",
            "audio": {
                "encoding": "pcm_s16le",
                "sampleRate": 16000,
                "channels": 1,
                "payload": base64.b64encode(pcm).decode("ascii"),
            },
        }
    )

    frame = await FlutterPcmSerializer().deserialize(message)

    assert isinstance(frame, InputAudioRawFrame)
    assert frame.audio == pcm
    assert frame.sample_rate == 16000
    assert frame.num_channels == 1


@pytest.mark.asyncio
async def test_flutter_pcm_serializer_sends_output_pcm_at_native_rate():
    pcm = struct.pack("<hhh", 100, -200, 300)
    frame = OutputAudioRawFrame(audio=pcm, sample_rate=24000, num_channels=1)

    encoded = await FlutterPcmSerializer().serialize(frame)
    message = json.loads(encoded)

    assert message["event"] == "audio"
    assert message["audio"]["encoding"] == "pcm_s16le"
    assert message["audio"]["sampleRate"] == 24000
    assert base64.b64decode(message["audio"]["payload"]) == pcm
