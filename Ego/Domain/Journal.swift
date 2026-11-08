import Foundation

struct Reflection: Codable, Equatable {
    var quote: String
    var observation: String?
    var themes: [String]
}

struct JournalEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var text = ""
    var context = ""
    var audioFile: String?
    var duration: TimeInterval = 0
    var model: String?
    var reflection: Reflection?
    var status: Status = .ready
    var failure: String?
    var failureKey: String?
    var failureDescription: String? { failureKey.map { L($0) } ?? failure.map { _ in L("Не удалось обработать запись. Она сохранена. Попробуй ещё раз.") } }
    enum Status: String, Codable { case recording, pending, pendingReflection, transcribing, reflecting, ready, failed }
    var headline: String { reflection?.quote.nonEmpty ?? text.nonEmpty ?? L("Аудиозапись") }
    var searchable: String { ([text, context] + (reflection?.themes ?? []) + [reflection?.observation ?? ""]).joined(separator: " ").folded }
    var durationLabel: String { duration > 0 ? Self.time(duration) : L("Текст") }
    static func time(_ value: TimeInterval) -> String { let s = max(0, Int(value)); return String(format: "%d:%02d", s / 60, s % 60) }
    func matches(_ query: String) -> Bool { query.folded.split(whereSeparator: \.isWhitespace).allSatisfy { searchable.contains($0) } }
}

struct WeekReview: Codable, Identifiable {
    var id: Date
    var text: String
    var entryIDs: [UUID]
    var created = Date()
}

extension String {
    var nonEmpty: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
    var folded: String { folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU")) }
}

extension Calendar {
    static var journal: Calendar { var c = Calendar(identifier: .gregorian); c.locale = Locale(identifier: "ru_RU"); c.firstWeekday = 2; return c }
    func daysOfWeek(containing date: Date) -> [Date] {
        let start = dateInterval(of: .weekOfYear, for: date)!.start
        return (0..<7).compactMap { self.date(byAdding: .day, value: $0, to: start) }
    }
}

enum EgoPaths {
    static let root: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ego", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var mutable = url; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
        return url
    }()
    static var audio: URL { directory("Audio") }
    static var models: URL {
        #if os(macOS)
        if let path = ProcessInfo.processInfo.environment["EGO_MODEL_ROOT"] { return URL(fileURLWithPath: path) }
        #endif
        return directory("Models")
    }
    static func directory(_ name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// A generated observation needs a verbatim supporting span. Unsupported output stays hidden.
enum ReflectionParser {
    private struct Payload: Decodable { var quote: String; var observation: String?; var themes: [String]; var evidence: [String]? }
    static func parse(_ response: String, original: String) throws -> Reflection {
        guard let start = response.firstIndex(of: "{"), let end = response.lastIndex(of: "}"), start <= end else { throw IntelligenceError.invalidResponse }
        let payload = try JSONDecoder().decode(Payload.self, from: Data(response[start...end].utf8))
        let evidence = payload.evidence ?? []
        let grounded = !evidence.isEmpty && evidence.allSatisfy { $0.count >= 8 && original.contains($0) }
        let quote = !payload.quote.isEmpty && original.contains(payload.quote) ? payload.quote : original.openingQuote
        let themes = Array(Set(payload.themes.filter { !$0.isEmpty && $0.count < 50 })).sorted().prefix(3).map { $0 }
        return Reflection(quote: quote, observation: grounded ? payload.observation : nil, themes: themes)
    }
}

extension String {
    var openingQuote: String {
        let excerpt = prefix(200)
        if let end = excerpt.firstIndex(where: { ".!?\n".contains($0) }) { return String(excerpt[...end]).trimmingCharacters(in: .whitespacesAndNewlines) }
        if excerpt.count < count, let end = excerpt.lastIndex(where: \.isWhitespace) { return String(excerpt[..<end]) }
        return String(excerpt)
    }
    func chunks(maxCharacters: Int) -> [String] {
        precondition(maxCharacters > 0)
        var result: [String] = []; var cursor = startIndex
        while cursor < endIndex { let end = index(cursor, offsetBy: maxCharacters, limitedBy: endIndex) ?? endIndex; result.append(String(self[cursor..<end])); cursor = end }
        return result
    }
    func excerpt(matching query: String, length: Int = 150) -> String? {
        guard let term = query.split(whereSeparator: \.isWhitespace).first,
              let match = range(of: String(term), options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU")) else { return nil }
        let start = index(match.lowerBound, offsetBy: -35, limitedBy: startIndex) ?? startIndex
        let end = index(start, offsetBy: length, limitedBy: endIndex) ?? endIndex
        return (start > startIndex ? "…" : "") + String(self[start..<end]) + (end < endIndex ? "…" : "")
    }
}
