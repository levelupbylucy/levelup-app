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
    morningFocus,
    'Small promises kept quietly become identity.',
    'The goal is not a perfect streak. The goal is becoming someone who returns.',
    'One clean action today is enough to keep the future version of you in motion.',
    eveningReflection,
    calendarPattern,
    dayComplete,
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
