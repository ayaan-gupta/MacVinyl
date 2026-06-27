import AppKit
import SwiftUI
import Carbon
import Combine
import CoreText

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panelController: MenuBarPanelController!
    private var menuBarCoordinator: MenuBarIconCoordinator!
    private let themeSettings = ThemeSettings.shared
    private let playerState = PlayerState.shared

    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerBundleFonts()
        setupMenuBar()
        setupPanel()
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
        button.action = #selector(togglePanel)
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

    // MARK: - Panel

    private func setupPanel() {
        panelController = MenuBarPanelController()

        let rootView = PopoverView(playerState: playerState, onSizeChange: { [weak self] size, animated in
            guard let self else { return }
            guard size.height > 10, size.width > 0 else { return }
            self.panelController.updateContentSize(
                NSSize(width: size.width, height: size.height),
                animated: animated
            )
        })
        .environmentObject(themeSettings)

        panelController.configure(rootView: rootView)
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        panelController.toggle(anchor: button)
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

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "vinyl" {
            SpotifyWebAPI.shared.handleCallback(url: url)
        }
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
            SpotifyWebAPI.shared.validateSession { success in
                if success {
                    PollingService.shared.refreshNow()
                    PollingService.shared.refreshQueueNow()
                }
            }
        }
        VinylSpinner.shared.start()
        PollingService.shared.start()

        // Keep spinner in sync with isPlaying even while panel is closed
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
    }
}
