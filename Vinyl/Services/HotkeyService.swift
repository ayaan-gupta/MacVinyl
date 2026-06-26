import AppKit
import Carbon

final class HotkeyService {
    static let shared = HotkeyService()

    // Media key interception via CGEventTap
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var accessibilityCheckTimer: Timer?

    // Custom shortcut monitoring via NSEvent global monitor
    private var customMonitor: Any?

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
        if let m = customMonitor { NSEvent.removeMonitor(m); customMonitor = nil }
        let config = HotkeyConfig.shared
        customMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            let code = event.keyCode
            for action in HotkeyAction.allCases {
                let b = config.binding(for: action)
                if code == b.keyCode && NSEvent.ModifierFlags(rawValue: b.modifierRaw) == mods {
                    switch action {
                    case .playPause:
                        PlayerState.shared.isPlaying.toggle()
                        AppleScriptBridge.playPause()
                    case .previous:
                        AppleScriptBridge.previousTrack()
                    case .next:
                        AppleScriptBridge.nextTrack()
                    }
                    break
                }
            }
        }
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
            PlayerState.shared.isPlaying.toggle()
            AppleScriptBridge.playPause()
        case Int(NX_KEYTYPE_NEXT):
            AppleScriptBridge.nextTrack()
        case Int(NX_KEYTYPE_PREVIOUS):
            AppleScriptBridge.previousTrack()
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
            }
        }
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        accessibilityCheckTimer?.invalidate()
        if let m = customMonitor { NSEvent.removeMonitor(m); customMonitor = nil }
    }
}
