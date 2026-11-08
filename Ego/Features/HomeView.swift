import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var state
    @State private var calendar = false
    @State private var search = false
    @State private var openedEntry: UUID?
    @State private var pendingDeletion: JournalEntry?
    var body: some View {
        @Bindable var state = state
        NavigationStack {
            List {
                VStack(alignment: .leading, spacing: 16) {
                    Button { calendar = true } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(state.selectedDate.formatted(.dateTime.day().month(.wide).year().locale(EgoLocale.current))).font(.system(size: 32, weight: .regular)).tracking(-1.1).minimumScaleFactor(0.7).lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 12)).foregroundStyle(EgoStyle.tertiary)
                        }.foregroundStyle(.white)
                    }.buttonStyle(.plain).padding(.top, 4).accessibilityLabel(L("Открыть календарь"))
                    WeekStrip(selected: $state.selectedDate, entries: state.store.entries)
                }.padding(.bottom, 9).journalListRow()
                let entries = state.store.entries(on: state.selectedDate)
                if entries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(Calendar.journal.isDateInToday(state.selectedDate) ? L("Что у тебя на уме?") : L("В этот день пока тихо.")).font(.system(size: 23))
                        Text(Calendar.journal.isDateInToday(state.selectedDate) ? L("Одна мысль. Или целый день.") : L("Выбери другую дату в календаре.")).font(.system(size: 16)).foregroundStyle(EgoStyle.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 32).journalListRow()
                } else {
                    ForEach(entries) { entry in
                        JournalEntryRow(entry: entry, open: { openedEntry = entry.id }, delete: { pendingDeletion = entry })
                    }
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollIndicators(.hidden).egoScreen()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { HStack(spacing: 17) {
                    Button { search = true } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel(L("Поиск"))
                    Button { calendar = true } label: { Image(systemName: "calendar") }.accessibilityLabel(L("Календарь"))
                }.padding(.horizontal, 12).foregroundStyle(EgoStyle.secondary) }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink { ReviewView() } label: { Image(systemName: "square.stack") }.accessibilityLabel(L("Итоги недели"))
                    Button { state.settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel(L("Настройки"))
                }
            }
            .safeAreaInset(edge: .bottom, alignment: .trailing) {
                CircleControl(symbol: "mic", label: L("Запись"), filled: true, size: 64) { state.replaceID = nil; state.capture = true }.padding(.trailing, 22).padding(.bottom, 10)
            }
            .navigationDestination(item: $openedEntry) { EntryView(id: $0) }
            .confirmEntryDeletion($pendingDeletion)
            .sheet(isPresented: $calendar) { CalendarView(selected: $state.selectedDate).environment(state) }
            .sheet(isPresented: $search) { SearchView().environment(state) }
            .sheet(isPresented: $state.settings) { SettingsView().environment(state) }
            .fullScreenCover(isPresented: $state.capture) { CaptureView().environment(state) }
            .sheet(isPresented: $state.compose) { TextComposeView().environment(state) }
        }.tint(.white)
    }
}
struct WeekStrip: View {
    @Binding var selected: Date
    var entries: [JournalEntry]
    var body: some View {
        HStack(spacing: 7) {
            ForEach(Calendar.journal.daysOfWeek(containing: selected), id: \.self) { day in
                let active = Calendar.journal.isDate(day, inSameDayAs: selected)
                let hasEntry = entries.contains { Calendar.journal.isDate($0.date, inSameDayAs: day) }
                Button { withAnimation(EgoStyle.spring) { selected = day } } label: {
                    VStack(spacing: 6) {
                        Text(day.formatted(.dateTime.weekday(.narrow).locale(EgoLocale.current))).font(.system(size: 11)).foregroundStyle(EgoStyle.tertiary)
                        Text(day.formatted(.dateTime.day())).font(.system(size: 16, weight: active ? .medium : .regular)).foregroundStyle(active ? .white : EgoStyle.secondary)
                        Circle().fill(hasEntry ? (active ? .white : EgoStyle.secondary) : .clear).frame(width: 4, height: 4)
                    }.padding(.vertical, 11).frame(maxWidth: .infinity).frame(minHeight: 74).overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(active ? Color(white: 0.34) : EgoStyle.line.opacity(0.5), lineWidth: active ? 1 : 0.5))
                }.buttonStyle(.plain).accessibilityLabel(day.egoFormatted(date: .complete, time: .omitted)).accessibilityAddTraits(active ? .isSelected : [])
            }
        }.padding(.vertical, 4)
    }
}
struct EntryCard: View {
    @Environment(AppState.self) private var state
    var entry: JournalEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 5) {
                Text(entry.date.formatted(.dateTime.hour().minute().locale(EgoLocale.current))); Text("·"); Text(entry.durationLabel)
                Spacer()
                if [.pending, .recording].contains(entry.status) { Image(systemName: "waveform") }
                if [.transcribing, .reflecting].contains(entry.status) { ProgressView().scaleEffect(0.65) }
            }.font(.system(size: 13)).foregroundStyle(EgoStyle.tertiary)
            Text(entry.text.isEmpty ? L("Аудиозапись") : "«\(entry.headline)»").font(.system(size: 20, weight: .regular)).tracking(-0.4).foregroundStyle(.white).lineLimit(4).multilineTextAlignment(.leading)
            if let reflection = entry.reflection, !reflection.themes.isEmpty { TagCloud(tags: reflection.themes) }
            if entry.status == .pending { Text(L("Готова к расшифровке")).font(.system(size: 13)).foregroundStyle(EgoStyle.secondary) }
            if entry.status == .failed { Text(L("Запись сохранена · повторить обработку")).font(.system(size: 13)).foregroundStyle(EgoStyle.secondary) }
            if entry.status == .transcribing { Text(state.processingID == entry.id && state.preparingModel ? L("Подготавливаю модель…") : L("Расшифровываю…")).font(.system(size: 13)).foregroundStyle(EgoStyle.secondary) }
            if entry.status == .reflecting { Text(L("Читаю запись…")).font(.system(size: 13)).foregroundStyle(EgoStyle.secondary) }
        }.egoCard()
    }
}

/// List supplies the native swipe gesture, reveal animation, and accessibility actions.
struct JournalEntryRow: View {
    var entry: JournalEntry
    var open: () -> Void
    var delete: () -> Void
    var body: some View {
        Button(action: open) { EntryCard(entry: entry) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("entryRow-" + entry.id.uuidString)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                // Confirmation owns deletion; no optimistic removal of the row.
                Button(action: delete) { Label(L("Удалить"), systemImage: "trash") }
                    .tint(Color(white: 0.25))
            }
            .journalListRow(top: 7, bottom: 7)
    }
}

extension View {
    func journalListRow(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: EgoStyle.inset, bottom: bottom, trailing: EgoStyle.inset))
            .listRowSeparator(.hidden).listRowBackground(Color.black)
    }
}
