import Foundation
import ZIPFoundation

enum ExportService {
    static func removeAbandonedExports() {
        let root = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for folder in files where folder.lastPathComponent.hasPrefix("Ego-") { try? FileManager.default.removeItem(at: folder) }
    }
    enum Format { case markdown, json, archive }
    static func export(_ entries: [JournalEntry], format: Format) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Ego-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: folder) } }
        let sorted = entries.sorted { $0.date < $1.date }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let markdown = sorted.map { entry in
            var value = "# \(entry.date.egoFormatted(date: .long, time: .shortened))\n\n\(entry.text)\n"
            if !entry.context.isEmpty { value += "\n## " + L("Контекст") + "\n\n" + entry.context + "\n" }
            if let r = entry.reflection { value += "\n## " + L("Наблюдение") + "\n\n" + (r.observation ?? "") + "\n\n" + r.themes.joined(separator: ", ") + "\n" }
            return value
        }.joined(separator: "\n---\n\n")
        switch format {
        case .markdown:
            let url = folder.appendingPathComponent("Ego.md"); try markdown.write(to: url, atomically: true, encoding: .utf8); succeeded = true; return url
        case .json:
            let url = folder.appendingPathComponent("Ego.json"); try encoder.encode(sorted).write(to: url, options: .atomic); succeeded = true; return url
        case .archive:
            let payload = folder.appendingPathComponent("Ego", isDirectory: true)
            try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
            try markdown.write(to: payload.appendingPathComponent("journal.md"), atomically: true, encoding: .utf8)
            try encoder.encode(sorted).write(to: payload.appendingPathComponent("journal.json"), options: .atomic)
            let audio = payload.appendingPathComponent("audio", isDirectory: true)
            try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
            for entry in entries { if let file = entry.audioFile { let source = EgoPaths.audio.appendingPathComponent(file); if FileManager.default.fileExists(atPath: source.path) { try FileManager.default.copyItem(at: source, to: audio.appendingPathComponent(file)) } } }
            let archive = folder.appendingPathComponent("Ego.zip")
            try FileManager.default.zipItem(at: payload, to: archive)
            try FileManager.default.removeItem(at: payload)
            succeeded = true; return archive
        }
    }
}
