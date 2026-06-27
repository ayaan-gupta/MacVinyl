import AppKit
import SwiftUI

/// Borderless floating panel anchored to the menu bar status item.
/// Replaces NSPopover so we own the full window — no AppKit frame inset or chrome band.
@MainActor
final class MenuBarPanelController: NSObject {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private var panel: Panel!
    private var hostingController: NSHostingController<AnyView>!
    private weak var statusButton: NSStatusBarButton?

    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    private var contentSize = NSSize(width: AppleTheme.popoverWidth, height: 400)
    private let anchorGap: CGFloat = 6

    var isVisible: Bool { panel?.isVisible ?? false }

    func configure(rootView: some View) {
        hostingController = NSHostingController(rootView: AnyView(rootView))
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController.view.layer?.cornerRadius = AppleTheme.cornerRadius
        hostingController.view.layer?.cornerCurve = .continuous
        hostingController.view.layer?.masksToBounds = true
        // Only auto-resize the width. Height is driven exclusively by the explicit
        // animator call in updateContentSize, so there is no conflict between
        // autoresizing and the animator that caused the panel to jitter.
        hostingController.view.autoresizingMask = [.width]

        panel = Panel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentViewController = hostingController
        panel.setContentSize(contentSize)
        hostingController.view.setFrameSize(contentSize)
    }

    func toggle(anchor: NSStatusBarButton) {
        if isVisible {
            hide()
        } else {
            show(anchor: anchor)
        }
    }

    func show(anchor: NSStatusBarButton) {
        statusButton = anchor
        anchor.window?.layoutIfNeeded()
        anchor.layoutSubtreeIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        applyFrame(animated: false)
        panel.makeKeyAndOrderFront(nil)
        startClickMonitoring()
    }

    func hide() {
        stopClickMonitoring()
        panel.orderOut(nil)
    }

    func updateContentSize(_ size: NSSize, animated: Bool) {
        guard size.width > 0, size.height > 0 else { return }

        guard isVisible, let button = statusButton else {
            contentSize = size
            hostingController.view.setFrameSize(size)
            panel.setContentSize(size)
            return
        }

        let target = frame(anchoredTo: button, contentSize: size)

        if animated {
            contentSize = size
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = false
                // Animate the panel frame (origin + size) and the hosting view height
                // together in the same context so they stay perfectly in sync.
                // With autoresizingMask = [.width], the hosting view height is driven
                // solely by this explicit call — no conflicting autoresize.
                panel.animator().setFrame(target, display: true)
                hostingController.view.animator().setFrameSize(size)
            } completionHandler: {
                self.panel.setContentSize(size)
            }
        } else {
            contentSize = size
            hostingController.view.setFrameSize(size)
            panel.setContentSize(size)
            panel.setFrame(target, display: true)
        }
    }

    // MARK: - Positioning

    private func applyFrame(animated: Bool) {
        guard let button = statusButton else { return }
        let target = frame(anchoredTo: button, contentSize: contentSize)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = false
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }

    private func frame(anchoredTo button: NSStatusBarButton, contentSize: NSSize) -> NSRect {
        guard let window = button.window else {
            return NSRect(origin: .zero, size: contentSize)
        }

        let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        var origin = NSPoint(
            x: buttonRect.midX - contentSize.width * 0.5,
            y: buttonRect.minY - contentSize.height - anchorGap
        )

        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let margin: CGFloat = 8
            origin.x = max(visible.minX + margin, min(origin.x, visible.maxX - contentSize.width - margin))
            origin.y = max(visible.minY + margin, origin.y)
        }

        return NSRect(origin: origin, size: contentSize)
    }

    // MARK: - Click outside to dismiss

    private func startClickMonitoring() {
        stopClickMonitoring()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.handleOutsideClick() }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in self?.handleOutsideClick() }
            return event
        }
    }

    private func stopClickMonitoring() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    private func handleOutsideClick() {
        guard isVisible else { return }

        let click = NSEvent.mouseLocation
        if panel.frame.contains(click) { return }

        if let button = statusButton, let window = button.window {
            let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
            if buttonRect.contains(click) { return }
        }

        hide()
    }
}
