import 'dart:convert';
import 'dart:io';

import '../data/level_up_models.dart';

class AiTaskPlanRequest {
  const AiTaskPlanRequest({
    required this.goalTitle,
    required this.category,
    required this.deadline,
    required this.daysPerWeek,
    required this.minutesPerSession,
    required this.preferredWeekdays,
  });

  final String goalTitle;
  final String category;
  final DateTime deadline;
  final int daysPerWeek;
  final int minutesPerSession;
  final List<int> preferredWeekdays;
}

class AiTaskPlanResult {
  const AiTaskPlanResult({required this.tasks, required this.note});

  final List<Milestone> tasks;
  final String note;
}

class AiFutureImageRequest {
  const AiFutureImageRequest({
    required this.sourceImagePath,
    required this.vision,
    required this.areaVisions,
  });

  final String sourceImagePath;
  final String vision;
  final Map<String, String> areaVisions;
}

class AiFutureImageResult {
  const AiFutureImageResult({required this.imageUrl});

  final String imageUrl;
}

class AiService {
  const AiService({String? baseUrl}) : this._(baseUrl);

  const AiService._(this._baseUrl);

  static const instance = AiService();
  static const _envBaseUrl = String.fromEnvironment('LEVELUP_AI_BASE_URL');

  final String? _baseUrl;

  String get _effectiveBaseUrl => (_baseUrl ?? _envBaseUrl).trim();
  bool get hasBackend => _effectiveBaseUrl.isNotEmpty;

  Future<AiTaskPlanResult> generateTaskPlan(AiTaskPlanRequest request) async {
    if (hasBackend) {
      final backendResult = await _generateTaskPlanFromBackend(request);
      if (backendResult != null) return backendResult;
    }
    return _generateLocalTaskPlan(request);
  }

  Future<AiFutureImageResult?> generateFutureImage(
    AiFutureImageRequest request,
  ) async {
    if (!hasBackend) return null;
    final sourceFile = File(request.sourceImagePath);
    if (!sourceFile.existsSync()) return null;

    final imageBytes = await sourceFile.readAsBytes();
    final uri = Uri.parse('$_effectiveBaseUrl/futureImage');
    final httpRequest = await HttpClient().postUrl(uri);
    httpRequest.headers.contentType = ContentType.json;
    httpRequest.write(
      jsonEncode({
        'sourceImageBase64': base64Encode(imageBytes),
        'sourceImageMimeType': _mimeTypeForPath(request.sourceImagePath),
        'vision': request.vision,
        'areaVisions': request.areaVisions,
      }),
    );

    final response = await httpRequest.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) return null;

    final json = jsonDecode(body) as Map<String, dynamic>;
    final imageUrl = (json['imageUrl'] ?? '').toString().trim();
    if (imageUrl.isEmpty) return null;
    return AiFutureImageResult(imageUrl: imageUrl);
  }

  Future<AiTaskPlanResult?> _generateTaskPlanFromBackend(
    AiTaskPlanRequest request,
  ) async {
    try {
      final uri = Uri.parse('$_effectiveBaseUrl/taskPlan');
      final httpRequest = await HttpClient().postUrl(uri);
      httpRequest.headers.contentType = ContentType.json;
      httpRequest.write(
        jsonEncode({
          'goalTitle': request.goalTitle,
          'category': request.category,
          'deadline': request.deadline.toIso8601String(),
          'daysPerWeek': request.daysPerWeek,
          'minutesPerSession': request.minutesPerSession,
          'preferredWeekdays': request.preferredWeekdays,
        }),
      );

      final response = await httpRequest.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final json = jsonDecode(body) as Map<String, dynamic>;
      final tasks = (json['tasks'] as List? ?? []).whereType<Map>().map((item) {
        final dueDateRaw = item['dueDate']?.toString();
        return Milestone(
          id: 'ai_${DateTime.now().microsecondsSinceEpoch}',
          title: (item['title'] ?? 'AI task').toString(),
          subtitle: (item['subtitle'] ?? '').toString(),
          dueDate: dueDateRaw == null ? null : DateTime.tryParse(dueDateRaw),
          repeatsDaily: item['repeatsDaily'] == true,
          repeatWeekdays: (item['repeatWeekdays'] as List? ?? [])
              .map(
                (value) => value is int ? value : int.tryParse('$value') ?? 0,
              )
              .where((value) => value >= 1 && value <= 7)
              .toList(),
        );
      }).toList();
      if (tasks.isEmpty) return null;
      return AiTaskPlanResult(
        tasks: tasks,
        note: (json['note'] ?? 'AI drafted a task plan.').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  AiTaskPlanResult _generateLocalTaskPlan(AiTaskPlanRequest request) {
    final title = request.goalTitle.toLowerCase();
    if (title.contains('book') || title.contains('knih')) {
      return _bookPlan(request);
    }
    if (title.contains('run') ||
        title.contains('běh') ||
        title.contains('behat') ||
        title.contains('10k') ||
        title.contains('10 km')) {
      return _runningPlan(request);
    }
    return _habitPlan(request);
  }

  AiTaskPlanResult _bookPlan(AiTaskPlanRequest request) {
    final now = DateTime.now();
    final totalMonths = _monthSpan(now, request.deadline).clamp(1, 12);
    final tasks = <Milestone>[];
    for (var i = 0; i < totalMonths; i++) {
      final dueDate = DateTime(now.year, now.month + i + 1, now.day);
      tasks.add(
        Milestone(
          id: 'ai_book_$i',
          title: 'Finish book ${i + 1}',
          subtitle: 'One book this month',
          dueDate: dueDate.isAfter(request.deadline)
              ? request.deadline
              : dueDate,
        ),
      );
    }
    return AiTaskPlanResult(
      tasks: tasks,
      note:
          'Drafted a monthly reading plan. Review titles and dates before saving.',
    );
  }

  AiTaskPlanResult _runningPlan(AiTaskPlanRequest request) {
    final days = request.preferredWeekdays.isEmpty
        ? _defaultWeekdays(request.daysPerWeek)
        : request.preferredWeekdays;
    return AiTaskPlanResult(
      tasks: [
        Milestone(
          id: 'ai_run_easy',
          title: 'Easy run',
          subtitle: '${request.minutesPerSession} min base run',
          repeatWeekdays: days,
        ),
        Milestone(
          id: 'ai_run_progress',
          title: 'Progressive run',
          subtitle: 'Increase distance gradually each week',
          repeatWeekdays: days.take(1).toList(),
        ),
        Milestone(
          id: 'ai_run_10k',
          title: 'Run 10 km',
          subtitle: 'Goal check',
          dueDate: request.deadline,
        ),
      ],
      note:
          'Drafted a progressive running plan. Adjust intensity to your real level.',
    );
  }

  AiTaskPlanResult _habitPlan(AiTaskPlanRequest request) {
    final days = request.preferredWeekdays.isEmpty
        ? _defaultWeekdays(request.daysPerWeek)
        : request.preferredWeekdays;
    return AiTaskPlanResult(
      tasks: [
        Milestone(
          id: 'ai_focus',
          title: 'Focused work session',
          subtitle: '${request.minutesPerSession} min',
          repeatWeekdays: days,
        ),
        Milestone(
          id: 'ai_review',
          title: 'Weekly progress review',
          subtitle: 'Adjust next week',
          repeatWeekdays: const [7],
        ),
        Milestone(
          id: 'ai_finish',
          title: 'Reach the goal outcome',
          subtitle: 'Final check',
          dueDate: request.deadline,
        ),
      ],
      note: 'Drafted a simple work plan. Tune the tasks before saving.',
    );
  }

  List<int> _defaultWeekdays(int daysPerWeek) {
    const patterns = {
      1: [1],
      2: [1, 4],
      3: [1, 3, 5],
      4: [1, 2, 4, 6],
      5: [1, 2, 3, 4, 5],
      6: [1, 2, 3, 4, 5, 6],
    };
    return patterns[daysPerWeek.clamp(1, 6)] ?? const [1, 3, 5];
  }

  int _monthSpan(DateTime start, DateTime end) {
    return (end.year - start.year) * 12 + end.month - start.month;
  }

  String _mimeTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
