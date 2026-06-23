# levelup_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


## Level Up MVP Task 4

This version connects Home and Goals to LevelUpAppState.

Added/updated:
- Home reads user name, streak, missions and progress from AppState.
- Mission completion persists through shared preferences.
- Goals reads active/completed goals from AppState.
- Add Goal now saves into persistent AppState storage.
- Empty states were added for missing missions/goals.
- Startup gate now shows onboarding when onboarding is incomplete or user name is empty.

Run after unzip:

```bash
flutter pub get
flutter analyze
flutter run
```
