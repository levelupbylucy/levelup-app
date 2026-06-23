class UserProfile {
  const UserProfile({
    required this.name,
    required this.vision,
    required this.identities,
    required this.streakDays,
    required this.onboardingCompleted,
    this.areaVisions = const {},
    this.futureImagePath = '',
    this.lastStreakCompletedDay,
  });

  final String name;
  final String vision;
  final List<String> identities;
  final int streakDays;
  final bool onboardingCompleted;
  final Map<String, String> areaVisions;
  final String futureImagePath;
  final DateTime? lastStreakCompletedDay;

  String get firstName {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  factory UserProfile.empty() {
    return const UserProfile(
      name: '',
      vision: '',
      identities: [],
      streakDays: 0,
      onboardingCompleted: false,
      areaVisions: {},
      futureImagePath: '',
      lastStreakCompletedDay: null,
    );
  }

  UserProfile copyWith({
    String? name,
    String? vision,
    List<String>? identities,
    int? streakDays,
    bool? onboardingCompleted,
    Map<String, String>? areaVisions,
    String? futureImagePath,
    DateTime? lastStreakCompletedDay,
    bool clearLastStreakCompletedDay = false,
  }) {
    return UserProfile(
      name: name ?? this.name,
      vision: vision ?? this.vision,
      identities: identities ?? this.identities,
      streakDays: streakDays ?? this.streakDays,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      areaVisions: areaVisions ?? this.areaVisions,
      futureImagePath: futureImagePath ?? this.futureImagePath,
      lastStreakCompletedDay: clearLastStreakCompletedDay
          ? null
          : lastStreakCompletedDay ?? this.lastStreakCompletedDay,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'vision': vision,
    'identities': identities,
    'streakDays': streakDays,
    'onboardingCompleted': onboardingCompleted,
    'areaVisions': areaVisions,
    'futureImagePath': futureImagePath,
    'lastStreakCompletedDay': lastStreakCompletedDay?.toIso8601String(),
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] ?? '',
      vision: json['vision'] ?? '',
      identities: List<String>.from(json['identities'] ?? []),
      streakDays: json['streakDays'] ?? 0,
      onboardingCompleted: json['onboardingCompleted'] ?? false,
      areaVisions: Map<String, String>.from(json['areaVisions'] ?? const {}),
      futureImagePath: json['futureImagePath'] ?? '',
      lastStreakCompletedDay: _dateTimeFromJson(json['lastStreakCompletedDay']),
    );
  }

  static DateTime? _dateTimeFromJson(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

enum AuthProvider { guest, google }

class AuthSession {
  const AuthSession({
    required this.userId,
    required this.provider,
    this.email = '',
    this.displayName = '',
    this.photoUrl = '',
    this.lastSyncedAt,
  });

  final String userId;
  final AuthProvider provider;
  final String email;
  final String displayName;
  final String photoUrl;
  final DateTime? lastSyncedAt;

  bool get isGuest => provider == AuthProvider.guest;
  bool get isSignedIn => provider != AuthProvider.guest;

  factory AuthSession.guest() {
    return AuthSession(
      userId: 'guest_${DateTime.now().millisecondsSinceEpoch}',
      provider: AuthProvider.guest,
      displayName: 'Guest',
    );
  }

  AuthSession copyWith({
    String? userId,
    AuthProvider? provider,
    String? email,
    String? displayName,
    String? photoUrl,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
  }) {
    return AuthSession(
      userId: userId ?? this.userId,
      provider: provider ?? this.provider,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      lastSyncedAt: clearLastSyncedAt
          ? null
          : lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'provider': provider.name,
    'email': email,
    'displayName': displayName,
    'photoUrl': photoUrl,
    'lastSyncedAt': lastSyncedAt?.toIso8601String(),
  };

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final providerName = json['provider'] ?? 'guest';
    return AuthSession(
      userId: json['userId'] ?? '',
      provider: AuthProvider.values.firstWhere(
        (provider) => provider.name == providerName,
        orElse: () => AuthProvider.guest,
      ),
      email: json['email'] ?? '',
      displayName: json['displayName'] ?? '',
      photoUrl: json['photoUrl'] ?? '',
      lastSyncedAt: _dateTimeFromJson(json['lastSyncedAt']),
    );
  }

  static DateTime? _dateTimeFromJson(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

enum GoalStatus { notStarted, currentTask, completed }

enum DailyTaskStatus { done, missed, partial, today, future }

class DailyTaskHistory {
  const DailyTaskHistory({
    required this.date,
    required this.plannedCount,
    required this.completedCount,
  });

  final DateTime date;
  final int plannedCount;
  final int completedCount;

  bool get isComplete => plannedCount > 0 && completedCount >= plannedCount;
  bool get hasAnyProgress => completedCount > 0;
  double get progress => plannedCount == 0 ? 0 : completedCount / plannedCount;

  DailyTaskHistory copyWith({
    DateTime? date,
    int? plannedCount,
    int? completedCount,
  }) {
    return DailyTaskHistory(
      date: date ?? this.date,
      plannedCount: plannedCount ?? this.plannedCount,
      completedCount: completedCount ?? this.completedCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'date': DateTime(date.year, date.month, date.day).toIso8601String(),
    'plannedCount': plannedCount,
    'completedCount': completedCount,
  };

  factory DailyTaskHistory.fromJson(Map<String, dynamic> json) {
    final parsedDate = _dateTimeFromJson(json['date']) ?? DateTime.now();
    return DailyTaskHistory(
      date: DateTime(parsedDate.year, parsedDate.month, parsedDate.day),
      plannedCount: json['plannedCount'] ?? 0,
      completedCount: json['completedCount'] ?? 0,
    );
  }

  DailyTaskStatus statusFor(DateTime now) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    if (normalizedDate.isAfter(today)) return DailyTaskStatus.future;
    if (normalizedDate == today) return DailyTaskStatus.today;
    if (isComplete) return DailyTaskStatus.done;
    if (hasAnyProgress) return DailyTaskStatus.partial;
    return plannedCount > 0 ? DailyTaskStatus.missed : DailyTaskStatus.future;
  }

  static DateTime? _dateTimeFromJson(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

class ReminderSettings {
  const ReminderSettings({
    this.morningEnabled = true,
    this.eveningEnabled = true,
    this.morningMinutesAfterMidnight = 9 * 60,
    this.eveningMinutesAfterMidnight = 20 * 60 + 30,
  });

  final bool morningEnabled;
  final bool eveningEnabled;
  final int morningMinutesAfterMidnight;
  final int eveningMinutesAfterMidnight;

  ReminderSettings copyWith({
    bool? morningEnabled,
    bool? eveningEnabled,
    int? morningMinutesAfterMidnight,
    int? eveningMinutesAfterMidnight,
  }) {
    return ReminderSettings(
      morningEnabled: morningEnabled ?? this.morningEnabled,
      eveningEnabled: eveningEnabled ?? this.eveningEnabled,
      morningMinutesAfterMidnight:
          morningMinutesAfterMidnight ?? this.morningMinutesAfterMidnight,
      eveningMinutesAfterMidnight:
          eveningMinutesAfterMidnight ?? this.eveningMinutesAfterMidnight,
    );
  }

  Map<String, dynamic> toJson() => {
    'morningEnabled': morningEnabled,
    'eveningEnabled': eveningEnabled,
    'morningMinutesAfterMidnight': morningMinutesAfterMidnight,
    'eveningMinutesAfterMidnight': eveningMinutesAfterMidnight,
  };

  factory ReminderSettings.fromJson(Map<String, dynamic> json) {
    return ReminderSettings(
      morningEnabled: json['morningEnabled'] ?? true,
      eveningEnabled: json['eveningEnabled'] ?? true,
      morningMinutesAfterMidnight:
          json['morningMinutesAfterMidnight'] ?? 9 * 60,
      eveningMinutesAfterMidnight:
          json['eveningMinutesAfterMidnight'] ?? 20 * 60 + 30,
    );
  }
}

class Milestone {
  const Milestone({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.completed = false,
    this.dueDate,
    this.repeatsDaily = false,
    this.repeatWeekdays = const [],
  });

  final String id;
  final String title;
  final String subtitle;
  final bool completed;
  final DateTime? dueDate;
  final bool repeatsDaily;
  final List<int> repeatWeekdays;

  String get scheduleLabel {
    if (repeatsDaily) return 'Every day';
    if (repeatWeekdays.isNotEmpty) return _weekdayLabel(repeatWeekdays);
    if (dueDate == null) return subtitle;
    return '${dueDate!.month}/${dueDate!.day}/${dueDate!.year}';
  }

  Milestone copyWith({
    String? id,
    String? title,
    String? subtitle,
    bool? completed,
    DateTime? dueDate,
    bool? repeatsDaily,
    List<int>? repeatWeekdays,
    bool clearDueDate = false,
  }) {
    return Milestone(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      completed: completed ?? this.completed,
      dueDate: clearDueDate ? null : dueDate ?? this.dueDate,
      repeatsDaily: repeatsDaily ?? this.repeatsDaily,
      repeatWeekdays: repeatWeekdays ?? this.repeatWeekdays,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'completed': completed,
    'dueDate': dueDate?.toIso8601String(),
    'repeatsDaily': repeatsDaily,
    'repeatWeekdays': repeatWeekdays,
  };

  factory Milestone.fromJson(Map<String, dynamic> json) {
    return Milestone(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      subtitle: json['subtitle'] ?? '',
      completed: json['completed'] ?? false,
      dueDate: _dateTimeFromJson(json['dueDate']),
      repeatsDaily: json['repeatsDaily'] ?? false,
      repeatWeekdays: (json['repeatWeekdays'] as List? ?? [])
          .map((value) => value is int ? value : int.tryParse('$value') ?? 0)
          .where((value) => value >= 1 && value <= 7)
          .toList(),
    );
  }

  static String _weekdayLabel(List<int> days) {
    const labels = {
      1: 'Mon',
      2: 'Tue',
      3: 'Wed',
      4: 'Thu',
      5: 'Fri',
      6: 'Sat',
      7: 'Sun',
    };
    final sorted = [...days]..sort();
    return sorted.map((day) => labels[day]).whereType<String>().join(', ');
  }

  static DateTime? _dateTimeFromJson(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

class Goal {
  const Goal({
    required this.id,
    required this.category,
    required this.title,
    required this.detail,
    required this.progress,
    required this.vision,
    required this.timeline,
    required this.completed,
    required this.milestones,
    this.startedAt,
    this.completedAt,
    this.paused = false,
  });

  final String id;
  final String category;
  final String title;
  final String detail;
  final double progress;
  final String vision;
  final String timeline;
  final bool completed;
  final List<Milestone> milestones;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final bool paused;

  GoalStatus get status {
    if (completed) return GoalStatus.completed;
    if (startedAt == null && progress <= 0) return GoalStatus.notStarted;
    return GoalStatus.currentTask;
  }

  Goal copyWith({
    String? id,
    String? category,
    String? title,
    String? detail,
    double? progress,
    String? vision,
    String? timeline,
    bool? completed,
    List<Milestone>? milestones,
    DateTime? startedAt,
    DateTime? completedAt,
    bool? paused,
    bool clearStartedAt = false,
    bool clearCompletedAt = false,
  }) {
    return Goal(
      id: id ?? this.id,
      category: category ?? this.category,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      progress: progress ?? this.progress,
      vision: vision ?? this.vision,
      timeline: timeline ?? this.timeline,
      completed: completed ?? this.completed,
      milestones: milestones ?? this.milestones,
      startedAt: clearStartedAt ? null : startedAt ?? this.startedAt,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      paused: paused ?? this.paused,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'title': title,
    'detail': detail,
    'progress': progress,
    'vision': vision,
    'timeline': timeline,
    'completed': completed,
    'milestones': milestones.map((milestone) => milestone.toJson()).toList(),
    'startedAt': startedAt?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'paused': paused,
  };

  factory Goal.fromJson(Map<String, dynamic> json) {
    return Goal(
      id: json['id'] ?? '',
      category: json['category'] ?? '',
      title: json['title'] ?? '',
      detail: json['detail'] ?? '',
      progress: (json['progress'] ?? 0).toDouble(),
      vision: json['vision'] ?? '',
      timeline: json['timeline'] ?? '',
      completed: json['completed'] ?? false,
      milestones: (json['milestones'] as List? ?? [])
          .map((item) => Milestone.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      startedAt: _dateTimeFromJson(json['startedAt']),
      completedAt: _dateTimeFromJson(json['completedAt']),
      paused: json['paused'] ?? false,
    );
  }

  static DateTime? _dateTimeFromJson(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

class DailyTask {
  const DailyTask({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.completed,
    this.goalId,
    this.plannedFor,
    this.dueDate,
    this.repeatGroupId,
    this.repeatIndex = 1,
    this.repeatTotal = 1,
    this.repeatWeekdays = const [],
    this.completedAt,
  });

  final String id;
  final String title;
  final String subtitle;
  final String category;
  final bool completed;
  final String? goalId;
  final DateTime? plannedFor;
  final DateTime? dueDate;
  final String? repeatGroupId;
  final int repeatIndex;
  final int repeatTotal;
  final List<int> repeatWeekdays;
  final DateTime? completedAt;

  DailyTask copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? category,
    bool? completed,
    String? goalId,
    DateTime? plannedFor,
    DateTime? dueDate,
    String? repeatGroupId,
    int? repeatIndex,
    int? repeatTotal,
    List<int>? repeatWeekdays,
    DateTime? completedAt,
    bool clearDueDate = false,
    bool clearCompletedAt = false,
  }) {
    return DailyTask(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      category: category ?? this.category,
      completed: completed ?? this.completed,
      goalId: goalId ?? this.goalId,
      plannedFor: plannedFor ?? this.plannedFor,
      dueDate: clearDueDate ? null : dueDate ?? this.dueDate,
      repeatGroupId: repeatGroupId ?? this.repeatGroupId,
      repeatIndex: repeatIndex ?? this.repeatIndex,
      repeatTotal: repeatTotal ?? this.repeatTotal,
      repeatWeekdays: repeatWeekdays ?? this.repeatWeekdays,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'category': category,
    'completed': completed,
    'goalId': goalId,
    'plannedFor': plannedFor?.toIso8601String(),
    'dueDate': dueDate?.toIso8601String(),
    'repeatGroupId': repeatGroupId,
    'repeatIndex': repeatIndex,
    'repeatTotal': repeatTotal,
    'repeatWeekdays': repeatWeekdays,
    'completedAt': completedAt?.toIso8601String(),
  };

  factory DailyTask.fromJson(Map<String, dynamic> json) {
    return DailyTask(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      subtitle: json['subtitle'] ?? '',
      category: json['category'] ?? '',
      completed: json['completed'] ?? false,
      goalId: json['goalId'],
      plannedFor: _dateTimeFromJson(json['plannedFor']),
      dueDate: _dateTimeFromJson(json['dueDate']),
      repeatGroupId: json['repeatGroupId'],
      repeatIndex: json['repeatIndex'] ?? 1,
      repeatTotal: json['repeatTotal'] ?? 1,
      repeatWeekdays: (json['repeatWeekdays'] as List? ?? [])
          .map((value) => value is int ? value : int.tryParse('$value') ?? 0)
          .where((value) => value >= 1 && value <= 7)
          .toList(),
      completedAt: _dateTimeFromJson(json['completedAt']),
    );
  }

  static DateTime? _dateTimeFromJson(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
