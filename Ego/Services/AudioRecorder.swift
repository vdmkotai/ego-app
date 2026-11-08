import AVFoundation
import Observation

/// Audio driver calls can block for seconds on a broken route. Keep them off MainActor.
private actor CaptureEngine {
    static let shared = CaptureEngine()
    private var owner: UUID?
    private var player: AVAudioPlayer?
    private var recorder: AVAudioRecorder?
    private var delegate: RecordingDelegate?
    func start(owner: UUID, url: URL, failure: @escaping @Sendable (String) -> Void) throws -> String {
        guard self.owner == nil else { throw CaptureError.unavailable }
        self.owner = owner
        let session = AVAudioSession.sharedInstance()
        do {
            try Task.checkCancellation()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            try Task.checkCancellation()
            let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96000])
            self.recorder = recorder
            let delegate = RecordingDelegate(failure: failure); self.delegate = delegate; recorder.delegate = delegate
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else { throw CaptureError.unavailable }
            try Task.checkCancellation()
            return session.currentRoute.inputs.first?.egoName ?? L("Микрофон iPhone")
        } catch {
            recorder?.stop(); recorder = nil; delegate = nil; self.owner = nil
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
    func meter(owner: UUID) -> (time: TimeInterval, amplitude: Float)? {
        guard self.owner == owner, let recorder else { return nil }; recorder.updateMeters()
        return (recorder.currentTime, pow(10, recorder.averagePower(forChannel: 0) / 25))
    }
    func pause(owner: UUID) { guard self.owner == owner else { return }; recorder?.pause() }
    func resume(owner: UUID) throws { guard self.owner == owner, recorder?.record() == true else { throw CaptureError.unavailable } }
    func stop(owner: UUID) -> TimeInterval {
        guard self.owner == owner else { return 0 }
        let duration = recorder?.currentTime ?? 0
        recorder?.stop(); recorder = nil; delegate = nil; self.owner = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return duration
    }
    func togglePlayback(owner: UUID, url: URL, position: TimeInterval) throws -> (playing: Bool, time: TimeInterval, duration: TimeInterval) {
        guard self.owner == nil || self.owner == owner else { throw CaptureError.unavailable }
        self.owner = owner
        do {
            if player == nil {
                try AVAudioSession.sharedInstance().setCategory(.playback)
                try AVAudioSession.sharedInstance().setActive(true)
                player = try AVAudioPlayer(contentsOf: url)
                player?.currentTime = position
            }
            guard let player else { throw CaptureError.unavailable }
            if player.isPlaying { player.pause() } else { guard player.play() else { throw CaptureError.unavailable } }
            return (player.isPlaying, player.currentTime, player.duration)
        } catch {
            stopPlayback(owner: owner)
            throw error
        }
    }
    func playbackSnapshot(owner: UUID) -> (playing: Bool, time: TimeInterval, duration: TimeInterval)? {
        guard self.owner == owner, let player else { return nil }
        return (player.isPlaying, player.currentTime, player.duration)
    }
    func seekPlayback(owner: UUID, to time: TimeInterval) { guard self.owner == owner else { return }; player?.currentTime = time }
    func stopPlayback(owner: UUID) {
        guard self.owner == owner else { return }
        player?.stop(); player = nil; self.owner = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func selectInput(_ input: AVAudioSessionPortDescription, owner: UUID) throws { guard self.owner == owner else { return }; try AVAudioSession.sharedInstance().setPreferredInput(input) }
}
private final class RecordingDelegate: NSObject, AVAudioRecorderDelegate, @unchecked Sendable {
    let failure: @Sendable (String) -> Void
    init(failure: @escaping @Sendable (String) -> Void) { self.failure = failure }
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) { failure(L("Запись прервалась. Сохранённую часть можно открыть в дневнике.")) }
}
private enum CaptureError: LocalizedError {
    case unavailable
    var errorDescription: String? { L("Микрофон не удалось запустить. Проверь подключение наушников и попробуй ещё раз.") }
}

@MainActor @Observable final class AudioRecorder {
    var isRecording = false
    var isPaused = false
    var elapsed: TimeInterval = 0
    var levels = Array(repeating: CGFloat(0.02), count: 38)
    var inputName = L("Микрофон iPhone")
    var error: String?
    @ObservationIgnored private let engine = CaptureEngine.shared
    @ObservationIgnored private let owner = UUID()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var interruption: NSObjectProtocol?
    @ObservationIgnored private var metering = false
    @ObservationIgnored private var interrupted = false
    var inputs: [AVAudioSessionPortDescription] { AVAudioSession.sharedInstance().availableInputs ?? [] }

    init() {
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue { Task { @MainActor in self?.interrupted = true; self?.pause() } }
        }
    }
    isolated deinit { if let interruption { NotificationCenter.default.removeObserver(interruption) }; timer?.invalidate() }
    func start(url: URL) async -> Bool {
        interrupted = false
        guard await AVAudioApplication.requestRecordPermission() else { error = L("Разреши доступ к микрофону в настройках iPhone."); return false }
        guard !Task.isCancelled else { return false }
        do {
            inputName = try await engine.start(owner: owner, url: url) { [weak self] message in Task { @MainActor in self?.error = message; self?.pause() } }
            guard !Task.isCancelled else { _ = await engine.stop(owner: owner); try? FileManager.default.removeItem(at: url); return false }
            isRecording = true; isPaused = interrupted; elapsed = 0
            if interrupted { await engine.pause(owner: owner) }
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in Task { @MainActor in await self?.meter() } }
            return true
        } catch is CancellationError { return false }
        catch { self.error = error.localizedDescription; return false }
    }
    private func meter() async {
        guard isRecording, !isPaused, !metering else { return }
        metering = true; defer { metering = false }
        guard let snapshot = await engine.meter(owner: owner), isRecording else { return }
        elapsed = snapshot.time
        levels.removeFirst(); levels.append(min(1, max(0.015, CGFloat(snapshot.amplitude)*1.8)))
    }
    func pause() { guard isRecording else { return }; isPaused = true; Task { await engine.pause(owner: owner) } }
    func resume() { Task { do { try await engine.resume(owner: owner); isPaused = false } catch { self.error = error.localizedDescription } } }
    func stop() async -> TimeInterval {
        timer?.invalidate(); timer = nil; isRecording = false; isPaused = false
        return max(elapsed, await engine.stop(owner: owner))
    }
    func selectInput(_ input: AVAudioSessionPortDescription) { Task { do { try await engine.selectInput(input, owner: owner); inputName = input.egoName } catch { self.error = error.localizedDescription } } }
}


extension AVAudioSessionPortDescription {
    var egoName: String { portType == .builtInMic ? L("Микрофон iPhone") : portName }
}

@MainActor @Observable final class AudioPlayback {
    var playing = false
    var time: TimeInterval = 0
    var duration: TimeInterval = 0
    var error: String?
    var busy = false
    var scrubbing = false
    @ObservationIgnored private let owner = UUID()
    @ObservationIgnored private let engine = CaptureEngine.shared
    @ObservationIgnored private var polling = false
    func toggle(url: URL) {
        guard !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do {
                let snapshot = try await engine.togglePlayback(owner: owner, url: url, position: time)
                playing = snapshot.playing; time = snapshot.time; duration = snapshot.duration
            } catch { self.error = L("Не удалось воспроизвести аудиозапись. Попробуй ещё раз.") }
        }
    }
    func poll() async {
        guard !polling, !scrubbing, playing else { return }
        polling = true; defer { polling = false }
        guard let snapshot = await engine.playbackSnapshot(owner: owner), !scrubbing else { return }
        playing = snapshot.playing; time = snapshot.time; duration = snapshot.duration
        if !playing { time = 0 }
    }
    func seek() { let position = time; Task { await engine.seekPlayback(owner: owner, to: position) } }
    func stop() { playing = false; Task { await engine.stopPlayback(owner: owner) } }
}
