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
}

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

      final roomOptions = const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioPublishOptions: AudioPublishOptions(
          name: 'student_audio',
          dtx: false, // Disattivato per eliminare il ritardo di riattivazione pacchetti all'inizio della frase
          encoding: AudioEncoding.presetSpeech,
        ),
        defaultAudioOutputOptions: AudioOutputOptions(
          speakerOn: true,
        ),
        defaultAudioCaptureOptions: AudioCaptureOptions(
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
          highPassFilter: false,
        ),
      );

      _room = Room(roomOptions: roomOptions);
      _listener = _room!.createListener();

      _setupRoomListeners();

      await _room!.connect(serverUrl, token);

      // Publish local microphone track
      final micTrackPub = await _room!.localParticipant?.setMicrophoneEnabled(true);
      debugPrint('LiveKit local mic track published: ${micTrackPub?.sid}, muted=${micTrackPub?.muted}');
      _isMicMuted = false;
      _micMutedController.add(false);

      // Prefer high-fidelity loudspeaker output on mobile devices
      if (!kIsWeb) {
        try {
          await AudioManager.instance.setSpeakerOutputPreferred(true);
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
        _updateSpeakingState(event.speakers);
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
        if (event.track is AudioTrack && !kIsWeb) {
          try {
            await AudioManager.instance.setSpeakerOutputPreferred(_isSpeakerphoneOn);
          } catch (_) {}
        }
      });
  }

  void _updateSpeakingState(List<Participant> speakers) {
    if (speakers.isEmpty) {
      _setSpeakingState(SpeakingStateEnum.idle);
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

    if (remoteSpeaking) {
      _setSpeakingState(SpeakingStateEnum.aiSpeaking);
    } else if (localSpeaking) {
      _setSpeakingState(SpeakingStateEnum.studentSpeaking);
    } else {
      _setSpeakingState(SpeakingStateEnum.idle);
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
          force: false,
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

  void dispose() {
    disconnect();
    _connectionStateController.close();
    _speakingStateController.close();
    _micMutedController.close();
  }
}
