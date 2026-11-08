import SwiftUI
import AppIntents

@main struct EgoApp: App {
    @State private var state = AppState()
    @Environment(\.scenePhase) private var phase
    @AppStorage("onboarded") private var onboarded = false
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    init() { ExportService.removeAbandonedExports() }
    var body: some Scene {
        WindowGroup {
            ZStack {
                HomeView().environment(state)
                if !onboarded { WelcomeView { onboarded = true }.transition(.opacity) }

            }
            .egoScreen().environment(\.locale, EgoLocale.current)
            .background(PrivacyShield(state: state, active: phase == .active))
            .onOpenURL { state.route($0) }
            .task { await ReminderSchedule.refresh(); state.setForeground(phase == .active); await state.resumePending(); await state.reviewCompletedWeekIfNeeded() }
            .onChange(of: state.models.installed) { _, _ in Task { await state.resumePending(); await state.reviewCompletedWeekIfNeeded() } }
            .onChange(of: phase) { _, phase in state.setForeground(phase == .active); if phase == .background && state.faceID { state.locked = true }; if phase == .active { Task { await state.resumePending(); await state.reviewCompletedWeekIfNeeded() } } }
            .onReceive(NotificationCenter.default.publisher(for: .egoShortcut)) { notification in state.route(URL(string: notification.object as? String == "write" ? "ego://write" : "ego://record")!) }
            .alert("Ego", isPresented: Binding(get: { state.message != nil || state.store.error != nil }, set: { if !$0 { state.message = nil; state.store.error = nil } })) { Button(L("Понятно"), role: .cancel) {} } message: { Text(state.message ?? state.store.error ?? "") }
        }
    }
}
struct WelcomeView: View {
    var finish: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            EgoMark().frame(width: 76, height: 76).padding(.bottom, 30)
            Text(L("Место для\nтвоих мыслей.")).font(.system(size: 44, weight: .regular)).tracking(-1.5)
            Text(L("Скажи, что у тебя на уме.\nИли просто запиши.")).font(.system(size: 18)).foregroundStyle(EgoStyle.secondary).lineSpacing(5)
            Spacer()
            WhiteButton(title: L("Начать"), action: finish).frame(maxWidth: .infinity).padding(.bottom, 32)
        }.padding(28).egoScreen()
    }
}
struct EgoMark: View {
    var body: some View {
        Canvas { context, size in
            for row in -5...5 { for column in -5...5 {
                let r = sqrt(Double(row*row + column*column)); guard r < 5.7 else { continue }
                let scale = 1 - r / 9
                let x = size.width/2 + CGFloat(column)*size.width/13
                let y = size.height/2 + CGFloat(row)*size.height/13
                let d = 1.5 + scale*2
                context.fill(Path(ellipseIn: CGRect(x:x-d/2,y:y-d/2,width:d,height:d)), with: .color(.white.opacity(0.4+scale*0.6)))
            } }
        }.accessibilityHidden(true)
    }
}
struct LockScreen: View {
    @Environment(AppState.self) private var state
    var body: some View { VStack(spacing: 28) { EgoMark().frame(width: 66, height: 66); Text("Ego").font(.system(size: 34)); WhiteButton(title: L("Открыть дневник"), symbol: "faceid") { Task { await state.unlock() } } }.egoScreen().task {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--manual-unlock") { return }
        #endif
        await state.unlock()
    } }
}
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: session.role); config.delegateClass = ShortcutSceneDelegate.self
        if let shortcut = options.shortcutItem { DispatchQueue.main.asyncAfter(deadline: .now()+0.5) { NotificationCenter.default.post(name: .egoShortcut, object: shortcut.type) } }
        return config
    }
}
final class ShortcutSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) { NotificationCenter.default.post(name: .egoShortcut, object: shortcutItem.type); completionHandler(true) }
}
extension Notification.Name { static let egoShortcut = Notification.Name("egoShortcut") }
struct NewEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "New entry in Ego"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & OpensIntent { .result(opensIntent: OpenURLIntent(URL(string: "ego://record")!)) }
}
struct EgoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] { AppShortcut(intent: NewEntryIntent(), phrases: ["Record a thought in \(.applicationName)"], shortTitle: "New entry", systemImageName: "mic") }
}
