import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/session_models.dart';
import '../services/api_service.dart';
import '../services/pipecat_service.dart';
import '../widgets/avatar/avatar_models.dart';

class ExamProvider with ChangeNotifier {
  late final ApiService _apiService;
  late final PipecatService _pipecatService;

  SessionStatusInfo? _sessionStatus;
  DiagnosticReport? _diagnosticReport;
  ExaminationPlanModel? _examinationPlan;
  ComparisonReportModel? _comparisonReport;
  List<Map<String, dynamic>> _historyList = [];
  List<SessionHistoryItem> _historyItems = [];
  List<DialogueTurn> _transcriptTurns = [];
  String? _currentCourseId;

  TokenResponse? _prewarmedSession;
  String? _prewarmedCourseId;

  ThemeMode _themeMode = ThemeMode.dark;

  bool _isLoading = false;
  String? _errorMessage;
  Timer? _statusPollingTimer;

  ExamProvider({String? initialBaseUrl}) {
    _apiService = ApiService(
      baseUrl: initialBaseUrl ?? AppConstants.defaultBaseUrl,
    );
    _pipecatService = PipecatService();

    // Listen to speaking state and connection changes
    _pipecatService.speakingStateStream.listen((_) => notifyListeners());
    _pipecatService.connectionStateStream.listen((_) => notifyListeners());
    _pipecatService.micMutedStream.listen((_) => notifyListeners());
  }

  // Getters
  ApiService get apiService => _apiService;
  PipecatService get pipecatService => _pipecatService;
  SessionStatusInfo? get sessionStatus => _sessionStatus;
  DiagnosticReport? get diagnosticReport => _diagnosticReport;
  ExaminationPlanModel? get examinationPlan => _examinationPlan;
  ComparisonReportModel? get comparisonReport => _comparisonReport;
  List<Map<String, dynamic>> get historyList => _historyList;
  List<SessionHistoryItem> get historyItems => _historyItems;
  List<DialogueTurn> get transcriptTurns => _transcriptTurns;
  String? get currentCourseId => _currentCourseId;
  TokenResponse? get prewarmedSession => _prewarmedSession;
  ThemeMode get themeMode => _themeMode;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  ConnectionStateEnum get connectionState => _pipecatService.connectionState;
  SpeakingStateEnum get speakingState => _pipecatService.speakingState;
  bool get isMicMuted => _pipecatService.isMicMuted;
  bool get isSpeakerphoneOn => _pipecatService.isSpeakerphoneOn;
  bool get isConnected => connectionState == ConnectionStateEnum.connected;
  bool get isAiSpeaking => speakingState == SpeakingStateEnum.aiSpeaking;
  bool get isStudentSpeaking =>
      speakingState == SpeakingStateEnum.studentSpeaking;
  bool get isAiThinking => speakingState == SpeakingStateEnum.thinking;

  /// Compiled once at class level — avoids re-creating RegExp on every call.
  static final List<RegExp> _aiQuestionPrefixes = [
    RegExp(
      r'^(perfetto,?\s*(iniziamo|riprendiamo)\s*(subito)?!?:?\s*)',
      caseSensitive: false,
    ),
    RegExp(r'^(molto bene\.?\s*)', caseSensitive: false),
    RegExp(r'^(ottimo\.?\s*)', caseSensitive: false),
    RegExp(
      r'^(nessun problema,?\s*lasciamo da parte questo argomento per ora\.?\s*passiamo ad altro:?\s*)',
      caseSensitive: false,
    ),
    RegExp(
      r'^(ora che abbiamo chiarito questi aspetti,?\s*torniamo un attimo indietro[^:]*:?\s*)',
      caseSensitive: false,
    ),
    RegExp(
      r'^(buongiorno!?\s*benvenuto[^?]+sei pronto\??\s*)',
      caseSensitive: false,
    ),
    RegExp(
      r'^(bentornato[^?]+sei pronto a riprendere\??\s*)',
      caseSensitive: false,
    ),
  ];

  /// Cleans conversational banter/greetings from the AI's question, leaving strictly the question
  static String cleanAiQuestion(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return '';

    // Remove common conversational greetings and transitions in Italian
    for (final p in _aiQuestionPrefixes) {
      text = text.replaceFirst(p, '').trim();
    }

    // If there is a question mark, extract the question clause/sentence ending with '?'
    if (text.contains('?')) {
      final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
      final questions = sentences.where((s) => s.trim().endsWith('?')).toList();
      if (questions.isNotEmpty) {
        text = questions.last.trim();
      }
    }

    return text;
  }

  /// Returns exclusively the question asked by the AI, free of surrounding conversational filler
  String get currentAiQuestion {
    // 1. Direct from SessionStatusInfo if available
    final statusQ = _sessionStatus?.currentQuestion.trim() ?? '';
    if (statusQ.isNotEmpty) {
      final cleaned = cleanAiQuestion(statusQ);
      if (cleaned.isNotEmpty) return cleaned;
    }

    // 2. From ExaminationPlan for the active concept
    final currCid = _sessionStatus?.currentConceptId ?? '';
    if (_examinationPlan != null && _examinationPlan!.concepts.isNotEmpty) {
      if (currCid.isNotEmpty) {
        final match = _examinationPlan!.concepts.firstWhere(
          (c) => c.conceptId == currCid,
          orElse: () => _examinationPlan!.concepts.first,
        );
        if (match.mainQuestion.trim().isNotEmpty) {
          return cleanAiQuestion(match.mainQuestion);
        }
      } else {
        final firstQ = _examinationPlan!.concepts.first.mainQuestion.trim();
        if (firstQ.isNotEmpty) {
          return cleanAiQuestion(firstQ);
        }
      }
    }

    // 3. Fallback to latest AI question recorded in turns
    for (final turn in _transcriptTurns.reversed) {
      if (turn.aiQuestion.trim().isNotEmpty) {
        final cleaned = cleanAiQuestion(turn.aiQuestion);
        if (cleaned.isNotEmpty &&
            !cleaned.toLowerCase().contains('sei pronto')) {
          return cleaned;
        }
      }
    }

    return '';
  }

  /// Reactive Grok Avatar mood based on Pipecat voice stream & Pedagogical FSM
  AvatarAgentMood get avatarMood {
    // 1. If exam paused -> Sleepy / resting
    if (_sessionStatus?.status == 'PAUSED') {
      return AvatarAgentMood.paused;
    }

    // 2. If AI is actively speaking -> Lively talking mouthless resonance
    if (speakingState == SpeakingStateEnum.aiSpeaking) {
      return AvatarAgentMood.speaking;
    }

    // 3. Agent is generating a response (LLM thinking window) -> show thinking cue
    if (speakingState == SpeakingStateEnum.thinking) {
      return AvatarAgentMood.thinking;
    }

    // 4. If student is speaking -> Alert & attentive listening
    if (speakingState == SpeakingStateEnum.studentSpeaking) {
      return AvatarAgentMood.listening;
    }

    // 5. Pedagogical State nuances when idle/waiting
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

    // 6. Default idle intelligent presence
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

  void setThemeMode(ThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();
    }
  }

  Future<void> updateBackendUrl(String newUrl) async {
    _apiService.updateBaseUrl(newUrl);
    notifyListeners();
    try {
      await Future.wait([fetchStatus(), fetchPlan(), fetchHistory()]);
    } catch (_) {}
  }

  Future<void> fetchStatus({String? courseId}) async {
    try {
      final targetCourse = (courseId != null && courseId.isNotEmpty)
          ? courseId
          : _currentCourseId;
      final newStatus = await _apiService.fetchSessionStatus(
        courseId: targetCourse,
      );
      if (newStatus.courseId.isNotEmpty) {
        _currentCourseId = newStatus.courseId;
      }
      if (_sessionStatus == null ||
          _sessionStatus?.status != newStatus.status ||
          _sessionStatus?.currentConceptId != newStatus.currentConceptId ||
          _sessionStatus?.pedagogicalState != newStatus.pedagogicalState ||
          _sessionStatus?.planProgressPercentage !=
              newStatus.planProgressPercentage ||
          _sessionStatus?.planStep != newStatus.planStep) {
        _sessionStatus = newStatus;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> fetchTranscript({String? courseId}) async {
    try {
      final targetCourse = (courseId != null && courseId.isNotEmpty)
          ? courseId
          : _currentCourseId;
      final turns = await _apiService.fetchTranscript(courseId: targetCourse);

      // Compare by both count AND the last turn's timestamp to catch backend corrections
      // where the turn count stays the same but content/transcript is updated.
      final lastTimestampNew = turns.isNotEmpty ? turns.last.timestamp : '';
      final lastTimestampOld = _transcriptTurns.isNotEmpty
          ? _transcriptTurns.last.timestamp
          : '';
      if (_transcriptTurns.length != turns.length ||
          lastTimestampNew != lastTimestampOld) {
        _transcriptTurns = turns;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> fetchPlan({String? courseId}) async {
    try {
      final targetCourse = (courseId != null && courseId.isNotEmpty)
          ? courseId
          : _currentCourseId;
      _examinationPlan = await _apiService.fetchPlan(courseId: targetCourse);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> fetchComparison({String? courseId}) async {
    try {
      final targetCourse = (courseId != null && courseId.isNotEmpty)
          ? courseId
          : _currentCourseId;
      _comparisonReport = await _apiService.fetchComparison(
        courseId: targetCourse,
      );
      notifyListeners();
    } catch (_) {}
  }

  Future<void> fetchHistory({String? courseId}) async {
    try {
      final rawList = await _apiService.fetchHistory(courseId: courseId);
      _historyList = rawList;
      final seenIds = <String>{};
      final uniqueItems = <SessionHistoryItem>[];
      for (final raw in rawList) {
        final item = SessionHistoryItem.fromJson(raw);
        final key = item.id.isNotEmpty ? item.id : 'iter_${item.iteration}';
        if (!seenIds.contains(key)) {
          seenIds.add(key);
          uniqueItems.add(item);
        }
      }
      _historyItems = uniqueItems;
      notifyListeners();
    } catch (_) {}
  }

  Future<List<DialogueTurn>> fetchTranscriptForIteration(
    int iteration, {
    String? courseId,
  }) async {
    try {
      return await _apiService.fetchTranscript(
        iteration: iteration,
        courseId: courseId,
      );
    } catch (_) {
      return [];
    }
  }

  String _resolvePipecatSignalingUrl() {
    // Use the reachable API origin selected by health discovery, not the
    // localhost server_url echoed by the backend for requests from a phone.
    final apiUri = Uri.parse(_apiService.baseUrl);
    final host =
        (apiUri.host == 'localhost' || apiUri.host == '127.0.0.1') &&
            defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : apiUri.host;
    return Uri(
      scheme: apiUri.scheme == 'https' ? 'https' : 'http',
      host: host,
      port: apiUri.hasPort ? apiUri.port : null,
      path: '/api/offer',
    ).toString();
  }

  /// Proactively prewarms the Pipecat session token in background.
  Future<void> prewarmExamSession({String? courseId}) async {
    final targetCourse = (courseId != null && courseId.isNotEmpty)
        ? courseId
        : (_currentCourseId ?? _sessionStatus?.courseId);

    try {
      final token = await _apiService.warmupSession(courseId: targetCourse);
      if (token != null) {
        _prewarmedSession = token;
        _prewarmedCourseId = targetCourse;
        debugPrint(
          '🔥 Pipecat prewarmed session acquired (Course: $targetCourse)',
        );
      }
    } catch (e) {
      debugPrint('Prewarm exam session error: $e');
    }
  }

  Future<void> startExam({
    String? roomName,
    String? courseId,
    String participantIdentity = 'student_default',
    String participantName = 'Studente',
    bool waitForAiInteraction = true,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final effectiveCourseId = (courseId != null && courseId.isNotEmpty)
        ? courseId
        : _currentCourseId;
    if (effectiveCourseId != null && effectiveCourseId.isNotEmpty) {
      _currentCourseId = effectiveCourseId;
    }

    try {
      // 1. Check if a prewarmed session matching this course is already available
      if (roomName == null &&
          _prewarmedSession != null &&
          (_prewarmedCourseId == effectiveCourseId ||
              (_prewarmedCourseId == null && effectiveCourseId == null))) {
        _prewarmedSession = null;
        debugPrint('⚡ Using prewarmed Pipecat session token');
      } else {
        // Generate deterministic course-scoped room name so backend knows which document is loaded
        final effectiveRoomName =
            roomName ??
            (effectiveCourseId != null && effectiveCourseId.isNotEmpty
                ? 'oral-exam-$effectiveCourseId-${DateTime.now().millisecondsSinceEpoch}'
                : 'oral-exam-${DateTime.now().millisecondsSinceEpoch}');

        // Fetch fresh Token from backend REST API
        await _apiService.fetchToken(
          roomName: effectiveRoomName,
          participantIdentity: participantIdentity,
          participantName: participantName,
          courseId: effectiveCourseId,
        );
      }

      final signalingUrl = _resolvePipecatSignalingUrl();
      debugPrint('🔌 Connecting to Pipecat WebRTC: $signalingUrl');
      await _pipecatService.connectWebRtc(
        signalingUrl: signalingUrl,
        courseId: effectiveCourseId,
      );

      // 3. Start Periodic Telemetry & Transcript Polling
      _startPolling();

      // 4. Wait for initial AI voice interaction before transitioning
      if (waitForAiInteraction) {
        await _pipecatService.waitForFirstAiInteraction();
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Errore avvio esame: $e';
      notifyListeners();
      rethrow;
    }
  }

  bool _pollingInFlight = false;

  void _startPolling() {
    _statusPollingTimer?.cancel();
    _statusPollingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      // Back-pressure guard: skip this tick if the previous poll is still in-flight.
      // Prevents duplicate requests when the network is slow (>2s response time).
      if (_pollingInFlight) return;
      _pollingInFlight = true;
      try {
        await Future.wait([fetchStatus(), fetchTranscript()]);
      } finally {
        _pollingInFlight = false;
      }
    });
  }

  void _stopPolling() {
    _statusPollingTimer?.cancel();
    _statusPollingTimer = null;
  }

  Future<void> toggleMicrophone() async {
    await _pipecatService.toggleMicrophone();
    notifyListeners();
  }

  Future<void> toggleSpeakerphone() async {
    await _pipecatService.toggleSpeakerphone();
    notifyListeners();
  }

  Future<void> setVolume(double volume) async {
    await _pipecatService.setVolume(volume);
  }

  Future<void> pauseExam({String? courseId}) async {
    try {
      _stopPolling();
      await _pipecatService.disconnect();
      final targetCourse = (courseId != null && courseId.isNotEmpty)
          ? courseId
          : _currentCourseId;
      await _apiService.pauseSession(courseId: targetCourse);
      await fetchStatus(courseId: targetCourse);
      await fetchHistory();
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

    final effectiveCourseId = (courseId != null && courseId.isNotEmpty)
        ? courseId
        : _currentCourseId;
    if (effectiveCourseId != null && effectiveCourseId.isNotEmpty) {
      _currentCourseId = effectiveCourseId;
    }

    try {
      if (effectiveCourseId != null && effectiveCourseId.isNotEmpty) {
        await _apiService.activateCourse(effectiveCourseId);
      }
      await _apiService.resumeSession(courseId: effectiveCourseId);
      await Future.wait([
        startExam(courseId: effectiveCourseId),
        fetchStatus(courseId: effectiveCourseId),
        fetchPlan(courseId: effectiveCourseId),
        fetchHistory(),
      ]);
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
      }
      // 1. Initialize a completely fresh, isolated discussion on the server
      final res = await _apiService.createNewDiscussion(courseId: courseId);
      final assignedRoom =
          res['room_name'] as String? ??
          (courseId != null && courseId.isNotEmpty
              ? 'oral-exam-$courseId-${DateTime.now().millisecondsSinceEpoch}'
              : 'oral-exam-${DateTime.now().millisecondsSinceEpoch}');
      _transcriptTurns = [];

      // 2. Start voice session and preload status, plan, and history in parallel
      await Future.wait([
        startExam(roomName: assignedRoom, courseId: courseId),
        fetchStatus(courseId: courseId),
        fetchPlan(courseId: courseId),
        fetchHistory(),
      ]);
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
      await Future.wait([fetchHistory(), fetchStatus(), fetchPlan()]);
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
      if (courseId != null && courseId.isNotEmpty) {
        _currentCourseId = courseId;
      }
      _transcriptTurns = [];
      await Future.wait([fetchPlan(), fetchStatus(), fetchHistory()]);
      await startExam(courseId: courseId);
      unawaited(Future.wait([fetchStatus(), fetchHistory()]));
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Errore caricamento documento: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> generateExamFromTopic({
    required String topic,
    String? title,
    String level = 'intermedio',
    int durationMinutes = 20,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _apiService.generateExamFromTopic(
        topic: topic,
        title: title,
        level: level,
        durationMinutes: durationMinutes,
      );
      final courseId = res['course_id'] as String?;
      if (courseId != null && courseId.isNotEmpty) {
        _currentCourseId = courseId;
      }
      _transcriptTurns = [];
      await Future.wait([fetchPlan(), fetchStatus(), fetchHistory()]);
      _isLoading = false;
      notifyListeners();
      return res;
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
    await _pipecatService.disconnect();
    try {
      // Archive completed session on backend into history
      await _apiService.repeatSession(adapt: false);
      _diagnosticReport = await _apiService.fetchDiagnosticReport();
      await Future.wait([fetchComparison(), fetchHistory(), fetchStatus()]);
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
    unawaited(_pipecatService.dispose());
    _apiService.close();
    super.dispose();
  }
}
