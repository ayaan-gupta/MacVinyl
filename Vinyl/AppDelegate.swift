import AppKit
import SwiftUI
import Carbon
import Combine
import CoreText

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var menuBarCoordinator: MenuBarIconCoordinator!
    private let themeSettings = ThemeSettings.shared
    private let playerState = PlayerState.shared

    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerBundleFonts()
        setupMenuBar()
        setupPopover()
        setupOAuthHandler()
        setupWakeObserver()
        startServices()
    }

    // MARK: - Fonts

    private func registerBundleFonts() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else { return }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem.button else { return }
        button.action = #selector(togglePopover)
        button.target = self

        // Size the custom spinning view to sit centered inside the 22pt slot
        let size = AppleTheme.menuBarIconSize
        menuBarCoordinator = MenuBarIconCoordinator(size: size)
        let spinView = menuBarCoordinator.hostView
        spinView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(spinView)
        NSLayoutConstraint.activate([
            spinView.widthAnchor.constraint(equalToConstant: size),
            spinView.heightAnchor.constraint(equalToConstant: size),
            spinView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            spinView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let rootView = PopoverView(playerState: playerState, onSizeChange: { [weak self] size in
            guard let self, let pop = self.popover else { return }
            guard size.height > 10 else { return }  // ignore the height:1 reset frame
            pop.contentSize = size
        })
        .environmentObject(themeSettings)

        let vc = NSHostingController(rootView: rootView)
        vc.view.setFrameSize(NSSize(width: AppleTheme.popoverWidth, height: 400))
        popover.contentViewController = vc
        popover.contentSize = NSSize(width: AppleTheme.popoverWidth, height: 400)
        vc.view.layoutSubtreeIfNeeded()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover(from: button)
        }
    }

    private func showPopover(from button: NSStatusBarButton) {
        NSApp.activate(ignoringOtherApps: true)

        // The status item window may not have finished layout on the first click
        // after launch; defer one run loop so bounds and isFlipped are reliable.
        DispatchQueue.main.async { [weak self] in
            guard let self, let button = self.statusItem.button, !self.popover.isShown else { return }

            button.window?.layoutIfNeeded()
            button.layoutSubtreeIfNeeded()

            // Flipped status bar buttons anchor below on .maxY; standard coords use .minY.
            let edge: NSRectEdge = button.isFlipped ? .maxY : .minY
            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: edge)
            self.popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - OAuth

    private func setupOAuthHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else { return }
        SpotifyWebAPI.shared.handleCallback(url: url)
    }

    // MARK: - Wake

    private func setupWakeObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWake() {
        SpotifyWebAPI.shared.handleWake()
    }

    // MARK: - Services

    private func startServices() {
        if SpotifyWebAPI.shared.isAuthenticated {
            playerState.authState = .authenticated
        }
        VinylSpinner.shared.start()
        PollingService.shared.start()
        HotkeyService.shared.start()

        // Keep spinner in sync with isPlaying even while popover is closed
        playerState.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { playing in
                if VinylSpinner.shared.targetDegreesPerSecond == 0 && playing {
                    VinylSpinner.shared.targetDegreesPerSecond = 120
                } else if !playing {
                    VinylSpinner.shared.targetDegreesPerSecond = 0
                }
            }
            .store(in: &cancellables)

        // On theme switch, reset contentSize to height=1 so the new theme's
        // SizePreferenceKey always fires and overrides the stale size.
        themeSettings.$active
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newTheme in
                guard let self, let pop = self.popover else { return }
                let w = newTheme == .pixel ? PixelTheme.popoverWidth : AppleTheme.popoverWidth
                pop.contentSize = NSSize(width: w, height: 1)
            }
            .store(in: &cancellables)
    }
}
