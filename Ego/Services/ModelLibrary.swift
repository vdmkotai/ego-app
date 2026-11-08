import Foundation
import Observation
import CryptoKit

enum LocalModel: String, CaseIterable, Identifiable, Codable {
    case parakeet, whisper, qwen
    var id: String { rawValue }
    var title: String { switch self { case .parakeet: "Parakeet v3"; case .whisper: "Whisper Large v3 Turbo"; case .qwen: "Qwen 3.5 · 2B" } }
    var subtitle: String { switch self { case .parakeet: L("Русский и ещё 24 языка"); case .whisper: L("Русский и другие языки · Turbo"); case .qwen: L("Наблюдения и итоги недели") } }
    var directory: URL { EgoPaths.models.appendingPathComponent(rawValue, isDirectory: true) }
}
struct ModelManifest: Decodable {
    struct File: Decodable { var url: URL; var path: String; var bytes: Int64; var sha256: String?; var gitBlobSHA1: String? }
    var id: String
    var revision: String
    var files: [File]
    var bytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
    static func load(_ model: LocalModel) throws -> Self {
        guard let url = Bundle.main.url(forResource: model.rawValue, withExtension: "json") else { throw ModelError.missingManifest }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}
enum ModelError: LocalizedError {
    case missingManifest, notInstalled, corrupt, empty, busy
    var errorDescription: String? { L(messageKey) }
    var messageKey: String { switch self {
    case .missingManifest: "Нет описания модели в приложении."
    case .notInstalled: "Сначала скачай модель в настройках. Аудиозапись уже сохранена."
    case .corrupt: "Файл модели не прошёл проверку. Повтори загрузку."
    case .empty: "Речь не распознана. Аудиозапись сохранена, можно выбрать другую модель."
    case .busy: "Дождись завершения текущей обработки."
    } }
}

@MainActor @Observable final class ModelLibrary {
    var installed: Set<LocalModel> = []
    var downloading: LocalModel?
    var progress: Double = 0
    var error: String?
    private var task: Task<Void, Never>?
    init() { refresh() }
    func refresh() { installed = Set(LocalModel.allCases.filter { model in
        guard let manifest = try? ModelManifest.load(model), let marker = try? String(contentsOf: model.directory.appendingPathComponent("installed"), encoding: .utf8), marker == manifest.revision else { return false }
        return manifest.files.allSatisfy { file in let attrs = try? FileManager.default.attributesOfItem(atPath: model.directory.appendingPathComponent(file.path).path); return (attrs?[.size] as? NSNumber)?.int64Value == file.bytes }
    }) }
    func size(_ model: LocalModel) -> String { (try? ModelManifest.load(model)).map { $0.bytes.formatted(.byteCount(style: .file).locale(EgoLocale.current)) } ?? "" }
    func download(_ model: LocalModel) {
        guard downloading == nil else { return }
        downloading = model; progress = 0; error = nil
        task = Task {
            defer { downloading = nil; task = nil; refresh() }
            do {
                let manifest = try ModelManifest.load(model)
                let destination = model.directory
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                var completed: Int64 = 0
                for file in manifest.files {
                    try Task.checkCancellation()
                    let target = destination.appendingPathComponent(file.path)
                    if await ModelFiles.valid(target, file) { completed += file.bytes; progress = Double(completed) / Double(manifest.bytes); continue }
                    let previous = completed
                    let temp = try await FileDownload.fetch(file.url) { fraction in
                        Task { @MainActor [weak self] in self?.progress = Double(previous) / Double(manifest.bytes) + fraction * Double(file.bytes) / Double(manifest.bytes) }
                    }
                    defer { try? FileManager.default.removeItem(at: temp) }
                    guard await ModelFiles.valid(temp, file) else { throw ModelError.corrupt }
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                    try FileManager.default.moveItem(at: temp, to: target)
                    completed += file.bytes
                }
                try Task.checkCancellation()
                try manifest.revision.write(to: destination.appendingPathComponent("installed"), atomically: true, encoding: .utf8)
                progress = 1
            } catch is CancellationError { } catch let failure as URLError where failure.code == .cancelled { } catch { self.error = error.localizedDescription }
        }
    }
    func cancel() { task?.cancel() }
    func remove(_ model: LocalModel) {
        guard downloading == nil else { return }
        do { try FileManager.default.removeItem(at: model.directory); refresh() } catch { self.error = error.localizedDescription }
    }
}

private enum ModelFiles {
    static func valid(_ url: URL, _ file: ModelManifest.File) async -> Bool {
        await Task.detached(priority: .utility) {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path), (attrs[.size] as? NSNumber)?.int64Value == file.bytes else { return false }
            guard file.sha256 != nil || file.gitBlobSHA1 != nil else { return false }
            guard let handle = try? FileHandle(forReadingFrom: url) else { return false }; defer { try? handle.close() }
            var hash = SHA256(); var gitHash = Insecure.SHA1(); gitHash.update(data: Data("blob \(file.bytes)\0".utf8))
            do { while let block = try handle.read(upToCount: 1_048_576), !block.isEmpty { hash.update(data: block); gitHash.update(data: block) } } catch { return false }
            if let expected = file.sha256 { return hash.finalize().map { String(format: "%02x", $0) }.joined() == expected }; return gitHash.finalize().map { String(format: "%02x", $0) }.joined() == file.gitBlobSHA1
        }.value
    }
}

private final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var result: Result<URL, Error>?
    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    static func fetch(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let delegate = FileDownload(progress: progress)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60; configuration.timeoutIntervalForResource = 7200
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        delegate.session = session
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in delegate.continuation = continuation; session.downloadTask(with: url).resume() }
        } onCancel: { session.invalidateAndCancel() }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) { if totalBytesExpectedToWrite > 0 { progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) } }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: location, to: copy); result = .success(copy)
        } catch { result = .failure(error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        continuation?.resume(with: error.map { .failure($0) } ?? result ?? .failure(URLError(.unknown))); continuation = nil
        session.finishTasksAndInvalidate(); self.session = nil
    }
}
