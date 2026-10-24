import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' hide AndroidAudioMode;
import 'package:flutter_webrtc/flutter_webrtc.dart'
as rtc
    show
    AndroidAudioAttributesContentType,
    AndroidAudioAttributesUsageType,
    AndroidAudioConfiguration,
    AndroidAudioMode;
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

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

// ─── PipecatService (WebRTC) ───────────────────────────────────────────────────

/// Pipecat voice service using SmallWebRTC.
///
/// Audio capture, echo cancellation, jitter buffering and playback are
/// handled natively by libwebrtc.
class PipecatService {
  // ── Internal state ────────────────────────────────────────────────────────
  RTCPeerConnection? _peerConnection;
  MediaStream? _localMediaStream;
  MediaStreamTrack? _remoteAudioTrack;
  double _outputVolume = 0.7;
  String? _webrtcEndpoint;
  String? _peerConnectionId;
  final List<Map<String, dynamic>> _pendingIceCandidates = [];
  Timer? _rtcStatsTimer;
  int _lastInboundAudioBytes = 0;
  int _lastOutboundAudioBytes = 0;
  DateTime? _lastInboundAudioActivity;
  DateTime? _lastOutboundAudioActivity;

  ConnectionStateEnum _connectionState = ConnectionStateEnum.disconnected;
  SpeakingStateEnum _speakingState = SpeakingStateEnum.idle;
  bool _isMicMuted = false;
  bool _isSpeakerphoneOn = true;

  // Speaking state window — AI/Student speaking state decays to idle after silence.
  static const _silenceWindowMs = 600;

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

  PipecatService();

  // ── Permissions ───────────────────────────────────────────────────────────
  Future<bool> requestMicrophonePermission() async {
    if (kIsWeb) return true;
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  // ── Connection ────────────────────────────────────────────────────────────

  /// Connect to the Pipecat SmallWebRTC endpoint.
  Future<void> connectWebRtc({
    required String signalingUrl,
    String? courseId,
  }) async {
    try {
      await disconnect();
      _setConnectionState(ConnectionStateEnum.connecting);

      final hasPermission = await requestMicrophonePermission();
      if (!hasPermission) {
        throw Exception('Permesso microfono non concesso');
      }

      final initOptions = <String, dynamic>{};
      rtc.AndroidAudioConfiguration? androidConfig;

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        androidConfig = rtc.AndroidAudioConfiguration(
          manageAudioFocus: true,
          androidAudioMode: rtc.AndroidAudioMode.normal,
          androidAudioAttributesUsageType:
              rtc.AndroidAudioAttributesUsageType.media,
          androidAudioAttributesContentType:
              rtc.AndroidAudioAttributesContentType.music,
          forceHandleAudioRouting: true,
        );
        initOptions.addAll({
          'androidUseHardwareAudioProcessing': false,
          'audioSampleRate': 48000,
          'androidAudioConfiguration': androidConfig.toMap(),
        });
      }

      // 1. Inizializza prima il motore WebRTC
      await WebRTC.initialize(options: initOptions);

      // 2. Applica la configurazione audio Android dopo l'inizializzazione
      if (androidConfig != null) {
        await Helper.setAndroidAudioConfiguration(androidConfig);
      }

      _webrtcEndpoint = signalingUrl;
      _peerConnectionId = null;
      _pendingIceCandidates.clear();
      _lastInboundAudioBytes = 0;
      _lastOutboundAudioBytes = 0;
      _lastInboundAudioActivity = null;
      _lastOutboundAudioActivity = null;

      _peerConnection = await createPeerConnection({
        'sdpSemantics': 'unified-plan',
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      });
      final peer = _peerConnection!;
      peer.onIceCandidate = _onLocalIceCandidate;
      peer.onConnectionState = _onPeerConnectionState;
      peer.onTrack = (event) {
        if (event.track.kind == 'audio') {
          _remoteAudioTrack = event.track;
          unawaited(Helper.setVolume(_outputVolume, event.track));
          event.track.onUnMute = () {
            _lastInboundAudioActivity = DateTime.now();
          };
        }
      };

      // 3. Struttura mandatory richiesta dal bridge JNI Android di flutter_webrtc
      // per attivare correttamente AEC3 software, AGC e Noise Suppression.
      // NOTA: tutti i valori nei vincoli devono essere stringhe ('true'/'false') per evitare
      // il bug noto di casting Integer->Double nel JNI di flutter_webrtc (ConstraintsMap.getDouble).
      _localMediaStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'mandatory': {
            'echoCancellation': 'true',
            'noiseSuppression': 'true',
            'autoGainControl': 'true',
            'googHighpassFilter': 'true',
            'googAutoGainControl': 'true',
          },
          'optional': <Map<String, dynamic>>[],
        },
        'video': false,
      });

      for (final track in _localMediaStream!.getAudioTracks()) {
        await peer.addTrack(track, _localMediaStream!);
      }

      // 4. Crea l'offerta e applica SDP Munging per Opus Fullband (64kbps CBR)
      final offer = await peer.createOffer({});
      final optimizedOfferSdp = _optimizeOpusSdp(offer.sdp ?? '');
      await peer.setLocalDescription(
        RTCSessionDescription(optimizedOfferSdp, offer.type),
      );

      final localDescription = await peer.getLocalDescription();
      if (localDescription?.sdp == null) {
        throw Exception('WebRTC non ha generato l’offerta audio');
      }

      final requestBody = <String, dynamic>{
        'sdp': localDescription!.sdp,
        'type': localDescription.type ?? 'offer',
      };
      if (courseId != null && courseId.isNotEmpty) {
        requestBody['course_id'] = courseId;
      }
      final response = await http
          .post(
        Uri.parse(signalingUrl),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Segnalazione WebRTC rifiutata (${response.statusCode}): ${response.body}',
        );
      }

      final answer = jsonDecode(response.body) as Map<String, dynamic>;
      final answerSdp = answer['sdp'] as String?;
      _peerConnectionId = answer['pc_id'] as String?;
      if (answerSdp == null || _peerConnectionId == null) {
        throw Exception(
          'Il backend non ha restituito una risposta WebRTC valida',
        );
      }

      // Ottimizza anche l'SDP di risposta ricevuto dal server
      final optimizedAnswerSdp = _optimizeOpusSdp(answerSdp);
      await peer.setRemoteDescription(
        RTCSessionDescription(
          optimizedAnswerSdp,
          answer['type'] as String? ?? 'answer',
        ),
      );

      if (_pendingIceCandidates.isNotEmpty) {
        final queued = List<Map<String, dynamic>>.from(_pendingIceCandidates);
        _pendingIceCandidates.clear();
        await _sendIceCandidates(queued);
      }

      // NOTA: su Android in AndroidAudioMode.normal NON chiamiamo Helper.setSpeakerphoneOn(true)
      // all'avvio perché costringe l'AudioManager Samsung a ricadere nel routing telefonico.
      // Lo chiamiamo solo su iOS.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        await Helper.setSpeakerphoneOn(_isSpeakerphoneOn);
      }

      _rtcStatsTimer = Timer.periodic(
        const Duration(milliseconds: 300),
            (_) => unawaited(_updateRtcSpeakingState()),
      );
      await _waitForWebRtcConnection();
    } catch (e) {
      debugPrint('PipecatService WebRTC connect error: $e');
      _setConnectionState(ConnectionStateEnum.failed);
      await _closeWebRtcConnection();
      rethrow;
    }
  }

  /// Alias for connectWebRtc.
  Future<void> connect({
    required String signalingUrl,
    String? courseId,
  }) => connectWebRtc(signalingUrl: signalingUrl, courseId: courseId);

  void _onLocalIceCandidate(RTCIceCandidate candidate) {
    final mapped = <String, dynamic>{
      'candidate': candidate.candidate ?? '',
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    };
    final pcId = _peerConnectionId;
    if (pcId == null) {
      _pendingIceCandidates.add(mapped);
    } else {
      unawaited(_sendIceCandidates([mapped]));
    }
  }

  Future<void> _sendIceCandidates(List<Map<String, dynamic>> candidates) async {
    final endpoint = _webrtcEndpoint;
    final pcId = _peerConnectionId;
    if (endpoint == null || pcId == null || candidates.isEmpty) return;
    try {
      final response = await http
          .patch(
        Uri.parse(endpoint),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'pc_id': pcId, 'candidates': candidates}),
      )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode >= 400) {
        debugPrint('PipecatService ICE patch rejected: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('PipecatService ICE patch error: $e');
    }
  }

  void _onPeerConnectionState(RTCPeerConnectionState state) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _setConnectionState(ConnectionStateEnum.connected);
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _setConnectionState(ConnectionStateEnum.failed);
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        _setConnectionState(ConnectionStateEnum.disconnected);
        _setSpeakingState(SpeakingStateEnum.idle);
        break;
      default:
        break;
    }
  }

  Future<void> _waitForWebRtcConnection() async {
    final peer = _peerConnection;
    if (peer?.connectionState ==
        RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      _setConnectionState(ConnectionStateEnum.connected);
      return;
    }
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      if (_connectionState == ConnectionStateEnum.connected) return;
      if (_connectionState == ConnectionStateEnum.failed) {
        throw Exception('Connessione WebRTC non riuscita');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('Connessione audio WebRTC scaduta');
  }

  Future<void> _updateRtcSpeakingState() async {
    final peer = _peerConnection;
    if (peer == null || _connectionState != ConnectionStateEnum.connected) {
      return;
    }
    try {
      final reports = await peer.getStats();
      var inboundBytes = _lastInboundAudioBytes;
      var outboundBytes = _lastOutboundAudioBytes;
      double? inboundLevel;
      double? outboundLevel;
      for (final report in reports) {
        final values = report.values;
        final mediaKind = values['kind'] ?? values['mediaType'];
        if (mediaKind != 'audio') continue;
        final bytes = (values['bytesReceived'] ?? values['bytesSent']) as num?;
        final level = values['audioLevel'] as num?;
        if (report.type == 'inbound-rtp') {
          if (bytes != null) inboundBytes = bytes.toInt();
          inboundLevel = level?.toDouble();
        }
        if (report.type == 'outbound-rtp') {
          if (bytes != null) outboundBytes = bytes.toInt();
          outboundLevel = level?.toDouble();
        }
      }
      final now = DateTime.now();
      _lastInboundAudioActivity = inboundLevel != null
          ? (inboundLevel > 0.02 ? now : null)
          : inboundBytes > _lastInboundAudioBytes
          ? now
          : _lastInboundAudioActivity;
      _lastOutboundAudioActivity = outboundLevel != null
          ? (outboundLevel > 0.02 ? now : null)
          : outboundBytes > _lastOutboundAudioBytes
          ? now
          : _lastOutboundAudioActivity;
      _lastInboundAudioBytes = inboundBytes;
      _lastOutboundAudioBytes = outboundBytes;

      final inboundActive =
          _lastInboundAudioActivity != null &&
              now.difference(_lastInboundAudioActivity!) <
                  const Duration(milliseconds: _silenceWindowMs);
      final outboundActive =
          _lastOutboundAudioActivity != null &&
              now.difference(_lastOutboundAudioActivity!) <
                  const Duration(milliseconds: _silenceWindowMs);
      _setSpeakingState(
        inboundActive
            ? SpeakingStateEnum.aiSpeaking
            : outboundActive && !_isMicMuted
            ? SpeakingStateEnum.studentSpeaking
            : SpeakingStateEnum.idle,
      );
    } catch (e) {
      debugPrint('PipecatService WebRTC stats error: $e');
    }
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  Future<void> toggleMicrophone() async {
    _isMicMuted = !_isMicMuted;
    if (!_micMutedController.isClosed) {
      _micMutedController.add(_isMicMuted);
    }
    if (_peerConnection != null) {
      for (final track in _localMediaStream?.getAudioTracks() ?? const []) {
        track.enabled = !_isMicMuted;
      }
    }
  }

  Future<void> toggleSpeakerphone() async {
    _isSpeakerphoneOn = !_isSpeakerphoneOn;
    if (_peerConnection != null) {
      await Helper.setSpeakerphoneOn(_isSpeakerphoneOn);
    }
    debugPrint('PipecatService speakerphone: $_isSpeakerphoneOn');
  }

  /// Sets the volume of the incoming remote audio track (range 0.0 to 1.0).
  Future<void> setVolume(double volume) async {
    _outputVolume = volume.clamp(0.0, 1.0);
    final track = _remoteAudioTrack;
    if (track != null) {
      await Helper.setVolume(_outputVolume, track);
    }
  }

  // ── Disconnect ────────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    await _closeWebRtcConnection();
    _setConnectionState(ConnectionStateEnum.disconnected);
    _setSpeakingState(SpeakingStateEnum.idle);
  }

  Future<void> _closeWebRtcConnection() async {
    _rtcStatsTimer?.cancel();
    _rtcStatsTimer = null;
    _peerConnectionId = null;
    _webrtcEndpoint = null;
    _pendingIceCandidates.clear();
    _remoteAudioTrack = null;
    final stream = _localMediaStream;
    _localMediaStream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await stream.dispose();
      } catch (_) {}
    }
    final peer = _peerConnection;
    _peerConnection = null;
    if (peer != null) {
      peer.onConnectionState = null;
      peer.onIceCandidate = null;
      peer.onTrack = null;
      try {
        await peer.close();
      } catch (_) {}
      try {
        await peer.dispose();
      } catch (_) {}
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await Helper.clearAndroidCommunicationDevice();
      } catch (_) {}
    }
    _lastInboundAudioBytes = 0;
    _lastOutboundAudioBytes = 0;
    _lastInboundAudioActivity = null;
    _lastOutboundAudioActivity = null;
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
    _connectionStateController.close();
    _speakingStateController.close();
    _micMutedController.close();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  String _optimizeOpusSdp(String sdp) {
    final opusRegex = RegExp(r'a=rtpmap:(\d+) opus/48000/2');
    final match = opusRegex.firstMatch(sdp);
    if (match == null) return sdp;

    final pt = match.group(1);
    final fmtpTarget = 'a=fmtp:$pt ';

    // Configura Opus per voce ad alta fedeltà (64kbps, CBR, Fullband, FEC attivo, no DTX)
    const customFmtp =
        'minptime=10;useinbandfec=1;stereo=0;sprop-stereo=0;maxaveragebitrate=64000;maxplaybackrate=48000;cbr=1;usedtx=0';

    if (sdp.contains(fmtpTarget)) {
      return sdp.replaceAllMapped(
        RegExp('$fmtpTarget.*'),
            (m) => '$fmtpTarget$customFmtp',
      );
    } else {
      return sdp.replaceFirst(
        match.group(0)!,
        '${match.group(0)!}\r\n$fmtpTarget$customFmtp',
      );
    }
  }

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
