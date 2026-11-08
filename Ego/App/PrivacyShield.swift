import SwiftUI

/// A separate window covers sheets, the share controller, and app-switcher snapshots.
struct PrivacyShield: UIViewRepresentable {
    var state: AppState
    var active: Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> Probe {
        let view = Probe(); view.isUserInteractionEnabled = false
        view.attached = { [weak coordinator = context.coordinator] window in coordinator?.parent = window; coordinator?.update(state: state, active: active) }
        return view
    }
    func updateUIView(_ view: Probe, context: Context) { context.coordinator.update(state: state, active: active) }
    static func dismantleUIView(_ view: Probe, coordinator: Coordinator) { coordinator.shield?.isHidden = true; coordinator.shield = nil }
    final class Probe: UIView {
        var attached: ((UIWindow) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); if let window { attached?(window) } }
    }
    @MainActor final class Coordinator {
        weak var parent: UIWindow?
        var shield: UIWindow?
        private var interactive: Bool?
        func update(state: AppState, active: Bool) {
            let visible = state.faceID && (state.locked || !active)
            parent?.accessibilityElementsHidden = visible
            guard visible, let scene = parent?.windowScene else { shield?.isHidden = true; shield = nil; interactive = nil; parent?.makeKey(); return }
            if shield == nil { let window = UIWindow(windowScene: scene); window.windowLevel = .alert + 1; window.backgroundColor = .black; shield = window }
            let canUnlock = state.locked && (active || interactive == true)
            if interactive != canUnlock {
                interactive = canUnlock
                if canUnlock { shield?.rootViewController = UIHostingController(rootView: LockScreen().environment(state).preferredColorScheme(.dark)) }
                else { shield?.rootViewController = UIHostingController(rootView: EgoMark().frame(width: 70, height: 70).egoScreen()) }
            }
            shield?.rootViewController?.view.accessibilityViewIsModal = true
            shield?.makeKeyAndVisible()
        }
    }
}
