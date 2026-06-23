import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_app/main.dart';
import 'package:levelup_app/state/level_up_app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders Level Up home screen', (tester) async {
    SharedPreferences.setMockInitialValues({
      'level_up_user': jsonEncode({
        'name': 'Lukas Novak',
        'vision': 'I am healthy and focused.',
        'identities': ['Healthy'],
        'streakDays': 3,
        'onboardingCompleted': true,
      }),
      'level_up_goals': jsonEncode([
        {
          'id': 'goal_half_marathon',
          'category': 'HEALTH',
          'title': 'Run a Half Marathon',
          'detail': 'Oct 2026 · 21 km race',
          'progress': 0.25,
          'vision': 'Run with confidence',
          'timeline': '5K -> 10K -> race day',
          'completed': false,
          'milestones': [
            {'id': 'hm_5k', 'title': 'Run 5 km', 'completed': true},
            {'id': 'hm_10k', 'title': 'Run 10 km', 'completed': false},
          ],
        },
      ]),
      'level_up_tasks': jsonEncode([
        {
          'id': 'task_run',
          'title': 'Run 10 km',
          'subtitle': 'Easy pace training run',
          'category': 'HEALTH',
          'completed': false,
          'goalId': 'goal_half_marathon',
          'plannedFor': DateTime.now().toIso8601String(),
        },
      ]),
    });

    final appState = LevelUpAppState();
    await appState.load();

    await tester.pumpWidget(
      LevelUpScope(
        notifier: appState,
        child: MaterialApp(
          home: HomeScreen(
            onOpenGoal: (_) {},
            onOpenMonth: () {},
            onTaskCompleted: () {},
            onDayCompleted: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('Lukas'), findsWidgets);
    expect(find.text('Today’s Tasks'), findsOneWidget);
    expect(find.text('weekly'), findsOneWidget);

    appState.dispose();
  });

  testWidgets('starts goals and shows completed goals segment', (tester) async {
    SharedPreferences.setMockInitialValues({
      'level_up_user': jsonEncode({
        'name': 'Lukas Novak',
        'vision': 'I am healthy and focused.',
        'identities': ['Healthy'],
        'streakDays': 3,
        'onboardingCompleted': true,
      }),
      'level_up_goals': jsonEncode([
        {
          'id': 'goal_books',
          'category': 'LEARNING',
          'title': 'Read 24 Books',
          'detail': '2026 · two books per month',
          'progress': 0,
          'vision': 'Become a consistent reader',
          'timeline': 'Choose first book → Read weekly → Finish book one',
          'completed': false,
          'milestones': [
            {
              'id': 'books_pick',
              'title': 'Choose first book',
              'completed': false,
            },
          ],
        },
        {
          'id': 'goal_5k_done',
          'category': 'HEALTH',
          'title': 'Run a 5K',
          'detail': 'Completed · 5 km',
          'progress': 1,
          'vision': 'Run with confidence',
          'timeline': 'Started → trained → completed',
          'completed': true,
          'completedAt': DateTime(2026, 6, 10).toIso8601String(),
          'milestones': [
            {'id': '5k_done', 'title': 'Run 5 km', 'completed': true},
          ],
        },
      ]),
      'level_up_tasks': jsonEncode([]),
    });

    final appState = LevelUpAppState();
    await appState.load();

    await tester.pumpWidget(
      LevelUpScope(
        notifier: appState,
        child: MaterialApp(
          home: GoalsScreen(onOpenGoal: (_) {}, resetToken: 0),
        ),
      ),
    );

    expect(find.text('Read 24 Books'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(find.text('Current task'), findsOneWidget);
    expect(appState.tasks.length, 1);

    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();

    expect(find.text('Run a 5K'), findsOneWidget);

    appState.dispose();
  });

  testWidgets('edits Future Me vision and shows area goals', (tester) async {
    SharedPreferences.setMockInitialValues({
      'level_up_user': jsonEncode({
        'name': 'Lukas Novak',
        'vision': 'I am becoming focused.',
        'identities': ['Healthy'],
        'streakDays': 1,
        'onboardingCompleted': true,
      }),
      'level_up_goals': jsonEncode([]),
      'level_up_tasks': jsonEncode([]),
    });

    final appState = LevelUpAppState();
    await appState.load();

    await tester.pumpWidget(
      LevelUpScope(
        notifier: appState,
        child: MaterialApp(home: FutureMeScreen(onOpenGoal: (_) {})),
      ),
    );

    await tester.tap(find.byIcon(CupertinoIcons.pencil).first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(CupertinoTextField).first,
      'I am healthy, calm and financially free.',
    );
    await tester.ensureVisible(find.text('Save visions'));
    await tester.tap(find.text('Save visions'));
    await tester.pumpAndSettle();

    expect(
      appState.user.vision,
      contains('I am healthy, calm and financially free.'),
    );
    expect(
      appState.user.areaVisions.values,
      contains('I am healthy, calm and financially free.'),
    );

    appState.dispose();
  });

  testWidgets('plays motivate inspiration without saved videos', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'level_up_user': jsonEncode({
        'name': 'Lukas Novak',
        'vision': 'I am focused.',
        'identities': ['Healthy'],
        'streakDays': 1,
        'onboardingCompleted': true,
      }),
      'level_up_goals': jsonEncode([]),
      'level_up_tasks': jsonEncode([]),
    });

    final appState = LevelUpAppState();
    await appState.load();

    await tester.pumpWidget(
      LevelUpScope(
        notifier: appState,
        child: const MaterialApp(home: MotivateScreen()),
      ),
    );

    expect(find.textContaining('Lukas'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.bookmark), findsNothing);
    await tester.scrollUntilVisible(
      find.byIcon(CupertinoIcons.play_fill).first,
      280,
    );
    await tester.tap(find.byIcon(CupertinoIcons.play_fill).first);
    await tester.pumpAndSettle();
    expect(find.text('WATCHED'), findsOneWidget);

    appState.dispose();
  });

  testWidgets('counts streak once per completed day from real task history', (
    tester,
  ) async {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));

    SharedPreferences.setMockInitialValues({
      'level_up_user': jsonEncode({
        'name': 'Lukas Novak',
        'vision': 'I am focused.',
        'identities': ['Healthy'],
        'streakDays': 0,
        'onboardingCompleted': true,
      }),
      'level_up_goals': jsonEncode([]),
      'level_up_tasks': jsonEncode([
        {
          'id': 'task_yesterday',
          'title': 'Yesterday complete',
          'subtitle': 'Already done',
          'category': 'HEALTH',
          'completed': true,
          'plannedFor': yesterday.toIso8601String(),
          'completedAt': yesterday.toIso8601String(),
        },
        {
          'id': 'task_today_one',
          'title': 'Today one',
          'subtitle': 'Done already',
          'category': 'HEALTH',
          'completed': true,
          'plannedFor': today.toIso8601String(),
          'completedAt': today.toIso8601String(),
        },
        {
          'id': 'task_today_two',
          'title': 'Today two',
          'subtitle': 'Last step',
          'category': 'HEALTH',
          'completed': false,
          'plannedFor': today.toIso8601String(),
        },
      ]),
    });

    final appState = LevelUpAppState();
    await appState.load();

    expect(appState.user.streakDays, 1);

    await appState.toggleTask('task_today_two');
    expect(appState.user.streakDays, 2);

    await appState.toggleTask('task_today_two');
    expect(appState.user.streakDays, 1);

    await appState.toggleTask('task_today_two');
    expect(appState.user.streakDays, 2);

    appState.dispose();
  });

  testWidgets('loads legacy mission storage into daily tasks', (tester) async {
    SharedPreferences.setMockInitialValues({
      'level_up_user': jsonEncode({
        'name': 'Lukas Novak',
        'vision': 'I am focused.',
        'identities': ['Healthy'],
        'streakDays': 0,
        'onboardingCompleted': true,
      }),
      'level_up_goals': jsonEncode([]),
      'level_up_missions': jsonEncode([
        {
          'id': 'legacy_task',
          'title': 'Legacy task',
          'subtitle': 'Stored under the old key',
          'category': 'HEALTH',
          'completed': false,
          'plannedFor': DateTime.now().toIso8601String(),
        },
      ]),
    });

    final appState = LevelUpAppState();
    await appState.load();

    expect(appState.tasks.single.title, 'Legacy task');

    await appState.toggleTask('legacy_task');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('level_up_tasks'), isNotNull);
    expect(prefs.getString('level_up_missions'), isNull);

    appState.dispose();
  });

  testWidgets('keeps calendar task history after deleting a goal', (
    tester,
  ) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));

    SharedPreferences.setMockInitialValues({
      'level_up_user': jsonEncode({
        'name': 'Lukas Novak',
        'vision': 'I am focused.',
        'identities': ['Healthy'],
        'streakDays': 0,
        'onboardingCompleted': true,
      }),
      'level_up_goals': jsonEncode([
        {
          'id': 'goal_history',
          'category': 'HEALTH',
          'title': 'Protect history',
          'detail': 'Calendar regression check',
          'progress': 0.5,
          'vision': 'Stay consistent',
          'timeline': 'Plan -> do -> review',
          'completed': false,
          'milestones': [
            {'id': 'history_step', 'title': 'Do the thing', 'completed': true},
          ],
        },
      ]),
      'level_up_tasks': jsonEncode([
        {
          'id': 'task_history',
          'title': 'Do the thing',
          'subtitle': 'This should remain in history',
          'category': 'HEALTH',
          'completed': true,
          'goalId': 'goal_history',
          'plannedFor': yesterday.toIso8601String(),
          'completedAt': yesterday.toIso8601String(),
        },
      ]),
    });

    final appState = LevelUpAppState();
    await appState.load();

    expect(appState.taskHistory.any((day) => day.isComplete), isTrue);

    await appState.deleteGoal('goal_history');

    expect(appState.tasks, isEmpty);
    expect(appState.taskHistory.any((day) => day.isComplete), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('level_up_task_history'), isNotNull);

    appState.dispose();
  });

  testWidgets('saves morning and evening reminder settings', (tester) async {
    SharedPreferences.setMockInitialValues({
      'level_up_user': jsonEncode({
        'name': 'Lukas Novak',
        'vision': 'I am focused.',
        'identities': ['Healthy'],
        'streakDays': 0,
        'onboardingCompleted': true,
      }),
      'level_up_goals': jsonEncode([]),
      'level_up_tasks': jsonEncode([]),
    });

    final appState = LevelUpAppState();
    await appState.load();

    await appState.updateReminderSettings(
      appState.reminderSettings.copyWith(
        morningEnabled: false,
        eveningEnabled: true,
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('level_up_reminder_settings');
    expect(raw, isNotNull);
    expect(jsonDecode(raw!)['morningEnabled'], isFalse);
    expect(jsonDecode(raw)['eveningEnabled'], isTrue);

    appState.dispose();
  });
}
