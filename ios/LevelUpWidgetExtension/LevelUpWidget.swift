import AppIntents
import SwiftUI
import WidgetKit

private let appGroupId = "group.com.lucienadvornik.levelup"

struct LevelUpTask: Codable, Hashable, Identifiable {
  let id: String
  let title: String
  var completed: Bool

  init(id: String, title: String, completed: Bool) {
    self.id = id.isEmpty ? LevelUpTask.fallbackId(for: title) : id
    self.title = title
    self.completed = completed
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Daily task"
    let id = try container.decodeIfPresent(String.self, forKey: .id) ?? LevelUpTask.fallbackId(for: title)
    self.init(id: id, title: title, completed: try container.decodeIfPresent(Bool.self, forKey: .completed) ?? false)
  }

  private enum CodingKeys: String, CodingKey { case id, title, completed }

  private static func fallbackId(for title: String) -> String {
    title.lowercased()
      .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  }
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

enum LevelUpWidgetStore {
  static let quotes = [
    "Small promises kept quietly become identity.",
    "A future life is built in ordinary minutes.",
    "The next right action is enough for today.",
    "Consistency is self trust made visible.",
    "You do not need a perfect day to make progress.",
    "One completed task is proof that you are moving.",
    "Start small enough that resistance has less to hold.",
    "Your habits are votes for the person you are becoming.",
    "Make the next step clear, then make it real.",
    "Progress likes repetition more than intensity.",
    "The future self you imagine needs evidence today.",
    "A calm plan beats a dramatic restart.",
    "Return to the path before you judge the pace.",
    "What you track gently becomes easier to change.",
    "Discipline can feel quiet, kind and steady.",
    "The smallest useful action still counts.",
    "You are allowed to build slowly and still build deeply.",
    "Clarity grows when action creates feedback.",
    "Keep one promise and let that be the win.",
    "A missed day is information, not identity.",
    "Focus is choosing what matters before the day chooses for you.",
    "Your calendar is a mirror. Use it with kindness.",
    "Every checked task is a small receipt from your future self.",
    "Make it simple enough to repeat tomorrow.",
    "Energy follows motion more often than waiting.",
    "The goal is not pressure. The goal is direction.",
    "Today can be a quiet turning point.",
    "Identity changes through repeated evidence.",
    "Let progress be practical before it becomes impressive.",
    "Small actions repeated daily create extraordinary lives."
  ]

  static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupId) }

  static func readEntry() -> LevelUpEntry {
    let defaults = defaults
    let tasks = readTasks()
    let totalTasks = intValue("todayTotalTasks", fallbackKey: "widget_total_tasks", defaultValue: max(tasks.count, 3))
    let completedTasks = intValue("todayCompletedTasks", fallbackKey: "widget_completed_tasks", defaultValue: tasks.filter(\.completed).count)
    let identities = defaults?.stringArray(forKey: "identityTags") ?? []
    let fallbackQuote = quoteForToday()

    return LevelUpEntry(
      date: Date(),
      todayCompletedTasks: completedTasks,
      todayTotalTasks: max(totalTasks, tasks.count),
      currentStreak: intValue("currentStreak", fallbackKey: "widget_streak", defaultValue: 4),
      todayFocusTask: stringValue("todayFocusTask", defaultValue: tasks.first(where: { !$0.completed })?.title ?? tasks.first?.title ?? "Choose today’s focus"),
      todayFocusGoal: stringValue("todayFocusGoal", defaultValue: "LevelUp"),
      futureVision: stringValue("futureVision", defaultValue: "I am healthy, confident and becoming the person I want to be."),
      visionClarity: intValue("visionClarity", defaultValue: 78),
      identityTags: identities.isEmpty ? ["Healthy", "Disciplined", "Confident", "Focused"] : identities,
      currentGoalTitle: stringValue("currentGoalTitle", defaultValue: "Create your first goal"),
      currentGoalProgress: intValue("currentGoalProgress", defaultValue: 0),
      currentGoalTask: stringValue("currentGoalTask", defaultValue: tasks.first(where: { !$0.completed })?.title ?? "Choose today’s task"),
      currentGoalTargetDate: stringValue("currentGoalTargetDate", defaultValue: "No target date"),
      quoteOfTheDay: defaults?.string(forKey: "widget_quote") ?? defaults?.string(forKey: "quoteOfTheDay") ?? fallbackQuote,
      tasks: tasks
    )
  }

  static func toggleTask(id: String) {
    var tasks = readTasks()
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    tasks[index].completed.toggle()
    save(tasks: tasks)
  }

  static func completeNextTask() {
    var tasks = readTasks()
    if let index = tasks.firstIndex(where: { !$0.completed }) {
      tasks[index].completed = true
    } else if !tasks.isEmpty {
      tasks = tasks.map { LevelUpTask(id: $0.id, title: $0.title, completed: false) }
    }
    save(tasks: tasks)
  }

  static func advanceQuote() {
    let current = defaults?.integer(forKey: "widget_quote_offset") ?? 0
    let next = (current + 1) % quotes.count
    defaults?.set(next, forKey: "widget_quote_offset")
    defaults?.set(quotes[next], forKey: "widget_quote")
    defaults?.set(Date().ISO8601Format(), forKey: "widget_last_updated")
    defaults?.synchronize()
    WidgetCenter.shared.reloadAllTimelines()
  }

  private static func readTasks() -> [LevelUpTask] {
    let tasksJson = defaults?.string(forKey: "widget_tasks_json") ?? "[]"
    let decoded = try? JSONDecoder().decode([LevelUpTask].self, from: Data(tasksJson.utf8))
    let tasks = decoded ?? []
    if tasks.isEmpty {
      return [
        LevelUpTask(id: "sample-run", title: "Run 5 km", completed: true),
        LevelUpTask(id: "sample-plan", title: "Plan tomorrow", completed: false),
        LevelUpTask(id: "sample-reflect", title: "Evening reflection", completed: false)
      ]
    }
    return tasks
  }

  private static func save(tasks: [LevelUpTask]) {
    let encoded = (try? JSONEncoder().encode(tasks)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    defaults?.set(encoded, forKey: "widget_tasks_json")
    defaults?.set(tasks.filter(\.completed).count, forKey: "widget_completed_tasks")
    defaults?.set(tasks.count, forKey: "widget_total_tasks")
    defaults?.set(tasks.filter(\.completed).count, forKey: "todayCompletedTasks")
    defaults?.set(tasks.count, forKey: "todayTotalTasks")
    defaults?.set(Date().ISO8601Format(), forKey: "widget_last_updated")
    defaults?.synchronize()
    WidgetCenter.shared.reloadAllTimelines()
  }

  private static func stringValue(_ key: String, defaultValue: String) -> String {
    let value = defaults?.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return value?.isEmpty == false ? value! : defaultValue
  }

  private static func intValue(_ key: String, fallbackKey: String? = nil, defaultValue: Int) -> Int {
    if let value = defaults?.object(forKey: key) as? Int { return value }
    if let fallbackKey, let value = defaults?.object(forKey: fallbackKey) as? Int { return value }
    return defaultValue
  }

  private static func quoteForToday() -> String {
    let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
    return quotes[abs(day) % quotes.count]
  }
}

struct ToggleTaskIntent: AppIntent {
  static var title: LocalizedStringResource = "Toggle LevelUp Task"
  static var description = IntentDescription("Marks a LevelUp task complete or incomplete directly from the widget.")
  @Parameter(title: "Task ID") var taskId: String
  init() { taskId = "" }
  init(taskId: String) { self.taskId = taskId }
  func perform() async throws -> some IntentResult {
    LevelUpWidgetStore.toggleTask(id: taskId)
    return .result()
  }
}

struct CompleteNextTaskIntent: AppIntent {
  static var title: LocalizedStringResource = "Complete Next LevelUp Task"
  static var description = IntentDescription("Completes the next unfinished LevelUp task directly from the widget.")
  func perform() async throws -> some IntentResult {
    LevelUpWidgetStore.completeNextTask()
    return .result()
  }
}

struct AdvanceLucyQuoteIntent: AppIntent {
  static var title: LocalizedStringResource = "New Lucy Quote"
  static var description = IntentDescription("Shows another science-based Lucy quote in the widget.")
  func perform() async throws -> some IntentResult {
    LevelUpWidgetStore.advanceQuote()
    return .result()
  }
}

struct LevelUpProvider: TimelineProvider {
  func placeholder(in context: Context) -> LevelUpEntry { LevelUpEntry.sample }
  func getSnapshot(in context: Context, completion: @escaping (LevelUpEntry) -> Void) { completion(LevelUpWidgetStore.readEntry()) }
  func getTimeline(in context: Context, completion: @escaping (Timeline<LevelUpEntry>) -> Void) {
    let entry = LevelUpWidgetStore.readEntry()
    let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
    completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
  }
}

extension LevelUpEntry {
  static let sample = LevelUpEntry(
    date: Date(),
    todayCompletedTasks: 1,
    todayTotalTasks: 3,
    currentStreak: 4,
    todayFocusTask: "Run 5 km",
    todayFocusGoal: "Run Half Marathon",
    futureVision: "I am healthy, confident and becoming the person I want to be.",
    visionClarity: 78,
    identityTags: ["Healthy", "Disciplined", "Confident", "Focused"],
    currentGoalTitle: "Run Half Marathon",
    currentGoalProgress: 62,
    currentGoalTask: "Run 10 km",
    currentGoalTargetDate: "October 25, 2026",
    quoteOfTheDay: "Small actions repeated daily create extraordinary lives.",
    tasks: [
      LevelUpTask(id: "sample-run", title: "Run 5 km", completed: true),
      LevelUpTask(id: "sample-plan", title: "Plan tomorrow", completed: false),
      LevelUpTask(id: "sample-reflect", title: "Evening reflection", completed: false)
    ]
  )
}

private enum LevelUpStyle {
  static let cream = Color(red: 0.969, green: 0.957, blue: 0.925)
  static let sage = Color(red: 0.365, green: 0.478, blue: 0.271)
  static let lightSage = Color(red: 0.867, green: 0.894, blue: 0.827)
  static let ink = Color(red: 0.114, green: 0.114, blue: 0.106)
  static let muted = Color(red: 0.439, green: 0.439, blue: 0.439)
}

struct WidgetShell<Content: View>: View {
  let content: Content
  init(@ViewBuilder content: () -> Content) { self.content = content() }
  var body: some View {
    ZStack(alignment: .topLeading) {
      LevelUpStyle.cream
      SubtleGlow()
      content.padding(12)
    }
    .containerBackground(LevelUpStyle.cream, for: .widget)
  }
}

struct BrandRow: View {
  var body: some View {
    HStack {
      Text("LevelUp").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(LevelUpStyle.sage)
      Spacer()
      Image(systemName: "leaf.fill").foregroundStyle(LevelUpStyle.sage).font(.system(size: 12, weight: .bold))
    }
  }
}

struct SubtleGlow: View {
  var body: some View {
    ZStack {
      Circle().fill(LevelUpStyle.lightSage.opacity(0.28)).frame(width: 150, height: 150).blur(radius: 18).offset(x: 76, y: 52)
      MountainSilhouette().fill(LevelUpStyle.sage.opacity(0.12)).frame(height: 78).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
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
      Circle().stroke(LevelUpStyle.lightSage.opacity(0.72), lineWidth: lineWidth)
      Circle().trim(from: 0, to: min(max(progress, 0), 1)).stroke(LevelUpStyle.sage, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)).rotationEffect(.degrees(-90))
      Text("\(Int(progress * 100))%").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(LevelUpStyle.sage)
    }
  }
}

struct IntentPill<Label: View>: View {
  let action: Label
  init(@ViewBuilder action: () -> Label) { self.action = action() }
  var body: some View {
    action.font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(LevelUpStyle.sage).padding(.horizontal, 8).padding(.vertical, 5).background(.white.opacity(0.58), in: Capsule())
  }
}

struct TaskToggleRow: View {
  let task: LevelUpTask
  var body: some View {
    Button(intent: ToggleTaskIntent(taskId: task.id)) {
      HStack(spacing: 8) {
        Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").font(.system(size: 17, weight: .semibold)).foregroundStyle(task.completed ? LevelUpStyle.sage : LevelUpStyle.muted)
        Text(task.title).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(LevelUpStyle.ink).lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 9).padding(.vertical, 5).background(.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }.buttonStyle(.plain)
  }
}

struct DailyProgressWidgetView: View {
  let entry: LevelUpEntry
  private var progress: Double { entry.todayTotalTasks == 0 ? 0 : Double(entry.todayCompletedTasks) / Double(entry.todayTotalTasks) }
  var body: some View {
    WidgetShell {
      VStack(alignment: .leading, spacing: 8) {
        BrandRow()
        HStack(alignment: .center) {
          VStack(alignment: .leading, spacing: 3) {
            Text("🔥 \(entry.currentStreak)").font(.system(size: 21, weight: .bold, design: .rounded)).foregroundStyle(LevelUpStyle.sage)
            Text("DAY STREAK").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(LevelUpStyle.sage)
          }
          Spacer()
          Ring(progress: progress, lineWidth: 7).frame(width: 48, height: 48)
        }
        Text("\(entry.todayCompletedTasks) / \(entry.todayTotalTasks) tasks").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(LevelUpStyle.ink)
        Button(intent: CompleteNextTaskIntent()) { IntentPill { Label("Mark next", systemImage: "checkmark") } }.buttonStyle(.plain)
      }
    }
  }
}

struct TodaysFocusWidgetView: View {
  let entry: LevelUpEntry
  var body: some View {
    WidgetShell {
      VStack(alignment: .leading, spacing: 8) {
        BrandRow()
        Text("TODAY’S FOCUS").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(LevelUpStyle.sage)
        HStack(spacing: 10) {
          Image(systemName: "figure.run").font(.system(size: 17, weight: .bold)).foregroundStyle(LevelUpStyle.sage).frame(width: 36, height: 36).background(LevelUpStyle.lightSage.opacity(0.72), in: Circle())
          VStack(alignment: .leading, spacing: 3) {
            Text(entry.todayFocusTask).font(.system(size: 18, weight: .semibold, design: .serif)).foregroundStyle(LevelUpStyle.ink).lineLimit(1)
            Text("Goal: \(entry.todayFocusGoal)").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(LevelUpStyle.muted).lineLimit(1)
          }
        }
        VStack(spacing: 5) { ForEach(Array(entry.tasks.prefix(2))) { task in TaskToggleRow(task: task) } }
      }
    }
  }
}

struct FutureMeWidgetView: View {
  let entry: LevelUpEntry
  var body: some View {
    WidgetShell {
      VStack(alignment: .leading, spacing: 11) {
        BrandRow()
        Text("FUTURE ME").font(.caption.weight(.bold)).foregroundStyle(LevelUpStyle.sage)
        Text(entry.futureVision).font(.system(size: 22, weight: .regular, design: .serif)).foregroundStyle(LevelUpStyle.ink).lineLimit(3)
        Spacer(minLength: 2)
        HStack {
          Image(systemName: "sparkles").foregroundStyle(LevelUpStyle.sage).frame(width: 28, height: 28).background(LevelUpStyle.lightSage.opacity(0.65), in: Circle())
          Text("\(entry.visionClarity)% clarity").font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(LevelUpStyle.sage)
          Spacer()
          Button(intent: CompleteNextTaskIntent()) { Image(systemName: "checkmark.circle").foregroundStyle(LevelUpStyle.sage) }.buttonStyle(.plain)
        }
      }
    }
  }
}

struct IdentityPill: View {
  let label: String
  let icon: String
  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: icon).font(.caption.weight(.semibold))
      Text(label).font(.system(size: 13, weight: .medium, design: .rounded)).lineLimit(1)
    }.foregroundStyle(LevelUpStyle.sage).padding(.horizontal, 10).padding(.vertical, 6).background(.white.opacity(0.55), in: Capsule())
  }
}

struct VisionWidgetView: View {
  let entry: LevelUpEntry
  var body: some View {
    WidgetShell {
      HStack(alignment: .top, spacing: 20) {
        VStack(alignment: .leading, spacing: 15) {
          BrandRow()
          Text("MY VISION").font(.caption.weight(.bold)).foregroundStyle(LevelUpStyle.sage)
          Text(entry.futureVision).font(.system(size: 24, weight: .regular, design: .serif)).foregroundStyle(LevelUpStyle.ink).lineLimit(5)
          Spacer()
          Button(intent: CompleteNextTaskIntent()) { IntentPill { Label("Complete next task", systemImage: "checkmark") } }.buttonStyle(.plain)
        }
        VStack(alignment: .leading, spacing: 8) {
          ForEach(Array(entry.identityTags.prefix(5).enumerated()), id: \.offset) { index, tag in IdentityPill(label: tag, icon: ["heart", "trophy", "target", "star", "dollarsign.circle"][index % 5]) }
          Spacer()
        }.padding(.top, 44)
      }
    }
  }
}

struct GoalProgressWidgetView: View {
  let entry: LevelUpEntry
  var body: some View {
    WidgetShell {
      HStack(spacing: 18) {
        VStack(alignment: .leading, spacing: 12) {
          BrandRow()
          Text("CURRENT GOAL").font(.caption.weight(.bold)).foregroundStyle(LevelUpStyle.sage)
          Text(entry.currentGoalTitle).font(.system(size: 24, weight: .regular, design: .serif)).foregroundStyle(LevelUpStyle.ink).lineLimit(2)
          Spacer()
          Ring(progress: Double(entry.currentGoalProgress) / 100, lineWidth: 10).frame(width: 88, height: 88)
        }
        Divider().opacity(0.32)
        VStack(alignment: .leading, spacing: 14) {
          Spacer(minLength: 28)
          Label { VStack(alignment: .leading, spacing: 2) { Text("Current task").font(.caption.weight(.bold)).foregroundStyle(LevelUpStyle.sage); Text(entry.currentGoalTask).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(LevelUpStyle.ink).lineLimit(1) } } icon: { Image(systemName: "figure.run").foregroundStyle(LevelUpStyle.sage) }
          Label { VStack(alignment: .leading, spacing: 2) { Text("Target").font(.caption.weight(.bold)).foregroundStyle(LevelUpStyle.sage); Text(entry.currentGoalTargetDate).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(LevelUpStyle.ink).lineLimit(1) } } icon: { Image(systemName: "calendar").foregroundStyle(LevelUpStyle.sage) }
          Button(intent: CompleteNextTaskIntent()) { IntentPill { Label("Done", systemImage: "checkmark") } }.buttonStyle(.plain)
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
      HStack(spacing: 12) {
        Text("“").font(.system(size: 42, weight: .bold, design: .serif)).foregroundStyle(LevelUpStyle.sage.opacity(0.24)).frame(width: 46, height: 46).background(LevelUpStyle.lightSage.opacity(0.52), in: Circle())
        VStack(alignment: .leading, spacing: 5) {
          Text("QUOTE OF THE DAY").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(LevelUpStyle.sage)
          Text(entry.quoteOfTheDay).font(.system(size: 16, weight: .regular, design: .serif)).foregroundStyle(LevelUpStyle.ink).lineLimit(3)
          Button(intent: AdvanceLucyQuoteIntent()) { IntentPill { Label("New quote", systemImage: "arrow.clockwise") } }.buttonStyle(.plain)
        }
      }
    }
  }
}

struct LucyMessageQuoteWidgetView: View {
  let entry: LevelUpEntry
  var body: some View {
    WidgetShell {
      VStack(alignment: .leading, spacing: 10) {
        BrandRow()
        HStack(alignment: .top, spacing: 10) {
          Circle().fill(LevelUpStyle.lightSage.opacity(0.78)).frame(width: 38, height: 38).overlay { Text("L").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(LevelUpStyle.sage) }
          VStack(alignment: .leading, spacing: 5) {
            Text("Lucy").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(LevelUpStyle.sage)
            Text(entry.quoteOfTheDay).font(.system(size: 16, weight: .regular, design: .serif)).foregroundStyle(LevelUpStyle.ink).lineLimit(4).padding(11).background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
          }
        }
        HStack {
          Button(intent: AdvanceLucyQuoteIntent()) { IntentPill { Label("Another", systemImage: "sparkles") } }.buttonStyle(.plain)
          Button(intent: CompleteNextTaskIntent()) { IntentPill { Label("Did it", systemImage: "checkmark") } }.buttonStyle(.plain)
        }
      }
    }
  }
}

struct DailyProgressWidget: Widget {
  let kind = "LevelUpDailyProgressWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: LevelUpProvider()) { entry in DailyProgressWidgetView(entry: entry) }
      .configurationDisplayName("LevelUp Daily Progress")
      .description("See your streak and mark the next task without opening the app.")
      .supportedFamilies([.systemSmall])
  }
}

struct TodaysFocusWidget: Widget {
  let kind = "LevelUpTodaysFocusWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: LevelUpProvider()) { entry in TodaysFocusWidgetView(entry: entry) }
      .configurationDisplayName("Today’s Focus")
      .description("Check off up to three daily tasks directly on your Home Screen.")
      .supportedFamilies([.systemMedium])
  }
}

struct FutureMeWidget: Widget {
  let kind = "LevelUpFutureMeWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: LevelUpProvider()) { entry in FutureMeWidgetView(entry: entry) }
      .configurationDisplayName("Future Me")
      .description("Keep your future identity visible and complete the next action.")
      .supportedFamilies([.systemMedium])
  }
}

struct VisionWidget: Widget {
  let kind = "LevelUpVisionWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: LevelUpProvider()) { entry in VisionWidgetView(entry: entry) }
      .configurationDisplayName("My Vision")
      .description("Display your vision and identity tags.")
      .supportedFamilies([.systemLarge])
  }
}

struct GoalProgressWidget: Widget {
  let kind = "LevelUpGoalProgressWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: LevelUpProvider()) { entry in GoalProgressWidgetView(entry: entry) }
      .configurationDisplayName("Goal Progress")
      .description("Track your current priority goal and complete the next task.")
      .supportedFamilies([.systemLarge])
  }
}

struct QuoteOfTheDayWidget: Widget {
  let kind = "LevelUpQuoteOfTheDayWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: LevelUpProvider()) { entry in QuoteWidgetView(entry: entry) }
      .configurationDisplayName("Quote of the Day")
      .description("Daily motivation from LevelUp with a refresh action.")
      .supportedFamilies([.systemMedium])
  }
}

struct LucyMessageQuoteWidget: Widget {
  let kind = "LevelUpLucyMessageQuoteWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: LevelUpProvider()) { entry in LucyMessageQuoteWidgetView(entry: entry) }
      .configurationDisplayName("Lucy Message")
      .description("Quote of the day shown as a message from Lucy.")
      .supportedFamilies([.systemMedium])
  }
}

@main
struct LevelUpWidgets: WidgetBundle {
  @WidgetBundleBuilder
  var body: some Widget {
    DailyProgressWidget()
    TodaysFocusWidget()
    QuoteOfTheDayWidget()
  }
}
