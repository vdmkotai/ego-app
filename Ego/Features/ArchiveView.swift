import SwiftUI

struct CalendarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: Date
    @State private var page: Date = Date()
    @State private var mode = 0
    @State private var chooseYear = false
    @State private var openedEntry: UUID?
    @State private var pendingDeletion: JournalEntry?
    private let calendar = Calendar.journal
    var body: some View {
        NavigationStack {
            List {
                VStack(alignment: .leading, spacing: 26) {
                    Picker(L("Вид календаря"), selection: $mode) { Text(L("Месяц")).tag(0); Text(L("Год")).tag(1) }.pickerStyle(.segmented)
                    HStack {
                        Button { chooseYear = true } label: { HStack { Text(page.formatted(mode == 0 ? .dateTime.month(.wide).year().locale(EgoLocale.current) : .dateTime.year())).font(.system(size: 29)).tracking(-0.8); Image(systemName: "chevron.down").font(.system(size: 12)) } }.buttonStyle(.plain).accessibilityLabel(L("Выбрать год"))
                        Spacer()
                        Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 35,height: 44) }.accessibilityLabel(L("Назад"))
                        Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 35,height: 44) }.accessibilityLabel(L("Вперёд"))
                    }
                    if mode == 0 {
                        MonthGrid(month: page, selected: selected, entries: state.store.entries, compact: false) { date in withAnimation(EgoStyle.spring) { selected = date } }
                        Divider().overlay(EgoStyle.line)
                        HStack { Text(selected.formatted(.dateTime.day().month(.wide).locale(EgoLocale.current))).font(.system(size: 22)); Spacer(); Button(L("Открыть день")) { dismiss() }.font(.system(size: 14)).foregroundStyle(EgoStyle.secondary) }
                    } else {
                        VStack(spacing: 30) {
                            ForEach(0..<6, id: \.self) { pair in
                                HStack(alignment: .top, spacing: 22) {
                                    ForEach(1...2, id: \.self) { column in
                                        let month = pair * 2 + column
                                        let date = calendar.date(from: DateComponents(year: calendar.component(.year, from: page), month: month, day: 1))!
                                        Button { withAnimation(EgoStyle.spring) { page = date; selected = date; mode = 0 } } label: {
                                            VStack(alignment: .leading, spacing: 12) {
                                                Text(date.formatted(.dateTime.month(.wide).locale(EgoLocale.current))).font(.system(size: 15)).foregroundStyle(.white)
                                                MonthGrid(month: date, selected: selected, entries: state.store.entries, compact: true) { _ in }.allowsHitTesting(false)
                                            }.frame(maxWidth: .infinity)
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }.buttonStyle(.plain).padding(.top, 20).padding(.bottom, 19).journalListRow()
                if mode == 0 {
                    let entries = state.store.entries(on: selected)
                    if entries.isEmpty { Text(L("Записей нет")).foregroundStyle(EgoStyle.secondary).journalListRow() }
                    ForEach(entries) { entry in
                        JournalEntryRow(entry: entry, open: { openedEntry = entry.id }, delete: { pendingDeletion = entry })
                    }
                }
            }.listStyle(.plain).scrollContentBackground(.hidden).contentMargins(.top, 0, for: .scrollContent)
                .accessibilityIdentifier("calendarEntries")
                .navigationDestination(item: $openedEntry) { EntryView(id: $0) }
                .confirmEntryDeletion($pendingDeletion)
                .egoScreen().navigationTitle(L("Календарь")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button(L("Сегодня")) { withAnimation(EgoStyle.spring) { page = Date(); selected = Date(); mode = 0 } } }; ToolbarItem(placement: .topBarTrailing) { Button(L("Готово")) { dismiss() } } }
                .sheet(isPresented: $chooseYear) { yearPicker }
        }.tint(.white).onAppear { page = selected }
    }
    private var yearPicker: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    let current = calendar.component(.year, from: Date())
                    let first = min(2000, state.store.entries.map { calendar.component(.year, from: $0.date) }.min() ?? current)
                    ForEach((first...current+1).reversed(), id: \.self) { year in
                        Button { page = calendar.date(from: DateComponents(year: year, month: calendar.component(.month, from: page), day: 1))!; mode = 1; chooseYear = false } label: {
                            HStack { Text(String(year)).font(.system(size: 26)); Spacer(); let count = state.store.entries.filter { calendar.component(.year, from: $0.date) == year }.count; if count > 0 { Text("\(count)").foregroundStyle(EgoStyle.secondary) } }
                        }.listRowBackground(Color.black).id(year)
                    }
                }.scrollContentBackground(.hidden).background(.black).onAppear { proxy.scrollTo(calendar.component(.year, from: page), anchor: .center) }
            }.navigationTitle(L("Выбери год")).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L("Готово")) { chooseYear = false } } }
        }.presentationDetents([.medium, .large]).preferredColorScheme(.dark).tint(.white)
    }
    private func shift(_ offset: Int) { if let next = calendar.date(byAdding: mode == 0 ? .month : .year, value: offset, to: page) { withAnimation(EgoStyle.spring) { page = next; if mode == 0 { selected = calendar.dateInterval(of: .month, for: next)!.start } } } }
}
struct MonthGrid: View {
    var month: Date
    var selected: Date
    var entries: [JournalEntry]
    var compact: Bool
    var pick: (Date) -> Void
    private let c = Calendar.journal
    var body: some View {
        let first = c.dateInterval(of: .month, for: month)!.start
        let offset = (c.component(.weekday, from: first) + 5) % 7
        let count = c.range(of: .day, in: .month, for: month)!.count
        VStack(spacing: compact ? 6 : 9) {
            HStack(spacing: compact ? 2 : 5) {
                ForEach(Array(EgoLocale.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.system(size: compact ? 8 : 11)).foregroundStyle(EgoStyle.tertiary).frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: compact ? 2 : 5) {
                    ForEach(0..<7, id: \.self) { column in
                        let index = row * 7 + column
                        if index >= offset && index < count + offset {
                            let date = c.date(byAdding: .day, value: index-offset, to: first)!
                            let has = entries.contains { c.isDate($0.date, inSameDayAs: date) }
                            let active = c.isDate(date, inSameDayAs: selected)
                            Button { pick(date) } label: {
                                VStack(spacing: compact ? 2 : 5) {
                                    Text("\(index-offset+1)").font(.system(size: compact ? 9 : 17, weight: has ? .medium : .regular)).foregroundStyle(active || has ? .white : EgoStyle.secondary)
                                    Circle().fill(has ? .white : .clear).frame(width: compact ? 2 : 3, height: compact ? 2 : 3)
                                }.frame(maxWidth: .infinity).frame(height: compact ? 17 : 43).background(active && !compact ? Color(white: 0.12) : .clear, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(active && !compact ? Color(white: 0.5) : .clear, lineWidth: 0.7))
                            }.buttonStyle(.plain).accessibilityLabel(date.egoFormatted(date: .complete, time: .omitted) + (has ? L(", есть записи") : ""))
                        } else { Color.clear.frame(maxWidth: .infinity).frame(height: compact ? 17 : 43) }
                    }
                }
            }
        }
    }
}
struct SearchView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var filter = 0
    private var results: [JournalEntry] {
        state.store.entries.filter { entry in
            guard query.nonEmpty != nil && entry.matches(query) else { return false }
            if filter == 1 { return entry.audioFile != nil }
            if filter == 2 { return entry.audioFile == nil }
            return true
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 12) { Image(systemName: "magnifyingglass").foregroundStyle(EgoStyle.secondary); TextField(L("Слова, мысли, темы"), text: $query).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("searchField"); if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(EgoStyle.secondary) }.accessibilityLabel(L("Очистить поиск")) } }.padding(15).background(EgoStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                    Picker(L("Тип записи"), selection: $filter) { Text(L("Все")).tag(0); Text(L("Голос")).tag(1); Text(L("Текст")).tag(2) }.pickerStyle(.segmented)
                    if query.isEmpty { VStack(alignment: .leading, spacing: 10) { Text(L("Мысль найдётся.")).font(.system(size: 27)); Text(L("Поиск по всем записям, темам и контексту.")).foregroundStyle(EgoStyle.secondary) }.padding(.top, 40) }
                    else if results.isEmpty { Text(L("Ничего не найдено")).foregroundStyle(EgoStyle.secondary).padding(.top, 40) }
                    else { Text(L("Найдено: %d", results.count)).font(.system(size: 13)).foregroundStyle(EgoStyle.secondary); LazyVStack(alignment: .leading, spacing: 16) { ForEach(results) { entry in VStack(alignment: .leading, spacing: 8) { Text(entry.date.egoFormatted(date: .long, time: .omitted)).font(.system(size: 12)).foregroundStyle(EgoStyle.secondary); NavigationLink { EntryView(id: entry.id) } label: { VStack(alignment: .leading, spacing: 10) { EntryCard(entry: entry); if let excerpt = [entry.text, entry.context, entry.reflection?.observation ?? ""].joined(separator: " ").excerpt(matching: query) { Text(excerpt).font(.system(size: 15)).foregroundStyle(EgoStyle.secondary).multilineTextAlignment(.leading).padding(.horizontal, 4) } } }.buttonStyle(.plain) } } } }
                }.padding(20)
            }.egoScreen().navigationTitle(L("Поиск")).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L("Готово")) { dismiss() } } }
        }.tint(.white)
    }
}
