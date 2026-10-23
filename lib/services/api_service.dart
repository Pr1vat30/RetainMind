import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/session_models.dart';

class ApiService {
  String baseUrl;

  /// Persistent HTTP client — reuses TCP connections across requests.
  /// This reduces per-request overhead from ~100ms (new TCP handshake) to ~5ms
  /// on the polling hot-path (every 2 seconds during exam session).
  final http.Client _client = http.Client();

  ApiService({required this.baseUrl});

  /// Must be called when the service is no longer needed to free socket resources.
  void close() => _client.close();

  void updateBaseUrl(String newUrl) {
    baseUrl = newUrl.endsWith('/')
        ? newUrl.substring(0, newUrl.length - 1)
        : newUrl;
  }

  Future<bool> checkHealth() async {
    // 1. Try current configured baseUrl fast
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(milliseconds: 2000));
      if (response.statusCode == 200) return true;
    } catch (_) {}

    // 2. Parallel fallback discovery for physical devices & USB tethering
    final candidates = [
      'http://192.168.1.8:8000', // Host Mac Wi-Fi LAN IP
      'http://192.168.1.15:8000', // Alternate Mac Wi-Fi / Hotspot IP
      'http://10.0.2.2:8000', // Android Emulator
      'http://127.0.0.1:8000', // USB adb reverse or Desktop
    ].where((c) => c != baseUrl).toList();

    try {
      final results = await Future.wait(
        candidates.map((candidate) async {
          try {
            final res = await _client
                .get(Uri.parse('$candidate/health'))
                .timeout(const Duration(milliseconds: 2500));
            if (res.statusCode == 200) {
              return candidate;
            }
          } catch (_) {}
          return null;
        }),
      );

      final workingCandidate = results.firstWhere(
        (c) => c != null,
        orElse: () => null,
      );

      if (workingCandidate != null) {
        updateBaseUrl(workingCandidate);
        return true;
      }
    } catch (_) {}

    return false;
  }

  Future<TokenResponse> fetchToken({
    String roomName = 'oral-exam-room',
    String participantIdentity = 'student_default',
    String participantName = 'Studente',
    String? courseId,
  }) async {
    final payload = <String, dynamic>{
      'room_name': roomName,
      'participant_identity': participantIdentity,
      'participant_name': participantName,
    };
    if (courseId != null && courseId.isNotEmpty) {
      payload['course_id'] = courseId;
    }

    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/token'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return TokenResponse.fromJson(data);
    } else {
      throw Exception(
        'Errore richiesta sessione vocale: ${response.statusCode} - ${response.body}',
      );
    }
  }

  /// Proactively prewarm Pipecat session state upon app start.
  Future<TokenResponse?> warmupSession({String? courseId}) async {
    try {
      final payload = <String, dynamic>{};
      if (courseId != null && courseId.isNotEmpty) {
        payload['course_id'] = courseId;
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/session/warmup'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return TokenResponse.fromJson(data);
      }
    } catch (e) {
      debugPrint('Pipecat session warmup skipped: $e');
    }
    return null;
  }

  Future<SessionStatusInfo> fetchSessionStatus({String? courseId}) async {
    final uri = courseId != null && courseId.isNotEmpty
        ? Uri.parse('$baseUrl/api/session/status?course_id=$courseId')
        : Uri.parse('$baseUrl/api/session/status');
    final response = await _client.get(uri).timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return SessionStatusInfo.fromJson(data);
    } else {
      throw Exception(
        'Impossibile recuperare lo stato: ${response.statusCode}',
      );
    }
  }

  static bool isSilenceOrNoise(String text) {
    final clean = text.trim();
    if (clean.isEmpty ||
        clean == '-' ||
        clean == '—' ||
        clean == '–' ||
        clean == '...' ||
        clean == '--') {
      return true;
    }
    final stripped = clean.replaceAll(
      RegExp(r'[^\p{L}\p{N}]', unicode: true),
      '',
    );
    if (stripped.isEmpty) return true;
    final lower = clean.toLowerCase();
    return lower == 'silenzio' ||
        lower == '[silenzio]' ||
        lower == 'silence' ||
        lower == '[silence]';
  }

  Future<List<DialogueTurn>> fetchTranscript({
    int? iteration,
    String? courseId,
  }) async {
    Uri uri;
    if (courseId != null && courseId.isNotEmpty) {
      uri = Uri.parse('$baseUrl/api/session/transcript?course_id=$courseId');
    } else if (iteration != null) {
      uri = Uri.parse('$baseUrl/api/session/transcript?iteration=$iteration');
    } else {
      uri = Uri.parse('$baseUrl/api/session/transcript');
    }

    final response = await _client.get(uri).timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final turns = data['turns'] as List<dynamic>? ?? [];
      return turns
          .map((t) => DialogueTurn.fromJson(t as Map<String, dynamic>))
          .where((t) => !isSilenceOrNoise(t.studentResponse))
          .toList();
    } else {
      return [];
    }
  }

  Future<bool> activateCourse(String courseId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/courses/activate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'course_id': courseId}),
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> pauseSession({
    String reason = 'Pausa da app mobile',
    String? courseId,
  }) async {
    final payload = <String, dynamic>{'reason': reason};
    if (courseId != null && courseId.isNotEmpty) {
      payload['course_id'] = courseId;
    }
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/session/pause'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 5));

    return response.statusCode == 200;
  }

  Future<bool> resumeSession({String? courseId}) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/session/resume'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'course_id': courseId}),
        )
        .timeout(const Duration(seconds: 5));

    return response.statusCode == 200;
  }

  Future<bool> repeatSession({bool adapt = true, String? courseId}) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/session/repeat'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'adapt': adapt, 'course_id': courseId}),
        )
        .timeout(const Duration(seconds: 5));

    return response.statusCode == 200;
  }

  Future<Map<String, dynamic>> createNewDiscussion({String? courseId}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/session/new'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'course_id': courseId}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(utf8.decode(response.bodyBytes))
            as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  Future<bool> deleteDiscussion(dynamic identifier) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/session/history/$identifier'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> resetSession({bool deletePlan = false}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/session/reset'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'delete_plan': deletePlan}),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<DiagnosticReport?> fetchDiagnosticReport({String? courseId}) async {
    final uri = courseId != null && courseId.isNotEmpty
        ? Uri.parse('$baseUrl/api/session/report?course_id=$courseId')
        : Uri.parse('$baseUrl/api/session/report');
    final response = await http.get(uri).timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return DiagnosticReport.fromJson(data);
    }
    return null;
  }

  Future<ExaminationPlanModel?> fetchPlan({String? courseId}) async {
    try {
      final uri = courseId != null && courseId.isNotEmpty
          ? Uri.parse('$baseUrl/api/plan?course_id=$courseId')
          : Uri.parse('$baseUrl/api/plan');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return ExaminationPlanModel.fromJson(data);
      }
    } catch (_) {}
    return null;
  }

  Future<ComparisonReportModel?> fetchComparison({String? courseId}) async {
    try {
      final uri = courseId != null && courseId.isNotEmpty
          ? Uri.parse('$baseUrl/api/session/compare?course_id=$courseId')
          : Uri.parse('$baseUrl/api/session/compare');
      final response = await http.get(uri).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return ComparisonReportModel.fromJson(data);
      }
    } catch (_) {}
    return null;
  }

  Future<List<Map<String, dynamic>>> fetchHistory({String? courseId}) async {
    try {
      final uri = courseId != null && courseId.isNotEmpty
          ? Uri.parse('$baseUrl/api/session/history?course_id=$courseId')
          : Uri.parse('$baseUrl/api/session/history');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final list = data['history'] as List<dynamic>? ?? [];
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>> uploadDocument({
    String? title,
    String? text,
    String? filename,
    List<int>? fileBytes,
  }) async {
    final uri = Uri.parse('$baseUrl/api/documents/upload');

    if (fileBytes != null && fileBytes.isNotEmpty) {
      final request = http.MultipartRequest('POST', uri);
      if (title != null && title.isNotEmpty) {
        request.fields['title'] = title;
      }
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: filename ?? 'document.pdf',
        ),
      );
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(utf8.decode(response.bodyBytes))
            as Map<String, dynamic>;
      } else {
        throw Exception(
          'Errore caricamento documento: ${response.statusCode} - ${response.body}',
        );
      }
    } else {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'title': title ?? 'Esame Orale',
              'content': text ?? '',
              'filename': filename ?? 'notes.md',
            }),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(utf8.decode(response.bodyBytes))
            as Map<String, dynamic>;
      } else {
        throw Exception(
          'Errore invio note: ${response.statusCode} - ${response.body}',
        );
      }
    }
  }

  Future<Map<String, dynamic>> generateExamFromTopic({
    required String topic,
    String? title,
    String level = 'intermedio',
    int durationMinutes = 20,
  }) async {
    final uri = Uri.parse('$baseUrl/api/courses/generate-from-topic');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'topic': topic,
            if (title != null && title.isNotEmpty) 'title': title,
            'level': level,
            'duration_minutes': durationMinutes,
          }),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } else {
      throw Exception(
        'Errore generazione esame da argomento: ${response.statusCode} - ${response.body}',
      );
    }
  }
}
