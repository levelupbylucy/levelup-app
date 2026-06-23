import SwiftUI
import WidgetKit

private let appGroupId = "group.com.lucienadvornik.levelup"

struct LevelUpTask: Decodable, Hashable {
  let title: String
  let completed: Bool
}

struct LevelUpEntry: TimelineEntry {
  let date: Date
  let todayCompletedTasks: Int
  let todayTotalTasks: Int
  let currentStreak: Int
  let todayFocusTask: String
  let todayFocusGoal: String
  let futureVision: String
  let visionClarity: Int
  let identityTags: [String]
  let currentGoalTitle: String
  let currentGoalProgress: Int
  let currentGoalTask: String
  let currentGoalTargetDate: String
  let quoteOfTheDay: String
  let tasks: [LevelUpTask]
}

struct LevelUpProvider: TimelineProvider {
  func placeholder(in context: Context) -> LevelUpEntry {
    LevelUpEntry.sample
  }

  func getSnapshot(in context: Context, completion: @escaping (LevelUpEntry) -> Void) {
    completion(readEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<LevelUpEntry>) -> Void) {
    let entry = readEntry()
    let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
    completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
  }

  private func readEntry() -> LevelUpEntry {
    let defaults = UserDefaults(suiteName: appGroupId)
    let tasksJson = defaults?.string(forKey: "widget_tasks_json") ?? "[]"
    let tasksData = Data(tasksJson.utf8)
    let tasks = (try? JSONDecoder().decode([LevelUpTask].self, from: tasksData)) ?? []
    let identities = defaults?.stringArray(forKey: "identityTags") ?? []

    return LevelUpEntry(
      date: Date(),
      todayCompletedTasks: defaults?.integer(forKey: "todayCompletedTasks") ?? defaults?.integer(forKey: "widget_completed_tasks") ?? 3,
      todayTotalTasks: defaults?.integer(forKey: "todayTotalTasks") ?? defaults?.integer(forKey: "widget_total_tasks") ?? 5,
      currentStreak: defaults?.integer(forKey: "currentStreak") ?? defaults?.integer(forKey: "widget_streak") ?? 4,
      todayFocusTask: defaults?.string(forKey: "todayFocusTask") ?? "Run 5 km",
      todayFocusGoal: defaults?.string(forKey: "todayFocusGoal") ?? "Run Half Marathon",
      futureVision: defaults?.string(forKey: "futureVision") ?? "I am healthy, confident and financially free.",
      visionClarity: defaults?.integer(forKey: "visionClarity") == 0 ? 78 : defaults?.integer(forKey: "visionClarity") ?? 78,
      identityTags: identities.isEmpty ? ["Healthy", "Successful", "Disciplined", "Confident", "Financially Free"] : identities,
      currentGoalTitle: defaults?.string(forKey: "currentGoalTitle") ?? "Run Half Marathon",
      currentGoalProgress: defaults?.integer(forKey: "currentGoalProgress") == 0 ? 62 : defaults?.integer(forKey: "currentGoalProgress") ?? 62,
      currentGoalTask: defaults?.string(forKey: "currentGoalTask") ?? "Run 10 km",
      currentGoalTargetDate: defaults?.string(forKey: "currentGoalTargetDate") ?? "October 25, 2025",
      quoteOfTheDay: defaults?.string(forKey: "quoteOfTheDay") ?? defaults?.string(forKey: "widget_quote") ?? "Small actions repeated daily create extraordinary lives.",
      tasks: tasks.isEmpty ? LevelUpEntry.sample.tasks : tasks
    )
  }
}

extension LevelUpEntry {
  static let sample = LevelUpEntry(
    date: Date(),
    todayCompletedTasks: 3,
    todayTotalTasks: 5,
    currentStreak: 4,
    todayFocusTask: "Run 5 km",
    todayFocusGoal: "Run Half Marathon",
    futureVision: "I am healthy, confident and financially free.",
    visionClarity: 78,
    identityTags: ["Healthy", "Successful", "Disciplined", "Confident", "Financially Free"],
    currentGoalTitle: "Run Half Marathon",
    currentGoalProgress: 62,
    currentGoalTask: "Run 10 km",
    currentGoalTargetDate: "October 25, 2025",
    quoteOfTheDay: "Small actions repeated daily create extraordinary lives.",
    tasks: [
      LevelUpTask(title: "Run 5 km", completed: true),
      LevelUpTask(title: "Mobility", completed: true),
      LevelUpTask(title: "Plan dinner", completed: false)
    ]
  )
}

private enum LevelUpStyle {
  static let cream = Color(red: 0.969, green: 0.957, blue: 0.925)
  static let card = Color(red: 0.984, green: 0.976, blue: 0.957)
  static let sage = Color(red: 0.365, green: 0.478, blue: 0.271)
  static let lightSage = Color(red: 0.867, green: 0.894, blue: 0.827)
  static let ink = Color(red: 0.114, green: 0.114, blue: 0.106)
  static let muted = Color(red: 0.439, green: 0.439, blue: 0.439)
}

struct WidgetShell<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    Link(destination: URL(string: "levelup://home")!) {
      ZStack(alignment: .topLeading) {
        LevelUpStyle.cream
        SubtleGlow()
        content.padding(18)
      }
      .containerBackground(LevelUpStyle.cream, for: .widget)
    }
  }
}

struct BrandRow: View {
  var body: some View {
    HStack {
      Text("LevelUp")
        .font(.system(size: 16, weight: .bold, design: .rounded))
        .foregroundStyle(LevelUpStyle.sage)
      Spacer()
      Image(systemName: "leaf.fill")
        .foregroundStyle(LevelUpStyle.sage)
        .font(.system(size: 14, weight: .bold))
    }
  }
}

struct SubtleGlow: View {
  var body: some View {
    ZStack {
      Circle()
        .fill(LevelUpStyle.lightSage.opacity(0.32))
        .frame(width: 180, height: 180)
        .blur(radius: 20)
        .offset(x: 80, y: 50)
      MountainSilhouette()
        .fill(LevelUpStyle.sage.opacity(0.15))
        .frame(height: 95)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
  }
}

struct MountainSilhouette: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.width * 0.45, y: rect.height * 0.55))
    path.addLine(to: CGPoint(x: rect.width * 0.68, y: rect.height * 0.10))
    path.addLine(to: CGPoint(x: rect.width * 0.92, y: rect.height * 0.48))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.38))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

struct Ring: View {
  let progress: Double
  let lineWidth: CGFloat

  var body: some View {
    ZStack {
      Circle().stroke(LevelUpStyle.lightSage.opacity(0.75), lineWidth: lineWidth)
      Circle()
        .trim(from: 0, to: min(max(progress, 0), 1))
        .stroke(LevelUpStyle.sage, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
      Text("\(Int(progress * 100))%")
        .font(.system(size: 18, weight: .semibold, design: .rounded))
        .foregroundStyle(LevelUpStyle.sage)
    }
  }
}

struct IdentityPill: View {
  let label: String
  let icon: String

  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: icon)
        .font(.caption.weight(.semibold))
      Text(label)
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .lineLimit(1)
    }
    .foregroundStyle(LevelUpStyle.sage)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(.white.opacity(0.55), in: Capsule())
  }
}

struct DailyProgressWidgetView: View {
  let entry: LevelUpEntry
  private var progress: Double { entry.todayTotalTasks == 0 ? 0 : Double(entry.todayCompletedTasks) / Double(entry.todayTotalTasks) }

  var body: some View {
    WidgetShell {
      VStack(alignment: .leading, spacing: 11) {
        BrandRow()
        HStack(alignment: .center) {
          VStack(alignment: .leading, spacing: 3) {
            Text("🔥 \(entry.currentStreak)")
              .font(.system(size: 27, weight: .bold, design: .rounded))
              .foregroundStyle(LevelUpStyle.sage)
            Text("DAY STREAK")
              .font(.system(size: 11, weight: .bold, design: .rounded))
              .foregroundStyle(LevelUpStyle.sage)
          }
          Spacer()
          Ring(progress: progress, lineWidth: 8)
            .frame(width: 58, height: 58)
        }
        Divider().opacity(0.45)
        Text("\(entry.todayCompletedTasks) / \(max(entry.todayTotalTasks, 0)) tasks")
          .font(.system(size: 17, weight: .semibold, design: .rounded))
          .foregroundStyle(LevelUpStyle.ink)
        HStack(spacing: 9) {
          ForEach(0..<max(entry.todayTotalTasks, 1), id: \.self) { index in
            Circle()
              .fill(index < entry.todayCompletedTasks ? LevelUpStyle.sage : LevelUpStyle.lightSage.opacity(0.65))
              .frame(width: 10, height: 10)
          }
        }
        Text(entry.todayCompletedTasks >= entry.todayTotalTasks && entry.todayTotalTasks > 0 ? "You did it." : "Keep going.")
          .font(.system(size: 13, weight: .medium, design: .rounded))
          .foregroundStyle(LevelUpStyle.muted)
      }
    }
  }
}

struct TodaysFocusWidgetView: View {
  let entry: LevelUpEntry

  var body: some View {
    WidgetShell {
      VStack(alignment: .leading, spacing: 14) {
        BrandRow()
        Text("TODAY’S FOCUS")
          .font(.caption.weight(.bold))
          .foregroundStyle(LevelUpStyle.sage)
        HStack(spacing: 14) {
          Image(systemName: "figure.run")
            .font(.title2.weight(.bold))
            .foregroundStyle(LevelUpStyle.sage)
            .frame(width: 44, height: 44)
            .background(LevelUpStyle.lightSage.opacity(0.72), in: Circle())
          VStack(alignment: .leading, spacing: 6) {
            Text(entry.todayFocusTask)
              .font(.system(size: 25, weight: .semibold, design: .serif))
              .foregroundStyle(LevelUpStyle.ink)
              .lineLimit(1)
            Text("Goal: \(entry.todayFocusGoal)")
              .font(.system(size: 15, weight: .medium, design: .rounded))
              .foregroundStyle(LevelUpStyle.muted)
              .lineLimit(1)
          }
        }
        Divider().opacity(0.42)
        HStack {
          Image(systemName: "checkmark")
            .font(.caption.weight(.bold))
            .foregroundStyle(LevelUpStyle.sage)
            .frame(width: 28, height: 28)
            .background(.white.opacity(0.56), in: Circle())
          Text("\(entry.todayCompletedTasks) / \(entry.todayTotalTasks) tasks complete")
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(LevelUpStyle.sage)
        }
      }
    }
  }
}

struct FutureMeWidgetView: View {
  let entry: LevelUpEntry

  var body: some View {
    WidgetShell {
      VStack(alignment: .leading, spacing: 13) {
        BrandRow()
        Text("FUTURE ME")
          .font(.caption.weight(.bold))
          .foregroundStyle(LevelUpStyle.sage)
        Text("“")
          .font(.system(size: 44, weight: .bold, design: .serif))
          .foregroundStyle(LevelUpStyle.lightSage)
          .overlay(alignment: .leading) {
            Text(entry.futureVision)
              .font(.system(size: 22, weight: .regular, design: .serif))
              .foregroundStyle(LevelUpStyle.ink)
              .lineLimit(3)
              .padding(.leading, 24)
              .padding(.top, 16)
          }
        Spacer()
        Divider().opacity(0.36)
        HStack {
          Image(systemName: "sparkles")
            .foregroundStyle(LevelUpStyle.sage)
            .frame(width: 28, height: 28)
            .background(LevelUpStyle.lightSage.opacity(0.65), in: Circle())
          Text("\(entry.visionClarity)% clarity")
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundStyle(LevelUpStyle.sage)
        }
      }
    }
  }
}

struct VisionWidgetView: View {
  let entry: LevelUpEntry

  var body: some View {
    WidgetShell {
      HStack(alignment: .top, spacing: 24) {
        VStack(alignment: .leading, spacing: 18) {
          BrandRow()
          Text("MY VISION")
            .font(.caption.weight(.bold))
            .foregroundStyle(LevelUpStyle.sage)
          Text(entry.futureVision)
            .font(.system(size: 25, weight: .regular, design: .serif))
            .foregroundStyle(LevelUpStyle.ink)
            .lineLimit(5)
          Spacer()
        }
        VStack(alignment: .leading, spacing: 8) {
          ForEach(Array(entry.identityTags.prefix(5).enumerated()), id: \.offset) { index, tag in
            IdentityPill(label: tag, icon: ["heart", "trophy", "target", "star", "dollarsign.circle"][index % 5])
          }
          Spacer()
        }
        .padding(.top, 44)
      }
    }
  }
}

struct GoalProgressWidgetView: View {
  let entry: LevelUpEntry

  var body: some View {
    WidgetShell {
      HStack(spacing: 22) {
        VStack(alignment: .leading, spacing: 13) {
          BrandRow()
          Text("CURRENT GOAL")
            .font(.caption.weight(.bold))
            .foregroundStyle(LevelUpStyle.sage)
          Text(entry.currentGoalTitle)
            .font(.system(size: 25, weight: .regular, design: .serif))
            .foregroundStyle(LevelUpStyle.ink)
            .lineLimit(2)
          Spacer()
          Ring(progress: Double(entry.currentGoalProgress) / 100, lineWidth: 10)
            .frame(width: 92, height: 92)
        }
        Divider().opacity(0.32)
        VStack(alignment: .leading, spacing: 18) {
          Spacer(minLength: 40)
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text("Current task")
                .font(.caption.weight(.bold))
                .foregroundStyle(LevelUpStyle.sage)
              Text(entry.currentGoalTask)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(LevelUpStyle.ink)
                .lineLimit(1)
            }
          } icon: {
            Image(systemName: "figure.run")
              .foregroundStyle(LevelUpStyle.sage)
          }
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text("Target")
                .font(.caption.weight(.bold))
                .foregroundStyle(LevelUpStyle.sage)
              Text(entry.currentGoalTargetDate)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(LevelUpStyle.ink)
                .lineLimit(1)
            }
          } icon: {
            Image(systemName: "calendar")
              .foregroundStyle(LevelUpStyle.sage)
          }
          Spacer()
        }
      }
    }
  }
}

struct QuoteWidgetView: View {
  let entry: LevelUpEntry

  var body: some View {
    WidgetShell {
      HStack(spacing: 18) {
        Text("“")
          .font(.system(size: 54, weight: .bold, design: .serif))
          .foregroundStyle(LevelUpStyle.sage.opacity(0.25))
          .frame(width: 58, height: 58)
          .background(LevelUpStyle.lightSage.opacity(0.55), in: Circle())
        VStack(alignment: .leading, spacing: 8) {
          Text("QUOTE OF THE DAY")
            .font(.caption.weight(.bold))
            .foregroundStyle(LevelUpStyle.sage)
          Text(entry.quoteOfTheDay)
            .font(.system(size: 20, weight: .regular, design: .serif))
            .foregroundStyle(LevelUpStyle.ink)
            .lineLimit(2)
        }
        Spacer()
        Image(systemName: "leaf")
          .font(.system(size: 48))
          .foregroundStyle(LevelUpStyle.sage.opacity(0.18))
      }
    }
  }
}

struct DailyProgressWidget: Widget {
  let kind = "LevelUpDailyProgressWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: LevelUpProvider()) { entry in
      DailyProgressWidgetView(entry: entry)
    }
    .configurationDisplayName("LevelUp Daily Progress")
    .description("See your streak and daily task progress.")
    .supportedFamilies([.systemSmall])
  }
}

struct TodaysFocusWidget: Widget {
  let kind = "LevelUpTodaysFocusWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: LevelUpProvider()) { entry in
      TodaysFocusWidgetView(entry: entry)
    }
    .configurationDisplayName("Today’s Focus")
    .description("See your most important task today.")
    .supportedFamilies([.systemMedium])
  }
}

struct FutureMeWidget: Widget {
  let kind = "LevelUpFutureMeWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: LevelUpProvider()) { entry in
      FutureMeWidgetView(entry: entry)
    }
    .configurationDisplayName("Future Me")
    .description("Keep your future identity visible.")
    .supportedFamilies([.systemMedium])
  }
}

struct VisionWidget: Widget {
  let kind = "LevelUpVisionWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: LevelUpProvider()) { entry in
      VisionWidgetView(entry: entry)
    }
    .configurationDisplayName("My Vision")
    .description("Display your vision and identity tags.")
    .supportedFamilies([.systemLarge])
  }
}

struct GoalProgressWidget: Widget {
  let kind = "LevelUpGoalProgressWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: LevelUpProvider()) { entry in
      GoalProgressWidgetView(entry: entry)
    }
    .configurationDisplayName("Goal Progress")
    .description("Track your current priority goal.")
    .supportedFamilies([.systemLarge])
  }
}

struct QuoteOfTheDayWidget: Widget {
  let kind = "LevelUpQuoteOfTheDayWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: LevelUpProvider()) { entry in
      QuoteWidgetView(entry: entry)
    }
    .configurationDisplayName("Quote of the Day")
    .description("Daily motivation from LevelUp.")
    .supportedFamilies([.systemMedium])
  }
}

@main
struct LevelUpWidgets: WidgetBundle {
  @WidgetBundleBuilder
  var body: some Widget {
    DailyProgressWidget()
    TodaysFocusWidget()
    FutureMeWidget()
    VisionWidget()
    GoalProgressWidget()
    QuoteOfTheDayWidget()
  }
}
