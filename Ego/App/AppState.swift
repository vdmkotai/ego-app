import SwiftUI
import LocalAuthentication
import UserNotifications

@MainActor @Observable final class AppState {
    let store: JournalStore
    let models = ModelLibrary()
    let intelligence = LocalIntelligence()
    var selectedDate = Date()
    var capture = false
    var compose = false
    var settings = false
    var locked = false
    var busy = false
    var processingID: UUID?
    var authenticating = false
    var message: String?
    var replaceID: UUID?
    @ObservationIgnored private var pendingRoute: URL?
    @ObservationIgnored private var activeTask: Task<Void, Never>?
    private var foreground = false
    @ObservationIgnored private var jobs: [(UUID, Bool)] = []
    var selectedModel: LocalModel {
        get { LocalModel(rawValue: UserDefaults.standard.string(forKey: "speechModel") ?? "parakeet") ?? .parakeet }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "speechModel") }
    }
    var language: String {
        get { UserDefaults.standard.string(forKey: "language") ?? "ru" }
        set { UserDefaults.standard.set(newValue, forKey: "language") }
    }
    var faceID: Bool { UserDefaults.standard.bool(forKey: "faceID") }
    init(store: JournalStore? = nil) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest") || ProcessInfo.processInfo.arguments.contains("--preview") {
            let directory = EgoPaths.directory("UITest")
            if !ProcessInfo.processInfo.arguments.contains("--keep-journal") { try? FileManager.default.removeItem(at: directory.appendingPathComponent("journal.json")) }
            self.store = JournalStore(directory: directory)
            locked = false
            if ProcessInfo.processInfo.arguments.contains("--preview") { seedPreview() }
            return
        }
        #endif
        self.store = store ?? JournalStore(); locked = UserDefaults.standard.bool(forKey: "faceID")
    }
    #if DEBUG
    private func seedPreview() {
        var first = JournalEntry(); first.date = Calendar.journal.date(bySettingHour: 9, minute: 41, second: 0, of: Date())!; first.text = "Сегодня вышел погулять без телефона. Кажется, впервые за неделю никуда не торопился. Хочу запомнить это ощущение."; first.duration = 83; first.reflection = Reflection(quote: "Впервые за неделю никуда не торопился.", observation: "На этой прогулке ты заметил, каково это: не спешить.", themes: ["Прогулка", "Время для себя"]); _ = store.save(first)
        var second = JournalEntry(); second.date = Calendar.journal.date(bySettingHour: 8, minute: 12, second: 0, of: Date())!; second.text = "В голове много идей для нового проекта. Пока хочется просто дать им место."; second.reflection = Reflection(quote: "Пока хочется просто дать им место.", observation: nil, themes: ["Идеи", "Работа"]); _ = store.save(second)
        for month in [1,3,5,7,9,11] { var old = JournalEntry(); old.date = Calendar.journal.date(from: DateComponents(year: Calendar.journal.component(.year, from: Date())-1, month: month, day: 17))!; old.text = "Мысль из прошлого года о прогулке и новом проекте."; _ = store.save(old) }
    }
    #endif
    func unlock() async {
        guard !authenticating else { return }; authenticating = true; defer { authenticating = false }
        do { let context = LAContext(); let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L("Открыть дневник Ego")); if success { locked = false; if let route = pendingRoute { pendingRoute = nil; self.route(route) }; await resumePending(); await reviewCompletedWeekIfNeeded() } }
        catch { message = L("Дневник заблокирован. Можно попробовать ещё раз.") }
    }
    func setLock(_ value: Bool) async -> Bool {
        if value || faceID { let context = LAContext(); do { guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L("Защитить дневник Ego")) else { return false } } catch { message = error.localizedDescription; return false } }
        UserDefaults.standard.set(value, forKey: "faceID"); return true
    }
    func setForeground(_ value: Bool) {
        foreground = value
        if !value { activeTask?.cancel() }
    }
    func process(_ id: UUID, transcribe: Bool = true) async {
        #if DEBUG
        // UI tests exercise capture/archive independently from heavyweight model tests.
        if ProcessInfo.processInfo.arguments.contains("--uitest") { return }
        #endif
        guard var entry = store.entry(id) else { return }
        guard foreground, !locked else {
            entry.status = transcribe && entry.audioFile != nil ? .pending : .pendingReflection
            _ = store.save(entry); return
        }
        if busy { if !jobs.contains(where: { $0.0 == id }) { jobs.append((id, transcribe)) }; return }
        busy = true; processingID = id
        let task = Task { await runEntry(id, transcribe: transcribe) }
        activeTask = task
        await task.value
    }
    var preparingModel = false
    var processingModel: LocalModel?

    private func runEntry(_ id: UUID, transcribe: Bool) async {
        defer { preparingModel = false; processingModel = nil; busy = false; processingID = nil; activeTask = nil; drain(); resumeAfterCancellation() }
        guard var entry = store.entry(id) else { return }
        let model = selectedModel; let language = language; processingModel = model
        var needsTranscription = transcribe && entry.audioFile != nil
        do {
            try Task.checkCancellation()
            if transcribe, let file = entry.audioFile {
                entry.status = .transcribing; entry.failure = nil; entry.failureKey = nil; guard store.save(entry) else { return }
                let text = try await intelligence.transcribe(url: EgoPaths.audio.appendingPathComponent(file), model: model, language: language) { preparing in
                    await MainActor.run { self.preparingModel = preparing }
                }
                try Task.checkCancellation()
                guard store.entry(id) != nil else { return }
                entry.text = text; entry.model = model.title; entry.reflection = nil
                entry.status = .ready; guard store.save(entry) else { return }
                needsTranscription = false
            }
            if models.installed.contains(.qwen), !entry.text.isEmpty, UserDefaults.standard.object(forKey: "reflections") as? Bool ?? true {
                entry.status = .reflecting; guard store.save(entry) else { return }
                entry.reflection = try await intelligence.reflect(text: entry.text, context: [UserDefaults.standard.string(forKey: "aboutPurpose") ?? "", entry.context].joined(separator: "\n"))
            }
            try Task.checkCancellation()
            guard store.entry(id) != nil else { return }
            entry.status = .ready; entry.failure = nil; entry.failureKey = nil; _ = store.save(entry)
            if UserDefaults.standard.bool(forKey: "entryReady") { await notifyReady() }
        } catch {
            guard store.entry(id) != nil else { return }
            if Task.isCancelled {
                entry.status = needsTranscription ? .pending : .pendingReflection
                entry.failure = nil; entry.failureKey = nil; _ = store.save(entry); return
            }
            entry.status = .failed; entry.failure = error.localizedDescription; entry.failureKey = (error as? ModelError)?.messageKey ?? (error is IntelligenceError ? "Не удалось составить наблюдение. Твоя запись сохранена." : "Не удалось обработать запись. Она сохранена. Попробуй ещё раз."); _ = store.save(entry)
        }
    }
    func createText(_ text: String) {
        guard let text = text.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty else { return }
        var entry = JournalEntry(); entry.text = text
        if store.save(entry) { selectedDate = entry.date; Task { await process(entry.id, transcribe: false) } }
    }
    func review(week: Date) async {
        guard foreground, !locked, !busy, let interval = Calendar.journal.dateInterval(of: .weekOfYear, for: week) else { return }
        let entries = store.entries(in: interval).filter { !$0.text.isEmpty }
        guard !entries.isEmpty else { return }
        busy = true
        let task = Task { await runReview(entries: entries, interval: interval) }
        activeTask = task
        await task.value
    }
    private func runReview(entries: [JournalEntry], interval: DateInterval) async {
        defer { busy = false; activeTask = nil; drain(); resumeAfterCancellation() }
        do { try Task.checkCancellation(); let text = try await intelligence.review(entries: entries); try Task.checkCancellation(); guard store.entries(in: interval).filter({ !$0.text.isEmpty }) == entries else { message = L("Записи недели изменились. Составь итог ещё раз."); return }; _ = store.save(review: WeekReview(id: interval.start, text: text, entryIDs: entries.map(\.id))) }
        catch { if !Task.isCancelled { message = error.localizedDescription } }
    }
    private func resumeAfterCancellation() {
        guard Task.isCancelled, foreground, !locked else { return }
        Task { await resumePending(); await reviewCompletedWeekIfNeeded() }
    }
    private func drain() {
        guard foreground, !locked, !jobs.isEmpty else { return }
        let next = jobs.removeFirst(); Task { await process(next.0, transcribe: next.1) }
    }
    func resumePending() async {
        guard foreground, !locked else { return }
        if models.installed.contains(selectedModel) { for entry in store.entries where entry.status == .pending { await process(entry.id) } }
        if models.installed.contains(.qwen) { for entry in store.entries where entry.status == .pendingReflection { await process(entry.id, transcribe: false) } }
    }
    func reviewCompletedWeekIfNeeded() async {
        guard foreground, !busy, !locked, models.installed.contains(.qwen), UserDefaults.standard.object(forKey: "reflections") as? Bool ?? true else { return }
        let calendar = Calendar.journal
        let now = Date()
        let sundayEvening = calendar.component(.weekday, from: now) == 1 && calendar.component(.hour, from: now) >= 19
        let target = sundayEvening ? now : calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
        let start = calendar.dateInterval(of: .weekOfYear, for: target)!.start
        guard !store.reviews.contains(where: { $0.id == start }) else { return }
        await review(week: target)
    }
    private func notifyReady() async {
        let content = UNMutableNotificationContent(); content.title = "Ego"; content.body = L("Запись готова.")
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    func route(_ url: URL) { guard url.scheme == "ego" else { return }; if locked { pendingRoute = url; return }; replaceID = nil; if url.host == "write" { compose = true } else { capture = true } }
}
