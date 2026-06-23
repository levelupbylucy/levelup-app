import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../data/level_up_models.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const _morningId = 901;
  static const _eveningId = 2030;
  static const _channelId = 'levelup_daily_reminders';
  static const _channelName = 'LevelUp daily reminders';

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
            onDidReceiveNotificationResponse: (_) {},
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
    await initialize();
    if (_disabled) return;
    await requestPermission();
    try {
      await cancelLevelUpNotifications();

      if (settings.morningEnabled) {
        await _scheduleDaily(
          id: _morningId,
          minutesAfterMidnight: 9 * 60,
          title: 'Your future self is waiting',
          body: 'Set your focus for today and move one step closer.',
        );
      }

      if (settings.eveningEnabled) {
        await _scheduleDaily(
          id: _eveningId,
          minutesAfterMidnight: 20 * 60 + 30,
          title: 'Did you level up today?',
          body: 'Open LevelUp and mark which daily tasks you completed.',
        );
      }
    } on MissingPluginException {
      return;
    }
  }

  Future<void> cancelLevelUpNotifications() async {
    await _plugin.cancel(_morningId).timeout(const Duration(seconds: 2));
    await _plugin.cancel(_eveningId).timeout(const Duration(seconds: 2));
  }

  Future<void> _scheduleDaily({
    required int id,
    required int minutesAfterMidnight,
    required String title,
    required String body,
  }) async {
    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription:
            'Morning and evening reminders for LevelUp tasks and streaks.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: const DarwinNotificationDetails(),
    );

    await _plugin
        .zonedSchedule(
          id,
          title,
          body,
          _nextInstanceOf(minutesAfterMidnight),
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: 'levelup://home',
        )
        .timeout(const Duration(seconds: 2));
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

  bool get _isFlutterTest =>
      Platform.environment.containsKey('FLUTTER_TEST') ||
      Platform.environment.containsKey('DART_TEST') ||
      WidgetsBinding.instance.runtimeType.toString().contains(
        'TestWidgetsFlutterBinding',
      );
}
