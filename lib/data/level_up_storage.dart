import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'level_up_models.dart';

class LevelUpStorage {
  static const _authSessionKey = 'level_up_auth_session';
  static const _userKey = 'level_up_user';
  static const _goalsKey = 'level_up_goals';
  static const _tasksKey = 'level_up_tasks';
  static const _taskHistoryKey = 'level_up_task_history';
  static const _reminderSettingsKey = 'level_up_reminder_settings';
  static const _legacyMissionsKey = 'level_up_missions';

  Future<AuthSession?> loadAuthSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_authSessionKey);

    if (raw == null) return null;

    return AuthSession.fromJson(jsonDecode(raw));
  }

  Future<void> saveAuthSession(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authSessionKey, jsonEncode(session.toJson()));
  }

  Future<void> clearAuthSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authSessionKey);
  }

  Future<UserProfile> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);

    if (raw == null) return UserProfile.empty();

    return UserProfile.fromJson(jsonDecode(raw));
  }

  Future<void> saveUser(UserProfile user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }

  Future<List<Goal>> loadGoals() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_goalsKey);

    if (raw == null) return [];

    return (jsonDecode(raw) as List)
        .map((item) => Goal.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> saveGoals(List<Goal> goals) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _goalsKey,
      jsonEncode(goals.map((goal) => goal.toJson()).toList()),
    );
  }

  Future<List<DailyTask>> loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getString(_tasksKey) ?? prefs.getString(_legacyMissionsKey);

    if (raw == null) return [];

    return (jsonDecode(raw) as List)
        .map((item) => DailyTask.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> saveTasks(List<DailyTask> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _tasksKey,
      jsonEncode(tasks.map((task) => task.toJson()).toList()),
    );
    await prefs.remove(_legacyMissionsKey);
  }

  Future<List<DailyTaskHistory>> loadTaskHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_taskHistoryKey);

    if (raw == null) return [];

    return (jsonDecode(raw) as List)
        .map(
          (item) => DailyTaskHistory.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<void> saveTaskHistory(List<DailyTaskHistory> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _taskHistoryKey,
      jsonEncode(history.map((day) => day.toJson()).toList()),
    );
  }

  Future<ReminderSettings> loadReminderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_reminderSettingsKey);

    if (raw == null) return const ReminderSettings();

    return ReminderSettings.fromJson(jsonDecode(raw));
  }

  Future<void> saveReminderSettings(ReminderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_reminderSettingsKey, jsonEncode(settings.toJson()));
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authSessionKey);
    await prefs.remove(_userKey);
    await prefs.remove(_goalsKey);
    await prefs.remove(_tasksKey);
    await prefs.remove(_taskHistoryKey);
    await prefs.remove(_reminderSettingsKey);
    await prefs.remove(_legacyMissionsKey);
  }
}
