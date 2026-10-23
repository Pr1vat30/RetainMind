// ignore_for_file: experimental_member_use

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

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

/// Profilo audio ad alta fedeltà con cancellazione hardware dell'eco (AEC Full-Duplex) e routing vivavoce
/// - Apple: category: playAndRecord, mode: videoChat (loudspeaker a piena frequenza 48kHz con DSP hardware Voice Processing I/O)
/// - Android: audioMode: inCommunication (indispensabile per attivare l'Acoustic Echo Cancellation hardware HAL ed evitare
///   che la voce dell'AI rientri nel microfono mandando in loop Gemini Live) + vivavoce forzato.
const kNaturalVoiceAudioOptions = AudioSessionOptions.communication(
  apple: AppleAudioSessionConfiguration(
    category: AppleAudioCategory.playAndRecord,
    categoryOptions: {
      AppleAudioCategoryOption.defaultToSpeaker,
      AppleAudioCategoryOption.allowBluetooth,
      AppleAudioCategoryOption.allowBluetoothA2DP,
      AppleAudioCategoryOption.allowAirPlay,
    },
    mode: AppleAudioMode.videoChat,
  ),
  android: AndroidAudioSessionConfiguration(
    audioMode: AndroidAudioMode.inCommunication,
    manageAudioFocus: true,
    focusMode: AndroidAudioFocusMode.gain,
    streamType: AndroidAudioStreamType.voiceCall,
    usageType: AndroidAudioAttributesUsageType.voiceCommunication,
    contentType: AndroidAudioAttributesContentType.speech,
    forceAudioRouting: true,
  ),
);

class LiveKitService {
  Room? _room;
  EventsListener<RoomEvent>? _listener;

  ConnectionStateEnum _connectionState = ConnectionStateEnum.disconnected;
  SpeakingStateEnum _speakingState = SpeakingStateEnum.idle;
  bool _isMicMuted = false;
  bool _isSpeakerphoneOn = true;

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

  ConnectionStateEnum get connectionState => _connectionState;
  SpeakingStateEnum get speakingState => _speakingState;
  bool get isMicMuted => _isMicMuted;
  bool get isSpeakerphoneOn => _isSpeakerphoneOn;
  Room? get room => _room;

  Future<bool> requestMicrophonePermission() async {
    if (kIsWeb) return true;
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> connect({
    required String serverUrl,
    required String token,
  }) async {
    try {
      // Cleanly disconnect and dispose any previous connection before connecting anew
      await disconnect();

      _setConnectionState(ConnectionStateEnum.connecting);

      final hasPermission = await requestMicrophonePermission();
      if (!hasPermission) {
        throw Exception('Permesso microfono non concesso');
      }

      if (!kIsWeb) {
        try {
          // Configure AudioSessionOptions with high-fidelity communication profile
          // (hardware AEC full-duplex for barge-in + forced loudspeaker).
          // NOTE: setSpeakerOutputPreferred is intentionally called AFTER mic track publish
          // to avoid a perceptible audio routing glitch on Samsung Galaxy devices.
          await AudioManager.instance.setAudioSessionOptions(kNaturalVoiceAudioOptions);
          // Speaker routing is deferred to after setMicrophoneEnabled() below.
        } catch (e) {
          debugPrint('AudioManager setup audio options error: $e');
        }
      }

      final roomOptions = const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioPublishOptions: AudioPublishOptions(
          name: 'student_audio',
          dtx: false, // Disattivato per eliminare il ritardo di riattivazione pacchetti all'inizio della frase
          encoding: AudioEncoding.presetSpeech, // Frame Opus a 20ms ottimizzati per speech e bassissima latenza
        ),
        defaultAudioOutputOptions: AudioOutputOptions(
          speakerOn: true,
        ),
        defaultAudioCaptureOptions: AudioCaptureOptions(
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true, // Livello microfonico normalizzato per reattività immediata del VAD / endpointing
          highPassFilter: true, // Filtra frequenze basse (<80Hz) per evitare falsi positivi del VAD
        ),
      );

      _room = Room(roomOptions: roomOptions);
      _listener = _room!.createListener();

      _setupRoomListeners();

      // Pre-warm DNS resolution and TLS handshake (LiveKit Flutter best practice)
      try {
        await _room!.prepareConnection(serverUrl, token);
      } catch (e) {
        debugPrint('LiveKit prepareConnection non-fatal error: $e');
      }

      await _room!.connect(serverUrl, token);

      // Publish local microphone track
      final micTrackPub = await _room!.localParticipant?.setMicrophoneEnabled(true);
      debugPrint('LiveKit local mic track published: ${micTrackPub?.sid}, muted=${micTrackPub?.muted}');
      _isMicMuted = false;
      _micMutedController.add(false);

      // Defer speaker routing to AFTER mic track publish to avoid audio routing glitch
      // on Samsung Galaxy / Android devices (routing brusco all'apertura).
      if (!kIsWeb) {
        try {
          await AudioManager.instance.setSpeakerOutputPreferred(true, force: true);
          _isSpeakerphoneOn = true;
        } catch (e) {
          debugPrint('AudioManager setSpeakerOutputPreferred error: $e');
        }
      }

      // Ensure audio playback context is active (unblocks autoplay restrictions)
      try {
        await _room!.startAudio();
      } catch (e) {
        debugPrint('LiveKit startAudio error: $e');
      }

      _setConnectionState(ConnectionStateEnum.connected);
    } catch (e) {
      _setConnectionState(ConnectionStateEnum.failed);
      rethrow;
    }
  }

  void _setupRoomListeners() {
    if (_listener == null) return;

    _listener!
      ..on<RoomDisconnectedEvent>((event) {
        _setConnectionState(ConnectionStateEnum.disconnected);
        _setSpeakingState(SpeakingStateEnum.idle);
      })
      ..on<RoomReconnectingEvent>((event) {
        _setConnectionState(ConnectionStateEnum.reconnecting);
      })
      ..on<RoomReconnectedEvent>((event) {
        _setConnectionState(ConnectionStateEnum.connected);
      })
      ..on<ActiveSpeakersChangedEvent>((event) {
        // ParticipantAttributesChanged is the authoritative source for the AI agent state.
        // Only use ActiveSpeakers to detect the LOCAL (student) speaking turn.
        // This prevents flicker when both events fire simultaneously with conflicting states.
        _updateSpeakingState(event.speakers);
      })
      ..on<ParticipantAttributesChanged>((event) {
        if (event.participant.kind == ParticipantKind.AGENT) {
          final attrs = AgentAttributes.fromJson(event.attributes);
          final state = attrs.lkAgentState;
          if (state == AgentState.speaking) {
            _setSpeakingState(SpeakingStateEnum.aiSpeaking);
          } else if (state == AgentState.thinking) {
            // Agent is processing — keep current state to avoid flicker,
            // but expose thinking so the avatar can show a subtle cue.
            _setSpeakingState(SpeakingStateEnum.thinking);
          } else if (state == AgentState.listening || state == AgentState.idle) {
            _setSpeakingState(SpeakingStateEnum.idle);
          }
        }
      })
      ..on<AudioPlaybackStatusChanged>((event) async {
        debugPrint('LiveKit AudioPlaybackStatusChanged: isPlaying=${event.isPlaying}');
        if (!event.isPlaying && _room != null) {
          try {
            await _room!.startAudio();
          } catch (_) {}
        }
      })
      ..on<TrackSubscribedEvent>((event) async {
        debugPrint('LiveKit TrackSubscribedEvent: track=${event.track.sid}, kind=${event.track.kind}');
      });
  }

  void _updateSpeakingState(List<Participant> speakers) {
    if (speakers.isEmpty) {
      // Only reset to idle if agent is NOT in a thinking state.
      // This avoids killing the thinking indicator when audio silence is detected.
      if (_speakingState != SpeakingStateEnum.thinking) {
        _setSpeakingState(SpeakingStateEnum.idle);
      }
      return;
    }

    bool localSpeaking = false;
    bool remoteSpeaking = false;

    for (final speaker in speakers) {
      if (speaker is LocalParticipant) {
        localSpeaking = true;
      } else {
        remoteSpeaking = true;
      }
    }

    // Agent audio takes precedence. Only override with ActiveSpeakers for the REMOTE
    // participant when the agent is NOT already marked as speaking via attributes.
    if (remoteSpeaking) {
      _setSpeakingState(SpeakingStateEnum.aiSpeaking);
    } else if (localSpeaking) {
      _setSpeakingState(SpeakingStateEnum.studentSpeaking);
    } else {
      if (_speakingState != SpeakingStateEnum.thinking) {
        _setSpeakingState(SpeakingStateEnum.idle);
      }
    }
  }

  Future<void> toggleMicrophone() async {
    if (_room == null || _room!.localParticipant == null) return;

    final newMuteState = !_isMicMuted;
    await _room!.localParticipant!.setMicrophoneEnabled(!newMuteState);
    _isMicMuted = newMuteState;
    if (!_micMutedController.isClosed) {
      _micMutedController.add(_isMicMuted);
    }
  }

  Future<void> toggleSpeakerphone() async {
    _isSpeakerphoneOn = !_isSpeakerphoneOn;
    if (!kIsWeb) {
      try {
        await AudioManager.instance.setSpeakerOutputPreferred(
          _isSpeakerphoneOn,
          force: _isSpeakerphoneOn,
        );
      } catch (e) {
        debugPrint('AudioManager toggleSpeakerphone error: $e');
      }
    }
  }

  Future<void> disconnect() async {
    try {
      await _room?.disconnect();
      await _room?.dispose();
    } finally {
      _room = null;
      _listener?.dispose();
      _listener = null;
      _setConnectionState(ConnectionStateEnum.disconnected);
      _setSpeakingState(SpeakingStateEnum.idle);
    }
  }

  void _setConnectionState(ConnectionStateEnum state) {
    _connectionState = state;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }

  void _setSpeakingState(SpeakingStateEnum state) {
    _speakingState = state;
    if (!_speakingStateController.isClosed) {
      _speakingStateController.add(state);
    }
  }

  /// Waits until the remote AI agent starts speaking its initial audio,
  /// or until [timeout] elapses as a safety fallback guarantee.
  ///
  /// The default timeout is 5000ms (instead of the previous 3500ms) to account
  /// for LiveKit Cloud agent dispatch latency of up to 2-5 seconds.
  Future<void> waitForFirstAiInteraction({
    Duration timeout = const Duration(milliseconds: 5000),
  }) async {
    if (_speakingState == SpeakingStateEnum.aiSpeaking) return;

    final completer = Completer<void>();
    StreamSubscription<SpeakingStateEnum>? sub;
    Timer? timer;

    void finish() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    timer = Timer(timeout, finish);

    sub = speakingStateStream.listen((state) {
      if (state == SpeakingStateEnum.aiSpeaking) {
        finish();
      }
    });

    try {
      await completer.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  Future<void> dispose() async {
    // Await disconnect before closing stream controllers to avoid
    // writing to a closed broadcast stream (Unhandled Exception).
    await disconnect();
    _connectionStateController.close();
    _speakingStateController.close();
    _micMutedController.close();
  }
}
