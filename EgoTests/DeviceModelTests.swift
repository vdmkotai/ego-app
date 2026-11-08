import XCTest
@testable import Ego

@MainActor final class DeviceModelTests: XCTestCase {
    func testRussianModelsOnPhysicalDevice() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Model integration is measured on a physical iPhone.")
        #else
        let library = ModelLibrary()
        guard LocalModel.allCases.allSatisfy({ library.installed.contains($0) }) else {
            throw XCTSkip("Download all three verified models before running the device integration test.")
        }
        let audio = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "russian-fixture", withExtension: "wav"))
        let engine = LocalIntelligence()
        var outputs: [String] = []
        for model in [LocalModel.parakeet, .whisper] {
            let started = Date()
            let text = try await engine.transcribe(url: audio, model: model, language: "ru")
            XCTAssertTrue(text.folded.contains("тбилиси"), text)
            XCTAssertTrue(text.folded.contains("не хочу"), text)
            outputs.append("\(model.title): \(Date().timeIntervalSince(started)) s\n\(text)")
        }
        let original = "Сегодня я наконец закончил сложную задачу на работе. После прогулки я нашёл решение. Не хочу снова откладывать отдых ради работы."
        let started = Date()
        let reflection = try await engine.reflect(text: original, context: "")
        XCTAssertFalse(reflection.quote.isEmpty)
        XCTAssertTrue(original.contains(reflection.quote))
        XCTAssertFalse(reflection.themes.isEmpty)
        outputs.append("Qwen: \(Date().timeIntervalSince(started)) s\nQuote: \(reflection.quote)\nObservation: \(reflection.observation ?? "nil")\nThemes: \(reflection.themes)")
        let switched = try await engine.transcribe(url: audio, model: .parakeet, language: "ru")
        XCTAssertTrue(switched.folded.contains("тбилиси"))
        outputs.append("Switch Qwen → Parakeet: passed")
        let attachment = XCTAttachment(string: outputs.joined(separator: "\n\n"))
        attachment.name = "Russian models on iPhone"; attachment.lifetime = .keepAlways; add(attachment)
        #endif
    }
    func testModelDownloadRepairsMissingVocabulary() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Run the download check on the physical device after installing models.")
        #else
        let model = LocalModel.parakeet
        let library = ModelLibrary()
        guard library.installed.contains(model) else { throw XCTSkip("Install Parakeet first.") }
        let vocabulary = model.directory.appendingPathComponent("parakeet_vocab.json")
        let backup = try Data(contentsOf: vocabulary)
        defer { if !FileManager.default.fileExists(atPath: vocabulary.path) { try? backup.write(to: vocabulary, options: .atomic) } }
        try FileManager.default.removeItem(at: vocabulary)
        library.refresh(); XCTAssertFalse(library.installed.contains(model))
        library.download(model)
        let deadline = Date().addingTimeInterval(90)
        while library.downloading != nil && Date() < deadline { try await Task.sleep(for: .milliseconds(200)) }
        guard library.downloading == nil else { library.cancel(); XCTFail("Model download timed out."); return }
        XCTAssertNil(library.error)
        XCTAssertTrue(library.installed.contains(model))
        XCTAssertEqual(try Data(contentsOf: vocabulary), backup)
        #endif
    }

    func testWhisperFirstAndSecondLoadTiming() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Whisper timing requires the physical iPhone.")
        #else
        guard ModelLibrary().installed.contains(.whisper) else { throw XCTSkip("Install Whisper first.") }
        let audio = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "russian-fixture", withExtension: "wav"))
        let engine = LocalIntelligence(); var reports: [String] = []
        for run in 1...2 {
            let text = try await engine.transcribe(url: audio, model: .whisper, language: "ru")
            XCTAssertTrue(text.folded.contains("тбилиси"))
            let timings = await engine.lastTimings
            reports.append("Run \(run): \(timings)")
            print(reports.last!)
        }
        let attachment = XCTAttachment(string: reports.joined(separator: "\n")); attachment.name = "Whisper load and decode timing"; attachment.lifetime = .keepAlways; add(attachment)
        #endif
    }

    func testEnglishReflectionPreservesRussianQuote() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Local Qwen runs on the physical iPhone.")
        #else
        guard ModelLibrary().installed.contains(.qwen) else { throw XCTSkip("Install Qwen first.") }
        let original = "Сегодня я наконец закончил сложную задачу на работе. После прогулки я нашёл решение. Не хочу снова откладывать отдых ради работы."
        let reflection = try await LocalIntelligence().reflect(text: original, context: "", language: "en")
        XCTAssertTrue(original.contains(reflection.quote))
        XCTAssertFalse(reflection.themes.isEmpty)
        let generated = reflection.themes.joined(separator: " ") + (reflection.observation ?? "")
        XCTAssertNil(generated.range(of: "[А-Яа-яЁё]", options: .regularExpression), generated)
        XCTAssertNotNil(generated.range(of: "[A-Za-z]", options: .regularExpression), generated)
        let attachment = XCTAttachment(string: "Quote: \(reflection.quote)\nObservation: \(reflection.observation ?? "nil")\nThemes: \(reflection.themes)")
        attachment.name = "English reflection with Russian source"; attachment.lifetime = .keepAlways; add(attachment)
        #endif
    }

}
