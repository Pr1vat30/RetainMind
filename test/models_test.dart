import 'package:flutter_test/flutter_test.dart';
import 'package:retain_mind_def/models/session_models.dart';

void main() {
  group('Session models serialization tests', () {
    test('TokenResponse.fromJson parses valid payload', () {
      final json = {
        'participant_token': 'mock-livekit-jwt',
        'server_url': 'wss://test.livekit.cloud',
        'room_name': 'oral-exam-test',
        'participant_identity': 'student-123',
        'participant_name': 'Mario Rossi',
      };
      final res = TokenResponse.fromJson(json);
      expect(res.participantToken, 'mock-livekit-jwt');
      expect(res.serverUrl, 'wss://test.livekit.cloud');
      expect(res.roomName, 'oral-exam-test');
      expect(res.participantIdentity, 'student-123');
      expect(res.participantName, 'Mario Rossi');
    });

    test('SessionStatusInfo.fromJson parses pedagogic states and progress', () {
      final json = {
        'has_active_session': true,
        'status': 'IN_PROGRESS',
        'student_id': 'stud-01',
        'current_concept_id': 'CAP_Theorem',
        'pedagogical_state': 'SCAFFOLDING',
        'current_iteration': 1,
        'plan_progress_percentage': 72.5,
        'plan_step': '3/6',
        'deferred_queue': ['ACID_Transactions'],
      };
      final status = SessionStatusInfo.fromJson(json);
      expect(status.hasActiveSession, isTrue);
      expect(status.status, 'IN_PROGRESS');
      expect(status.studentId, 'stud-01');
      expect(status.currentConceptId, 'CAP_Theorem');
      expect(status.pedagogicalState, 'SCAFFOLDING');
      expect(status.currentIteration, 1);
      expect(status.planProgressPercentage, 72.5);
      expect(status.planStep, '3/6');
      expect(status.deferredQueue, contains('ACID_Transactions'));
    });

    test('DiagnosticReport.fromJson parses report fields accurately', () {
      final json = {
        'student_id': 'stud-01',
        'total_turns': 12,
        'overall_mastery_score': 84.5,
        'exam_passed': true,
        'mastered_concepts': ['CAP_Theorem', 'NoSQL_Data_Models'],
        'struggling_concepts': ['Consistency_Models'],
        'root_cause_prerequisites': ['Distributed_Transactions'],
        'spokenSummary': 'Ottima preparazione complessiva.',
      };
      final report = DiagnosticReport.fromJson(json);
      expect(report.studentId, 'stud-01');
      expect(report.totalTurns, 12);
      expect(report.overallMasteryScore, 84.5);
      expect(report.examPassed, isTrue);
      expect(report.masteredConcepts, contains('CAP_Theorem'));
      expect(report.strugglingConcepts, contains('Consistency_Models'));
      expect(report.rootCausePrerequisites, contains('Distributed_Transactions'));
    });

    test('SessionHistoryItem.fromJson parses iteration history item', () {
      final json = {
        'iteration': 2,
        'title': 'Conversazione #2',
        'status': 'COMPLETED',
        'is_current': false,
        'turns_completed': 8,
        'average_mastery': 0.85,
        'mastered_concepts': ['Sharding', 'Replication'],
        'weak_concepts': ['CAP_Theorem'],
        'active_concept_id': 'Replication',
        'timestamp': '2026-10-20T10:30:00Z',
        'created_at': '2026-10-19T08:00:00Z',
        'updated_at': '2026-10-21T14:00:00Z',
        'session_dates': ['2026-10-19', '2026-10-20', '2026-10-21'],
      };
      final item = SessionHistoryItem.fromJson(json);
      expect(item.iteration, 2);
      expect(item.title, 'Conversazione #2');
      expect(item.status, 'COMPLETED');
      expect(item.isCurrent, isFalse);
      expect(item.turnsCompleted, 8);
      expect(item.averageMastery, 0.85);
      expect(item.masteredConcepts, contains('Sharding'));
      expect(item.weakConcepts, contains('CAP_Theorem'));
      expect(item.timestamp, '2026-10-20T10:30:00Z');
      expect(item.createdAt, '2026-10-19T08:00:00Z');
      expect(item.updatedAt, '2026-10-21T14:00:00Z');
      expect(item.sessionDates, containsAll(['2026-10-19', '2026-10-20', '2026-10-21']));
      expect(item.parsedSessionDates.length, 3);
      expect(item.parsedSessionDates.first, DateTime(2026, 10, 19));
    });

    test('DialogueTurn.fromJson parses turn with both AI question and student response', () {
      final json = {
        'turn': 3,
        'ai_question': 'Cos\'è lo sharding orizzontale?',
        'student_response': 'È una tecnica per distribuire righe di dati su più nodi.',
        'concept_id': 'sharding',
        'outcome': 'ACCURATE',
        'next_state': 'EXPLORATION',
        'score_delta': 0.15,
        'timestamp': '2026-10-20T10:31:00Z',
      };
      final turn = DialogueTurn.fromJson(json);
      expect(turn.turnNumber, 3);
      expect(turn.aiQuestion, 'Cos\'è lo sharding orizzontale?');
      expect(turn.studentResponse, 'È una tecnica per distribuire righe di dati su più nodi.');
      expect(turn.conceptId, 'sharding');
      expect(turn.evaluationOutcome, 'ACCURATE');
      expect(turn.scoreDelta, 0.15);
    });
  });
}
