import WidgetKit
import SwiftUI

struct EgoWidgetEntry: TimelineEntry { let date: Date }
struct EgoProvider: TimelineProvider {
    func placeholder(in context: Context) -> EgoWidgetEntry { EgoWidgetEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (EgoWidgetEntry) -> Void) { completion(EgoWidgetEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EgoWidgetEntry>) -> Void) { completion(Timeline(entries: [EgoWidgetEntry(date: Date())], policy: .never)) }
}
struct EgoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: EgoWidgetEntry
    var body: some View {
        Group {
            if family == .accessoryCircular { Image(systemName: "mic").font(.system(size: 24)).widgetAccentable() }
            else if family == .accessoryRectangular { HStack { Image(systemName: "mic"); Text("Есть мысль?").font(.headline) } }
            else { VStack(alignment: .leading, spacing: 12) { HStack { Text("ego").font(.system(size: 17,weight: .medium)); Spacer(); Image(systemName: "mic").font(.system(size: 15)) }; Spacer(); Text("Есть мысль,\nкоторую хочется\nсохранить?").font(.system(size: 18, weight: .regular)).tracking(-0.4) }.foregroundStyle(.white) }
        }.containerBackground(.black, for: .widget).widgetURL(URL(string: "ego://record"))
    }
}
@main struct EgoWidget: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "EgoCapture", provider: EgoProvider()) { EgoWidgetView(entry: $0) }.configurationDisplayName("Новая мысль").description("Открой Ego и начни запись.").supportedFamilies([.systemSmall,.systemMedium,.accessoryCircular,.accessoryRectangular]) }
}
