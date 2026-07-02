import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../data/level_up_models.dart';

class LucyNotificationCopy {
  const LucyNotificationCopy._();

  static const morningTitle = 'Zpráva od Lucy';
  static const morningBody =
      'Dobré ráno. Dneska stačí začít jedním malým krokem.';

  static const afternoonTitle = 'Lucy se hlásí';
  static const afternoonBody = 'Ještě není pozdě udělat dnes jeden malý krok.';

  static const streakRiskTitle = 'Tvůj streak ještě žije';
  static const streakRiskBody =
      'Stačí dokončit dnešní kroky a momentum pokračuje.';

  static const eveningTitle = 'Krátký check-in od Lucy';
  static const eveningBody = 'Chceš si ještě odškrtnout, co se dnes povedlo?';

  static const completedTitle = 'Lucy je na tebe pyšná';
  static const completedBody = 'Tohle byl silný den. Dneska máš hotovo 🤍';

  static const inactivityTitle = 'Zpráva od Lucy';
  static const inactivityBody = 'Jsem tady. Pojď udělat jeden malý návrat.';

  static const returnTitle = 'Lucy tě vítá zpátky';
  static const returnBody = 'Neřešíme pauzu. Dneska jen navážeme.';

  static const streakMilestones = {
    3: 'Tři dny v řadě. Začínáš budovat momentum.',
    7: 'Týden konzistence. Tohle už není náhoda.',
    14: 'Dva týdny. Tvoje nová verze už má rytmus.',
    30: 'Třicet dní. Tohle je skutečná změna.',
  };
}

class LucyNotificationSnapshot {
  const LucyNotificationSnapshot({
    required this.settings,
    required this.todayTaskCount,
    required this.todayCompletedTaskCount,
    required this.currentStreak,
    required this.now,
  });

  final ReminderSettings settings;
  final int todayTaskCount;
  final int todayCompletedTaskCount;
  final int currentStreak;
  final DateTime now;

  bool get hasTasksToday => todayTaskCount > 0;
  bool get hasCompletedAnyTaskToday => todayCompletedTaskCount > 0;
  bool get hasCompletedAllTasksToday =>
      todayTaskCount > 0 && todayCompletedTaskCount >= todayTaskCount;
  bool get hasIncompleteTasksToday =>
      todayTaskCount > 0 && todayCompletedTaskCount < todayTaskCount;
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const lucyMorningId = 800;
  static const lucyAfternoonCheckId = 1600;
  static const lucyStreakRiskId = 1800;
  static const lucyEveningCheckId = 2030;
  static const lucyCompletedDayId = 2401;
  static const lucyInactivity24hId = 2400;
  static const lucyReturnAfterPauseId = 3000;
  static const lucyStreakMilestoneBaseId = 3100;

  static const _channelId = 'levelup_lucy_messages';
  static const _channelName = 'Zprávy od Lucy';
  static const _lastOpenedAtKey = 'levelup_last_opened_at';
  static const _completedDayNotificationKey =
      'levelup_last_completed_day_notification';
  static const _streakMilestonePrefix = 'levelup_streak_milestone_';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _disabled = false;

  Future<void> initialize() async {
    if (_initialized || _disabled) return;
    if (_isFlutterTest) {
      _disabled = true;
      return;
    }

    tz.initializeTimeZones();
    try {
      final timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (_) {
      // Fall back to the package default if the platform timezone is unavailable.
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    try {
      await _plugin
          .initialize(
            const InitializationSettings(android: android, iOS: darwin),
            onDidReceiveNotificationResponse: (_) {
              // TODO: Route payloads such as levelup://home/tasks once deep-link
              // routing is centralized in the Flutter shell.
            },
          )
          .timeout(const Duration(seconds: 2));
    } on MissingPluginException {
      _disabled = true;
      return;
    } on TimeoutException {
      _disabled = true;
      return;
    }

    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    if (_disabled) return false;

    if (Platform.isIOS || Platform.isMacOS) {
      try {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: true, sound: true)
                .timeout(const Duration(seconds: 2)) ??
            false;
      } on MissingPluginException {
        return false;
      } on TimeoutException {
        return false;
      }
    }

    if (Platform.isAndroid) {
      try {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission()
                .timeout(const Duration(seconds: 2)) ??
            true;
      } on MissingPluginException {
        return false;
      } on TimeoutException {
        return false;
      }
    }

    return true;
  }

  Future<void> scheduleDailyReminders(ReminderSettings settings) async {
    await scheduleDailyLucyNotifications(settings);
  }

  Future<void> scheduleDailyLucyNotifications(ReminderSettings settings) async {
    await initialize();
    if (_disabled) return;
    if (!settings.lucyMessagesEnabled) {
      await cancelLevelUpNotifications();
      return;
    }

    await requestPermission();
    await _safeCancel(lucyMorningId);

    if (settings.morningEnabled) {
      await _scheduleDaily(
        id: lucyMorningId,
        minutesAfterMidnight: 8 * 60,
        title: LucyNotificationCopy.morningTitle,
        body: LucyNotificationCopy.morningBody,
        payload: 'levelup://home/tasks',
      );
    }
  }

  Future<void> evaluateLucyNotificationRules(
    LucyNotificationSnapshot snapshot,
  ) async {
    await initialize();
    if (_disabled) return;

    if (!snapshot.settings.lucyMessagesEnabled) {
      await cancelLevelUpNotifications();
      return;
    }

    await requestPermission();
    await scheduleDailyLucyNotifications(snapshot.settings);

    if (!snapshot.hasCompletedAnyTaskToday && snapshot.hasTasksToday) {
      await _scheduleOneShotTodayOrTomorrow(
        id: lucyAfternoonCheckId,
        minutesAfterMidnight: 16 * 60,
        title: LucyNotificationCopy.afternoonTitle,
        body: LucyNotificationCopy.afternoonBody,
        payload: 'levelup://home/tasks',
        now: snapshot.now,
      );
    } else {
      await _safeCancel(lucyAfternoonCheckId);
    }

    if (snapshot.currentStreak >= 2 && snapshot.hasIncompleteTasksToday) {
      await _scheduleOneShotTodayOrTomorrow(
        id: lucyStreakRiskId,
        minutesAfterMidnight: 18 * 60,
        title: LucyNotificationCopy.streakRiskTitle,
        body: LucyNotificationCopy.streakRiskBody,
        payload: 'levelup://home/tasks',
        now: snapshot.now,
      );
    } else {
      await _safeCancel(lucyStreakRiskId);
    }

    if (snapshot.settings.eveningEnabled && snapshot.hasIncompleteTasksToday) {
      await _scheduleOneShotTodayOrTomorrow(
        id: lucyEveningCheckId,
        minutesAfterMidnight: 20 * 60 + 30,
        title: LucyNotificationCopy.eveningTitle,
        body: LucyNotificationCopy.eveningBody,
        payload: 'levelup://home/tasks',
        now: snapshot.now,
      );
    } else {
      await _safeCancel(lucyEveningCheckId);
    }

    if (snapshot.hasCompletedAllTasksToday) {
      await cancelCompletedDayReminders();
    }

    await scheduleInactivityNotification(snapshot.settings, now: snapshot.now);
    await scheduleStreakMilestoneNotification(
      snapshot.currentStreak,
      settings: snapshot.settings,
    );
  }

  Future<void> markAppOpenedAndScheduleInactivity(
    ReminderSettings settings,
  ) async {
    await _saveLastOpenedAt(DateTime.now());
    await scheduleInactivityNotification(settings);
  }

  Future<void> scheduleInactivityNotification(
    ReminderSettings settings, {
    DateTime? now,
  }) async {
    await initialize();
    if (_disabled || !settings.lucyMessagesEnabled) return;

    final base = now ?? DateTime.now();
    await _scheduleOneShotAt(
      id: lucyInactivity24hId,
      scheduledDate: base.add(const Duration(hours: 24)),
      title: LucyNotificationCopy.inactivityTitle,
      body: LucyNotificationCopy.inactivityBody,
      payload: 'levelup://home',
    );
    await _scheduleOneShotAt(
      id: lucyReturnAfterPauseId,
      scheduledDate: base.add(const Duration(days: 3)),
      title: LucyNotificationCopy.returnTitle,
      body: LucyNotificationCopy.returnBody,
      payload: 'levelup://home',
    );
  }

  Future<void> cancelCompletedDayReminders() async {
    await _safeCancel(lucyAfternoonCheckId);
    await _safeCancel(lucyStreakRiskId);
    await _safeCancel(lucyEveningCheckId);
  }

  Future<void> showAllGoalsCompletedNotification({DateTime? now}) async {
    await initialize();
    if (_disabled) return;

    final todayKey = _dayKey(now ?? DateTime.now());
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_completedDayNotificationKey) == todayKey) return;

    await requestPermission();
    await _plugin
        .show(
          lucyCompletedDayId,
          LucyNotificationCopy.completedTitle,
          LucyNotificationCopy.completedBody,
          _notificationDetails(),
          payload: 'levelup://home/progress',
        )
        .timeout(const Duration(seconds: 2));
    await prefs.setString(_completedDayNotificationKey, todayKey);
  }

  Future<void> scheduleStreakMilestoneNotification(
    int streakDays, {
    ReminderSettings settings = const ReminderSettings(),
  }) async {
    await initialize();
    if (_disabled || !settings.lucyMessagesEnabled) return;

    final body = LucyNotificationCopy.streakMilestones[streakDays];
    if (body == null) return;

    final prefs = await SharedPreferences.getInstance();
    final key = '$_streakMilestonePrefix$streakDays';
    if (prefs.getBool(key) ?? false) return;

    await requestPermission();
    await _plugin
        .show(
          lucyStreakMilestoneBaseId + streakDays,
          'Zpráva od Lucy',
          body,
          _notificationDetails(),
          payload: 'levelup://home/progress',
        )
        .timeout(const Duration(seconds: 2));
    await prefs.setBool(key, true);
  }

  Future<void> cancelLevelUpNotifications() async {
    for (final id in [
      lucyMorningId,
      lucyAfternoonCheckId,
      lucyStreakRiskId,
      lucyEveningCheckId,
      lucyCompletedDayId,
      lucyInactivity24hId,
      lucyReturnAfterPauseId,
      lucyStreakMilestoneBaseId + 3,
      lucyStreakMilestoneBaseId + 7,
      lucyStreakMilestoneBaseId + 14,
      lucyStreakMilestoneBaseId + 30,
    ]) {
      await _safeCancel(id);
    }
  }

  Future<void> _scheduleDaily({
    required int id,
    required int minutesAfterMidnight,
    required String title,
    required String body,
    required String payload,
  }) async {
    await _plugin
        .zonedSchedule(
          id,
          title,
          body,
          _nextInstanceOf(minutesAfterMidnight),
          _notificationDetails(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: payload,
        )
        .timeout(const Duration(seconds: 2));
  }

  Future<void> _scheduleOneShotTodayOrTomorrow({
    required int id,
    required int minutesAfterMidnight,
    required String title,
    required String body,
    required String payload,
    required DateTime now,
  }) async {
    final scheduledToday = DateTime(
      now.year,
      now.month,
      now.day,
      minutesAfterMidnight ~/ 60,
      minutesAfterMidnight % 60,
    );
    final scheduled = scheduledToday.isAfter(now)
        ? scheduledToday
        : scheduledToday.add(const Duration(days: 1));
    await _scheduleOneShotAt(
      id: id,
      scheduledDate: scheduled,
      title: title,
      body: body,
      payload: payload,
    );
  }

  Future<void> _scheduleOneShotAt({
    required int id,
    required DateTime scheduledDate,
    required String title,
    required String body,
    required String payload,
  }) async {
    await _safeCancel(id);
    await _plugin
        .zonedSchedule(
          id,
          title,
          body,
          tz.TZDateTime.from(scheduledDate, tz.local),
          _notificationDetails(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        )
        .timeout(const Duration(seconds: 2));
  }

  NotificationDetails _notificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription:
            'Osobní koučovací zprávy od Lucy podle dnešních tasků a streaku.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
    );
  }

  tz.TZDateTime _nextInstanceOf(int minutesAfterMidnight) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      minutesAfterMidnight ~/ 60,
      minutesAfterMidnight % 60,
    );

    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }

  Future<void> _safeCancel(int id) async {
    try {
      await _plugin.cancel(id).timeout(const Duration(seconds: 2));
    } on MissingPluginException {
      return;
    } on TimeoutException {
      return;
    }
  }

  Future<void> _saveLastOpenedAt(DateTime openedAt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastOpenedAtKey, openedAt.toIso8601String());
  }

  String _dayKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

  bool get _isFlutterTest =>
      Platform.environment.containsKey('FLUTTER_TEST') ||
      Platform.environment.containsKey('DART_TEST') ||
      WidgetsBinding.instance.runtimeType.toString().contains(
        'TestWidgetsFlutterBinding',
      );
}
