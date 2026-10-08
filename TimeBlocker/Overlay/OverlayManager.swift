import AppKit
import SwiftUI

enum OverlayDisplayMode: String, CaseIterable, Identifiable {
    case allDisplays
    case mainDisplay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allDisplays: "すべてのディスプレイ"
        case .mainDisplay: "メインディスプレイのみ"
        }
    }
}

private final class InteractiveOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayManager {
    private var panels: [NSPanel] = []

    func show(
        events: [CalendarEvent],
        displayMode: OverlayDisplayMode,
        onOpenURL: @escaping (URL) -> Void,
        onSnooze: @escaping (Int) -> Void,
        onSkip: @escaping () -> Void
    ) {
        dismiss()
        let screens: [NSScreen]
        switch displayMode {
        case .allDisplays:
            screens = NSScreen.screens
        case .mainDisplay:
            screens = [NSScreen.main ?? NSScreen.screens.first].compactMap { $0 }
        }
        for screen in screens {
            let panel = InteractiveOverlayPanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]
            // Keep the panel transparent so SwiftUI's full-screen material can sample
            // the desktop or full-screen app behind it.
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: OverlayView(
                events: events,
                onOpenURL: onOpenURL,
                onSnooze: onSnooze,
                onSkip: onSkip
            ))
            panels.append(panel)
            panel.orderFrontRegardless()
        }
    }

    func dismiss() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }
}
