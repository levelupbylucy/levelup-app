class LucyMessageCatalog {
  const LucyMessageCatalog._();

  static const calendarPattern =
      'Your calendar is showing the real pattern, not a perfect story. One missed day is just data. Let’s protect the next two days and rebuild rhythm gently.';

  static const eveningReflection =
      'Before the day closes, mark what happened honestly. Progress needs proof, not perfection.';

  static const morningFocus =
      'Pick the one task that would make today feel aligned with your future self.';

  static const taskWin =
      'Tiny, visible proof is how identity gets built. Take the win, then choose the next clean step.';

  static const dayComplete =
      'That is a full day of promises kept. Let it register before you rush to the next thing.';

  static const List<String> dailyMessages = [
    'Small promises kept quietly become identity.',
    'A future life is built in ordinary minutes.',
    'The next right action is enough for today.',
    'Consistency is self trust made visible.',
    'You do not need a perfect day to make progress.',
    'One completed task is proof that you are moving.',
    'Start small enough that resistance has less to hold.',
    'Your habits are votes for the person you are becoming.',
    'Make the next step clear, then make it real.',
    'Progress likes repetition more than intensity.',
    'The future self you imagine needs evidence today.',
    'A calm plan beats a dramatic restart.',
    'Return to the path before you judge the pace.',
    'What you track gently becomes easier to change.',
    'Discipline can feel quiet, kind and steady.',
    'The smallest useful action still counts.',
    'You are allowed to build slowly and still build deeply.',
    'Clarity grows when action creates feedback.',
    'Keep one promise and let that be the win.',
    'A missed day is information, not identity.',
    'Focus is choosing what matters before the day chooses for you.',
    'Your calendar is a mirror. Use it with kindness.',
    'Every checked task is a small receipt from your future self.',
    'Make it simple enough to repeat tomorrow.',
    'Energy follows motion more often than waiting.',
    'The goal is not pressure. The goal is direction.',
    'Today can be a quiet turning point.',
    'Identity changes through repeated evidence.',
    'Let progress be practical before it becomes impressive.',
    'Small actions repeated daily create extraordinary lives.',
  ];

  static String home(String firstName) {
    return 'Identity precedes behaviour. Every rep, every page, every early night — you’re not just building habits, you’re becoming someone who does these things. That person is already in you, $firstName.';
  }

  static String taskCompleted(String firstName) {
    return 'That counted${firstName.isEmpty ? '' : ', $firstName'}. $taskWin';
  }

  static String quoteOfTheDay(DateTime date) {
    final daySeed = DateTime(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime(2026)).inDays.abs();
    return dailyMessages[daySeed % dailyMessages.length];
  }
}
