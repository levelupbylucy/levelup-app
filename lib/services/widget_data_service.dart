import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/level_up_models.dart';

class WidgetDataService {
  const WidgetDataService();

  static const MethodChannel _channel = MethodChannel('levelup/widget_data');

  Future<void> update({
    required int todayCompletedTasks,
    required int todayTotalTasks,
    required int currentStreak,
    required String todayFocusTask,
    required String todayFocusGoal,
    required String futureVision,
    required int visionClarity,
    required List<String> identityTags,
    required String currentGoalTitle,
    required int currentGoalProgress,
    required String currentGoalTask,
    required String currentGoalTargetDate,
    required String quoteOfTheDay,
    required List<DailyTask> todayTasks,
  }) async {
    if (_isFlutterTest) return;

    try {
      await _channel
          .invokeMethod<void>('updateWidgetData', {
            'todayCompletedTasks': todayCompletedTasks,
            'todayTotalTasks': todayTotalTasks,
            'currentStreak': currentStreak,
            'todayFocusTask': todayFocusTask,
            'todayFocusGoal': todayFocusGoal,
            'futureVision': futureVision,
            'visionClarity': visionClarity,
            'identityTags': identityTags,
            'currentGoalTitle': currentGoalTitle,
            'currentGoalProgress': currentGoalProgress,
            'currentGoalTask': currentGoalTask,
            'currentGoalTargetDate': currentGoalTargetDate,
            'quoteOfTheDay': quoteOfTheDay,
            'widget_streak': currentStreak,
            'widget_completed_tasks': todayCompletedTasks,
            'widget_total_tasks': todayTotalTasks,
            'widget_quote': quoteOfTheDay,
            'widget_tasks_json': jsonEncode(
              todayTasks
                  .take(3)
                  .map(
                    (task) => {
                      'title': task.title,
                      'completed': task.completed,
                    },
                  )
                  .toList(),
            ),
            'widget_last_updated': DateTime.now().toIso8601String(),
          })
          .timeout(const Duration(seconds: 2));
    } on MissingPluginException {
      // WidgetKit data sharing is only available on iOS builds.
    } on TimeoutException {
      // Flutter tests can leave platform channels unresolved.
    }
  }

  bool get _isFlutterTest =>
      Platform.environment.containsKey('FLUTTER_TEST') ||
      Platform.environment.containsKey('DART_TEST') ||
      WidgetsBinding.instance.runtimeType.toString().contains(
        'TestWidgetsFlutterBinding',
      );
}
