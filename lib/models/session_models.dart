class TokenResponse {
  final String serverUrl;
  final String participantToken;
  final String roomName;
  final String participantIdentity;
  final String participantName;

  TokenResponse({
    required this.serverUrl,
    required this.participantToken,
    required this.roomName,
    required this.participantIdentity,
    required this.participantName,
  });

  factory TokenResponse.fromJson(Map<String, dynamic> json) {
    return TokenResponse(
      serverUrl: json['server_url'] as String? ?? '',
      participantToken: json['participant_token'] as String? ?? '',
      roomName: json['room_name'] as String? ?? '',
      participantIdentity: json['participant_identity'] as String? ?? '',
      participantName: json['participant_name'] as String? ?? '',
    );
  }
}

class SessionStatusInfo {
  final bool hasActiveSession;
  final String status;
  final String studentId;
  final String currentConceptId;
  final String pedagogicalState;
  final int currentIteration;
  final double planProgressPercentage;
  final String planStep;
  final List<String> deferredQueue;

  SessionStatusInfo({
    required this.hasActiveSession,
    required this.status,
    required this.studentId,
    required this.currentConceptId,
    required this.pedagogicalState,
    required this.currentIteration,
    required this.planProgressPercentage,
    required this.planStep,
    required this.deferredQueue,
  });

  factory SessionStatusInfo.fromJson(Map<String, dynamic> json) {
    return SessionStatusInfo(
      hasActiveSession: json['has_active_session'] as bool? ?? false,
      status: json['status'] as String? ?? 'NOT_INITIALIZED',
      studentId: json['student_id'] as String? ?? '',
      currentConceptId: json['current_concept_id'] as String? ?? '',
      pedagogicalState: json['pedagogical_state'] as String? ?? 'EXPLORATION',
      currentIteration: json['current_iteration'] as int? ?? 1,
      planProgressPercentage: (json['plan_progress_percentage'] as num?)?.toDouble() ?? 0.0,
      planStep: json['plan_step'] as String? ?? '0/0',
      deferredQueue: (json['deferred_queue'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

class DialogueTurn {
  final int turnNumber;
  final String role; // 'examiner' | 'student' | 'system'
  final String content;
  final String aiQuestion;
  final String studentResponse;
  final String conceptId;
  final String evaluationOutcome;
  final String pedagogicalState;
  final double scoreDelta;
  final String timestamp;

  DialogueTurn({
    required this.turnNumber,
    required this.role,
    required this.content,
    this.aiQuestion = '',
    this.studentResponse = '',
    required this.conceptId,
    required this.evaluationOutcome,
    required this.pedagogicalState,
    required this.scoreDelta,
    required this.timestamp,
  });

  factory DialogueTurn.fromJson(Map<String, dynamic> json) {
    final studentText = json['student_response'] as String? ??
        json['student_transcript'] as String? ??
        '';
    final aiQ = json['ai_question'] as String? ??
        json['directive'] as String? ??
        '';
    final rawContent = json['content'] as String? ??
        (studentText.isNotEmpty ? studentText : aiQ);

    return DialogueTurn(
      turnNumber: json['turn_number'] as int? ?? json['turn'] as int? ?? 0,
      role: json['role'] as String? ??
          (studentText.isNotEmpty ? 'student' : 'assistant'),
      content: rawContent.isNotEmpty
          ? rawContent
          : (json['transcript'] as String? ?? ''),
      aiQuestion: aiQ,
      studentResponse: studentText,
      conceptId: json['concept_id'] as String? ??
          json['concept_name'] as String? ??
          '',
      evaluationOutcome: json['outcome'] as String? ??
          json['evaluation_outcome'] as String? ??
          json['evaluation_result'] as String? ??
          json['evaluation'] as String? ??
          '',
      pedagogicalState: json['pedagogical_state'] as String? ??
          json['next_state'] as String? ??
          '',
      scoreDelta: (json['score_delta'] as num?)?.toDouble() ??
          (json['mastery_delta'] as num?)?.toDouble() ??
          0.0,
      timestamp: json['timestamp'] as String? ?? '',
    );
  }
}

class SessionHistoryItem {
  final int iteration;
  final String title;
  final String status;
  final bool isCurrent;
  final int turnsCompleted;
  final double? averageMastery;
  final List<String> masteredConcepts;
  final List<String> weakConcepts;
  final String activeConceptId;
  final String timestamp;
  final String createdAt;
  final String updatedAt;
  final List<String> sessionDates;
  final String planTitle;
  final List<ConceptItemModel> concepts;
  final String id;
  final String filename;
  final int totalConcepts;

  SessionHistoryItem({
    required this.iteration,
    required this.title,
    required this.status,
    required this.isCurrent,
    required this.turnsCompleted,
    this.averageMastery,
    this.masteredConcepts = const [],
    this.weakConcepts = const [],
    this.activeConceptId = '',
    this.timestamp = '',
    this.createdAt = '',
    this.updatedAt = '',
    this.sessionDates = const [],
    this.planTitle = '',
    this.concepts = const [],
    this.id = '',
    this.filename = '',
    this.totalConcepts = 0,
  });

  /// Returns all unique calendar dates (midnight) on which this session was active
  List<DateTime> get parsedSessionDates {
    final dates = <DateTime>{};
    for (final str in sessionDates) {
      final parsed = DateTime.tryParse(str);
      if (parsed != null) {
        dates.add(DateTime(parsed.year, parsed.month, parsed.day));
      }
    }
    for (final str in [timestamp, createdAt, updatedAt]) {
      if (str.isNotEmpty) {
        final parsed = DateTime.tryParse(str);
        if (parsed != null) {
          dates.add(DateTime(parsed.year, parsed.month, parsed.day));
        }
      }
    }
    return dates.toList()..sort();
  }

  factory SessionHistoryItem.fromJson(Map<String, dynamic> json) {
    final itNum = json['iteration'] as int? ?? 1;
    final isCur = json['is_current'] as bool? ?? false;
    final turnsCount = json['turns_completed'] as int? ??
        (json['history'] as List?)?.length ??
        0;

    final rawConcepts = json['concepts'] as List<dynamic>? ?? [];
    final parsedConcepts = rawConcepts
        .whereType<Map>()
        .map((e) => ConceptItemModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    final cid = json['id'] as String? ?? json['course_id'] as String? ?? '';
    final fname = json['filename'] as String? ?? '';
    final totalC = json['total_concepts'] as int? ?? parsedConcepts.length;
    final sDates = (json['session_dates'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return SessionHistoryItem(
      iteration: itNum,
      title: json['title'] as String? ??
          (isCur ? 'Conversazione #$itNum (In corso)' : 'Conversazione #$itNum'),
      status: json['status'] as String? ?? (isCur ? 'ACTIVE' : 'COMPLETED'),
      isCurrent: isCur,
      turnsCompleted: turnsCount,
      averageMastery: (json['average_mastery'] as num?)?.toDouble(),
      masteredConcepts: (json['mastered_concepts'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      weakConcepts: (json['weak_concepts'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      activeConceptId: json['active_concept_id'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
      sessionDates: sDates,
      planTitle: json['plan_title'] as String? ?? '',
      concepts: parsedConcepts,
      id: cid,
      filename: fname,
      totalConcepts: totalC,
    );
  }
}

class DiagnosticReport {
  final String studentId;
  final int totalTurns;
  final double overallMasteryScore;
  final bool examPassed;
  final List<String> masteredConcepts;
  final List<String> strugglingConcepts;
  final List<String> rootCausePrerequisites;
  final String spokenSummary;

  DiagnosticReport({
    required this.studentId,
    required this.totalTurns,
    required this.overallMasteryScore,
    required this.examPassed,
    required this.masteredConcepts,
    required this.strugglingConcepts,
    required this.rootCausePrerequisites,
    required this.spokenSummary,
  });

  factory DiagnosticReport.fromJson(Map<String, dynamic> json) {
    return DiagnosticReport(
      studentId: json['student_id'] as String? ?? '',
      totalTurns: json['total_turns'] as int? ?? 0,
      overallMasteryScore: (json['overall_mastery_score'] as num?)?.toDouble() ?? 0.0,
      examPassed: json['exam_passed'] as bool? ?? false,
      masteredConcepts: (json['mastered_concepts'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      strugglingConcepts: (json['struggling_concepts'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      rootCausePrerequisites: (json['root_cause_prerequisites'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      spokenSummary: json['spoken_summary'] as String? ?? '',
    );
  }
}

class ConceptItemModel {
  final String conceptId;
  final String conceptName;
  final double difficulty;
  final List<String> prerequisites;
  final String mainQuestion;

  ConceptItemModel({
    required this.conceptId,
    required this.conceptName,
    required this.difficulty,
    required this.prerequisites,
    required this.mainQuestion,
  });

  factory ConceptItemModel.fromJson(Map<String, dynamic> json) {
    return ConceptItemModel(
      conceptId: json['concept_id'] as String? ?? '',
      conceptName: json['concept_name'] as String? ?? '',
      difficulty: (json['difficulty'] as num?)?.toDouble() ?? 1.0,
      prerequisites: (json['prerequisites'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      mainQuestion: json['main_question'] as String? ?? '',
    );
  }
}

class ExaminationPlanModel {
  final bool hasPlan;
  final String title;
  final int totalConcepts;
  final List<String> conceptOrder;
  final List<ConceptItemModel> concepts;

  ExaminationPlanModel({
    required this.hasPlan,
    required this.title,
    required this.totalConcepts,
    required this.conceptOrder,
    required this.concepts,
  });

  factory ExaminationPlanModel.fromJson(Map<String, dynamic> json) {
    final list = (json['concepts'] as List<dynamic>?) ?? [];
    return ExaminationPlanModel(
      hasPlan: json['has_plan'] as bool? ?? false,
      title: json['title'] as String? ?? 'Esame Orale',
      totalConcepts: json['total_concepts'] as int? ?? 0,
      conceptOrder: (json['concept_order'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      concepts: list
          .map((c) => ConceptItemModel.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ComparisonReportModel {
  final bool hasPreviousIterations;
  final String spokenComparison;
  final double? deltaAverageMastery;
  final List<String> recoveredConcepts;
  final List<String> persistentWeakSpots;

  ComparisonReportModel({
    required this.hasPreviousIterations,
    required this.spokenComparison,
    this.deltaAverageMastery,
    this.recoveredConcepts = const [],
    this.persistentWeakSpots = const [],
  });

  factory ComparisonReportModel.fromJson(Map<String, dynamic> json) {
    return ComparisonReportModel(
      hasPreviousIterations: json['has_previous_iterations'] as bool? ?? false,
      spokenComparison: json['spoken_comparison'] as String? ?? '',
      deltaAverageMastery: (json['delta_average_mastery'] as num?)?.toDouble(),
      recoveredConcepts: (json['recovered_concepts'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      persistentWeakSpots: (json['persistent_weak_spots'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

