import Foundation

/// Developer-only macOS smoke check. Uses exactly the app's inference service.
/// EGO_MODEL_ROOT must point at verified downloaded model directories.
@main struct ModelCheck {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 3, ProcessInfo.processInfo.environment["EGO_MODEL_ROOT"] != nil else {
            print("EGO_MODEL_ROOT=/path/to/Models EgoModelCheck parakeet|whisper audio.wav")
            print("EGO_MODEL_ROOT=/path/to/Models EgoModelCheck qwen text.txt")
            return
        }
        guard let model = LocalModel(rawValue: args[1]) else { throw ModelError.notInstalled }
        let engine = LocalIntelligence(); let start = Date()
        if model == .qwen {
            let text = try String(contentsOfFile: args[2], encoding: .utf8)
            if args.contains("--cancel-check") {
                _ = try await engine.reflect(text: text, context: "")
                let longText = String(String(repeating: text + "\n", count: 80).prefix(14000))
                let task = Task { try await engine.reflect(text: longText, context: "") }
                try await Task.sleep(for: .milliseconds(200))
                let cancelled = Date(); task.cancel()
                do { _ = try await task.value; throw IntelligenceError.invalidResponse }
                catch is CancellationError { print("Cancellation drained in seconds: \(Date().timeIntervalSince(cancelled))") }
            }
            let result = try await engine.reflect(text: text, context: "")
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(result), as: UTF8.self))
        } else { print(try await engine.transcribe(url: URL(fileURLWithPath: args[2]), model: model, language: "ru")) }
        print("Elapsed seconds: \(Date().timeIntervalSince(start))")
    }
}
