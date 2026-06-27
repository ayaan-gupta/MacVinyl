import AppKit
import Carbon

final class HotkeyService {
    static let shared = HotkeyService()

    // Media key interception via CGEventTap
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var accessibilityCheckTimer: Timer?

    // Custom shortcut monitoring via NSEvent global + local monitors
    private var customGlobalMonitor: Any?
    private var customLocalMonitor: Any?

    private static let relevantModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    private init() {}

    func start() {
        installCustomMonitor()
        if AXIsProcessTrusted() {
            installEventTap()
        } else {
            promptForAccessibility()
            startPollingForAccessibility()
        }
    }

    // MARK: - Custom shortcuts (NSEvent global monitor)

    func installCustomMonitor() {
        if let m = customGlobalMonitor { NSEvent.removeMonitor(m); customGlobalMonitor = nil }
        if let m = customLocalMonitor { NSEvent.removeMonitor(m); customLocalMonitor = nil }

        // Global: other apps frontmost (requires Accessibility trust).
        customGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = Self.handleCustomHotkey(event)
        }

        // Local: Vinyl is key (popover open) — works without Accessibility.
        customLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            Self.handleCustomHotkey(event) ? nil : event
        }
    }

    /// Returns true when the event matched a configured shortcut and was handled.
    @discardableResult
    private static func handleCustomHotkey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(relevantModifiers)
        let code = event.keyCode
        let config = HotkeyConfig.shared

        for action in HotkeyAction.allCases {
            let binding = config.binding(for: action)
            let boundMods = binding.modifiers.intersection(relevantModifiers)
            guard code == binding.keyCode, mods == boundMods else { continue }

            DispatchQueue.main.async {
                switch action {
                case .playPause:
                    PlayerState.shared.togglePlayingOptimistically()
                    AppleScriptBridge.playPause()
                    PollingService.shared.refreshNow()
                case .previous:
                    PlayerState.shared.requestSkip(direction: -1)
                case .next:
                    PlayerState.shared.requestSkip(direction: 1)
                }
            }
            return true
        }
        return false
    }

    // MARK: - Media key interception (CGEventTap)

    private func installEventTap() {
        let mask = CGEventMask(1 << 14)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in HotkeyService.handleMediaEvent(event) },
            userInfo: nil
        ) else {
            promptForAccessibility()
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    private static func handleMediaEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passRetained(event)
        }
        let keyCode  = (nsEvent.data1 & 0xFFFF0000) >> 16
        let keyFlags = nsEvent.data1 & 0x0000FFFF
        let keyDown  = (keyFlags & 0xFF00) >> 8 == 0xA
        guard keyDown else { return nil }
        switch keyCode {
        case Int(NX_KEYTYPE_PLAY):
            DispatchQueue.main.async {
                PlayerState.shared.togglePlayingOptimistically()
                AppleScriptBridge.playPause()
                PollingService.shared.refreshNow()
            }
        case Int(NX_KEYTYPE_NEXT):
            DispatchQueue.main.async { PlayerState.shared.requestSkip(direction: 1) }
        case Int(NX_KEYTYPE_PREVIOUS):
            DispatchQueue.main.async { PlayerState.shared.requestSkip(direction: -1) }
        default:
            return Unmanaged.passRetained(event)
        }
        return nil
    }

    private func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func startPollingForAccessibility() {
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if AXIsProcessTrusted() {
                t.invalidate()
                self.accessibilityCheckTimer = nil
                self.installEventTap()
                self.installCustomMonitor()
            }
        }
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        accessibilityCheckTimer?.invalidate()
        if let m = customGlobalMonitor { NSEvent.removeMonitor(m); customGlobalMonitor = nil }
        if let m = customLocalMonitor { NSEvent.removeMonitor(m); customLocalMonitor = nil }
    }
}
