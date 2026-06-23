import 'package:flutter/widgets.dart';

import '../data/level_up_models.dart';
import '../data/level_up_storage.dart';
import '../data/lucy_message_catalog.dart';
import '../services/auth_service.dart';
import '../services/firestore_data_service.dart';
import '../services/notification_service.dart';
import '../services/widget_data_service.dart';

class LevelUpAppState extends ChangeNotifier {
  LevelUpAppState({
    LevelUpStorage? storage,
    AuthService? authService,
    FirestoreDataService? firestoreDataService,
    NotificationService? notificationService,
    WidgetDataService? widgetDataService,
  }) : _storage = storage ?? LevelUpStorage(),
       _authService = authService ?? AuthService.instance,
       _firestoreDataService =
           firestoreDataService ?? const FirestoreDataService(),
       _notificationService =
           notificationService ?? NotificationService.instance,
       _widgetDataService = widgetDataService ?? const WidgetDataService();

  final LevelUpStorage _storage;
  final AuthService _authService;
  final FirestoreDataService _firestoreDataService;
  final NotificationService _notificationService;
  final WidgetDataService _widgetDataService;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  UserProfile _user = UserProfile.empty();
  UserProfile get user => _user;

  AuthSession _authSession = AuthSession.guest();
  AuthSession get authSession => _authSession;
  bool get isGuest => _authSession.isGuest;
  bool get isSignedIn => _authSession.isSignedIn;
  String get accountDisplayName {
    final sessionName = _authSession.displayName.trim();
    if (sessionName.isNotEmpty && !isGuest) return sessionName;
    final userName = _user.name.trim();
    if (userName.isNotEmpty) return userName;
    return isGuest ? 'Guest' : 'Level Up user';
  }

  List<Goal> _goals = [];
  List<Goal> get goals => List.unmodifiable(_goals);
  List<Goal> get activeGoals =>
      _goals.where((goal) => !goal.completed).toList(growable: false);
  List<Goal> get completedGoals =>
      _goals.where((goal) => goal.completed).toList(growable: false);

  List<DailyTask> _tasks = [];
  List<DailyTask> get tasks => List.unmodifiable(_tasks);
  List<DailyTask> get todayTasks {
    final now = DateTime.now();
    return _tasks
        .where(
          (task) =>
              task.plannedFor == null || _isSameDay(task.plannedFor!, now),
        )
        .toList(growable: false);
  }

  int get completedTaskCount =>
      todayTasks.where((task) => task.completed).length;
  double get dailyProgress =>
      todayTasks.isEmpty ? 0 : completedTaskCount / todayTasks.length;
  List<DailyTask> get weeklyTasks {
    final now = DateTime.now();
    return _tasks
        .where(
          (task) =>
              task.plannedFor == null || _isSameWeek(task.plannedFor!, now),
        )
        .toList(growable: false);
  }

  int get completedWeeklyTaskCount =>
      weeklyTasks.where((task) => task.completed).length;
  double get weeklyProgress =>
      weeklyTasks.isEmpty ? 0 : completedWeeklyTaskCount / weeklyTasks.length;
  List<DailyTaskHistory> _taskHistory = [];
  List<DailyTaskHistory> get taskHistory => List.unmodifiable(
    _mergeTaskHistory(_taskHistory, _buildCurrentTaskHistory()),
  );
  ReminderSettings _reminderSettings = const ReminderSettings();
  ReminderSettings get reminderSettings => _reminderSettings;
  double get averageGoalProgress {
    final active = activeGoals;
    if (active.isEmpty) return 0;
    final total = active.fold<double>(0, (sum, goal) => sum + goal.progress);
    return total / active.length;
  }

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    final storedSession = await _storage.loadAuthSession();
    final firebaseSession = _authService.currentSession();
    _authSession = firebaseSession ?? storedSession ?? AuthSession.guest();
    if (firebaseSession != null || storedSession == null) {
      await _storage.saveAuthSession(_authSession);
    }

    _user = await _storage.loadUser();
    _goals = await _storage.loadGoals();
    _tasks = await _storage.loadTasks();
    _taskHistory = _mergeTaskHistory(
      await _storage.loadTaskHistory(),
      _buildCurrentTaskHistory(),
    );
    _reminderSettings = await _storage.loadReminderSettings();
    await _storage.saveTaskHistory(_taskHistory);
    await _notificationService.scheduleDailyReminders(_reminderSettings);
    await _refreshStreakFromHistory();
    await _syncWidgetData();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> completeOnboarding({
    required String name,
    required String vision,
    required List<String> identities,
    required Map<String, String> areaVisions,
    required Goal firstGoal,
  }) async {
    _user = _user.copyWith(
      name: name.trim(),
      vision: vision.trim(),
      identities: identities,
      areaVisions: areaVisions,
      onboardingCompleted: true,
    );

    _goals = [firstGoal, ..._goals.where((goal) => goal.id != firstGoal.id)];
    _tasks = _createStarterTasks(firstGoal);

    await _persistAll();
    await _syncWidgetData();
    notifyListeners();
  }

  Future<void> updateUser({
    String? name,
    String? vision,
    List<String>? identities,
    int? streakDays,
    bool? onboardingCompleted,
    Map<String, String>? areaVisions,
    String? futureImagePath,
    DateTime? lastStreakCompletedDay,
  }) async {
    _user = _user.copyWith(
      name: name,
      vision: vision,
      identities: identities,
      streakDays: streakDays,
      onboardingCompleted: onboardingCompleted,
      areaVisions: areaVisions,
      futureImagePath: futureImagePath,
      lastStreakCompletedDay: lastStreakCompletedDay,
    );
    await _storage.saveUser(_user);
    await _syncWidgetData();
    notifyListeners();
  }

  Future<void> addGoal(Goal goal) async {
    _goals = [goal, ..._goals];
    await _storage.saveGoals(_goals);
    await _syncWidgetData();
    notifyListeners();
  }

  Future<void> addTask(DailyTask task) async {
    _tasks = [task, ..._tasks];
    await _storage.saveTasks(_tasks);
    await _recordTaskHistorySnapshot();
    await _refreshStreakFromHistory();
    await _syncWidgetData();
    notifyListeners();
  }

  Future<void> startGoal(String goalId) async {
    Goal? startedGoal;
    _goals = _goals.map((goal) {
      if (goal.id != goalId) return goal;
      startedGoal = goal.copyWith(startedAt: DateTime.now(), paused: false);
      return startedGoal!;
    }).toList();

    if (startedGoal != null && !_tasks.any((task) => task.goalId == goalId)) {
      _tasks = [..._createStarterTasks(startedGoal!), ..._tasks];
      await _storage.saveTasks(_tasks);
    }

    await _storage.saveGoals(_goals);
    await _syncWidgetData();
    notifyListeners();
  }

  Future<void> updateGoal(Goal updatedGoal) async {
    _goals = _goals
        .map((goal) => goal.id == updatedGoal.id ? updatedGoal : goal)
        .toList();
    await _storage.saveGoals(_goals);
    await _syncWidgetData();
    notifyListeners();
  }

  Future<void> setGoalPaused(String goalId, bool paused) async {
    _goals = _goals.map((goal) {
      if (goal.id != goalId) return goal;
      return goal.copyWith(paused: paused);
    }).toList();
    await _storage.saveGoals(_goals);
    notifyListeners();
  }

  Future<void> deleteGoal(String goalId) async {
    await _recordTaskHistorySnapshot();
    _goals = _goals.where((goal) => goal.id != goalId).toList();
    _tasks = _tasks.where((task) => task.goalId != goalId).toList();
    await _storage.saveGoals(_goals);
    await _storage.saveTasks(_tasks);
    await _refreshStreakFromHistory();
    await _syncWidgetData();
    notifyListeners();
  }

  Future<void> completeGoal(String goalId) async {
    _goals = _goals.map((goal) {
      if (goal.id != goalId) return goal;
      final completedMilestones = goal.milestones
          .map((milestone) => milestone.copyWith(completed: true))
          .toList();
      return goal.copyWith(
        completed: true,
        completedAt: DateTime.now(),
        paused: false,
        progress: 1,
        milestones: completedMilestones,
      );
    }).toList();
    await _storage.saveGoals(_goals);
    await _syncWidgetData();
    notifyListeners();
  }

  Future<void> restoreGoal(String goalId) async {
    _goals = _goals.map((goal) {
      if (goal.id != goalId) return goal;
      return goal.copyWith(
        completed: false,
        clearCompletedAt: true,
        startedAt: goal.startedAt ?? DateTime.now(),
        progress: goal.progress >= 1 ? .95 : goal.progress,
      );
    }).toList();
    await _storage.saveGoals(_goals);
    await _syncWidgetData();
    notifyListeners();
  }

  Future<void> toggleTask(String taskId) async {
    var completedNow = false;
    String? relatedGoalId;
    _tasks = _tasks.map((task) {
      if (task.id != taskId) return task;
      completedNow = !task.completed;
      relatedGoalId = task.goalId;
      return task.copyWith(
        completed: completedNow,
        completedAt: completedNow ? DateTime.now() : null,
        clearCompletedAt: !completedNow,
      );
    }).toList();

    if (relatedGoalId != null) {
      _updateGoalProgressFromTask(
        goalId: relatedGoalId!,
        taskId: taskId,
        completed: completedNow,
      );
      await _storage.saveGoals(_goals);
    }

    await _storage.saveTasks(_tasks);
    await _recordTaskHistorySnapshot();
    await _refreshStreakFromHistory();
    await _syncWidgetData();
    notifyListeners();
  }

  Future<void> toggleMilestone({
    required String goalId,
    required String milestoneId,
  }) async {
    _goals = _goals.map((goal) {
      if (goal.id != goalId) return goal;

      final milestones = goal.milestones.map((milestone) {
        if (milestone.id != milestoneId) return milestone;
        return milestone.copyWith(completed: !milestone.completed);
      }).toList();

      final progress = milestones.isEmpty
          ? goal.progress
          : milestones.where((milestone) => milestone.completed).length /
                milestones.length;

      return goal.copyWith(
        milestones: milestones,
        progress: progress,
        completed: progress >= 1,
        completedAt: progress >= 1 ? DateTime.now() : null,
        clearCompletedAt: progress < 1,
      );
    }).toList();

    await _storage.saveGoals(_goals);
    await _syncWidgetData();
    notifyListeners();
  }

  Future<void> continueAsGuest() async {
    if (!_authSession.isGuest) {
      await _authService.signOut();
      _authSession = AuthSession.guest();
    }
    await _storage.saveAuthSession(_authSession);
    notifyListeners();
  }

  Future<String> signInWithGoogle() async {
    return _signInWith(() => _authService.signInWithGoogle(), 'Google');
  }

  Future<void> signOutToGuest() async {
    await _authService.signOut();
    _authSession = AuthSession.guest();
    await _storage.saveAuthSession(_authSession);
    notifyListeners();
  }

  Future<String> _signInWith(
    Future<AuthSession> Function() action,
    String providerLabel,
  ) async {
    try {
      final session = await action();
      _authSession = session;
      await _storage.saveAuthSession(_authSession);
      if (_authSession.isSignedIn) {
        await _prepareRemoteUserDocument();
      }
      notifyListeners();
      return 'Signed in with $providerLabel. Your existing local data is still on this device and is ready to be merged into your account.';
    } catch (error) {
      return error.toString();
    }
  }

  Future<void> markLocalSyncComplete() async {
    _authSession = _authSession.copyWith(lastSyncedAt: DateTime.now());
    await _storage.saveAuthSession(_authSession);
    notifyListeners();
  }

  Future<void> _prepareRemoteUserDocument() async {
    if (_authSession.isGuest) return;
    try {
      await _firestoreDataService.prepareUserDocument(
        userId: _authSession.userId,
        session: _authSession,
      );
      await _firestoreDataService.mergeLocalDataAfterSignIn(
        userId: _authSession.userId,
        user: _user,
        goals: _goals,
        tasks: _tasks,
        taskHistory: _taskHistory,
      );
      _authSession = _authSession.copyWith(lastSyncedAt: DateTime.now());
      await _storage.saveAuthSession(_authSession);
    } catch (_) {
      // Keep sign-in usable even before Firestore rules/config are finalized.
    }
  }

  Future<void> updateReminderSettings(ReminderSettings settings) async {
    _reminderSettings = settings;
    await _storage.saveReminderSettings(_reminderSettings);
    await _notificationService.scheduleDailyReminders(_reminderSettings);
    notifyListeners();
  }

  Future<void> resetLocalData() async {
    final currentSession = _authSession;
    final currentReminderSettings = _reminderSettings;
    await _storage.clearAll();
    _authSession = currentSession;
    _reminderSettings = currentReminderSettings;
    _user = UserProfile.empty();
    _goals = [];
    _tasks = [];
    _taskHistory = [];
    _seedDemoData();
    _taskHistory = _buildCurrentTaskHistory();
    await _persistAll();
    await _syncWidgetData();
    notifyListeners();
  }

  Future<void> _persistAll() async {
    await _storage.saveAuthSession(_authSession);
    await _storage.saveUser(_user);
    await _storage.saveGoals(_goals);
    await _storage.saveTasks(_tasks);
    await _storage.saveTaskHistory(_taskHistory);
    await _storage.saveReminderSettings(_reminderSettings);
  }

  Future<void> _syncWidgetData() async {
    final focusTask = todayTasks.cast<DailyTask?>().firstWhere(
      (task) => task != null && !task.completed,
      orElse: () => todayTasks.isNotEmpty ? todayTasks.first : null,
    );
    final focusGoal = focusTask?.goalId == null
        ? null
        : _goals.cast<Goal?>().firstWhere(
            (goal) => goal != null && goal.id == focusTask!.goalId,
            orElse: () => null,
          );
    final currentGoal = activeGoals.isNotEmpty
        ? activeGoals.first
        : completedGoals.isNotEmpty
        ? completedGoals.first
        : null;
    final currentGoalTask =
        _tasks
            .cast<DailyTask?>()
            .firstWhere(
              (task) =>
                  task != null &&
                  currentGoal != null &&
                  task.goalId == currentGoal.id &&
                  !task.completed,
              orElse: () => null,
            )
            ?.title ??
        currentGoal?.milestones
            .cast<Milestone?>()
            .firstWhere(
              (milestone) => milestone != null && !milestone.completed,
              orElse: () => null,
            )
            ?.title ??
        'Choose today’s task';

    await _widgetDataService.update(
      todayCompletedTasks: completedTaskCount,
      todayTotalTasks: todayTasks.length,
      currentStreak: _user.streakDays,
      todayFocusTask: focusTask?.title ?? 'Choose today’s focus',
      todayFocusGoal: focusGoal?.title ?? currentGoal?.title ?? 'LevelUp',
      futureVision: _user.vision.trim().isEmpty
          ? 'I am healthy, confident and financially free.'
          : _user.vision.trim(),
      visionClarity: _user.vision.trim().isEmpty ? 0 : 78,
      identityTags: _user.identities.isEmpty
          ? const [
              'Healthy',
              'Successful',
              'Disciplined',
              'Confident',
              'Financially Free',
            ]
          : _user.identities,
      currentGoalTitle: currentGoal?.title ?? 'Create your first goal',
      currentGoalProgress: ((currentGoal?.progress ?? dailyProgress) * 100)
          .round()
          .clamp(0, 100),
      currentGoalTask: currentGoalTask,
      currentGoalTargetDate: currentGoal?.detail.trim().isEmpty ?? true
          ? 'No target date'
          : currentGoal!.detail.trim(),
      quoteOfTheDay: LucyMessageCatalog.quoteOfTheDay(DateTime.now()),
      todayTasks: todayTasks,
    );
  }

  void _seedDemoData() {
    _user = const UserProfile(
      name: 'Lukas',
      vision: 'I am healthy, confident and financially free.',
      identities: ['Healthy', 'Disciplined', 'Financially Free'],
      streakDays: 4,
      onboardingCompleted: false,
      lastStreakCompletedDay: null,
    );

    _goals = const [
      Goal(
        id: 'goal_half_marathon',
        category: 'HEALTH',
        title: 'Run a Half Marathon',
        detail: 'Oct 2025 · 21 km race',
        progress: .62,
        vision: 'Run a marathon',
        timeline: 'Jan 2025 -> Sep 2025 -> 2029',
        completed: false,
        milestones: [
          Milestone(id: 'hm_5k', title: 'Run 5 km', completed: true),
          Milestone(id: 'hm_10k', title: 'Run 10 km', completed: true),
          Milestone(id: 'hm_16k', title: 'Run 16 km long run'),
          Milestone(id: 'hm_race', title: 'Race day'),
        ],
      ),
      Goal(
        id: 'goal_doctor',
        category: 'CAREER',
        title: 'Become a Doctor',
        detail: '2026 · Medical School entry',
        progress: .38,
        vision: 'Become a doctor',
        timeline: 'MCAT -> applications -> interviews',
        completed: false,
        milestones: [
          Milestone(id: 'doc_mcat', title: 'Pass the MCAT', completed: true),
          Milestone(id: 'doc_apply', title: 'Apply to medical school'),
          Milestone(id: 'doc_interviews', title: 'Interview offers'),
        ],
      ),
      Goal(
        id: 'goal_emergency_fund',
        category: 'FINANCE',
        title: 'Build Emergency Fund',
        detail: '2026 · £5K safety buffer',
        progress: .24,
        vision: 'Feel financially calm and prepared',
        timeline: '£500 -> £2K -> £5K ready',
        completed: false,
        milestones: [
          Milestone(id: 'fund_500', title: 'Save £500', completed: true),
          Milestone(id: 'fund_2k', title: 'Save £2K'),
          Milestone(id: 'fund_ready', title: 'Reach £5K'),
        ],
      ),
      Goal(
        id: 'goal_relationships',
        category: 'RELATIONSHIPS',
        title: 'Build Strong Relationships',
        detail: '2026 · Weekly connection habit',
        progress: .31,
        vision: 'Be present with the people who matter',
        timeline: 'Reach out -> meet weekly -> deepen trust',
        completed: false,
        milestones: [
          Milestone(id: 'rel_call', title: 'Call one friend', completed: true),
          Milestone(id: 'rel_plan', title: 'Plan a shared activity'),
          Milestone(id: 'rel_reflect', title: 'Weekly relationship reflection'),
        ],
      ),
      Goal(
        id: 'goal_books',
        category: 'LEARNING',
        title: 'Read 24 Books',
        detail: '2026 · Two books per month',
        progress: 0,
        vision: 'Become a consistent reader',
        timeline: 'Pick first book -> read weekly -> 24 books',
        completed: false,
        milestones: [
          Milestone(id: 'books_pick', title: 'Choose the first book'),
          Milestone(
            id: 'books_session',
            title: 'Complete first reading session',
          ),
          Milestone(id: 'books_finish', title: 'Finish book one'),
        ],
      ),
      Goal(
        id: 'goal_5k_done',
        category: 'HEALTH',
        title: 'Run a 5K',
        detail: 'Completed Mar 2024 · 5 km',
        progress: 1,
        vision: 'Run a marathon',
        timeline: 'Started -> trained -> completed',
        completed: true,
        milestones: [
          Milestone(
            id: '5k_train',
            title: 'Train consistently',
            completed: true,
          ),
          Milestone(id: '5k_done', title: 'Run 5 km', completed: true),
        ],
      ),
    ];

    final today = DateTime.now();
    _tasks = [
      DailyTask(
        id: 'task_workout',
        title: 'Workout · 30 min',
        subtitle: 'Upper body + core training',
        category: 'HEALTH',
        completed: true,
        goalId: 'goal_half_marathon',
        plannedFor: today,
        completedAt: today,
      ),
      DailyTask(
        id: 'task_study',
        title: 'Study MCAT notes',
        subtitle: 'One focused study block',
        category: 'CAREER',
        completed: true,
        goalId: 'goal_doctor',
        plannedFor: today,
        completedAt: today,
      ),
      DailyTask(
        id: 'task_savings',
        title: 'Move £25 to savings',
        subtitle: 'Tiny proof for your emergency fund',
        category: 'FINANCE',
        completed: false,
        goalId: 'goal_emergency_fund',
        plannedFor: today,
      ),
      DailyTask(
        id: 'task_mum',
        title: 'Call mum',
        subtitle: 'Ten calm minutes, no multitasking',
        category: 'PERSONAL',
        completed: false,
        plannedFor: today,
      ),
      DailyTask(
        id: 'task_sleep',
        title: 'Sleep wind-down',
        subtitle: 'No screens for the final 20 min',
        category: 'BALANCE',
        completed: false,
        plannedFor: today,
      ),
    ];
  }

  List<DailyTask> _createStarterTasks(Goal goal) {
    return [
      DailyTask(
        id: 'task_${goal.id}_first_step',
        title: goal.milestones.isEmpty
            ? 'Take the first step'
            : goal.milestones.first.title,
        subtitle: goal.milestones.isEmpty
            ? 'Your first visible proof toward ${goal.title}'
            : _milestoneTaskSubtitle(goal.milestones.first, goal.title),
        category: goal.category,
        completed: false,
        goalId: goal.id,
        plannedFor: goal.milestones.isEmpty
            ? DateTime.now()
            : _plannedDateForMilestone(goal.milestones.first),
      ),
    ];
  }

  DateTime _plannedDateForMilestone(Milestone milestone) {
    if (milestone.repeatsDaily) return DateTime.now();
    if (milestone.repeatWeekdays.isNotEmpty) {
      final today = DateTime.now();
      for (var offset = 0; offset < 7; offset++) {
        final date = today.add(Duration(days: offset));
        if (milestone.repeatWeekdays.contains(date.weekday)) return date;
      }
    }
    return milestone.dueDate ?? DateTime.now();
  }

  String _milestoneTaskSubtitle(Milestone milestone, String goalTitle) {
    if (milestone.repeatsDaily) return 'Daily action toward $goalTitle';
    if (milestone.repeatWeekdays.isNotEmpty) {
      return 'Repeats ${milestone.scheduleLabel} toward $goalTitle';
    }
    if (milestone.dueDate != null) {
      return 'Planned for ${milestone.dueDate!.month}/${milestone.dueDate!.day}/${milestone.dueDate!.year}';
    }
    if (milestone.subtitle.trim().isNotEmpty) return milestone.subtitle;
    return 'Your first visible proof toward $goalTitle';
  }

  void _updateGoalProgressFromTask({
    required String goalId,
    required String taskId,
    required bool completed,
  }) {
    final task = _tasks.firstWhere(
      (item) => item.id == taskId,
      orElse: () => const DailyTask(
        id: '',
        title: '',
        subtitle: '',
        category: '',
        completed: false,
      ),
    );

    _goals = _goals.map((goal) {
      if (goal.id != goalId || goal.completed || goal.milestones.isEmpty) {
        return goal;
      }

      var changed = false;
      final milestones = goal.milestones.map((milestone) {
        if (changed) return milestone;
        final titleMatches =
            milestone.title.toLowerCase() == task.title.toLowerCase();
        final shouldUpdate = completed
            ? !milestone.completed &&
                  (titleMatches ||
                      !goal.milestones.any(
                        (item) =>
                            item.title.toLowerCase() ==
                                task.title.toLowerCase() &&
                            !item.completed,
                      ))
            : milestone.completed && titleMatches;

        if (!shouldUpdate) return milestone;
        changed = true;
        return milestone.copyWith(completed: completed);
      }).toList();

      if (!changed && !completed) {
        for (var i = milestones.length - 1; i >= 0; i--) {
          if (milestones[i].completed) {
            milestones[i] = milestones[i].copyWith(completed: false);
            changed = true;
            break;
          }
        }
      }

      if (!changed) return goal;

      final progress =
          milestones.where((milestone) => milestone.completed).length /
          milestones.length;
      return goal.copyWith(progress: progress, completed: progress >= 1);
    }).toList();
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  bool _isSameWeek(DateTime left, DateTime right) {
    final leftDate = DateTime(left.year, left.month, left.day);
    final rightDate = DateTime(right.year, right.month, right.day);
    final leftWeekStart = leftDate.subtract(
      Duration(days: leftDate.weekday - 1),
    );
    final rightWeekStart = rightDate.subtract(
      Duration(days: rightDate.weekday - 1),
    );
    return _isSameDay(leftWeekStart, rightWeekStart);
  }

  List<DailyTaskHistory> _buildCurrentTaskHistory() {
    final byDate = <DateTime, ({int planned, int completed})>{};
    for (final task in _tasks) {
      final plannedFor = task.plannedFor ?? DateTime.now();
      final date = DateTime(plannedFor.year, plannedFor.month, plannedFor.day);
      final existing = byDate[date] ?? (planned: 0, completed: 0);
      byDate[date] = (
        planned: existing.planned + 1,
        completed: existing.completed + (task.completed ? 1 : 0),
      );
    }

    final history = [
      for (final entry in byDate.entries)
        DailyTaskHistory(
          date: entry.key,
          plannedCount: entry.value.planned,
          completedCount: entry.value.completed,
        ),
    ]..sort((a, b) => a.date.compareTo(b.date));
    return history;
  }

  Future<void> _recordTaskHistorySnapshot() async {
    _taskHistory = _mergeTaskHistory(_taskHistory, _buildCurrentTaskHistory());
    await _storage.saveTaskHistory(_taskHistory);
  }

  List<DailyTaskHistory> _mergeTaskHistory(
    List<DailyTaskHistory> stored,
    List<DailyTaskHistory> current,
  ) {
    final byDate = <DateTime, DailyTaskHistory>{};
    for (final day in stored) {
      final date = DateTime(day.date.year, day.date.month, day.date.day);
      byDate[date] = day.copyWith(date: date);
    }
    for (final day in current) {
      final date = DateTime(day.date.year, day.date.month, day.date.day);
      byDate[date] = day.copyWith(date: date);
    }

    return byDate.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  int _calculateCurrentStreak(DateTime now) {
    final byDay = {
      for (final day in taskHistory)
        DateTime(day.date.year, day.date.month, day.date.day): day,
    };

    final today = DateTime(now.year, now.month, now.day);
    final todayHistory = byDay[today];
    var cursor = todayHistory != null && todayHistory.isComplete
        ? today
        : today.subtract(const Duration(days: 1));

    var streak = 0;
    while (true) {
      final history = byDay[cursor];
      if (history == null || !history.isComplete) break;
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  Future<void> _refreshStreakFromHistory() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayHistory = taskHistory.cast<DailyTaskHistory?>().firstWhere(
      (day) => day != null && _isSameDay(day.date, today),
      orElse: () => null,
    );
    final streak = _calculateCurrentStreak(now);

    final lastCompletedDay = todayHistory != null && todayHistory.isComplete
        ? today
        : streak > 0
        ? _latestCompletedDayBeforeOrOn(today)
        : null;

    final unchanged =
        _user.streakDays == streak &&
        ((lastCompletedDay == null && _user.lastStreakCompletedDay == null) ||
            (lastCompletedDay != null &&
                _user.lastStreakCompletedDay != null &&
                _isSameDay(lastCompletedDay, _user.lastStreakCompletedDay!)));

    if (unchanged) return;

    _user = _user.copyWith(
      streakDays: streak,
      lastStreakCompletedDay: lastCompletedDay,
      clearLastStreakCompletedDay: lastCompletedDay == null,
    );
    await _storage.saveUser(_user);
  }

  DateTime? _latestCompletedDayBeforeOrOn(DateTime date) {
    final completeDays =
        taskHistory
            .where((day) => !day.date.isAfter(date) && day.isComplete)
            .map((day) => day.date)
            .toList()
          ..sort();
    return completeDays.isEmpty ? null : completeDays.last;
  }
}

class LevelUpScope extends InheritedNotifier<LevelUpAppState> {
  const LevelUpScope({
    super.key,
    required LevelUpAppState notifier,
    required super.child,
  }) : super(notifier: notifier);

  static LevelUpAppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LevelUpScope>();
    assert(scope != null, 'LevelUpScope not found in widget tree.');
    return scope!.notifier!;
  }

  static LevelUpAppState read(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<LevelUpScope>();
    final scope = element?.widget as LevelUpScope?;
    assert(scope != null, 'LevelUpScope not found in widget tree.');
    return scope!.notifier!;
  }
}
