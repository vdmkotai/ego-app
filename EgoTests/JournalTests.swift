import XCTest
@testable import Ego

@MainActor final class JournalTests: XCTestCase {
    func temporary() throws -> URL { let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url }
    func testPersistsRussianTextAndContextAcrossLaunches() throws {
        let root = try temporary(); let store = JournalStore(directory: root)
        var entry = JournalEntry(); entry.text = "Я не хочу отменять поездку в Тбилиси."; entry.context = "Билеты уже куплены"
        XCTAssertTrue(store.save(entry))
        let restored = JournalStore(directory: root)
        XCTAssertEqual(restored.entry(entry.id)?.text, entry.text)
        XCTAssertTrue(restored.entry(entry.id)!.matches("ТБИЛИСИ билеты"))
        XCTAssertFalse(restored.entry(entry.id)!.matches("Москва"))
    }
    func testSearchFindsYoAndAllTermsAcrossFields() {
        var entry = JournalEntry(); entry.text = "Ещё одна мысль про работу"; entry.context = "Проект Ego"
        XCTAssertTrue(entry.matches("еще EGO")); XCTAssertFalse(entry.matches("еще отпуск"))
    }
    func testInterruptedTranscriptionKeepsAudioAndBecomesPending() throws {
        let root = try temporary(); let store = JournalStore(directory: root)
        var entry = JournalEntry(); entry.audioFile = "test.m4a"; entry.status = .transcribing
        XCTAssertTrue(store.save(entry))
        let restored = JournalStore(directory: root)
        XCTAssertEqual(restored.entry(entry.id)?.status, .pending)
        XCTAssertEqual(restored.entry(entry.id)?.audioFile, "test.m4a")
    }
    func testDeleteRemovesDependentReviewAndSurvivesRelaunch() throws {
        let root = try temporary(); let store = JournalStore(directory: root)
        let entry = JournalEntry(); XCTAssertTrue(store.save(entry))
        XCTAssertTrue(store.save(review: WeekReview(id: Date(), text: "Неделя", entryIDs: [entry.id])))
        XCTAssertTrue(store.delete(entry.id))
        let restored = JournalStore(directory: root); XCTAssertTrue(restored.entries.isEmpty); XCTAssertTrue(restored.reviews.isEmpty)
    }
    func testWeekStartsMondayAcrossYearBoundary() {
        let calendar = Calendar.journal
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let days = calendar.daysOfWeek(containing: date)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(calendar.component(.weekday, from: days[0]), 2)
        XCTAssertEqual(calendar.component(.year, from: days[0]), 2025)
        XCTAssertEqual(calendar.component(.day, from: days[0]), 29)
    }
    func testFailedWriteDoesNotMutateMemory() throws {
        let root = try temporary().appendingPathComponent("missing")
        let store = JournalStore(directory: root)
        XCTAssertFalse(store.save(JournalEntry())); XCTAssertTrue(store.entries.isEmpty); XCTAssertNotNil(store.error)
    }
    func testJSONExportContainsOriginalTextAndNoModelPaths() throws {
        var entry = JournalEntry(); entry.text = "Не забыть 25 сентября"; entry.context = "Личное"
        let url = try ExportService.export([entry], format: .json)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let data = try Data(contentsOf: url); let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode([JournalEntry].self, from: data)
        XCTAssertEqual(restored.first?.text, entry.text); XCTAssertEqual(restored.first?.context, entry.context)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Application Support"))
    }
    func testCorruptArchiveCannotBeOverwritten() throws {
        let root = try temporary(); let url = root.appendingPathComponent("journal.json")
        let corrupt = Data("partial broken archive".utf8); try corrupt.write(to: url)
        let store = JournalStore(directory: root)
        XCTAssertFalse(store.save(JournalEntry())); XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }
    func testUngroundedReflectionIsDiscarded() throws {
        let result = try ReflectionParser.parse(#"{"quote":"Выдуманная цитата","observation":"Ты всегда тревожишься","themes":["Работа"],"evidence":["нет в тексте"]}"#, original: "Сегодня спокойно работал дома.")
        XCTAssertNil(result.observation); XCTAssertEqual(result.quote, "Сегодня спокойно работал дома.")
    }
    func testEditingEntryInvalidatesWeeklyReview() throws {
        let store = JournalStore(directory: try temporary()); var entry = JournalEntry(); entry.text = "Первый текст"
        XCTAssertTrue(store.save(entry)); let week = Calendar.journal.dateInterval(of: .weekOfYear, for: entry.date)!.start
        XCTAssertTrue(store.save(review: WeekReview(id: week, text: "Итог", entryIDs: [entry.id])))
        entry.text = "Исправленный текст"; XCTAssertTrue(store.save(entry)); XCTAssertTrue(store.reviews.isEmpty)
    }

    func testInterruptedReflectionPreservesEditedAudioTranscript() throws {
        let root = try temporary(); let store = JournalStore(directory: root)
        var entry = JournalEntry(); entry.audioFile = "original.m4a"; entry.text = "Исправленный вручную текст"; entry.status = .reflecting
        XCTAssertTrue(store.save(entry)); let restored = JournalStore(directory: root)
        XCTAssertEqual(restored.entry(entry.id)?.status, .pendingReflection)
        XCTAssertEqual(restored.entry(entry.id)?.text, entry.text)
    }
    func testReviewChunksPreserveEntireUnicodeText() {
        let source = String(repeating: "Русский текст 👨‍👩‍👦\n", count: 1700)
        let pieces = source.chunks(maxCharacters: 10000)
        XCTAssertGreaterThan(pieces.count, 1); XCTAssertEqual(pieces.joined(), source)
        XCTAssertTrue(pieces.allSatisfy { $0.count <= 10000 })
    }

}
