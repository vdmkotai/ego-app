import SwiftUI
import AVFoundation

struct CaptureView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var recorder = AudioRecorder()
    @State private var draft: JournalEntry?
    @State private var discard = false
    @State private var starting = false
    @State private var startTask: Task<Void, Never>?
    @State private var replacement: UUID?
    @State private var openingID: UUID?
    @State private var finishing = false
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack { Spacer(); Button { if starting { startTask?.cancel(); if let openingID { _ = state.store.delete(openingID) }; dismiss() } else if draft != nil { discard = true } else { dismiss() } } label: { Image(systemName: "xmark").font(.system(size: 18)).frame(width: 44, height: 44) }.accessibilityLabel(L("Закрыть запись")).disabled(finishing) }.padding(.horizontal, 14).padding(.top, 8)
                Spacer(minLength: 20)
                VStack(spacing: 48) {
                    if recorder.isRecording || draft != nil {
                        WaveformView(levels: recorder.levels, paused: recorder.isPaused).frame(height: 92)
                        Text(JournalEntry.time(recorder.elapsed)).font(.system(size: 30, weight: .regular)).monospacedDigit().contentTransition(.numericText()).accessibilityLabel(L("Длительность %@", JournalEntry.time(recorder.elapsed))).accessibilityIdentifier("recordingTimer").accessibilityValue(String(Int(recorder.elapsed)))
                        Menu {
                            ForEach(recorder.inputs, id: \.uid) { input in Button(input.egoName) { recorder.selectInput(input) } }
                        } label: { HStack(spacing: 6) { Text(recorder.isPaused ? L("На паузе") : recorder.inputName); Image(systemName: "chevron.down").font(.system(size: 10)) }.font(.system(size: 13)).foregroundStyle(EgoStyle.secondary) }
                    } else {
                        Text(L("Что у тебя на уме?")).font(.system(size: 24, weight: .regular)).tracking(-0.4).multilineTextAlignment(.center)
                        Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now()+0.35) { state.compose = true } } label: { Label(L("Лучше напишу"), systemImage: "pencil") }.font(.system(size: 15)).foregroundStyle(EgoStyle.secondary).disabled(starting || finishing)
                    }
                }.frame(maxWidth: .infinity)
                Spacer(minLength: 20)
                ZStack {
                    if recorder.isRecording || draft != nil {
                        HStack { CircleControl(symbol: recorder.isPaused ? "play.fill" : "pause.fill", label: recorder.isPaused ? L("Продолжить") : L("Пауза"), size: 56) { if recorder.isPaused { recorder.resume() } else { recorder.pause() } }; Spacer() }.frame(width: 250)
                        CircleControl(symbol: "checkmark", label: L("Сохранить запись"), filled: true, size: 74, action: finish)
                    } else {
                        Button { startTask = Task { await begin() } } label: { Text(starting ? "…" : L("Начать")).font(.system(size: 17, weight: .medium)).foregroundStyle(.black).frame(width: 74, height: 74).background(.white, in: Circle()) }.buttonStyle(PressStyle()).disabled(starting).accessibilityLabel(L("Начать запись"))
                    }
                }.disabled(finishing).padding(.bottom, max(42, geometry.size.height * 0.065))
            }
        }.egoScreen().interactiveDismissDisabled(draft != nil || starting)
            .onAppear { replacement = state.replaceID; state.replaceID = nil }
            .onDisappear { startTask?.cancel(); if let openingID { _ = state.store.delete(openingID) }; if !finishing, var entry = draft { draft = nil; Task { entry.duration = await recorder.stop(); entry.status = .pending; _ = state.store.save(entry) } } }
            .confirmationDialog(L("Сохранить эту запись?"), isPresented: $discard, titleVisibility: .visible) {
                Button(L("Сохранить"), action: finish)
                Button(L("Удалить запись")) { guard !finishing, let entry = draft else { return }; finishing = true; Task { _ = await recorder.stop(); _ = state.store.delete(entry.id); draft = nil; replacement = nil; dismiss() } }
                Button(L("Продолжить запись"), role: .cancel) {}
            }
            .alert(L("Микрофон"), isPresented: Binding(get: { recorder.error != nil }, set: { if !$0 { recorder.error = nil } })) {
                Button(L("Понятно"), role: .cancel) {}
                Button(L("Настройки iPhone")) { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            } message: { Text(recorder.error ?? "") }
    }
    private func begin() async {
        guard !starting else { return }; starting = true; defer { starting = false }
        var entry = JournalEntry(); entry.audioFile = entry.id.uuidString + ".m4a"; entry.status = .recording
        guard state.store.save(entry) else { return }; openingID = entry.id
        defer { openingID = nil }
        if await recorder.start(url: EgoPaths.audio.appendingPathComponent(entry.audioFile!)) { draft = entry }
        else { _ = state.store.delete(entry.id) }
    }
    private func finish() { guard !finishing else { return }; finishing = true; Task { await saveRecording(); finishing = false } }
    private func saveRecording() async {
        guard var entry = draft else { dismiss(); return }
        entry.duration = await recorder.stop(); entry.status = .pending
        guard state.store.save(entry) else { return }
        // The original survives until the replacement audio has been durably saved.
        if let original = replacement { _ = state.store.delete(original); replacement = nil }
        state.selectedDate = entry.date; draft = nil; dismiss()
        Task { await state.process(entry.id) }
    }
}
struct WaveformView: View {
    var levels: [CGFloat]
    var paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 6) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule().fill(.white.opacity(paused ? 0.45 : 1)).frame(width: max(3, (geometry.size.width-37*6)/38), height: max(3, levels[index]*82)).animation(reduceMotion ? nil : .interpolatingSpring(stiffness: 210, damping: 22), value: levels[index])
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(.horizontal, 22).accessibilityLabel(paused ? L("Запись на паузе") : L("Звуковая волна")).accessibilityHidden(true)
    }
}
struct TextComposeView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack { ZStack(alignment: .topLeading) {
            if text.isEmpty { Text(L("Что у тебя на уме?")).foregroundStyle(EgoStyle.tertiary).padding(.top, 12).padding(.leading, 5).allowsHitTesting(false) }
            TextEditor(text: $text).scrollContentBackground(.hidden).focused($focused).accessibilityLabel(L("Текст записи"))
        }.font(.system(size: 22)).lineSpacing(7).padding(20).egoScreen().navigationTitle(L("Новая запись")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Отмена")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(L("Готово")) { state.createText(text); if state.store.error == nil { dismiss() } }.disabled(text.nonEmpty == nil) } }
        }.tint(.white).onAppear { focused = true }
    }
}
