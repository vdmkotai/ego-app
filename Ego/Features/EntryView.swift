import SwiftUI
import AVFoundation
import Combine

struct EntryView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    var id: UUID
    @State private var pendingDeletion: JournalEntry?
    @State private var rerecord = false
    @State private var edit = false
    @State private var editContext = false
    @State private var exporting = false
    @State private var share: ShareItem?
    @State private var copied = false
    private var entry: JournalEntry? { state.store.entry(id) }
    var body: some View {
        ScrollView {
            if let entry {
                VStack(alignment: .leading, spacing: 28) {
                    if !entry.text.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("«\(entry.headline)»").font(.system(size: 23)).tracking(-0.5).lineSpacing(3)
                            if let reflection = entry.reflection {
                                Text(reflection.observation ?? L("Здесь нечего добавлять. Твои слова говорят сами за себя.")).font(.system(size: 16)).foregroundStyle(EgoStyle.secondary).lineSpacing(4)
                                TagCloud(tags: reflection.themes)
                            } else if entry.status == .reflecting { HStack { ProgressView(); Text(L("Читаю запись…")).foregroundStyle(EgoStyle.secondary) }.font(.system(size: 14)) }
                        }.egoCard()
                        Button { editContext = true } label: { Label(entry.context.isEmpty ? L("Добавить контекст") : L("Изменить контекст"), systemImage: "arrow.uturn.backward").font(.system(size: 14)).foregroundStyle(EgoStyle.secondary) }.buttonStyle(.plain)
                        if !entry.context.isEmpty { Text(entry.context).font(.system(size: 16)).foregroundStyle(EgoStyle.secondary).lineSpacing(4) }
                    }
                    if let audio = entry.audioFile { AudioPlayerView(url: EgoPaths.audio.appendingPathComponent(audio), duration: entry.duration) }
                    if !entry.text.isEmpty { Text(entry.text).font(.system(size: 19)).lineSpacing(8).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    if [.pending, .pendingReflection, .failed, .transcribing].contains(entry.status) {
                        VStack(alignment: .leading, spacing: 14) {
                            if state.processingID == id {
                                HStack { ProgressView(); Text(state.preparingModel ? L("Подготавливаю модель…") : L("Обрабатываю на iPhone…")) }.font(.system(size: 14))
                                if state.preparingModel && state.processingModel == .whisper { Text(L("Первый запуск Whisper может занять около полутора минут. Аудиозапись уже сохранена.")).font(.system(size: 13)).foregroundStyle(EgoStyle.secondary) }
                            }
                            else { Text(entry.failureDescription ?? L("Аудиозапись сохранена.")).font(.system(size: 15)).foregroundStyle(EgoStyle.secondary); Button(entry.text.isEmpty ? L("Расшифровать") : L("Повторить обработку")) { Task { await state.process(id, transcribe: entry.text.isEmpty) } }.disabled(state.busy) }
                        }.egoCard()
                    }
                    FlowLayout(spacing: 8) {
                        if entry.audioFile != nil { action(L("Перезаписать"), "mic") { rerecord = true } }
                        action(L("Удалить"), "trash") { pendingDeletion = entry }
                        action(copied ? L("Скопировано") : L("Копировать"), copied ? "checkmark" : "doc.on.doc") { UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: entry.text]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)]); copied = true }
                        if entry.audioFile != nil {
                            Menu { ForEach([LocalModel.parakeet, .whisper]) { model in Button(model.title + (state.models.installed.contains(model) ? "" : L(" · не скачана"))) { state.selectedModel = model; Task { await state.process(id) } }.disabled(!state.models.installed.contains(model) || state.busy) } } label: { chip(L("Распознать заново"), "waveform") }
                        }
                        action(L("Изменить текст"), "pencil") { edit = true }
                        Menu { Button("Markdown") { export(.markdown, entry) }; Button("JSON") { export(.json, entry) }; Button(L("Всё + аудио")) { export(.archive, entry) } } label: { chip(exporting ? L("Подготавливаю…") : L("Экспорт"), "square.and.arrow.up") }.disabled(exporting)
                        if entry.reflection == nil && !entry.text.isEmpty && entry.status != .reflecting {
                            action(L("Наблюдение"), "sparkle") { Task { await state.process(id, transcribe: false) } }.disabled(!state.models.installed.contains(.qwen) || state.busy)
                        }
                    }
                    if let model = entry.model { Text(model).font(.system(size: 11)).foregroundStyle(EgoStyle.tertiary).padding(.top, 4) }
                }.padding(20).padding(.top, 12).padding(.bottom, 30)
            }
        }.egoScreen().navigationTitle(entry?.date.formatted(.dateTime.day().month(.wide).year().locale(EgoLocale.current)) ?? L("Запись")).navigationBarTitleDisplayMode(.inline)
            .confirmEntryDeletion($pendingDeletion) { _ in dismiss() }
            .confirmationDialog(L("Перезаписать?"), isPresented: $rerecord, titleVisibility: .visible) { Button(L("Новая запись")) { state.replaceID = id; state.capture = true; dismiss() }; Button(L("Отмена"), role: .cancel) {} } message: { Text(L("Текущая запись останется, пока ты не сохранишь новую.")) }
            .sheet(isPresented: $edit) { EntryEditor(id: id, contextOnly: false).environment(state) }
            .sheet(isPresented: $editContext) { EntryEditor(id: id, contextOnly: true).environment(state) }
            .sheet(item: $share, onDismiss: { share = nil }) { ShareSheet(url: $0.url) }
    }
    private func chip(_ text: String, _ icon: String) -> some View { Label(text, systemImage: icon).font(.system(size: 13)).foregroundStyle(EgoStyle.secondary).padding(.horizontal, 13).frame(height: 36).background(EgoStyle.surface, in: Capsule()) }
    private func action(_ text: String, _ icon: String, run: @escaping () -> Void) -> some View { Button(action: run) { chip(text, icon) }.buttonStyle(PressStyle()) }
    private func export(_ format: ExportService.Format, _ entry: JournalEntry) {
        guard !exporting else { return }; exporting = true
        Task {
            defer { exporting = false }
            do { share = ShareItem(url: try await Task.detached(priority: .userInitiated) { try ExportService.export([entry], format: format) }.value) }
            catch { state.message = error.localizedDescription }
        }
    }
}
struct EntryEditor: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    var id: UUID
    var contextOnly: Bool
    @State private var text = ""
    var body: some View {
        NavigationStack { TextEditor(text: $text).font(.system(size: 20)).lineSpacing(6).scrollContentBackground(.hidden).padding(16).egoScreen().navigationTitle(contextOnly ? L("Контекст") : L("Текст записи")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Отмена")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(L("Сохранить")) { guard var entry = state.store.entry(id) else { return }; if contextOnly { entry.context = text } else { entry.text = text }; entry.reflection = nil; entry.status = .ready; if state.store.save(entry) { dismiss(); Task { await state.process(id, transcribe: false) } } }.disabled(state.busy || (!contextOnly && text.nonEmpty == nil)) } }
        }.tint(.white).onAppear { if let entry = state.store.entry(id) { text = contextOnly ? entry.context : entry.text } }
    }
}
struct ShareItem: Identifiable { let id = UUID(); var url: URL }
struct ShareSheet: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
struct AudioPlayerView: View {
    var url: URL
    var duration: TimeInterval
    @State private var playback = AudioPlayback()
    private let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()
    var body: some View {
        @Bindable var playback = playback
        HStack(spacing: 15) {
            Button { playback.toggle(url: url) } label: { Image(systemName: playback.playing ? "pause.fill" : "play.fill").font(.system(size: 19)).frame(width: 28,height: 40) }.accessibilityLabel(playback.playing ? L("Пауза воспроизведения") : L("Воспроизвести")).disabled(playback.busy)
            Slider(value: $playback.time, in: 0...max(1, playback.duration > 0 ? playback.duration : duration), onEditingChanged: { changing in playback.scrubbing = changing; if !changing { playback.seek() } }).tint(.white).accessibilityLabel(L("Позиция воспроизведения"))
            Text(JournalEntry.time(playback.playing || playback.time > 0 ? playback.time : duration)).font(.system(size: 12)).monospacedDigit().foregroundStyle(EgoStyle.secondary)
        }.egoCard().onReceive(timer) { _ in Task { await playback.poll() } }.onDisappear { playback.stop() }
            .alert(L("Аудиозапись"), isPresented: Binding(get: { playback.error != nil }, set: { if !$0 { playback.error = nil } })) { Button(L("Понятно"), role: .cancel) {} } message: { Text(playback.error ?? "") }
    }
}

private struct EntryDeletionConfirmation: ViewModifier {
    @Environment(AppState.self) private var state
    @Binding var entry: JournalEntry?
    var onDeleted: (UUID) -> Void
    func body(content: Content) -> some View {
        content.alert(L("Удалить запись?"), isPresented: Binding(get: { entry != nil }, set: { if !$0 { entry = nil } }), presenting: entry) { candidate in
            Button(candidate.audioFile == nil ? L("Удалить запись") : L("Удалить запись и аудио")) {
                if state.store.delete(candidate.id) { onDeleted(candidate.id) }
            }
            Button(L("Отмена"), role: .cancel) {}
        } message: { _ in Text(L("Это действие нельзя отменить.")) }
    }
}

extension View {
    func confirmEntryDeletion(_ entry: Binding<JournalEntry?>, onDeleted: @escaping (UUID) -> Void = { _ in }) -> some View {
        modifier(EntryDeletionConfirmation(entry: entry, onDeleted: onDeleted))
    }
}
