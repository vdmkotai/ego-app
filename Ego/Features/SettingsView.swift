import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @AppStorage("faceID") private var faceID = false
    @AppStorage("reminder") private var reminder = false
    @AppStorage("reminderHour") private var reminderHour = 21
    @AppStorage("reminderMinute") private var reminderMinute = 0
    @AppStorage("entryReady") private var entryReady = false
    @AppStorage("reflections") private var reflections = true
    @AppStorage("aboutPurpose") private var purpose = ""
    @State private var exporting = false
    @State private var share: ShareItem?
    @State private var removeModel: LocalModel?
    @State private var notificationBusy = false
    var body: some View {
        @Bindable var state = state
        NavigationStack {
            Form {
                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: {
                        HStack { Text(L("Язык интерфейса")); Spacer(); Text(EgoLocale.language == "ru" ? "Русский" : "English").foregroundStyle(EgoStyle.secondary); Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(EgoStyle.secondary) }
                    }.accessibilityIdentifier("interfaceLanguage")
                } footer: { Text(L("Системный язык или отдельный язык для Ego — в настройках iPhone. Язык распознавания выбирается ниже.")) }
                Section {
                    Toggle(isOn: Binding(get: { faceID }, set: { value in Task { _ = await state.setLock(value) } })) { Label("Face ID", systemImage: "faceid") }.tint(Color(white: 0.36))
                    Toggle(L("Напоминать каждый день"), isOn: Binding(get: { reminder }, set: { value in Task { await configureReminder(value) } })).tint(Color(white: 0.38)).disabled(notificationBusy)
                    if reminder { DatePicker(L("Время"), selection: Binding(get: { Calendar.journal.date(from: DateComponents(hour: reminderHour, minute: reminderMinute)) ?? Date() }, set: { date in reminderHour = Calendar.journal.component(.hour, from: date); reminderMinute = Calendar.journal.component(.minute, from: date); Task { await configureReminder(true) } }), displayedComponents: .hourAndMinute).colorMultiply(.white) }
                    Toggle(L("Запись готова"), isOn: Binding(get: { entryReady }, set: { value in Task { if !value { entryReady = false } else { entryReady = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false } } })).tint(Color(white: 0.38))
                } header: { Text(L("Твой дневник")) } footer: { Text(L("В уведомлениях нет текста записей.")) }
                Section {
                    Picker(L("Модель"), selection: Binding(get: { state.selectedModel }, set: { state.selectedModel = $0 })) { Text("Parakeet v3").tag(LocalModel.parakeet); Text("Whisper Turbo").tag(LocalModel.whisper) }
                    Picker(L("Язык"), selection: Binding(get: { state.language }, set: { state.language = $0 })) { Text(L("Русский")).tag("ru"); Text(L("Определять автоматически")).tag("auto"); Text("English").tag("en") }
                    ForEach([LocalModel.parakeet, .whisper]) { model in modelRow(model) }
                } header: { Text(L("Распознавание речи")) } footer: { Text(L("Скачай одну или обе модели. После загрузки интернет не нужен.")) }
                Section {
                    Toggle(L("Наблюдения к записям"), isOn: $reflections).tint(Color(white: 0.38))
                    modelRow(.qwen)
                } header: { Text(L("Наблюдения и итоги недели")) } footer: { Text(L("Новые наблюдения — на языке интерфейса. Всё обрабатывается на iPhone.")) }
                Section {
                    TextField(L("Для чего ты ведёшь дневник"), text: $purpose, axis: .vertical).lineLimit(2...5)
                } header: { Text(L("О тебе")) } footer: { Text(L("Этот контекст поможет точнее понимать записи.")) }
                Section {
                    NavigationLink { ShortcutHelpView() } label: { Label(L("Кнопка действия"), systemImage: "button.programmable") }
                    NavigationLink { WidgetHelpView() } label: { Label(L("Виджеты"), systemImage: "square.grid.2x2") }
                } header: { Text(L("Быстрый доступ")) }
                Section {
                    Button("Markdown") { export(.markdown) }
                    Button("JSON") { export(.json) }
                    Button(L("Весь дневник + аудио")) { export(.archive) }
                    if exporting { HStack { ProgressView(); Text(L("Подготавливаю архив…")) }.font(.footnote) }
                } header: { Text(L("Экспорт")) }.disabled(exporting)
                Section { NavigationLink(L("Модели и лицензии")) { LicensesView() }; HStack { Text("Ego"); Spacer(); Text("1.0").foregroundStyle(EgoStyle.secondary) } }
            }.scrollContentBackground(.hidden).background(.black).tint(.white)
                .navigationTitle(L("Настройки")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L("Готово")) { dismiss() } } }
                .sheet(item: $share) { ShareSheet(url: $0.url) }
                .alert(L("Модели"), isPresented: Binding(get: { state.models.error != nil }, set: { if !$0 { state.models.error = nil } })) { Button(L("Понятно"), role: .cancel) {} } message: { Text(state.models.error ?? "") }
                .confirmationDialog(L("Удалить модель с iPhone?"), isPresented: Binding(get: { removeModel != nil }, set: { if !$0 { removeModel = nil } }), titleVisibility: .visible) { if let model = removeModel { Button(L("Удалить %@", model.title)) { state.models.remove(model); removeModel = nil } }; Button(L("Отмена"), role: .cancel) { removeModel = nil } } message: { Text(L("Записи и расшифровки сохранятся.")) }
        }.preferredColorScheme(.dark).tint(.white)
    }
    @ViewBuilder private func modelRow(_ model: LocalModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) { Text(model.title).font(.system(size: 16)); Text(state.models.size(model)).font(.system(size: 12)).foregroundStyle(EgoStyle.secondary) }
                Spacer()
                if state.models.downloading == model { Button { state.models.cancel() } label: { Image(systemName: "xmark").frame(width: 32,height: 32) }.accessibilityLabel(L("Отменить загрузку")) }
                else if state.models.installed.contains(model) { Menu { Button(L("Удалить модель")) { removeModel = model }.disabled(state.busy || state.models.downloading != nil) } label: { Image(systemName: "checkmark.circle").font(.system(size: 22)).frame(width: 40,height: 40) }.accessibilityLabel(L("%@ скачана", model.title)) }
                else { Button { state.models.download(model) } label: { Image(systemName: "arrow.down.circle").font(.system(size: 23)).frame(width: 40,height: 40) }.buttonStyle(.borderless).disabled(state.models.downloading != nil).accessibilityLabel(L("Скачать %@", model.title)) }
            }
            if state.models.downloading == model { ProgressView(value: state.models.progress).tint(.white); Text(L("Загрузка · %d%%", Int(state.models.progress*100))).font(.system(size: 12)).foregroundStyle(EgoStyle.secondary) }
        }.padding(.vertical, 6)
    }
    private func export(_ format: ExportService.Format) {
        guard !exporting else { return }; exporting = true
        let entries = state.store.entries
        Task {
            defer { exporting = false }
            do { share = ShareItem(url: try await Task.detached(priority: .userInitiated) { try ExportService.export(entries, format: format) }.value) }
            catch { state.message = error.localizedDescription }
        }
    }
    private func configureReminder(_ enabled: Bool) async {
        notificationBusy = true; defer { notificationBusy = false }
        guard enabled else { reminder = false; await ReminderSchedule.refresh(); return }
        do {
            guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) else { reminder = false; await ReminderSchedule.refresh(); state.message = L("Разреши уведомления для Ego в настройках iPhone."); return }
            reminder = true
            await ReminderSchedule.refresh()
        } catch { state.message = error.localizedDescription; reminder = false; await ReminderSchedule.refresh() }
    }
}
struct ShortcutHelpView: View {
    var body: some View { VStack(alignment: .leading, spacing: 24) { Image(systemName: "button.programmable").font(.system(size: 42)).padding(.top, 30); Text(L("Одна кнопка.\nНовая мысль.")).font(.system(size: 34)); Text(L("Открой настройки iPhone → Кнопка действия → Быстрая команда. Выбери «Новая запись в Ego».")).font(.system(size: 18)).foregroundStyle(EgoStyle.secondary).lineSpacing(6); Spacer() }.padding(24).egoScreen().navigationTitle(L("Кнопка действия")).navigationBarTitleDisplayMode(.inline) }
}
struct WidgetHelpView: View {
    var body: some View { VStack(alignment: .leading, spacing: 24) { Image(systemName: "square.grid.2x2").font(.system(size: 42)).padding(.top, 30); Text(L("Мысль рядом.")).font(.system(size: 34)); Text(L("Удерживай свободное место на экране «Домой», нажми «Изменить» → «Добавить виджет» и выбери Ego. На экране блокировки виджет можно добавить через его настройку.")).font(.system(size: 18)).foregroundStyle(EgoStyle.secondary).lineSpacing(6); Spacer() }.padding(24).egoScreen().navigationTitle(L("Виджеты")).navigationBarTitleDisplayMode(.inline) }
}
struct LicensesView: View {
    var body: some View { List { Section(L("Распознавание")) { Link("NVIDIA Parakeet v3 · CC BY 4.0", destination: URL(string: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3")!); Link("FluidAudio · Apache 2.0", destination: URL(string: "https://github.com/FluidInference/FluidAudio")!); Link("OpenAI Whisper · MIT", destination: URL(string: "https://github.com/openai/whisper")!); Link("WhisperKit · MIT", destination: URL(string: "https://github.com/argmaxinc/argmax-oss-swift")!) }; Section(L("Наблюдения")) { Link("Qwen 3.5 · Apache 2.0", destination: URL(string: "https://huggingface.co/mlx-community/Qwen3.5-2B-4bit")!); Link("MLX Swift · MIT", destination: URL(string: "https://github.com/ml-explore/mlx-swift-lm")!) }; Section { Text(L("Parakeet создан NVIDIA; Core ML-конверсия и варианты квантования предоставлены FluidInference. Whisper создан OpenAI; Core ML-конверсия предоставлена Argmax. Qwen создан Qwen Team; 4-битная конверсия предоставлена MLX Community.")).font(.footnote).foregroundStyle(EgoStyle.secondary) } }.scrollContentBackground(.hidden).egoScreen().navigationTitle(L("Модели и лицензии")) }
}

/// Rebuild scheduled copy after the native app language changes and the app restarts.
@MainActor enum ReminderSchedule {
    private static var tail: Task<Void, Never>?
    private static var revision = 0
    static func refresh() async {
        revision += 1
        let current = revision
        let previous = tail
        let task = Task { await previous?.value; await applyCurrentPreference() }
        tail = task
        await task.value
        if revision == current { tail = nil }
    }
    private static func applyCurrentPreference() async {
        let defaults = UserDefaults.standard
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        center.removePendingNotificationRequests(withIdentifiers: ["ego.daily"])
        guard defaults.bool(forKey: "reminder"), settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent(); content.title = "Ego"; content.body = L("Есть мысль, которую хочется сохранить?")
        let hour = defaults.object(forKey: "reminderHour") as? Int ?? 21
        let minute = defaults.integer(forKey: "reminderMinute")
        try? await center.add(UNNotificationRequest(identifier: "ego.daily", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)))
    }
}
