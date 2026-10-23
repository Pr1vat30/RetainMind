import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart' as pcm;
import 'package:web_socket_channel/web_socket_channel.dart';

// ─── Shared voice connection and speaking state enums ─────────────────────────

enum ConnectionStateEnum {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

enum SpeakingStateEnum {
  idle,
  aiSpeaking,
  studentSpeaking,

  /// Agent is processing / generating a response (LLM latency window).
  /// Use this to show a subtle "thinking" cue without stopping animations.
  thinking,
}

// ─── PipecatService ───────────────────────────────────────────────────────────

/// WebSocket-based Pipecat voice service.
///
/// Streams Gemini-native PCM audio to/from the Pipecat WebSocket transport.
///
/// Audio flow:
///   Mic PCM-16 @ 16 kHz → base64 WebSocket → Gemini Live
///   Gemini Live PCM-16 @ 24 kHz → base64 WebSocket → native PCM playback
class PipecatService {
  // ── Internal state ────────────────────────────────────────────────────────
  WebSocketChannel? _channel;
  StreamSubscription? _wsSubscription;
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Uint8List>? _micSubscription;
  late final StreamSubscription<void> _playbackSubscription;
  final Queue<Uint8List> _playbackQueue = Queue<Uint8List>();
  BytesBuilder _pendingPlaybackPcm = BytesBuilder(copy: false);
  bool _isPlayingQueuedAudio = false;

  ConnectionStateEnum _connectionState = ConnectionStateEnum.disconnected;
  SpeakingStateEnum _speakingState = SpeakingStateEnum.idle;
  bool _isMicMuted = false;
  bool _isSpeakerphoneOn = true;
  bool _pcmSoundReady = false;
  int _sentMicChunks = 0;
  int _receivedMediaChunks = 0;
  int _playedAudioChunks = 0;

  // Monotonic packet sequence for transport diagnostics.
  int _seqNumber = 0;

  // Speaking state timer — AI is "speaking" while audio arrives; we set it back
  // to idle after a short silence window.
  Timer? _silenceTimer;
  Timer? _playbackFlushTimer;
  static const _silenceWindowMs = 600;
  static const _playbackBatchBytes = 2880; // 60 ms at 24 kHz, mono, PCM-16.
  static const _playbackTailFlushMs = 80;
  static const _inputSampleRate = 16000;
  static const _outputSampleRate = 24000;

  // ── Public streams ────────────────────────────────────────────────────────
  final StreamController<ConnectionStateEnum> _connectionStateController =
      StreamController<ConnectionStateEnum>.broadcast();
  final StreamController<SpeakingStateEnum> _speakingStateController =
      StreamController<SpeakingStateEnum>.broadcast();
  final StreamController<bool> _micMutedController =
      StreamController<bool>.broadcast();

  Stream<ConnectionStateEnum> get connectionStateStream =>
      _connectionStateController.stream;
  Stream<SpeakingStateEnum> get speakingStateStream =>
      _speakingStateController.stream;
  Stream<bool> get micMutedStream => _micMutedController.stream;

  // ── Synchronous getters ───────────────────────────────────────────────────
  ConnectionStateEnum get connectionState => _connectionState;
  SpeakingStateEnum get speakingState => _speakingState;
  bool get isMicMuted => _isMicMuted;
  bool get isSpeakerphoneOn => _isSpeakerphoneOn;

  // ── Permissions ───────────────────────────────────────────────────────────
  PipecatService() {
    _playbackSubscription = _player.onPlayerComplete.listen((_) {
      _isPlayingQueuedAudio = false;
      _playNextAudioChunk();
    });
  }

  Future<bool> requestMicrophonePermission() async {
    if (kIsWeb) return true;
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  // ── Connection ────────────────────────────────────────────────────────────

  /// Connect to Pipecat backend via WebSocket.
  ///
  /// [wsUrl] example: `ws://192.168.1.x:8000/ws/my_course_id`
  Future<void> connect({required String wsUrl}) async {
    try {
      await disconnect();

      _setConnectionState(ConnectionStateEnum.connecting);

      // Recording and playback share the native audio session. Configure it
      // for a two-way voice call before opening the microphone.
      await _configureAudioRoute();

      final hasPermission = await requestMicrophonePermission();
      if (!hasPermission) {
        throw Exception('Permesso microfono non concesso');
      }

      // 1. Open WebSocket
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Wait for the WebSocket to establish
      await _channel!.ready.timeout(
        const Duration(seconds: 10),
        onTimeout: () =>
            throw TimeoutException('WebSocket connection timed out'),
      );

      // 2. Listen to incoming WS frames
      _wsSubscription = _channel!.stream.listen(
        _onWsMessage,
        onError: _onWsError,
        onDone: _onWsDone,
      );

      if (!kIsWeb) {
        await pcm.FlutterPcmSound.setup(
          sampleRate: _outputSampleRate,
          channelCount: 1,
          iosAudioCategory: pcm.IosAudioCategory.playAndRecord,
        );
        _pcmSoundReady = true;
      }

      // 5. Start microphone capture (PCM-16 @ 16 kHz mono → WS)
      await _startMicCapture();

      _setConnectionState(ConnectionStateEnum.connected);
    } catch (e) {
      debugPrint('PipecatService connect error: $e');
      _setConnectionState(ConnectionStateEnum.failed);
      rethrow;
    }
  }

  // ── Mic capture ───────────────────────────────────────────────────────────

  Future<void> _startMicCapture() async {
    // Stop any previous recording
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    await _micSubscription?.cancel();

    // Keep Gemini's native input rate; downsampling to telephony audio harms quality.
    final micStream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _inputSampleRate,
        numChannels: 1,
        noiseSuppress: true,
        echoCancel: true,
        autoGain: true,
        streamBufferSize: kIsWeb
            ? 1024
            : (defaultTargetPlatform == TargetPlatform.android ? 1280 : 320),
      ),
    );
    // Some recorder backends select a recording route when the stream starts.
    // Re-apply the call route so incoming audio remains audible while recording.
    await _configureAudioRoute();

    _micSubscription = micStream.listen((chunk) {
      if (_isMicMuted) return;
      if (_connectionState != ConnectionStateEnum.connected) return;
      _sentMicChunks++;
      if (_sentMicChunks == 1 || _sentMicChunks % 100 == 0) {
        debugPrint(
          'PipecatService mic: chunks=$_sentMicChunks bytes=${chunk.length}',
        );
      }
      _sendAudioChunk(chunk);
    });
  }

  // ── PCM WebSocket protocol ────────────────────────────────────────────────

  void _sendAudioChunk(Uint8List pcm16Bytes) {
    _send({
      'event': 'audio',
      'sequenceNumber': '${++_seqNumber}',
      'audio': {
        'encoding': 'pcm_s16le',
        'sampleRate': _inputSampleRate,
        'channels': 1,
        'payload': base64Encode(pcm16Bytes),
      },
    });
  }

  void _send(Map<String, dynamic> payload) {
    try {
      _channel?.sink.add(jsonEncode(payload));
    } catch (e) {
      debugPrint('PipecatService WS send error: $e');
    }
  }

  // ── Incoming WS message handling ─────────────────────────────────────────

  void _onWsMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final event = msg['event'] as String?;

      switch (event) {
        case 'audio':
          _receivedMediaChunks++;
          if (_receivedMediaChunks == 1 || _receivedMediaChunks % 50 == 0) {
            final payload = (msg['audio'] as Map?)?['payload'];
            debugPrint(
              'PipecatService audio received: chunks=$_receivedMediaChunks '
              'payloadChars=${payload is String ? payload.length : 0}',
            );
          }
          _handleIncomingAudio(msg);
          break;
        case 'clear':
          // Backend asked to clear the audio buffer (barge-in / interruption).
          _pendingPlaybackPcm = BytesBuilder(copy: false);
          _playbackQueue.clear();
          _isPlayingQueuedAudio = false;
          _playbackFlushTimer?.cancel();
          unawaited(_clearPlaybackOutput());
          _setSpeakingState(SpeakingStateEnum.idle);
          _silenceTimer?.cancel();
          break;
        case 'mark':
          // Mark event: backend signaling a boundary — treat as thinking→idle
          _setSpeakingState(SpeakingStateEnum.idle);
          break;
        default:
          debugPrint('PipecatService unknown event: $event');
      }
    } catch (e) {
      debugPrint('PipecatService WS message parse error: $e');
    }
  }

  void _handleIncomingAudio(Map<String, dynamic> msg) {
    final audio = msg['audio'] as Map<String, dynamic>?;
    final payload = audio?['payload'] as String?;
    if (payload == null || payload.isEmpty) return;

    final pcm16 = base64Decode(payload);
    final sampleRate = audio?['sampleRate'] as int? ?? _outputSampleRate;
    if (sampleRate != _outputSampleRate) {
      debugPrint('PipecatService unexpected output sample rate: $sampleRate');
      return;
    }
    _pendingPlaybackPcm.add(pcm16);
    if (_pendingPlaybackPcm.length >= _playbackBatchBytes) {
      _queuePendingAudio();
    }
    _playbackFlushTimer?.cancel();
    _playbackFlushTimer = Timer(
      const Duration(milliseconds: _playbackTailFlushMs),
      _queuePendingAudio,
    );

    // Mark AI as speaking while audio arrives, reset to idle after silence window
    _setSpeakingState(SpeakingStateEnum.aiSpeaking);
    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(milliseconds: _silenceWindowMs), () {
      _queuePendingAudio();
      _setSpeakingState(SpeakingStateEnum.idle);
    });
  }

  void _queuePendingAudio() {
    if (_pendingPlaybackPcm.isEmpty) return;
    _playbackQueue.add(_pendingPlaybackPcm.takeBytes());
    _playNextAudioChunk();
  }

  Future<void> _playNextAudioChunk() async {
    if (_isPlayingQueuedAudio || _playbackQueue.isEmpty) return;
    _isPlayingQueuedAudio = true;

    if (!kIsWeb) {
      try {
        while (_playbackQueue.isNotEmpty && _pcmSoundReady) {
          final pcm16 = _playbackQueue.removeFirst();
          await pcm.FlutterPcmSound.feed(
            pcm.PcmArrayInt16(bytes: ByteData.sublistView(pcm16)),
          );
          _playedAudioChunks++;
          if (_playedAudioChunks == 1 || _playedAudioChunks % 20 == 0) {
            debugPrint(
              'PipecatService PCM playback fed: chunks=$_playedAudioChunks',
            );
          }
        }
      } catch (e) {
        debugPrint('PipecatService PCM playback error: $e');
      } finally {
        _isPlayingQueuedAudio = false;
        if (_playbackQueue.isNotEmpty) _playNextAudioChunk();
      }
      return;
    }

    try {
      await _player.play(
        BytesSource(
          _pcm16ToWav(
            _playbackQueue.removeFirst(),
            sampleRate: _outputSampleRate,
          ),
        ),
      );
      _playedAudioChunks++;
      if (_playedAudioChunks == 1 || _playedAudioChunks % 20 == 0) {
        debugPrint(
          'PipecatService audio playback started: chunks=$_playedAudioChunks',
        );
      }
    } catch (e) {
      _isPlayingQueuedAudio = false;
      debugPrint('PipecatService audio playback error: $e');
      _playNextAudioChunk();
    }
  }

  static Uint8List _pcm16ToWav(Uint8List pcm16, {required int sampleRate}) {
    const channels = 1;
    const bitsPerSample = 16;
    final out = Uint8List(44 + pcm16.length);
    final header = ByteData.sublistView(out);
    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        out[offset + i] = value.codeUnitAt(i);
      }
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, 36 + pcm16.length, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(
      28,
      sampleRate * channels * bitsPerSample ~/ 8,
      Endian.little,
    );
    header.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    header.setUint32(40, pcm16.length, Endian.little);
    out.setRange(44, out.length, pcm16);
    return out;
  }

  void _onWsError(dynamic error) {
    debugPrint('PipecatService WS error: $error');
    _setConnectionState(ConnectionStateEnum.failed);
  }

  void _onWsDone() {
    debugPrint('PipecatService WS closed');
    _setConnectionState(ConnectionStateEnum.disconnected);
    _setSpeakingState(SpeakingStateEnum.idle);
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  Future<void> toggleMicrophone() async {
    _isMicMuted = !_isMicMuted;
    if (!_micMutedController.isClosed) {
      _micMutedController.add(_isMicMuted);
    }
    if (_isMicMuted) {
      // Pause the recorder to save battery (stop sending audio)
      await _recorder.pause();
    } else {
      await _recorder.resume();
    }
  }

  Future<void> toggleSpeakerphone() async {
    _isSpeakerphoneOn = !_isSpeakerphoneOn;
    await _configureAudioRoute();
    debugPrint('PipecatService speakerphone: $_isSpeakerphoneOn');
  }

  Future<void> _configureAudioRoute() async {
    await _player.setAudioContext(
      AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: _isSpeakerphoneOn,
          audioMode: AndroidAudioMode.inCommunication,
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.voiceCommunication,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playAndRecord,
          options: {
            if (_isSpeakerphoneOn) AVAudioSessionOptions.defaultToSpeaker,
            AVAudioSessionOptions.allowBluetooth,
          },
        ),
      ),
    );
  }

  Future<void> _clearPlaybackOutput() async {
    if (kIsWeb) {
      await _player.stop();
      return;
    }
    if (!_pcmSoundReady) return;

    try {
      await pcm.FlutterPcmSound.release();
      _pcmSoundReady = false;
      await pcm.FlutterPcmSound.setup(
        sampleRate: _outputSampleRate,
        channelCount: 1,
        iosAudioCategory: pcm.IosAudioCategory.playAndRecord,
      );
      _pcmSoundReady = true;
      await _configureAudioRoute();
    } catch (e) {
      debugPrint('PipecatService PCM reset error: $e');
    }
  }

  // ── Disconnect ────────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _playbackFlushTimer?.cancel();
    _playbackFlushTimer = null;
    _pendingPlaybackPcm = BytesBuilder(copy: false);
    _playbackQueue.clear();
    _isPlayingQueuedAudio = false;
    _sentMicChunks = 0;
    _receivedMediaChunks = 0;
    _playedAudioChunks = 0;

    // Stop microphone
    await _micSubscription?.cancel();
    _micSubscription = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}

    // Stop playback
    try {
      await _player.stop();
    } catch (_) {}
    if (_pcmSoundReady) {
      try {
        await pcm.FlutterPcmSound.release();
      } catch (_) {}
      _pcmSoundReady = false;
    }

    // Close WebSocket gracefully
    try {
      if (_channel != null) {
        await _channel!.sink.close();
      }
    } catch (_) {}
    await _wsSubscription?.cancel();
    _wsSubscription = null;
    _channel = null;

    _setConnectionState(ConnectionStateEnum.disconnected);
    _setSpeakingState(SpeakingStateEnum.idle);
  }

  // ── Wait for the first AI audio frame ──────────────────────────────────────

  /// Waits until the remote AI agent starts speaking its initial audio,
  /// or until [timeout] elapses as a safety fallback.
  Future<void> waitForFirstAiInteraction({
    Duration timeout = const Duration(milliseconds: 5000),
  }) async {
    if (_speakingState == SpeakingStateEnum.aiSpeaking) return;

    final completer = Completer<void>();
    StreamSubscription<SpeakingStateEnum>? sub;
    Timer? timer;

    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    timer = Timer(timeout, finish);
    sub = speakingStateStream.listen((state) {
      if (state == SpeakingStateEnum.aiSpeaking) finish();
    });

    try {
      await completer.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await disconnect();
    await _playbackSubscription.cancel();
    _connectionStateController.close();
    _speakingStateController.close();
    _micMutedController.close();
    _recorder.dispose();
    _player.dispose();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _setConnectionState(ConnectionStateEnum state) {
    _connectionState = state;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }

  void _setSpeakingState(SpeakingStateEnum state) {
    if (_speakingState == state) return;
    _speakingState = state;
    if (!_speakingStateController.isClosed) {
      _speakingStateController.add(state);
    }
  }
}
