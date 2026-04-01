import SwiftUI
import Charts
import UserNotifications
import AVFoundation
import SwiftData
import UniformTypeIdentifiers

// MARK: - 📱 APP ENTRY POINT
struct ContentView: View {
    @StateObject private var db = ActivityDatabase.shared
    @StateObject private var stopwatchModel = StopwatchModel()
    @StateObject private var timerModel = TimerModel()
    
    @State private var selection = 0
    @Environment(\.scenePhase) var scenePhase
    
    // Detect if the app is currently running on macOS
    private var isMac: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac || ProcessInfo.processInfo.isMacCatalystApp
    }
    
    var body: some View {
        Group {
            if isMac {
                macOSCustomTabView
            } else {
                iOSTabView
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            NotificationManager.shared.requestPermission()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                stopwatchModel.saveState()
                timerModel.saveState()
            }
        }
    }
    
    // 🔥 The Native Tab View for iOS / iPadOS
    var iOSTabView: some View {
        TabView(selection: $selection) {
            StopwatchView(model: stopwatchModel)
                .tabItem {
                    Image(systemName: "stopwatch.fill")
                    Text("Pacer")
                }.tag(0)
            
            TimerView(model: timerModel)
                .tabItem {
                    Image(systemName: "timer")
                    Text("Exam Timer")
                }.tag(1)
            
            LoggerView(db: db, stopwatch: stopwatchModel, timer: timerModel)
                .tabItem {
                    Image(systemName: "checklist")
                    Text("Log")
                }.tag(2)
            
            StatisticsView(db: db, stopwatch: stopwatchModel, timer: timerModel)
                .tabItem {
                    Image(systemName: "chart.xyaxis.line")
                    Text("Analytics")
                }.tag(3)
        }
        .accentColor(.orange)
        .toolbarBackground(Color.black, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
    
    // 🔥 The Custom Tab View for macOS (Forces True Black Full Screen)
    var macOSCustomTabView: some View {
        VStack(spacing: 0) {
            // Main Content Area
            ZStack {
                if selection == 0 {
                    StopwatchView(model: stopwatchModel)
                } else if selection == 1 {
                    TimerView(model: timerModel)
                } else if selection == 2 {
                    LoggerView(db: db, stopwatch: stopwatchModel, timer: timerModel)
                } else if selection == 3 {
                    StatisticsView(db: db, stopwatch: stopwatchModel, timer: timerModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Custom Tab Bar (Bypasses the macOS Grey Toolbar completely)
            VStack(spacing: 0) {
                Rectangle().fill(Color(white: 0.15)).frame(height: 1)
                HStack(spacing: 0) {
                    CustomTabBarButton(icon: "stopwatch.fill", title: "Pacer", isSelected: selection == 0) { selection = 0 }
                    CustomTabBarButton(icon: "timer", title: "Exam Timer", isSelected: selection == 1) { selection = 1 }
                    CustomTabBarButton(icon: "checklist", title: "Log", isSelected: selection == 2) { selection = 2 }
                    CustomTabBarButton(icon: "chart.xyaxis.line", title: "Analytics", isSelected: selection == 3) { selection = 3 }
                }
                .padding(.top, 10)
                .padding(.bottom, 10)
            }
            .background(Color.black.ignoresSafeArea(edges: .bottom))
        }
        .background(Color.black.ignoresSafeArea())
    }
}

// MARK: - CUSTOM TAB BUTTON
struct CustomTabBarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption2).bold()
            }
            .foregroundColor(isSelected ? .orange : .gray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 🛠️ SHARED UTILITIES
struct AnalyticsHelper {
    static func clampAndSplitLogs(_ logs: [ActivityLog], start: Date, end: Date) -> [ActivityLog] {
        var processedLogs: [ActivityLog] = []
        let cal = Calendar.current
        
        for log in logs {
            var currentStart = log.startDate
            let finalEnd = log.endDate
            let originalDuration = max(1, finalEnd.timeIntervalSince(currentStart))
            
            while currentStart < finalEnd {
                let startOfNextDay = cal.startOfDay(for: currentStart).addingTimeInterval(86400)
                let currentEnd = min(finalEnd, startOfNextDay)
                let segmentDuration = currentEnd.timeIntervalSince(currentStart)
                
                if segmentDuration > 0 {
                    let clampedStart = max(currentStart, start)
                    let clampedEnd = min(currentEnd, end)
                    let clampedDuration = clampedEnd.timeIntervalSince(clampedStart)
                    
                    if clampedDuration > 0 {
                        let ratio = clampedDuration / originalDuration
                        
                        let newLog = ActivityLog(
                            startDate: clampedStart,
                            endDate: clampedEnd,
                            category: log.category,
                            questionsSolved: Int(round(Double(log.questionsSolved) * ratio)),
                            doubtTime: log.doubtTime * ratio,
                            breakTime: log.breakTime * ratio,
                            note: log.note
                        )
                        processedLogs.append(newLog)
                    }
                }
                currentStart = currentEnd
            }
        }
        return processedLogs
    }
}

struct Formatters {
    static let dateLabel: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()
    
    static let timeLabel: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    
    static func formatTime(_ t: TimeInterval) -> String {
        let ti = Int(max(0, t))
        return String(format: "%02d:%02d:%02d", ti / 3600, (ti % 3600) / 60, ti % 60)
    }
    
    static func formatDurationText(_ t: TimeInterval) -> String {
        let ti = Int(max(0, t))
        let h = ti / 3600
        let m = (ti % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

class HapticManager {
    static let shared = HapticManager()
    private let generator = UIImpactFeedbackGenerator(style: .medium)
    init() { generator.prepare() }
    func success() { generator.impactOccurred() }
}

class NotificationManager {
    static let shared = NotificationManager()
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    func scheduleTimerNotification(seconds: TimeInterval) {
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time's Up!"; content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: "tm", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
    func cancelNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

// MARK: - 🗄️ SWIFTDATA MODELS

enum ActivityCategory: String, Codable, CaseIterable, Identifiable {
    case study = "Study", sleep = "Sleep", meal = "Food", waste = "Wasted", other = "Other"
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .study: return .green
        case .sleep: return .indigo
        case .meal: return .cyan
        case .waste: return .red
        case .other: return .purple
        }
    }
    
    var icon: String {
        switch self {
        case .study: return "book.fill"
        case .sleep: return "bed.double.fill"
        case .meal: return "fork.knife"
        case .waste: return "exclamationmark.triangle.fill"
        case .other: return "circle.grid.2x2.fill"
        }
    }
}

@Model
final class ActivityLog: Identifiable, Codable {
    @Attribute(.unique) var id: UUID = UUID()
    var startDate: Date
    var endDate: Date
    var category: ActivityCategory
    var questionsSolved: Int
    var doubtTime: TimeInterval
    var breakTime: TimeInterval
    var note: String?
    
    init(startDate: Date, endDate: Date, category: ActivityCategory, questionsSolved: Int = 0, doubtTime: TimeInterval = 0, breakTime: TimeInterval = 0, note: String? = nil) {
        self.startDate = startDate
        self.endDate = endDate
        self.category = category
        self.questionsSolved = questionsSolved
        self.doubtTime = doubtTime
        self.breakTime = breakTime
        self.note = note
    }
    
    @Transient var duration: TimeInterval { endDate.timeIntervalSince(startDate) }
    
    enum CodingKeys: CodingKey {
        case id, startDate, endDate, category, questionsSolved, doubtTime, breakTime, note
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        category = try container.decode(ActivityCategory.self, forKey: .category)
        questionsSolved = try container.decode(Int.self, forKey: .questionsSolved)
        doubtTime = try container.decode(TimeInterval.self, forKey: .doubtTime)
        breakTime = try container.decode(TimeInterval.self, forKey: .breakTime)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(category, forKey: .category)
        try container.encode(questionsSolved, forKey: .questionsSolved)
        try container.encode(doubtTime, forKey: .doubtTime)
        try container.encode(breakTime, forKey: .breakTime)
        try container.encode(note, forKey: .note)
    }
}

enum AnalyticsScope: String, CaseIterable, Identifiable {
    case today = "Today", yesterday = "Yesterday", week = "Week", month = "Month", year = "Year"
    var id: String { rawValue }
}

// MARK: - 🗄️ DATABASE MANAGER
@MainActor
class ActivityDatabase: ObservableObject {
    static let shared = ActivityDatabase()
    
    let container: ModelContainer
    @Published var logs: [ActivityLog] = []
    
    init() {
        do {
            container = try ModelContainer(for: ActivityLog.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        fetchAll()
    }
    
    func fetchAll() {
        let descriptor = FetchDescriptor<ActivityLog>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        do {
            logs = try container.mainContext.fetch(descriptor)
        } catch {
            print("Fetch failed")
        }
    }
    
    func log(start: Date, end: Date, category: ActivityCategory, questions: Int = 0, doubt: TimeInterval = 0, breakTime: TimeInterval = 0, note: String? = nil) {
        guard end > start else { return }
        let newLog = ActivityLog(startDate: start, endDate: end, category: category, questionsSolved: questions, doubtTime: doubt, breakTime: breakTime, note: note)
        
        container.mainContext.insert(newLog)
        
        withAnimation {
            logs.insert(newLog, at: 0)
        }
        saveContext()
    }
    
    func delete(at offsets: IndexSet) {
        for index in offsets {
            let logToDelete = logs[index]
            container.mainContext.delete(logToDelete)
        }
        logs.remove(atOffsets: offsets)
        saveContext()
    }
    
    func clearAll() {
        do {
            try container.mainContext.delete(model: ActivityLog.self)
            logs.removeAll()
            saveContext()
        } catch {
            print("Failed to clear data")
        }
    }
    
    func getLogs(from start: Date, to end: Date) -> [ActivityLog] {
        return logs.filter { $0.endDate > start && $0.startDate < end }
    }
    
    private func saveContext() {
        try? container.mainContext.save()
    }
    
    // MARK: - 📤📥 EXPORT & IMPORT LOGIC
    func exportTodaysData() -> URL? {
        let cal = Calendar.current
        let todayLogs = getLogs(from: cal.startOfDay(for: Date()), to: Date())
        
        do {
            let data = try JSONEncoder().encode(todayLogs)
            let tempDir = FileManager.default.temporaryDirectory
            let url = tempDir.appendingPathComponent("StudyTracker_\(Int(Date().timeIntervalSince1970)).json")
            try data.write(to: url)
            return url
        } catch {
            print("Failed to export: \(error)")
            return nil
        }
    }
    
    func importData(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let data = try Data(contentsOf: url)
            let importedLogs = try JSONDecoder().decode([ActivityLog].self, from: data)
            
            for log in importedLogs {
                if !logs.contains(where: { $0.id == log.id }) {
                    container.mainContext.insert(log)
                    logs.insert(log, at: 0)
                }
            }
            try container.mainContext.save()
            logs.sort { $0.startDate > $1.startDate }
        } catch {
            print("Failed to import: \(error)")
        }
    }
}

// MARK: - ⏱️ LOGIC MODELS
struct LapItem: Identifiable, Codable {
    var id = UUID(); let index: Int; let time: TimeInterval; let totalTime: TimeInterval
}

protocol SessionTracker {
    var isSessionActive: Bool { get }
    var currentSegmentStart: Date? { get }
    var currentStatus: SessionStatus { get }
    var tempSegments: [ActivityLog] { get }
    var currentSegmentQuestionCount: Int { get }
}

enum SessionStatus: String {
    case running = "Study"
    case doubt = "Doubt"
    case breakMode = "Break"
}

enum StopwatchMode: String, Codable, CaseIterable {
    case solving = "Solving"
    case theory = "Theory"
}

class StopwatchModel: ObservableObject, SessionTracker {
    @Published var isRunning = false
    @Published var isOnBreak = false
    @Published var mode: StopwatchMode = .solving
    @Published var laps: [LapItem] = []
    @Published var accumulated: TimeInterval = 0
    @Published var startTime: Date?
    @Published var accumulatedDoubtTime: TimeInterval = 0
    @Published var accumulatedBreakTime: TimeInterval = 0
    @Published var showBreakCategorySheet = false
    @Published var tempSegments: [ActivityLog] = []
    @Published var currentSegmentQuestionCount = 0
    
    @Published var averageLapTime: TimeInterval = 0
    
    private var lastSwitchTime: Date?
    var lastLapTime: TimeInterval = 0
    private var saveTimer: Timer?
    
    var isSessionActive: Bool { lastSwitchTime != nil }
    var currentSegmentStart: Date? { lastSwitchTime }
    
    var currentStatus: SessionStatus {
        if isOnBreak { return .breakMode }
        if isRunning { return .running }
        return .doubt
    }
    
    init() { loadState() }
    
    var completedQuestionsCount: Int { laps.count }
    
    func getElapsedTime(at date: Date = Date()) -> TimeInterval {
        if isRunning, let start = startTime { return accumulated + date.timeIntervalSince(start) }
        return accumulated
    }
    
    private func updateAverage() {
        averageLapTime = (mode == .theory || laps.isEmpty) ? 0 : laps.reduce(0){$0 + $1.time} / Double(laps.count)
    }
    
    var currentTotalDoubtTime: TimeInterval {
        if !isRunning && !isOnBreak, let last = lastSwitchTime { return accumulatedDoubtTime + Date().timeIntervalSince(last) }
        return accumulatedDoubtTime
    }
    
    var currentTotalBreakTime: TimeInterval {
        if isOnBreak, let last = lastSwitchTime { return accumulatedBreakTime + Date().timeIntervalSince(last) }
        return accumulatedBreakTime
    }
    
    func togglePauseResume() {
        HapticManager.shared.success()
        commitCurrentSegment()
        if isOnBreak { isOnBreak = false; start() }
        else if isRunning { pause() }
        else { start() }
    }
    
    func toggleBreak() {
        HapticManager.shared.success()
        if isOnBreak { showBreakCategorySheet = true }
        else {
            commitCurrentSegment()
            if isRunning { pause() }
            isOnBreak = true
            lastSwitchTime = Date()
            saveState()
        }
    }
    
    func confirmBreakEnd(category: ActivityCategory) {
        commitCurrentSegment(overrideCategory: category)
        isOnBreak = false; start()
    }
    
    private func commitCurrentSegment(overrideCategory: ActivityCategory? = nil) {
        guard let start = lastSwitchTime else { return }
        let end = Date()
        let duration = end.timeIntervalSince(start)
        
        var category: ActivityCategory = .study
        var isDoubt = false
        
        if isOnBreak {
            category = overrideCategory ?? .other
            accumulatedBreakTime += duration
        } else if !isRunning {
            category = .study
            isDoubt = true
            accumulatedDoubtTime += duration
        } else {
            category = .study
        }
        
        if duration > 1 {
            let qCount = (mode == .theory) ? 0 : currentSegmentQuestionCount
            var noteString = ""
            if isDoubt { noteString = "Doubt" }
            else if isOnBreak { noteString = overrideCategory?.rawValue ?? "Break" }
            else { noteString = (mode == .theory) ? "Study: Theory" : "Study: Solving" }
            
            let seg = ActivityLog(startDate: start, endDate: end, category: category, questionsSolved: qCount, doubtTime: isDoubt ? duration : 0, breakTime: isOnBreak ? duration : 0, note: noteString)
            tempSegments.append(seg)
        }
        
        currentSegmentQuestionCount = 0
        lastSwitchTime = Date()
    }
    
    func nextQuestion() {
        guard mode == .solving else { return }
        HapticManager.shared.success()
        currentSegmentQuestionCount += 1
        lap()
    }
    
    func reset() {
        HapticManager.shared.success()
        commitCurrentSegment()
        
        Task { @MainActor in
            for seg in tempSegments {
                ActivityDatabase.shared.log(start: seg.startDate, end: seg.endDate, category: seg.category, questions: seg.questionsSolved, doubt: seg.doubtTime, breakTime: seg.breakTime, note: seg.note)
            }
            tempSegments = []
            
            let d = UserDefaults.standard
            ["sw_accumulated", "sw_lastLapTime", "sw_isRunning", "sw_isOnBreak", "sw_doubt", "sw_break", "sw_segQ", "sw_laps", "sw_segments", "sw_startTime", "sw_lastSwitch"].forEach { d.removeObject(forKey: $0) }
        }
        
        isRunning = false; isOnBreak = false; saveTimer?.invalidate()
        accumulated = 0; startTime = nil; laps = []; lastLapTime = 0
        accumulatedDoubtTime = 0; accumulatedBreakTime = 0
        lastSwitchTime = nil
        currentSegmentQuestionCount = 0
        updateAverage()
    }
    
    private func start() {
        if lastSwitchTime == nil { lastSwitchTime = Date() }
        isOnBreak = false; isRunning = true
        startTime = Date()
        setupSaveTimer()
        saveState()
    }
    
    private func pause() {
        isRunning = false
        if let s = startTime { accumulated += Date().timeIntervalSince(s) }
        startTime = nil
        lastSwitchTime = Date()
        setupSaveTimer()
        saveState()
    }
    
    private func lap() {
        let now = getElapsedTime()
        let diff = now - lastLapTime
        laps.insert(LapItem(index: laps.count + 1, time: diff, totalTime: now), at: 0)
        lastLapTime = now
        updateAverage()
        saveState()
    }
    
    func deleteLap(at offsets: IndexSet) {
        laps.remove(atOffsets: offsets)
        updateAverage()
        saveState()
    }
    
    private func setupSaveTimer() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in self?.saveState() }
    }
    
    func saveState() {
        let snapshot = (accumulated, lastLapTime, isRunning, isOnBreak, accumulatedDoubtTime, accumulatedBreakTime, currentSegmentQuestionCount, mode.rawValue, lastSwitchTime, startTime)
        let lapsSnapshot = self.laps
        let segmentsSnapshot = self.tempSegments
        
        DispatchQueue.global(qos: .utility).async {
            let d = UserDefaults.standard
            d.set(snapshot.0, forKey: "sw_accumulated"); d.set(snapshot.1, forKey: "sw_lastLapTime")
            d.set(snapshot.2, forKey: "sw_isRunning"); d.set(snapshot.3, forKey: "sw_isOnBreak")
            d.set(snapshot.4, forKey: "sw_doubt"); d.set(snapshot.5, forKey: "sw_break")
            d.set(snapshot.6, forKey: "sw_segQ"); d.set(snapshot.7, forKey: "sw_mode")
            if let lst = snapshot.8 { d.set(lst, forKey: "sw_lastSwitch") }
            if let s = snapshot.9 { d.set(s, forKey: "sw_startTime") }
            if let data = try? JSONEncoder().encode(lapsSnapshot) { d.set(data, forKey: "sw_laps") }
            if let data = try? JSONEncoder().encode(segmentsSnapshot) { d.set(data, forKey: "sw_segments") }
        }
    }
    
    func loadState() {
        let d = UserDefaults.standard
        accumulated = d.double(forKey: "sw_accumulated"); lastLapTime = d.double(forKey: "sw_lastLapTime")
        accumulatedDoubtTime = d.double(forKey: "sw_doubt"); accumulatedBreakTime = d.double(forKey: "sw_break")
        currentSegmentQuestionCount = d.integer(forKey: "sw_segQ")
        lastSwitchTime = d.object(forKey: "sw_lastSwitch") as? Date
        if let raw = d.string(forKey: "sw_mode"), let m = StopwatchMode(rawValue: raw) { mode = m }
        if let data = d.data(forKey: "sw_laps"), let dec = try? JSONDecoder().decode([LapItem].self, from: data) { laps = dec }
        if let data = d.data(forKey: "sw_segments"), let dec = try? JSONDecoder().decode([ActivityLog].self, from: data) { tempSegments = dec }
        
        updateAverage()
        
        if d.bool(forKey: "sw_isRunning"), let s = d.object(forKey: "sw_startTime") as? Date {
            startTime = s; isRunning = true; setupSaveTimer()
        } else if d.bool(forKey: "sw_isOnBreak") {
            isRunning = false; isOnBreak = true; setupSaveTimer()
        }
    }
}

class TimerModel: ObservableObject, SessionTracker {
    @Published var duration: TimeInterval = 0
    @Published var remainingWhenPaused: TimeInterval = 0
    @Published var endTime: Date?
    @Published var isRunning = false
    @Published var isOnBreak = false
    @Published var questions: [LapItem] = []
    @Published var accumulatedDoubtTime: TimeInterval = 0
    @Published var accumulatedBreakTime: TimeInterval = 0
    @Published var showBreakCategorySheet = false
    @Published var h = 0; @Published var m = 0; @Published var s = 0
    @Published var tempSegments: [ActivityLog] = []
    @Published var currentSegmentQuestionCount = 0
    
    @Published var averageTime: TimeInterval = 0
    
    private var lastSwitchTime: Date?
    var lastElapsed: TimeInterval = 0
    private var saveTimer: Timer?
    
    var isSessionActive: Bool { lastSwitchTime != nil }
    var currentSegmentStart: Date? { lastSwitchTime }
    var currentStatus: SessionStatus {
        if isOnBreak { return .breakMode }
        if isRunning { return .running }
        return .doubt
    }
    
    init() { loadState() }
    
    var completedQuestionsCount: Int { questions.count }
    
    func getRemainingTime(at date: Date = Date()) -> TimeInterval {
        if isRunning, let end = endTime { return max(0, end.timeIntervalSince(date)) }
        return remainingWhenPaused
    }
    
    func getElapsedTime(at date: Date = Date()) -> TimeInterval { return duration - getRemainingTime(at: date) }
    
    private func updateAverage() {
        averageTime = questions.isEmpty ? 0 : questions.reduce(0){$0+$1.time} / Double(questions.count)
    }
    
    var currentTotalDoubtTime: TimeInterval { if !isRunning && !isOnBreak, let last = lastSwitchTime { return accumulatedDoubtTime + Date().timeIntervalSince(last) }; return accumulatedDoubtTime }
    var currentTotalBreakTime: TimeInterval { if isOnBreak, let last = lastSwitchTime { return accumulatedBreakTime + Date().timeIntervalSince(last) }; return accumulatedBreakTime }
    
    func togglePauseResume() {
        HapticManager.shared.success()
        commitCurrentSegment()
        if isOnBreak { isOnBreak = false; resume() }
        else if isRunning { pause() }
        else {
            if getRemainingTime() <= 0 && duration == 0 {
                let d = TimeInterval(h*3600+m*60+s)
                if d > 0 { start(d) }
            } else if getRemainingTime() > 0 { resume() }
            else {
                let d = TimeInterval(h*3600+m*60+s)
                if d > 0 { start(d) }
            }
        }
    }
    
    func toggleBreak() {
        HapticManager.shared.success()
        if isOnBreak { showBreakCategorySheet = true }
        else {
            commitCurrentSegment()
            if isRunning {
                isRunning = false
                remainingWhenPaused = max(0, endTime?.timeIntervalSinceNow ?? 0)
                endTime = nil; NotificationManager.shared.cancelNotifications()
            }
            isOnBreak = true
            lastSwitchTime = Date(); setupSaveTimer(); saveState()
        }
    }
    
    func confirmBreakEnd(category: ActivityCategory) {
        commitCurrentSegment(overrideCategory: category)
        isOnBreak = false; resume()
    }
    
    private func commitCurrentSegment(overrideCategory: ActivityCategory? = nil) {
        guard let start = lastSwitchTime else { return }
        let end = Date(); let duration = end.timeIntervalSince(start)
        var category: ActivityCategory = .study; var isDoubt = false
        
        if isOnBreak { category = overrideCategory ?? .other; accumulatedBreakTime += duration }
        else if !isRunning { category = .study; isDoubt = true; accumulatedDoubtTime += duration }
        else { category = .study }
        
        if duration > 1 {
            let seg = ActivityLog(startDate: start, endDate: end, category: category, questionsSolved: currentSegmentQuestionCount, doubtTime: isDoubt ? duration : 0, breakTime: isOnBreak ? duration : 0, note: isDoubt ? "Doubt" : (isOnBreak ? (overrideCategory?.rawValue ?? "Break") : "Exam Segment"))
            tempSegments.append(seg)
        }
        currentSegmentQuestionCount = 0; lastSwitchTime = Date()
    }
    
    func nextQuestion() {
        HapticManager.shared.success()
        let el = getElapsedTime()
        let q = el - lastElapsed
        questions.insert(LapItem(index: questions.count+1, time: q, totalTime: el), at: 0)
        lastElapsed = el; currentSegmentQuestionCount += 1
        updateAverage()
        saveState()
    }
    
    func cancel() {
        HapticManager.shared.success()
        commitCurrentSegment()
        Task { @MainActor in
            for seg in tempSegments { ActivityDatabase.shared.log(start: seg.startDate, end: seg.endDate, category: seg.category, questions: seg.questionsSolved, doubt: seg.doubtTime, breakTime: seg.breakTime, note: seg.note) }
            tempSegments = []
            resetInternal()
        }
    }
    
    private func resetInternal() {
        isRunning = false; saveTimer?.invalidate()
        remainingWhenPaused = 0; duration = 0; questions = []; lastElapsed = 0; isOnBreak = false
        accumulatedDoubtTime = 0; accumulatedBreakTime = 0; lastSwitchTime = nil
        currentSegmentQuestionCount = 0; endTime = nil; NotificationManager.shared.cancelNotifications()
        updateAverage()
        let d = UserDefaults.standard
        ["tm_duration", "tm_remaining", "tm_lastElapsed", "tm_isRunning", "tm_isOnBreak", "tm_doubt", "tm_break", "tm_segQ", "tm_questions", "tm_segments", "tm_endTime", "tm_lastSwitch"].forEach { d.removeObject(forKey: $0) }
    }
    
    private func start(_ t: TimeInterval) {
        lastSwitchTime = Date()
        duration = t; remainingWhenPaused = t; endTime = Date().addingTimeInterval(t)
        isRunning = true; isOnBreak = false
        NotificationManager.shared.scheduleTimerNotification(seconds: t)
        setupSaveTimer(); saveState()
    }
    
    private func resume() {
        lastSwitchTime = Date()
        endTime = Date().addingTimeInterval(remainingWhenPaused)
        isRunning = true; isOnBreak = false
        NotificationManager.shared.scheduleTimerNotification(seconds: remainingWhenPaused)
        setupSaveTimer(); saveState()
    }
    
    private func pause() {
        isRunning = false
        remainingWhenPaused = max(0, endTime?.timeIntervalSinceNow ?? 0)
        endTime = nil; NotificationManager.shared.cancelNotifications()
        lastSwitchTime = Date(); setupSaveTimer(); saveState()
    }
    
    func deleteQuestion(at offsets: IndexSet) {
        questions.remove(atOffsets: offsets)
        updateAverage()
        saveState()
    }
    
    private func setupSaveTimer() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.checkFinish() }
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in self?.saveState() }
    }
    
    private func checkFinish() {
        guard isRunning, let end = endTime else { return }
        if end.timeIntervalSinceNow <= 0 { Task { @MainActor in self.finish() } }
    }
    
    private func finish() { cancel(); AudioServicesPlaySystemSound(1005) }
    
    func saveState() {
        let snapshot = (duration, remainingWhenPaused, lastElapsed, isRunning, isOnBreak, accumulatedDoubtTime, accumulatedBreakTime, currentSegmentQuestionCount, lastSwitchTime, endTime)
        let qSnapshot = self.questions; let sSnapshot = self.tempSegments
        DispatchQueue.global(qos: .utility).async {
            let d = UserDefaults.standard
            d.set(snapshot.0, forKey: "tm_duration"); d.set(snapshot.1, forKey: "tm_remaining"); d.set(snapshot.2, forKey: "tm_lastElapsed")
            d.set(snapshot.3, forKey: "tm_isRunning"); d.set(snapshot.4, forKey: "tm_isOnBreak"); d.set(snapshot.5, forKey: "tm_doubt")
            d.set(snapshot.6, forKey: "tm_break"); d.set(snapshot.7, forKey: "tm_segQ")
            if let lst = snapshot.8 { d.set(lst, forKey: "tm_lastSwitch") }
            if let e = snapshot.9 { d.set(e, forKey: "tm_endTime") }
            if let data = try? JSONEncoder().encode(qSnapshot) { d.set(data, forKey: "tm_questions") }
            if let data = try? JSONEncoder().encode(sSnapshot) { d.set(data, forKey: "tm_segments") }
        }
    }
    
    func loadState() {
        let d = UserDefaults.standard
        duration = d.double(forKey: "tm_duration"); remainingWhenPaused = d.double(forKey: "tm_lastElapsed")
        accumulatedDoubtTime = d.double(forKey: "tm_doubt"); accumulatedBreakTime = d.double(forKey: "tm_break"); currentSegmentQuestionCount = d.integer(forKey: "tm_segQ")
        lastSwitchTime = d.object(forKey: "tm_lastSwitch") as? Date
        if let data = d.data(forKey: "tm_questions"), let dec = try? JSONDecoder().decode([LapItem].self, from: data) { questions = dec }
        if let data = d.data(forKey: "tm_segments"), let dec = try? JSONDecoder().decode([ActivityLog].self, from: data) { tempSegments = dec }
        
        updateAverage()
        
        if d.bool(forKey: "tm_isRunning"), let e = d.object(forKey: "tm_endTime") as? Date {
            let r = e.timeIntervalSinceNow
            if r > 0 { endTime = e; isRunning = true; setupSaveTimer() }
            else { remainingWhenPaused = 0; isRunning = false }
        } else if d.bool(forKey: "tm_isOnBreak") {
            isRunning = false; isOnBreak = true; setupSaveTimer()
        }
    }
}

// MARK: - ⏱️ STOPWATCH VIEW
struct StopwatchView: View {
    @ObservedObject var model: StopwatchModel
    @State private var showResetConfirmation = false
    
    var body: some View {
        ResizableStack(top: { size in controlSection(size: size) }, bottom: { size in lapListSection(size: size) })
            .background(Color.black)
            .confirmationDialog("Break Activity", isPresented: $model.showBreakCategorySheet, titleVisibility: .visible) {
                ForEach(ActivityCategory.allCases.filter { $0 != .study }) { category in
                    Button(category.rawValue) { model.confirmBreakEnd(category: category) }
                }
                Button("Resume (Uncategorized)", role: .cancel) { model.confirmBreakEnd(category: .waste) }
            } message: {
                Text("How did you spend your break?")
            }
            .alert("Reset Session?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) { model.reset() }
            } message: { Text("This will clear all time and question data.") }
    }
    
    func controlSection(size: CGSize) -> some View {
        return ZStack {
            VStack {
                HStack {
                    if model.getElapsedTime() == 0 {
                        HStack(spacing: 0) {
                            ForEach(StopwatchMode.allCases, id: \.self) { m in
                                Button(action: { HapticManager.shared.success(); model.mode = m }) {
                                    Text(m.rawValue).font(.caption).bold().padding(.vertical, 6).padding(.horizontal, 12)
                                        .background(model.mode == m ? Color.orange : Color(white: 0.1)).foregroundColor(model.mode == m ? .black : .white)
                                }
                            }
                        }.cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.2), lineWidth: 1))
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: model.mode == .solving ? "pencil.and.ruler.fill" : "book.fill")
                            Text(model.mode.rawValue.uppercased())
                        }.font(.caption).bold().foregroundColor(.gray).padding(6).background(Color(white: 0.1)).cornerRadius(6)
                    }
                    Spacer()
                    if model.getElapsedTime() > 0 || !model.laps.isEmpty {
                        Button(action: { showResetConfirmation = true }) {
                            Text("Reset").foregroundColor(.red).padding(8).background(Color(white: 0.1)).cornerRadius(8)
                        }
                    }
                }.padding().padding(.top, 10)
                Spacer()
            }.zIndex(10)
            
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if model.mode == .solving {
                    VStack(spacing: 0) {
                        Text("QUESTIONS").font(.system(size: 12, weight: .bold)).foregroundColor(.gray).tracking(2)
                        Text("\(model.completedQuestionsCount)").font(.system(size: 80, weight: .bold)).minimumScaleFactor(0.5).foregroundColor(.orange).lineLimit(1)
                    }.frame(height: size.height * 0.15)
                } else { Spacer().frame(height: size.height * 0.15) }
                Spacer(minLength: 0)
                
                MainClockDisplay(model: model, height: size.height * 0.40)
                
                if model.mode == .solving && (!model.laps.isEmpty || model.isRunning) { LiveLapStats(model: model, height: size.height * 0.15) }
                else if model.mode == .theory { Text("READING / NOTES").font(.headline).foregroundColor(.gray).frame(height: size.height * 0.15) }
                else { Spacer().frame(height: size.height * 0.15) }
                
                HStack(spacing: 20) {
                    if model.currentTotalDoubtTime > 0 || model.currentStatus == .doubt {
                        LiveAuxTimer(icon: "exclamationmark.triangle.fill", title: "DOUBT", color: .orange, baseTime: model.accumulatedDoubtTime, refDate: model.currentStatus == .doubt ? model.currentSegmentStart : nil)
                    }
                    if model.currentTotalBreakTime > 0 || model.isOnBreak {
                        LiveAuxTimer(icon: "cup.and.saucer.fill", title: "BREAK", color: .blue, baseTime: model.accumulatedBreakTime, refDate: model.isOnBreak ? model.currentSegmentStart : nil)
                    }
                }.frame(height: size.height * 0.10)
                
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ClockButton(label: model.isOnBreak ? "Resume" : "Break", bgColor: model.isOnBreak ? Color.blue.opacity(0.3) : Color(white: 0.15), textColor: .blue) { model.toggleBreak() }
                        .keyboardShortcut("b", modifiers: [])
                    
                    Spacer()
                    
                    ClockButton(label: "Next Q", bgColor: Color(white: 0.2), textColor: .white) { model.nextQuestion() }
                        .disabled(model.accumulated == 0 && model.startTime == nil || model.mode == .theory)
                        .opacity((model.accumulated == 0 && model.startTime == nil || model.mode == .theory) ? 0.3 : 1.0)
                        .keyboardShortcut(.defaultAction)
                    
                    Spacer()
                    
                    ClockButton(label: model.isRunning ? "Pause" : (model.accumulated > 0 || model.startTime != nil ? "Resume" : "Start"), bgColor: model.isRunning ? Color(red: 0.3, green: 0.2, blue: 0) : Color(red: 0, green: 0.3, blue: 0), textColor: model.isRunning ? .orange : .green) { model.togglePauseResume() }
                        .keyboardShortcut(.space, modifiers: [])
                }.padding(.horizontal, 30).frame(height: 100).padding(.bottom, 10)
            }
        }
    }
    
    func lapListSection(size: CGSize) -> some View {
        List {
            if model.mode == .solving {
                if model.isRunning || model.accumulated > 0 { LiveCurrentLapRow(model: model).listRowBackground(Color.black) }
                ForEach(model.laps) { lap in
                    HStack {
                        Text("Q\(lap.index)").foregroundColor(.gray); Spacer()
                        let isSlow = model.averageLapTime > 0 && lap.time > model.averageLapTime
                        Text(Formatters.formatTime(lap.time)).monospacedDigit().foregroundColor(isSlow ? Color(red: 0.8, green: 0.3, blue: 0.3) : .white)
                    }.listRowBackground(Color.black)
                }.onDelete(perform: model.deleteLap)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Image(systemName: "book.fill"); Text("Theory Mode Active") }.font(.headline).foregroundColor(.orange)
                    Text("Time tracked here will count as Study time, but will NOT affect your 'Average Time Per Question' metrics.").font(.caption).foregroundColor(.gray)
                }.listRowBackground(Color.black)
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(Color.black)
    }
}

struct MainClockDisplay: View {
    @ObservedObject var model: StopwatchModel
    let height: CGFloat
    var body: some View {
        if model.isOnBreak {
            Text("ON BREAK").font(.system(size: 100, weight: .black)).foregroundColor(.blue).minimumScaleFactor(0.2).lineLimit(1).frame(maxWidth: .infinity, maxHeight: height)
        } else {
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let total = model.getElapsedTime(at: context.date)
                Text(Formatters.formatTime(total)).font(.system(size: 250, weight: .light)).minimumScaleFactor(0.2).lineLimit(1).monospacedDigit()
                    .foregroundColor(model.isRunning ? .white : (total > 0 ? .orange : .white))
            }.frame(maxWidth: .infinity, maxHeight: height)
        }
    }
}

struct LiveLapStats: View {
    @ObservedObject var model: StopwatchModel
    let height: CGFloat
    var body: some View {
        HStack(spacing: 20) {
            VStack(spacing: 0) {
                Text("AVG LAP").font(.system(size: 16, weight: .bold)).foregroundColor(Color(white: 0.5))
                Text(Formatters.formatTime(model.averageLapTime)).font(.system(size: 48, weight: .regular)).monospacedDigit().minimumScaleFactor(0.5).foregroundColor(Color(white: 0.8))
            }
            VStack(spacing: 0) {
                Text("CURRENT").font(.system(size: 16, weight: .bold)).foregroundColor(Color(white: 0.5))
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    let total = model.getElapsedTime(at: context.date)
                    let current = max(0, total - model.lastLapTime)
                    let isSlow = model.averageLapTime > 0 && current > model.averageLapTime
                    Text(Formatters.formatTime(current)).font(.system(size: 48, weight: .regular)).monospacedDigit().minimumScaleFactor(0.5)
                        .foregroundColor(isSlow ? Color(red: 1, green: 0.3, blue: 0.3) : .white)
                }
            }
        }.frame(height: height)
    }
}

struct LiveAuxTimer: View {
    let icon: String; let title: String; let color: Color; let baseTime: TimeInterval; let refDate: Date?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let extra = refDate != nil ? context.date.timeIntervalSince(refDate!) : 0
            let total = baseTime + extra
            HStack(spacing: 6) {
                Image(systemName: icon).font(.title3); Text(title).font(.headline).fontWeight(.bold)
                Text(Formatters.formatTime(total)).font(.system(size: 24, weight: .bold)).monospacedDigit()
            }.foregroundColor(refDate != nil ? color : .gray)
        }
    }
}

struct LiveCurrentLapRow: View {
    @ObservedObject var model: StopwatchModel
    var body: some View {
        HStack {
            Text("Current Question").foregroundColor(.white); Spacer()
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let total = model.getElapsedTime(at: context.date)
                let current = max(0, total - model.lastLapTime)
                let isSlow = model.averageLapTime > 0 && current > model.averageLapTime
                Text(Formatters.formatTime(current)).monospacedDigit().foregroundColor(isSlow ? Color(red: 1, green: 0.3, blue: 0.3) : .white)
            }
        }
    }
}

// MARK: - ⏱️ TIMER VIEW
struct TimerView: View {
    @ObservedObject var model: TimerModel
    @State private var showCancelConfirmation = false
    
    var body: some View {
        ResizableStack(top: { size in mainContent(size: size) }, bottom: { size in questionListSection(size: size) })
            .background(Color.black)
            .confirmationDialog("Break Activity", isPresented: $model.showBreakCategorySheet, titleVisibility: .visible) {
                ForEach(ActivityCategory.allCases.filter { $0 != .study }) { category in
                    Button(category.rawValue) { model.confirmBreakEnd(category: category) }
                }
                Button("Resume (Uncategorized)", role: .cancel) { model.confirmBreakEnd(category: .waste) }
            } message: { Text("How did you spend your break?") }
            .alert("End Exam Session?", isPresented: $showCancelConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("End", role: .destructive) { model.cancel() }
            } message: { Text("This will clear your current progress.") }
    }
    
    func mainContent(size: CGSize) -> some View {
        return ZStack {
            if model.getRemainingTime() > 0 || model.duration > 0 {
                VStack {
                    HStack {
                        Button(action: { showCancelConfirmation = true }) {
                            Text("End").foregroundColor(.red).padding(8).background(Color(white: 0.1)).cornerRadius(8)
                        }
                        Spacer()
                    }
                    Spacer()
                }.padding().zIndex(10)
            }
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if model.isRunning || model.getRemainingTime() != model.duration {
                    VStack(spacing: 0) {
                        Text("QUESTIONS").font(.system(size: 12, weight: .bold)).foregroundColor(.gray).tracking(2)
                        Text("\(model.completedQuestionsCount)").font(.system(size: 80, weight: .bold)).minimumScaleFactor(0.5).foregroundColor(.orange)
                    }.frame(height: size.height * 0.15)
                } else { Spacer().frame(height: size.height * 0.15) }
                
                if model.isRunning || (model.getRemainingTime() > 0 && model.getRemainingTime() != model.duration) {
                    TimerRingDisplay(model: model, height: size.height * 0.50)
                    
                    HStack(spacing: 20) {
                        if model.currentTotalDoubtTime > 0 || model.currentStatus == .doubt {
                            LiveAuxTimer(icon: "exclamationmark.triangle.fill", title: "DOUBT", color: .orange, baseTime: model.accumulatedDoubtTime, refDate: model.currentStatus == .doubt ? model.currentSegmentStart : nil)
                        }
                        if model.currentTotalBreakTime > 0 || model.isOnBreak {
                            LiveAuxTimer(icon: "cup.and.saucer.fill", title: "BREAK", color: .blue, baseTime: model.accumulatedBreakTime, refDate: model.isOnBreak ? model.currentSegmentStart : nil)
                        }
                    }.frame(height: size.height * 0.10)
                    
                } else {
                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            NativePicker(val: $model.h, range: 0...23, label: "hr"); NativePicker(val: $model.m, range: 0...59, label: "min"); NativePicker(val: $model.s, range: 0...59, label: "sec")
                        }.padding().padding(.horizontal, 20)
                        Spacer()
                    }.frame(height: size.height * 0.60)
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ClockButton(label: model.isOnBreak ? "Resume" : "Break", bgColor: model.isOnBreak ? Color.blue.opacity(0.3) : Color(white: 0.15), textColor: .blue) { model.toggleBreak() }
                        .disabled(!model.isRunning && model.remainingWhenPaused == model.duration).opacity((!model.isRunning && model.remainingWhenPaused == model.duration) ? 0.3 : 1)
                        .keyboardShortcut("b", modifiers: [])
                    
                    Spacer()
                    
                    ClockButton(label: "Next Q", bgColor: Color(white: 0.2), textColor: .white) { model.nextQuestion() }
                        .disabled(model.remainingWhenPaused == model.duration || model.remainingWhenPaused == 0).opacity((model.remainingWhenPaused == model.duration || model.remainingWhenPaused == 0) ? 0.3 : 1)
                        .keyboardShortcut(.defaultAction)
                    
                    Spacer()
                    
                    ClockButton(label: model.isRunning ? "Pause" : (model.remainingWhenPaused > 0 && model.remainingWhenPaused < model.duration ? "Resume" : "Start"), bgColor: model.isRunning ? Color(red: 0.3, green: 0.2, blue: 0) : Color(red: 0, green: 0.3, blue: 0), textColor: model.isRunning ? .orange : .green) { model.togglePauseResume() }
                        .keyboardShortcut(.space, modifiers: [])
                }.padding(.horizontal, 30).frame(height: 100).padding(.bottom, 10)
            }
        }
    }
    
    func questionListSection(size: CGSize) -> some View {
        List {
            if model.isRunning || (model.getRemainingTime() < model.duration && model.getRemainingTime() > 0) {
                LiveCurrentTimerRow(model: model).listRowBackground(Color.black)
            }
            ForEach(model.questions) { q in
                HStack {
                    Text("Q\(q.index)").foregroundColor(.gray); Spacer()
                    let isSlow = q.time > model.averageTime
                    Text(Formatters.formatTime(q.time)).monospacedDigit().foregroundColor(isSlow ? Color(red: 0.8, green: 0.3, blue: 0.3) : .white)
                }.listRowBackground(Color.black)
            }.onDelete(perform: model.deleteQuestion)
        }.listStyle(.plain).scrollContentBackground(.hidden).background(Color.black)
    }
}

struct TimerRingDisplay: View {
    @ObservedObject var model: TimerModel
    let height: CGFloat
    
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height) - 40
            ZStack {
                if model.isOnBreak {
                    Text("ON BREAK").font(.system(size: size * 0.15, weight: .black)).foregroundColor(.blue)
                } else {
                    TimelineView(.periodic(from: .now, by: 0.1)) { context in
                        ZStack {
                            let rem = model.getRemainingTime(at: context.date)
                            let duration = model.duration; let elapsed = duration - rem
                            let currentQ = max(0, elapsed - model.lastElapsed)
                            
                            Circle().stroke(Color(white: 0.15), lineWidth: 20)
                            Circle().trim(from: 0, to: duration > 0 ? CGFloat(rem / duration) : 0)
                                .stroke(Color.orange, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 0.1), value: rem)
                            
                            VStack(spacing: 4) {
                                if !model.questions.isEmpty {
                                    Text("AVG: \(Formatters.formatTime(model.averageTime))").font(.system(size: size * 0.08, weight: .bold)).monospacedDigit().foregroundColor(Color(white: 0.7))
                                }
                                Text(Formatters.formatTime(currentQ)).font(.system(size: size * 0.25, weight: .bold)).monospacedDigit()
                                    .foregroundColor(!model.isRunning ? .orange : (model.averageTime > 0 && currentQ > model.averageTime ? Color(red: 1, green: 0.3, blue: 0.3) : .white))
                                    .lineLimit(1).minimumScaleFactor(0.5)
                                Text(Formatters.formatTime(rem)).font(.system(size: size * 0.10, weight: .regular)).monospacedDigit().foregroundColor(.white)
                            }.frame(width: size * 0.7, height: size * 0.7)
                        }.frame(width: size, height: size)
                    }
                }
            }.frame(width: geo.size.width, height: geo.size.height)
        }.frame(height: height)
    }
}

struct LiveCurrentTimerRow: View {
    @ObservedObject var model: TimerModel
    var body: some View {
        HStack {
            Text("Q\(model.questions.count + 1) (Current)").fontWeight(.bold).foregroundColor(.orange); Spacer()
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let elapsed = model.getElapsedTime(at: context.date)
                let current = max(0, elapsed - model.lastElapsed)
                let isSlow = model.averageTime > 0 && current > model.averageTime
                Text(Formatters.formatTime(current)).monospacedDigit().foregroundColor(isSlow ? Color(red: 1, green: 0.3, blue: 0.3) : .white)
            }
        }
    }
}

// MARK: - 📊 ANALYTICS DATA HELPERS
extension Array where Element == ActivityLog {
    func totalDuration(category: ActivityCategory) -> TimeInterval { filter { $0.category == category }.reduce(0) { $0 + $1.duration } }
    func totalQuestions() -> Int { filter { $0.category == .study }.reduce(0) { $0 + $1.questionsSolved } }
    func totalDoubt() -> TimeInterval { reduce(0) { $0 + $1.doubtTime } }
    
    // 🔥 Math Fix: Stop double-counting break times
    func totalBreak() -> TimeInterval {
        reduce(0) { total, log in
            let isExplicitBreak = log.category == .waste || log.category == .other || (log.note?.contains("Break") ?? false)
            return total + (isExplicitBreak ? log.duration : log.breakTime)
        }
    }
    
    var averageSpeed: Double {
        let solvingLogs = filter { $0.category == .study && $0.questionsSolved > 0 }
        let totalTimeMins = solvingLogs.reduce(0) { $0 + $1.duration } / 60
        let q = solvingLogs.reduce(0) { $0 + $1.questionsSolved }
        return q > 0 ? totalTimeMins / Double(q) : 0
    }
}

// MARK: - 🗓️ TIMELINE LEGEND
struct TimelineLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(ActivityCategory.allCases) { cat in
                HStack(spacing: 4) {
                    Circle().fill(cat.color).frame(width: 8, height: 8)
                    Text(cat.rawValue).font(.caption).foregroundColor(.gray)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(Color.black)
    }
}

// MARK: - 🗓️ TIMELINE VIEW
struct DailyTimelineView: View {
    let logs: [ActivityLog]
    let onGapTap: (Date, Date) -> Void
    var activeSession: SessionTracker? = nil
    
    @State private var hourHeight: CGFloat = 60
    @GestureState private var magnification: CGFloat = 1.0
    
    var currentHourHeight: CGFloat { min(300, max(40, hourHeight * magnification)) }
    
    var processedLogs: [ActivityLog] {
        let referenceDay = logs.first?.startDate ?? Date()
        let startOfDay = Calendar.current.startOfDay(for: referenceDay)
        let endOfDay = startOfDay.addingTimeInterval(86399)
        
        var combined = logs
        if let session = activeSession {
            combined.append(contentsOf: session.tempSegments)
        }
        return AnalyticsHelper.clampAndSplitLogs(combined, start: startOfDay, end: endOfDay)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            TimelineLegend()
            
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        ZStack(alignment: .topLeading) {
                            
                            // 1. Grid Lines
                            VStack(spacing: 0) {
                                ForEach(0..<24) { hour in
                                    HStack(alignment: .top) {
                                        Text(formatHour(hour)).font(.caption).foregroundColor(.gray).frame(width: 50, alignment: .trailing).offset(y: -6)
                                        Rectangle().fill(Color(white: 0.15)).frame(height: 1)
                                    }
                                    .frame(height: currentHourHeight, alignment: .top)
                                }
                            }
                            
                            // 2. Logs
                            ForEach(processedLogs) { log in renderLogBlock(log) }
                            
                            // 3. Live Animated Pulse Tick (Scoped correctly)
                            if let session = activeSession, session.isSessionActive, let start = session.currentSegmentStart {
                                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                                    let referenceDay = logs.first?.startDate ?? Date()
                                    let startOfDay = Calendar.current.startOfDay(for: referenceDay)
                                    let clampedStart = max(start, startOfDay)
                                    let end = context.date
                                    
                                    if clampedStart < end {
                                        let frame = calculateFrame(start: clampedStart, end: end)
                                        let color = getStatusColor(session.currentStatus)
                                        
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(color.opacity(0.5))
                                            .frame(width: frame.width, height: max(2, frame.height))
                                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color, style: StrokeStyle(lineWidth: 2, dash: [5])))
                                            .offset(x: 60, y: frame.y)
                                    }
                                }
                            }
                            
                            // 4. Gaps
                            ForEach(calculateGaps()) { gap in
                                let frame = calculateFrame(start: gap.start, end: gap.end)
                                Button(action: { onGapTap(gap.start, gap.end) }) {
                                    ZStack {
                                        Rectangle().fill(Color(white: 0.05))
                                        Image(systemName: "plus").foregroundColor(.gray).opacity(0.3)
                                    }
                                }
                                .frame(width: frame.width, height: max(10, frame.height))
                                .cornerRadius(6)
                                .offset(x: 60, y: frame.y)
                            }
                            
                            // 5. Current Time Line (Scoped correctly)
                            TimelineView(.periodic(from: .now, by: 60.0)) { context in
                                let nowY = getMinutes(from: context.date) / 60.0 * currentHourHeight
                                ZStack(alignment: .leading) {
                                    Circle().fill(Color.red).frame(width: 8, height: 8)
                                    Rectangle().fill(Color.red).frame(height: 1).offset(x: 8)
                                }
                                .offset(x: 56, y: nowY - 4)
                                .padding(.trailing, 20)
                            }
                            
                        }.padding(.bottom, 50)
                    }
                    .highPriorityGesture(
                        MagnificationGesture()
                            .updating($magnification) { currentState, gestureState, _ in gestureState = currentState }
                            .onEnded { value in self.hourHeight = min(300, max(40, self.hourHeight * value)) }
                    )
                }
            }
        }
    }
    
    // MARK: - Helpers
    func logColor(_ log: ActivityLog) -> Color {
        if log.doubtTime > 0 { return .orange }
        return log.category.color
    }
    
    @ViewBuilder
    func renderLogBlock(_ log: ActivityLog) -> some View {
        let frame = calculateFrame(start: log.startDate, end: log.endDate)
        RoundedRectangle(cornerRadius: 6)
            .fill(logColor(log).opacity(0.7))
            .frame(width: frame.width, height: max(2, frame.height))
            .offset(x: 60, y: frame.y)
    }
    
    func getStatusColor(_ status: SessionStatus) -> Color {
        switch status {
        case .running: return .green
        case .breakMode: return .blue
        case .doubt: return .orange
        }
    }
    
    func formatHour(_ h: Int) -> String {
        let ampm = h >= 12 ? "PM" : "AM"
        let h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h)
        return "\(h12) \(ampm)"
    }
    
    func getMinutes(from date: Date) -> Double {
        let cal = Calendar.current; let h = cal.component(.hour, from: date); let m = cal.component(.minute, from: date)
        return Double(h * 60 + m)
    }
    
    func calculateFrame(start: Date, end: Date) -> (y: CGFloat, height: CGFloat, width: CGFloat) {
        let startMins = getMinutes(from: start)
        let endMins = getMinutes(from: end)
        
        let durationMins = max(2, endMins - startMins)
        let y = CGFloat(startMins / 60.0) * currentHourHeight
        let h = CGFloat(durationMins / 60.0) * currentHourHeight
        let w = UIScreen.main.bounds.width - 80
        return (y, h, w)
    }
    
    struct Gap: Identifiable { var id = UUID(); let start: Date; let end: Date }
    
    func calculateGaps() -> [Gap] {
        let cal = Calendar.current
        let referenceDay = logs.first?.startDate ?? Date()
        let startOfDay = cal.startOfDay(for: referenceDay)
        let now = Date()
        
        var filledRanges: [(Date, Date)] = processedLogs.map { ($0.startDate, $0.endDate) }
        
        if let session = activeSession, session.isSessionActive, let s = session.currentSegmentStart {
            let clampedS = max(s, startOfDay)
            if clampedS < now { filledRanges.append((clampedS, now)) }
        }
        
        filledRanges.sort { $0.0 < $1.0 }
        
        var gaps: [Gap] = []; var cursor = startOfDay
        for range in filledRanges {
            if range.0.timeIntervalSince(cursor) > 300 { gaps.append(Gap(start: cursor, end: range.0)) }
            if range.1 > cursor { cursor = range.1 }
        }
        if cursor < now && now.timeIntervalSince(cursor) > 300 { gaps.append(Gap(start: cursor, end: now)) }
        return gaps
    }
}

// MARK: - 📊 CHART OVERVIEW
struct BarChartOverview: View {
    let logs: [ActivityLog]
    let scope: AnalyticsScope
    
    var body: some View {
        let grouped: [Date: [ActivityLog]]
        if scope == .year {
            grouped = Dictionary(grouping: logs) { log in
                let comps = Calendar.current.dateComponents([.year, .month], from: log.startDate)
                return Calendar.current.date(from: comps)!
            }
        } else {
            grouped = Dictionary(grouping: logs) { Calendar.current.startOfDay(for: $0.startDate) }
        }
        
        let sortedDates = grouped.keys.sorted()
        
        return Chart {
            ForEach(sortedDates, id: \.self) { date in
                let dayLogs = grouped[date] ?? []
                let study = dayLogs.totalDuration(category: .study)
                let breaks = dayLogs.totalBreak() // 🔥 Math Fix applied
                let doubt = dayLogs.totalDoubt()
                
                BarMark(x: .value("Date", date, unit: scope == .year ? .month : .day), y: .value("Hours", (study - doubt) / 3600))
                    .foregroundStyle(.green)
                BarMark(x: .value("Date", date, unit: scope == .year ? .month : .day), y: .value("Hours", doubt / 3600))
                    .foregroundStyle(.orange)
                BarMark(x: .value("Date", date, unit: scope == .year ? .month : .day), y: .value("Hours", breaks / 3600))
                    .foregroundStyle(.blue)
            }
        }
        .chartXAxis {
            AxisMarks(values: scope == .year ? .stride(by: .month) : .stride(by: .day)) { value in
                if scope == .year { AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true) }
                else if scope == .week { AxisValueLabel(format: .dateTime.weekday(), centered: true) }
                else { AxisValueLabel(format: .dateTime.day(), centered: true) }
            }
        }
    }
}

struct ActivityHeatmap: View {
    let logs: [ActivityLog]
    let scope: AnalyticsScope
    let colors: [Color] = [Color(white: 0.15), Color(red: 0, green: 0.2, blue: 0), Color(red: 0, green: 0.4, blue: 0), Color(red: 0, green: 0.6, blue: 0), Color(red: 0, green: 0.8, blue: 0), Color.green]
    
    var body: some View {
        let calendar = Calendar.current; let today = Date()
        let startDate: Date
        if scope == .month { startDate = calendar.date(from: calendar.dateComponents([.year, .month], from: today))! }
        else { startDate = calendar.date(byAdding: .year, value: -1, to: today)! }
        
        let dates = generateDates(from: startDate, to: today)
        let logsByDay = Dictionary(grouping: logs) { calendar.startOfDay(for: $0.startDate) }
        
        return VStack(alignment: .leading, spacing: 5) {
            Text("CONSISTENCY").font(.caption).bold().foregroundColor(.gray)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(10), spacing: 3), count: 7), spacing: 3) {
                    ForEach(dates, id: \.self) { date in
                        let intensity = calculateIntensity(for: logsByDay[date] ?? [])
                        RoundedRectangle(cornerRadius: 2).fill(colors[min(intensity, 5)]).frame(width: 10, height: 10)
                    }
                }
            }.frame(height: 100)
        }.padding().background(Color(white: 0.1)).cornerRadius(12)
    }
    
    func generateDates(from start: Date, to end: Date) -> [Date] {
        var dates: [Date] = []; var current = Calendar.current.startOfDay(for: start)
        let final = Calendar.current.startOfDay(for: end)
        while current <= final { dates.append(current); current = Calendar.current.date(byAdding: .day, value: 1, to: current)! }
        return dates
    }
    func calculateIntensity(for logs: [ActivityLog]) -> Int {
        if logs.isEmpty { return 0 }
        let study = logs.totalDuration(category: .study); let q = logs.totalQuestions()
        let score = (study / 3600) + Double(q / 10)
        return score == 0 ? 1 : Int(ceil(score))
    }
}

struct StudyBreakdownChart: View {
    let logs: [ActivityLog]
    
    var body: some View {
        let studyLogs = logs.filter { $0.category == .study }
        
        // 🔥 Math Fix: Grab Exam segments, use pure totalBreak(), subtract doubt from Unclassified
        let solvingTime = studyLogs.filter {
            $0.questionsSolved > 0 ||
            ($0.note?.contains("Solving") ?? false) ||
            ($0.note?.contains("Exam Segment") ?? false)
        }.reduce(0) { $0 + $1.duration }
        
        let theoryTime = studyLogs.filter { $0.questionsSolved == 0 && ($0.note?.contains("Theory") ?? false) }.reduce(0) { $0 + $1.duration }
        let doubtTime = logs.totalDoubt()
        let breakTime = logs.totalBreak()
        let totalStudy = studyLogs.reduce(0) { $0 + $1.duration }
        let unclassified = max(0, totalStudy - solvingTime - theoryTime - doubtTime)
        
        let data: [(String, Double, Color)] = [
            ("Solving", solvingTime, .green),
            ("Theory", theoryTime, .teal),
            ("Unclassified", unclassified, .gray),
            ("Doubt", doubtTime, .orange),
            ("Break", breakTime, .blue)
        ].filter { $0.1 > 0 }
        
        return VStack(alignment: .leading, spacing: 10) {
            Text("STUDY SESSION BREAKDOWN").font(.caption).bold().foregroundColor(.gray)
            
            if data.isEmpty {
                Text("No data").font(.caption).foregroundColor(.gray)
            } else {
                Chart(data, id: \.0) { item in
                    SectorMark(
                        angle: .value("Time", item.1),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(item.2)
                    .annotation(position: .overlay) {
                        if item.1 / (solvingTime + theoryTime + doubtTime + breakTime + unclassified) > 0.1 {
                            Text(item.0).font(.caption2).bold().foregroundColor(.white)
                        }
                    }
                }
                .frame(height: 200)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(data, id: \.0) { item in
                        HStack {
                            Circle().fill(item.2).frame(width: 8, height: 8)
                            Text(item.0).font(.caption).foregroundColor(.gray)
                            Spacer()
                            Text(Formatters.formatDurationText(item.1)).font(.caption).bold()
                        }
                    }
                }
            }
        }
        .padding().background(Color(white: 0.1)).cornerRadius(12)
    }
}

struct ScopeTimeDistribution: View {
    let logs: [ActivityLog]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LIFESTYLE").font(.caption).bold().foregroundColor(.gray)
            HStack(spacing: 10) {
                VStack(alignment: .leading) {
                    HStack { Image(systemName: "bed.double.fill").foregroundColor(.indigo); Text("Sleep").font(.caption).foregroundColor(.gray) }
                    Text(Formatters.formatDurationText(logs.totalDuration(category: .sleep))).font(.headline).bold()
                }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(white: 0.1)).cornerRadius(12)
                
                VStack(alignment: .leading) {
                    HStack { Image(systemName: "fork.knife").foregroundColor(.cyan); Text("Food").font(.caption).foregroundColor(.gray) }
                    Text(Formatters.formatDurationText(logs.totalDuration(category: .meal))).font(.headline).bold()
                }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(white: 0.1)).cornerRadius(12)
            }
        }
    }
}

// MARK: - 📊 MAIN ANALYTICS VIEW
struct StatisticsView: View {
    @ObservedObject var db: ActivityDatabase
    @ObservedObject var stopwatch: StopwatchModel
    @ObservedObject var timer: TimerModel
    @State private var scope: AnalyticsScope = .today
    @State private var showClearAlert = false
    
    @State private var showImporter = false
    @State private var exportURL: URL? = nil
    
    var rawLogsForScope: [ActivityLog] {
        let cal = Calendar.current; let now = Date()
        let start: Date; let end: Date
        
        switch scope {
        case .today:
            start = cal.startOfDay(for: now); end = now
        case .yesterday:
            let y = cal.date(byAdding: .day, value: -1, to: now)!
            start = cal.startOfDay(for: y)
            end = cal.date(bySettingHour: 23, minute: 59, second: 59, of: start) ?? start.addingTimeInterval(86399)
        case .week:
            start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            end = now
        case .month:
            start = cal.date(from: cal.dateComponents([.year, .month], from: now))!
            end = now
        case .year:
            start = cal.date(from: cal.dateComponents([.year], from: now))!
            end = now
        }
        
        var rawLogs = db.getLogs(from: start, to: end)
        
        if stopwatch.isSessionActive {
            rawLogs.append(contentsOf: stopwatch.tempSegments)
            if let s = stopwatch.currentSegmentStart {
                let liveNote = stopwatch.currentStatus == .running ? (stopwatch.mode == .theory ? "Study: Theory" : "Study: Solving") : (stopwatch.currentStatus == .breakMode ? "Break" : "Doubt")
                rawLogs.append(ActivityLog(startDate: s, endDate: now, category: stopwatch.currentStatus == .running ? .study : (stopwatch.currentStatus == .doubt ? .study : .other), questionsSolved: stopwatch.mode == .theory ? 0 : stopwatch.currentSegmentQuestionCount, doubtTime: stopwatch.currentStatus == .doubt ? now.timeIntervalSince(s) : 0, breakTime: stopwatch.currentStatus == .breakMode ? now.timeIntervalSince(s) : 0, note: liveNote))
            }
        }
        
        if timer.isSessionActive {
            rawLogs.append(contentsOf: timer.tempSegments)
            if let s = timer.currentSegmentStart {
                let liveNote = timer.currentStatus == .running ? "Live Exam" : (timer.currentStatus == .breakMode ? "Break" : "Doubt")
                rawLogs.append(ActivityLog(startDate: s, endDate: now, category: timer.currentStatus == .running ? .study : (timer.currentStatus == .doubt ? .study : .other), questionsSolved: timer.currentSegmentQuestionCount, doubtTime: timer.currentStatus == .doubt ? now.timeIntervalSince(s) : 0, breakTime: timer.currentStatus == .breakMode ? now.timeIntervalSince(s) : 0, note: liveNote))
            }
        }
        
        return AnalyticsHelper.clampAndSplitLogs(rawLogs, start: start, end: end)
    }
    
    var body: some View {
        NavigationView {
            let currentLogs = rawLogsForScope
            
            VStack(spacing: 0) {
                Picker("Scope", selection: $scope) { ForEach(AnalyticsScope.allCases) { s in Text(s.rawValue).tag(s) } }
                    .pickerStyle(.segmented).padding()
                
                ScrollView {
                    VStack(spacing: 16) {
                        HStack(spacing: 10) {
                            StatCard(title: "Study Time", value: Formatters.formatDurationText(currentLogs.totalDuration(category: .study)), icon: "book.fill", color: .green)
                            StatCard(title: "Questions", value: "\(currentLogs.totalQuestions())", icon: "checkmark.circle.fill", color: .orange)
                        }.padding(.horizontal)
                        
                        VStack(alignment: .leading) {
                            HStack {
                                Text(scope == .week || scope == .month || scope == .year ? "OVERVIEW" : "TIMELINE").font(.caption).bold().foregroundColor(.gray)
                                Spacer()
                                if scope == .today || scope == .yesterday { Text("Pinch to zoom").font(.caption2).foregroundColor(.gray) }
                            }.padding(.horizontal)
                            
                            if scope == .week || scope == .month || scope == .year {
                                BarChartOverview(logs: currentLogs, scope: scope)
                                    .frame(height: 300).padding().background(Color(white: 0.05)).cornerRadius(12).padding(.horizontal)
                                if scope == .year || scope == .month { ActivityHeatmap(logs: currentLogs, scope: scope).padding(.horizontal) }
                            } else {
                                DailyTimelineView(logs: currentLogs, onGapTap: { _, _ in }, activeSession: nil)
                                    .frame(height: 400).background(Color(white: 0.05)).cornerRadius(12).padding(.horizontal)
                            }
                        }
                        
                        StudyBreakdownChart(logs: currentLogs).padding(.horizontal)
                        
                        ScopeTimeDistribution(logs: currentLogs).padding(.horizontal)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            VStack(alignment: .leading) {
                                HStack { Image(systemName: "stopwatch").foregroundColor(.blue); Text("Avg Speed").font(.caption).foregroundColor(.gray) }
                                Text(String(format: "%.1f", currentLogs.averageSpeed)).font(.title2).bold() + Text(" m/q").font(.caption).foregroundColor(.gray)
                            }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(white: 0.1)).cornerRadius(12)
                            
                            VStack(alignment: .leading) {
                                HStack { Image(systemName: "exclamationmark.triangle").foregroundColor(.orange); Text("Doubt").font(.caption).foregroundColor(.gray) }
                                let d = currentLogs.totalDoubt(); let s = currentLogs.totalDuration(category: .study); let p = s > 0 ? (d/s)*100 : 0
                                Text(Formatters.formatTime(d)).font(.headline).bold().monospacedDigit()
                                Text(String(format: "%.1f%% of study", p)).font(.caption2).foregroundColor(.gray)
                            }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(white: 0.1)).cornerRadius(12)
                        }.padding(.horizontal)
                        
                        NavigationLink(destination: HistoryListView(db: db)) {
                            HStack { Text("View Full History"); Spacer(); Image(systemName: "chevron.right") }
                                .padding().background(Color(white: 0.1)).cornerRadius(12).foregroundColor(.white)
                        }.padding(.horizontal).padding(.bottom, 30)
                    }.padding(.top)
                }
            }
            .background(Color.black)
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { showImporter = true }) { Image(systemName: "square.and.arrow.down") }
                    
                    if let url = exportURL { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") } }
                    else { Button(action: { exportURL = db.exportTodaysData() }) { Image(systemName: "square.and.arrow.up") } }
                    
                    Button(action: { showClearAlert = true }) { Image(systemName: "trash").foregroundColor(.red) }
                }
            }
            .alert("Clear Data?", isPresented: $showClearAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) { db.clearAll() }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls): if let url = urls.first { db.importData(from: url) }
                case .failure(let error): print("Import error: \(error.localizedDescription)")
                }
            }
            .onAppear { exportURL = db.exportTodaysData() }
            .onChange(of: db.logs) { oldLogs, newLogs in
                exportURL = db.exportTodaysData()
            }
        }.navigationViewStyle(.stack)
    }
}

// MARK: - 📝 LOGGER VIEW
struct LoggerView: View {
    @ObservedObject var db: ActivityDatabase
    @ObservedObject var stopwatch: StopwatchModel
    @ObservedObject var timer: TimerModel
    
    @State private var tab = 0
    @State private var category: ActivityCategory = .study
    @State private var studyMode: StopwatchMode = .solving
    @State private var start = Date(); @State private var end = Date(); @State private var note = ""
    @State private var showSuccess = false
    
    @AppStorage("logger_isSleeping") private var isSleeping = false
    @AppStorage("logger_sleepStart") private var sleepStartTimestamp: Double = 0
    
    var activeTracker: SessionTracker? {
        if stopwatch.isSessionActive { return stopwatch }
        if timer.isSessionActive { return timer }
        return nil
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Mode", selection: $tab) {
                    Text("Timeline").tag(1)
                    Text("Manual").tag(2)
                    Text("Sleep").tag(3)
                }
                .pickerStyle(.segmented).padding()
                
                if tab == 1 {
                    ZStack(alignment: .bottom) {
                        let startOfToday = Calendar.current.startOfDay(for: Date())
                        DailyTimelineView(
                            logs: db.getLogs(from: startOfToday, to: Date()),
                            onGapTap: { s, e in start = s; end = e; tab = 2 },
                            activeSession: activeTracker
                        )
                        Text("Tap + on gaps to log").font(.caption).foregroundColor(.gray).padding().background(Material.ultraThinMaterial).cornerRadius(8).padding()
                    }
                } else if tab == 2 {
                    ScrollView { formView() }
                } else {
                    sleepTimerView()
                }
            }
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Saved", isPresented: $showSuccess){ Button("OK"){ if tab == 2 { tab = 1 } } }
        }.navigationViewStyle(.stack)
    }
    
    func sleepTimerView() -> some View {
        VStack {
            Spacer()
            if isSleeping {
                VStack(spacing: 20) {
                    Image(systemName: "moon.stars.fill").font(.system(size: 60)).foregroundColor(.indigo)
                    Text("Good Night").font(.title).fontWeight(.bold)
                    TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                        let start = Date(timeIntervalSince1970: sleepStartTimestamp)
                        Text(Formatters.formatTime(Date().timeIntervalSince(start))).font(.system(size: 60, weight: .light)).monospacedDigit()
                    }
                    Button(action: {
                        let wakeTime = Date()
                        let sleepTime = Date(timeIntervalSince1970: sleepStartTimestamp)
                        db.log(start: sleepTime, end: wakeTime, category: .sleep, note: "Tracked Sleep")
                        isSleeping = false; sleepStartTimestamp = 0; HapticManager.shared.success(); showSuccess = true
                    }) {
                        Text("Wake Up").font(.title2).bold().foregroundColor(.white).frame(width: 200, height: 60).background(Color.orange).cornerRadius(30)
                    }
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "bed.double.fill").font(.system(size: 60)).foregroundColor(.gray)
                    Text("Ready to sleep?").font(.title2).foregroundColor(.gray)
                    Button(action: {
                        sleepStartTimestamp = Date().timeIntervalSince1970; isSleeping = true; HapticManager.shared.success()
                    }) {
                        Text("Start Sleep").font(.title2).bold().foregroundColor(.white).frame(width: 200, height: 60).background(Color.indigo).cornerRadius(30)
                    }
                }
            }
            Spacer()
        }
    }
    
    func formView() -> some View {
        VStack(spacing: 20) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                ForEach(ActivityCategory.allCases) { cat in
                    Button(action: { category = cat }) {
                        VStack { Image(systemName: cat.icon).font(.title2); Text(cat.rawValue).font(.caption2).bold() }
                        .frame(maxWidth: .infinity).padding(.vertical, 12).background(category == cat ? cat.color : Color(white: 0.1)).cornerRadius(10).foregroundColor(.white)
                    }
                }
            }.padding(.horizontal)
            
            if category == .study {
                Picker("Study Type", selection: $studyMode) {
                    Text("Problem Solving").tag(StopwatchMode.solving)
                    Text("Theory / Reading").tag(StopwatchMode.theory)
                }.pickerStyle(.segmented).padding(.horizontal)
            }
            
            VStack(alignment: .leading) {
                Text("Time Range").font(.caption).foregroundColor(.gray).padding(.leading)
                VStack(spacing: 1) { DatePicker("Start", selection: $start).padding().background(Color(white: 0.1)); DatePicker("End", selection: $end).padding().background(Color(white: 0.1)) }.cornerRadius(12)
            }.padding(.horizontal)
            
            TextField("Note (Optional)", text: $note).padding().background(Color(white: 0.1)).cornerRadius(10).padding(.horizontal)
            
            Button(action: {
                var finalNote = note
                if category == .study {
                    let modeStr = (studyMode == .theory) ? "Study: Theory" : "Study: Solving"
                    finalNote = finalNote.isEmpty ? modeStr : "\(modeStr) - \(finalNote)"
                }
                
                db.log(start: start, end: end, category: category, note: finalNote)
                HapticManager.shared.success(); showSuccess = true; note = ""
            }) {
                Text("Log Activity").bold().foregroundColor(.black).frame(maxWidth: .infinity).padding().background(Color.white).cornerRadius(12)
            }.padding(.horizontal)
        }
    }
}

// MARK: - 📜 HISTORY LIST
struct HistoryListView: View {
    @ObservedObject var db: ActivityDatabase
    @State private var searchText = ""
    @State private var selectedCategory: ActivityCategory? = nil
    
    var sections: [DaySection] {
        let filtered = db.logs.filter { log in
            let matchesSearch = searchText.isEmpty || (log.note?.localizedCaseInsensitiveContains(searchText) ?? false) || log.category.rawValue.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategory == nil || log.category == selectedCategory
            return matchesSearch && matchesCategory
        }
        let grouped = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.startDate) }
        let sortedDates = grouped.keys.sorted(by: >)
        return sortedDates.map { date in DaySection(date: date, logs: grouped[date]?.sorted(by: { $0.startDate > $1.startDate }) ?? []) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    FilterChip(title: "All", isSelected: selectedCategory == nil) { selectedCategory = nil }
                    ForEach(ActivityCategory.allCases) { cat in
                        FilterChip(title: cat.rawValue, color: cat.color, isSelected: selectedCategory == cat) {
                            if selectedCategory == cat { selectedCategory = nil } else { selectedCategory = cat }
                        }
                    }
                }.padding()
            }.background(Color(white: 0.05))
            
            List {
                ForEach(sections) { section in
                    Section(header: HistorySectionHeader(section: section)) {
                        ForEach(section.logs) { log in HistoryRow(log: log) }
                        .onDelete { indexSet in
                            let logsToDelete = indexSet.map { section.logs[$0] }
                            for log in logsToDelete {
                                if let index = db.logs.firstIndex(where: { $0.id == log.id }) { db.delete(at: IndexSet(integer: index)) }
                            }
                        }
                    }
                }
            }.listStyle(.plain).scrollContentBackground(.hidden).background(Color.black)
        }
        .searchable(text: $searchText, prompt: "Search notes or tags")
        .navigationTitle("History")
    }
}

struct DaySection: Identifiable {
    let id = UUID(); let date: Date; let logs: [ActivityLog]
    var totalTime: TimeInterval { logs.reduce(0) { $0 + $1.duration } }
    var totalQuestions: Int { logs.reduce(0) { $0 + $1.questionsSolved } }
}

struct HistorySectionHeader: View {
    let section: DaySection
    var body: some View {
        HStack {
            Text(formatDate(section.date)).font(.headline).foregroundColor(.white)
            Spacer()
            HStack(spacing: 12) {
                if section.totalQuestions > 0 { HStack(spacing: 4) { Image(systemName: "checkmark.circle.fill"); Text("\(section.totalQuestions)") }.foregroundColor(.orange).font(.caption).bold() }
                HStack(spacing: 4) { Image(systemName: "clock.fill"); Text(Formatters.formatDurationText(section.totalTime)) }.foregroundColor(.gray).font(.caption).bold()
            }
        }.padding(.vertical, 8).padding(.horizontal, 4).background(Color.black)
    }
    func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f.string(from: date)
    }
}

struct HistoryRow: View {
    let log: ActivityLog
    var body: some View {
        HStack(spacing: 16) {
            ZStack { Circle().fill(log.category.color.opacity(0.2)).frame(width: 40, height: 40); Image(systemName: log.category.icon).foregroundColor(log.category.color).font(.caption) }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(log.category.rawValue).font(.subheadline).bold().foregroundColor(.white)
                    if let note = log.note, !note.isEmpty { Text("•").foregroundColor(.gray); Text(note).font(.caption).lineLimit(1).foregroundColor(.gray) }
                }
                Text("\(Formatters.timeLabel.string(from: log.startDate)) - \(Formatters.timeLabel.string(from: log.endDate))").font(.caption2).foregroundColor(Color(white: 0.4))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatters.formatDurationText(log.duration)).font(.subheadline).bold().monospacedDigit().foregroundColor(.white)
                if log.questionsSolved > 0 { Text("\(log.questionsSolved) Qs").font(.caption2).bold().foregroundColor(.orange) }
                else if log.doubtTime > 0 { HStack(spacing: 2) { Image(systemName: "exclamationmark.triangle.fill"); Text(Formatters.formatDurationText(log.doubtTime)) }.font(.caption2).foregroundColor(.orange) }
            }
        }.padding(.vertical, 4).listRowBackground(Color(white: 0.1)).listRowSeparatorTint(Color.black)
    }
}

struct FilterChip: View {
    let title: String; var color: Color = .white; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.caption).bold().padding(.vertical, 6).padding(.horizontal, 14)
                .background(isSelected ? color : Color(white: 0.15))
                .foregroundColor(isSelected ? (color == .white ? .black : .white) : .gray)
                .cornerRadius(20)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(isSelected ? color : Color.clear, lineWidth: 1))
        }
    }
}

struct ResizableStack<Top: View, Bottom: View>: View {
    @State private var splitRatio: CGFloat = 0.60
    let top: (CGSize) -> Top; let bottom: (CGSize) -> Bottom
    init(@ViewBuilder top: @escaping (CGSize) -> Top, @ViewBuilder bottom: @escaping (CGSize) -> Bottom) { self.top = top; self.bottom = bottom }
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                top(CGSize(width: geo.size.width, height: geo.size.height * splitRatio)).frame(height: geo.size.height * splitRatio).clipped()
                ZStack { Rectangle().fill(Color.black); Capsule().fill(Color(white: 0.3)).frame(width: 40, height: 5) }.frame(height: 30).contentShape(Rectangle())
                    .gesture(DragGesture(coordinateSpace: .named("stackSpace")).onChanged { value in
                        let ratio = value.location.y / geo.size.height; withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) { self.splitRatio = min(0.85, max(0.2, ratio)) }
                    })
                bottom(CGSize(width: geo.size.width, height: max(0, geo.size.height * (1 - splitRatio) - 30))).frame(height: max(0, geo.size.height * (1 - splitRatio) - 30))
            }
        }.coordinateSpace(name: "stackSpace")
    }
}

struct ClockButton: View {
    let label: String; let bgColor: Color; let textColor: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack { Circle().stroke(bgColor, lineWidth: 2).frame(width: 88, height: 88); Circle().fill(bgColor).frame(width: 82, height: 82); Text(label).font(.headline).bold().foregroundColor(textColor) }
        }.buttonStyle(.plain)
    }
}

struct NativePicker: View {
    @Binding var val: Int; let range: ClosedRange<Int>; let label: String
    var body: some View {
        HStack(spacing: 0) {
            Picker("", selection: $val) { ForEach(range, id: \.self) { Text("\($0)").tag($0).foregroundColor(.white) } }
            .pickerStyle(.wheel).frame(width: 60, height: 100).clipped().compositingGroup(); Text(label).font(.headline).foregroundColor(.gray).padding(.leading, 5)
        }.frame(width: 100)
    }
}

struct StatCard: View {
    let title: String, value: String, icon: String, color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: icon).foregroundColor(color); Text(title).font(.caption).fontWeight(.bold).foregroundColor(.gray) }
            Text(value).font(.title3).fontWeight(.bold).foregroundColor(.white).minimumScaleFactor(0.8).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color(white: 0.1)).cornerRadius(12)
    }
}
