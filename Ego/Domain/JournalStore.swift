import Foundation
import Observation

@MainActor @Observable final class JournalStore {
    private(set) var entries: [JournalEntry] = []
    private(set) var reviews: [WeekReview] = []
    var error: String?
    private let url: URL
    private var readable = true
    private struct Archive: Codable { var version = 1; var entries: [JournalEntry]; var reviews: [WeekReview] }

    init(directory: URL = EgoPaths.root) {
        url = directory.appendingPathComponent("journal.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
            entries = archive.entries; reviews = archive.reviews
            // An interrupted job is retryable. Its source recording stays untouched.
            for i in entries.indices where [.transcribing, .reflecting, .recording].contains(entries[i].status) {
                entries[i].status = entries[i].status == .reflecting ? .pendingReflection : (entries[i].audioFile != nil ? .pending : .ready)
            }
        } catch { readable = false; self.error = L("Не удалось прочитать дневник. Файл сохранён без изменений. %@", error.localizedDescription) }
    }

    @discardableResult func save(_ entry: JournalEntry) -> Bool {
        var next = entries
        if let i = next.firstIndex(where: { $0.id == entry.id }) { next[i] = entry } else { next.append(entry) }
        let old = entries.first { $0.id == entry.id }
        let changed = old == nil || old?.text != entry.text || old?.context != entry.context
        let retained = changed ? reviews.filter { review in
            guard let interval = Calendar.journal.dateInterval(of: .weekOfYear, for: review.id) else { return false }
            return !(entry.date >= interval.start && entry.date < interval.end)
        } : reviews
        return commit(entries: next.sorted { $0.date > $1.date }, reviews: retained)
    }
    @discardableResult func save(review: WeekReview) -> Bool {
        var next = reviews.filter { $0.id != review.id }; next.append(review)
        return commit(entries: entries, reviews: next)
    }
    @discardableResult func delete(_ id: UUID) -> Bool {
        guard let entry = entry(id) else { return true }
        let remaining = reviews.filter { !$0.entryIDs.contains(id) }
        guard commit(entries: entries.filter { $0.id != id }, reviews: remaining) else { return false }
        if let file = entry.audioFile { try? FileManager.default.removeItem(at: EgoPaths.audio.appendingPathComponent(file)) }
        return true
    }
    func entry(_ id: UUID) -> JournalEntry? { entries.first { $0.id == id } }
    func entries(on date: Date) -> [JournalEntry] { entries.filter { Calendar.journal.isDate($0.date, inSameDayAs: date) } }
    func entries(in interval: DateInterval) -> [JournalEntry] { entries.filter { $0.date >= interval.start && $0.date < interval.end } }
    private func commit(entries: [JournalEntry], reviews: [WeekReview]) -> Bool {
        guard readable else { error = L("Дневник не прочитан. Сохранение остановлено, чтобы не перезаписать исходный файл."); return false }
        do {
            let data = try JSONEncoder().encode(Archive(entries: entries, reviews: reviews))
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            self.entries = entries; self.reviews = reviews; return true
        } catch { self.error = L("Не удалось сохранить запись. %@", error.localizedDescription); return false }
    }
}
