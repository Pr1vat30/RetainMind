import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/session_models.dart';
import '../services/api_service.dart';
import '../services/livekit_service.dart';
import '../widgets/avatar/avatar_models.dart';

class ExamProvider with ChangeNotifier {
  late final ApiService _apiService;
  late final LiveKitService _liveKitService;

  SessionStatusInfo? _sessionStatus;
  DiagnosticReport? _diagnosticReport;
  ExaminationPlanModel? _examinationPlan;
  ComparisonReportModel? _comparisonReport;
  List<Map<String, dynamic>> _historyList = [];
  List<SessionHistoryItem> _historyItems = [];
  List<DialogueTurn> _transcriptTurns = [];

  bool _isLoading = false;
  String? _errorMessage;
  Timer? _statusPollingTimer;

  ExamProvider({String? initialBaseUrl}) {
    _apiService = ApiService(baseUrl: initialBaseUrl ?? AppConstants.defaultBaseUrl);
    _liveKitService = LiveKitService();

    // Listen to speaking state and connection changes
    _liveKitService.speakingStateStream.listen((_) => notifyListeners());
    _liveKitService.connectionStateStream.listen((_) => notifyListeners());
    _liveKitService.micMutedStream.listen((_) => notifyListeners());
  }

  // Getters
  ApiService get apiService => _apiService;
  LiveKitService get liveKitService => _liveKitService;
  SessionStatusInfo? get sessionStatus => _sessionStatus;
  DiagnosticReport? get diagnosticReport => _diagnosticReport;
  ExaminationPlanModel? get examinationPlan => _examinationPlan;
  ComparisonReportModel? get comparisonReport => _comparisonReport;
  List<Map<String, dynamic>> get historyList => _historyList;
  List<SessionHistoryItem> get historyItems => _historyItems;
  List<DialogueTurn> get transcriptTurns => _transcriptTurns;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  ConnectionStateEnum get connectionState => _liveKitService.connectionState;
  SpeakingStateEnum get speakingState => _liveKitService.speakingState;
  bool get isMicMuted => _liveKitService.isMicMuted;
  bool get isSpeakerphoneOn => _liveKitService.isSpeakerphoneOn;
  bool get isConnected => connectionState == ConnectionStateEnum.connected;
  bool get isAiSpeaking => speakingState == SpeakingStateEnum.aiSpeaking;
  bool get isStudentSpeaking => speakingState == SpeakingStateEnum.studentSpeaking;

  /// Reactive Grok Avatar mood based on LiveKit voice stream & Pedagogical FSM
  AvatarAgentMood get avatarMood {
    // 1. If exam paused -> Sleepy / resting
    if (_sessionStatus?.status == 'PAUSED') {
      return AvatarAgentMood.paused;
    }

    // 2. If AI is actively speaking -> Lively talking mouthless resonance
    if (speakingState == SpeakingStateEnum.aiSpeaking) {
      return AvatarAgentMood.speaking;
    }

    // 3. If student is speaking -> Alert & attentive listening
    if (speakingState == SpeakingStateEnum.studentSpeaking) {
      return AvatarAgentMood.listening;
    }

    // 4. Pedagogical State nuances when idle/waiting
    final fsm = _sessionStatus?.pedagogicalState.toUpperCase() ?? '';
    if (fsm == 'SCAFFOLDING') {
      return AvatarAgentMood.scaffolding;
    } else if (fsm == 'CAUSAL_NARROWING') {
      return AvatarAgentMood.narrowing;
    } else if (fsm == 'CONCEPTUAL_COLLISION') {
      return AvatarAgentMood.collision;
    } else if (fsm == 'PREREQUISITE_FALLBACK') {
      return AvatarAgentMood.thinking;
    }

    // 5. Default idle intelligent presence
    return AvatarAgentMood.idle;
  }

  Color get avatarGlowColor {
    if (isMicMuted) return AppConstants.textSecondary;

    switch (avatarMood) {
      case AvatarAgentMood.speaking:
        return AppConstants.primaryGlow;
      case AvatarAgentMood.listening:
        return AppConstants.success;
      case AvatarAgentMood.thinking:
        return AppConstants.accent;
      case AvatarAgentMood.scaffolding:
        return AppConstants.warning;
      case AvatarAgentMood.collision:
        return const Color(0xFFEC4899);
      case AvatarAgentMood.narrowing:
        return const Color(0xFFA855F7);
      case AvatarAgentMood.paused:
        return AppConstants.textSecondary;
      case AvatarAgentMood.idle:
        return AppConstants.primary;
    }
  }

  Future<void> updateBackendUrl(String newUrl) async {
    _apiService.updateBaseUrl(newUrl);
    notifyListeners();
    try {
      await Future.wait([
        fetchStatus(),
        fetchPlan(),
        fetchHistory(),
      ]);
    } catch (_) {}
  }

  Future<void> fetchStatus() async {
    try {
      final newStatus = await _apiService.fetchSessionStatus();
      if (_sessionStatus == null ||
          _sessionStatus?.status != newStatus.status ||
          _sessionStatus?.currentConceptId != newStatus.currentConceptId ||
          _sessionStatus?.pedagogicalState != newStatus.pedagogicalState ||
          _sessionStatus?.planProgressPercentage != newStatus.planProgressPercentage ||
          _sessionStatus?.planStep != newStatus.planStep) {
        _sessionStatus = newStatus;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> fetchTranscript() async {
    try {
      final turns = await _apiService.fetchTranscript();
      if (_transcriptTurns.length != turns.length) {
        _transcriptTurns = turns;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> fetchPlan({String? courseId}) async {
    try {
      _examinationPlan = await _apiService.fetchPlan(courseId: courseId);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> fetchComparison() async {
    try {
      _comparisonReport = await _apiService.fetchComparison();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> fetchHistory() async {
    try {
      final rawList = await _apiService.fetchHistory();
      _historyList = rawList;
      _historyItems = rawList.map((e) => SessionHistoryItem.fromJson(e)).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<List<DialogueTurn>> fetchTranscriptForIteration(int iteration, {String? courseId}) async {
    try {
      return await _apiService.fetchTranscript(iteration: iteration, courseId: courseId);
    } catch (_) {
      return [];
    }
  }

  String _resolveLiveKitServerUrl(String rawUrl) {
    try {
      final lkUri = Uri.parse(rawUrl);
      if (lkUri.host == '127.0.0.1' || lkUri.host == 'localhost') {
        final apiUri = Uri.parse(_apiService.baseUrl);
        final targetHost = (apiUri.host.isNotEmpty &&
                apiUri.host != '127.0.0.1' &&
                apiUri.host != 'localhost')
            ? apiUri.host
            : (defaultTargetPlatform == TargetPlatform.android
                ? '10.0.2.2'
                : lkUri.host);
        return lkUri.replace(host: targetHost).toString();
      }
    } catch (_) {}
    return rawUrl;
  }

  Future<void> startExam({
    String? roomName,
    String? courseId,
    String participantIdentity = 'student_default',
    String participantName = 'Studente',
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Generate deterministic course-scoped room name so backend LiveKit agent knows exactly which document is loaded
      final effectiveRoomName = roomName ??
          (courseId != null && courseId.isNotEmpty
              ? 'oral-exam-$courseId-${DateTime.now().millisecondsSinceEpoch}'
              : 'oral-exam-${DateTime.now().millisecondsSinceEpoch}');

      // 1. Fetch Token from backend REST API
      final tokenRes = await _apiService.fetchToken(
        roomName: effectiveRoomName,
        participantIdentity: participantIdentity,
        participantName: participantName,
        courseId: courseId,
      );

      final resolvedUrl = _resolveLiveKitServerUrl(tokenRes.serverUrl);

      // 2. Connect to LiveKit Room via WebRTC
      await _liveKitService.connect(
        serverUrl: resolvedUrl,
        token: tokenRes.participantToken,
      );

      // 3. Start Periodic Telemetry & Transcript Polling
      _startPolling();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Errore avvio esame: $e';
      notifyListeners();
      rethrow;
    }
  }

  void _startPolling() {
    _statusPollingTimer?.cancel();
    _statusPollingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await Future.wait([
        fetchStatus(),
        fetchTranscript(),
      ]);
    });
  }

  void _stopPolling() {
    _statusPollingTimer?.cancel();
    _statusPollingTimer = null;
  }

  Future<void> toggleMicrophone() async {
    await _liveKitService.toggleMicrophone();
    notifyListeners();
  }

  Future<void> toggleSpeakerphone() async {
    await _liveKitService.toggleSpeakerphone();
    notifyListeners();
  }

  Future<void> pauseExam() async {
    try {
      _stopPolling();
      await _liveKitService.disconnect();
      await _apiService.pauseSession();
      await fetchStatus();
    } catch (e) {
      _errorMessage = 'Errore pausa: $e';
      notifyListeners();
    }
  }

  Future<void> resumeExam({String? courseId}) async {
    try {
      await _apiService.resumeSession(courseId: courseId);
      if (!isConnected) {
        await startExam(courseId: courseId);
      } else {
        await fetchStatus();
      }
    } catch (e) {
      _errorMessage = 'Errore ripresa: $e';
      notifyListeners();
    }
  }

  Future<void> resumeExamAndConnect({String? courseId}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (courseId != null && courseId.isNotEmpty) {
        await _apiService.activateCourse(courseId);
        unawaited(fetchPlan(courseId: courseId));
      }
      await _apiService.resumeSession(courseId: courseId);
      await startExam(courseId: courseId);
      unawaited(Future.wait([fetchStatus(), fetchHistory()]));
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Errore ripresa conversazione: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> startNewExam({bool adapt = false, String? courseId}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (courseId != null && courseId.isNotEmpty) {
        await _apiService.activateCourse(courseId);
        unawaited(fetchPlan(courseId: courseId));
      }
      // 1. Initialize a completely fresh, isolated discussion on the server
      final res = await _apiService.createNewDiscussion(courseId: courseId);
      final assignedRoom = res['room_name'] as String? ??
          (courseId != null && courseId.isNotEmpty
              ? 'oral-exam-$courseId-${DateTime.now().millisecondsSinceEpoch}'
              : 'oral-exam-${DateTime.now().millisecondsSinceEpoch}');
      _transcriptTurns = [];

      // 2. Start LiveKit WebRTC connection with the isolated room name
      await startExam(roomName: assignedRoom, courseId: courseId);
      unawaited(Future.wait([fetchStatus(), fetchHistory()]));
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Errore avvio nuova conversazione: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteDiscussion(dynamic identifier) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _apiService.deleteDiscussion(identifier);
      await Future.wait([
        fetchHistory(),
        fetchStatus(),
        fetchPlan(),
      ]);
    } catch (e) {
      _errorMessage = 'Errore eliminazione discussione: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> uploadDocumentAndStartNewDiscussion({
    String? title,
    String? text,
    String? filename,
    List<int>? fileBytes,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uploadRes = await _apiService.uploadDocument(
        title: title,
        text: text,
        filename: filename,
        fileBytes: fileBytes,
      );
      final courseId = uploadRes['course_id'] as String?;
      _transcriptTurns = [];
      await Future.wait([
        fetchPlan(),
        fetchStatus(),
        fetchHistory(),
      ]);
      await startExam(courseId: courseId);
      unawaited(Future.wait([fetchStatus(), fetchHistory()]));
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Errore caricamento documento: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> generateExamFromTopicAndStartNewDiscussion({
    required String topic,
    String? title,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _apiService.generateExamFromTopic(
        topic: topic,
        title: title,
      );
      final courseId = res['course_id'] as String?;
      _transcriptTurns = [];
      await Future.wait([
        fetchPlan(),
        fetchStatus(),
        fetchHistory(),
      ]);
      await startExam(courseId: courseId);
      unawaited(Future.wait([fetchStatus(), fetchHistory()]));
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Errore generazione esame da argomento: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> repeatExam({bool adapt = true, String? courseId}) async {
    try {
      if (courseId != null && courseId.isNotEmpty) {
        await _apiService.activateCourse(courseId);
      }
      await _apiService.repeatSession(adapt: adapt, courseId: courseId);
      await fetchStatus();
      await fetchTranscript();
    } catch (e) {
      _errorMessage = 'Errore ripetizione esame: $e';
      notifyListeners();
    }
  }

  Future<void> resetAllSessionData({bool deletePlan = true}) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _apiService.resetSession(deletePlan: deletePlan);
      _sessionStatus = null;
      _examinationPlan = null;
      _historyList = [];
      _historyItems = [];
      _transcriptTurns = [];
      _diagnosticReport = null;
      _comparisonReport = null;
      await fetchPlan();
      await fetchHistory();
      await fetchStatus();
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
  }

  Future<void> endExam() async {
    _stopPolling();
    await _liveKitService.disconnect();
    try {
      // Archive completed session on backend into history
      await _apiService.repeatSession(adapt: false);
      _diagnosticReport = await _apiService.fetchDiagnosticReport();
      await Future.wait([
        fetchComparison(),
        fetchHistory(),
        fetchStatus(),
      ]);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> loadReport() async {
    try {
      _diagnosticReport = await _apiService.fetchDiagnosticReport();
      await fetchComparison();
      await fetchHistory();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Impossibile caricare il report: $e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stopPolling();
    _liveKitService.dispose();
    super.dispose();
  }
}
