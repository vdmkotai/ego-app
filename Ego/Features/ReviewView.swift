import SwiftUI

struct ReviewView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var week = Date()
    private var interval: DateInterval { Calendar.journal.dateInterval(of: .weekOfYear, for: week)! }
    private var entries: [JournalEntry] { state.store.entries(in: interval) }
    private var review: WeekReview? { state.store.reviews.first { $0.id == interval.start } }
    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    WeekStrip(selected: $week, entries: state.store.entries)
                        .accessibilityAction(named: L("Предыдущая неделя")) { move(-1) }
                        .accessibilityAction(named: L("Следующая неделя")) { move(1) }
                    if let review {
                        Text(review.text).font(.system(size: 21)).lineSpacing(7).textSelection(.enabled)
                        SectionCaption(title: L("Записи этой недели"))
                        ForEach(entries) { entry in NavigationLink { EntryView(id: entry.id) } label: { EntryCard(entry: entry) }.buttonStyle(.plain) }
                        Button(L("Обновить итог")) { Task { await state.review(week: week) } }.foregroundStyle(EgoStyle.secondary).disabled(state.busy)
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(entries.isEmpty ? L("Неделя ещё не рассказана.") : L("Твоя неделя в записях.")).font(.system(size: 22)).tracking(-0.4)
                            Text(entries.isEmpty ? L("Здесь появятся записи и то, что их объединяет.") : L("Записей за неделю: %d.\nПосмотри, что повторялось и что изменилось.", entries.count)).font(.system(size: 16)).foregroundStyle(EgoStyle.secondary).lineSpacing(5)
                            Button(L("Начать запись")) { state.replaceID = nil; state.capture = true }.font(.system(size: 17)).padding(.top, 12)
                            if !entries.isEmpty { if !state.models.installed.contains(.qwen) { Button(L("Скачать модель наблюдений")) { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now()+0.4) { state.settings = true } }.font(.system(size: 15)).padding(.top, 16) } else { WhiteButton(title: L("Прочитать неделю")) { Task { await state.review(week: week) } }.disabled(state.busy).padding(.top, 16) } }
                        }.egoCard().padding(.top, 8)
                    }
                    if state.busy && state.processingID == nil { HStack(spacing: 12) { ProgressView(); Text(L("Читаю неделю…")).foregroundStyle(EgoStyle.secondary) }.padding(.top, 12) }
                }.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 40)
            }.egoScreen().navigationTitle(L("Обзор")).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 22) {
                        Button { move(-1) } label: { Image(systemName: "chevron.left").font(.system(size: 13)).frame(width: 28, height: 44) }.accessibilityLabel(L("Предыдущая неделя"))
                        VStack(spacing: 1) {
                            Text(L("Обзор")).font(.system(size: 17))
                            Text(interval.start.formatted(.dateTime.day().month(.abbreviated).year().locale(EgoLocale.current))).font(.system(size: 10)).foregroundStyle(EgoStyle.secondary)
                        }.accessibilityElement(children: .combine)
                        Button { move(1) } label: { Image(systemName: "chevron.right").font(.system(size: 13)).frame(width: 28, height: 44) }.accessibilityLabel(L("Следующая неделя"))
                    }
                }
            }.tint(.white)
    }
    private func move(_ offset: Int) { withAnimation(EgoStyle.spring) { week = Calendar.journal.date(byAdding: .weekOfYear, value: offset, to: week)! } }
}
