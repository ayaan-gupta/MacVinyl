import SwiftUI
import Combine

enum AppTheme: String, CaseIterable, Identifiable {
    case apple
    case pixel

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple"
        case .pixel: return "Pixel"
        }
    }
}

final class ThemeSettings: ObservableObject {
    static let shared = ThemeSettings()

    @Published var active: AppTheme {
        didSet { UserDefaults.standard.set(active.rawValue, forKey: "activeTheme") }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: "activeTheme") ?? ""
        active = AppTheme(rawValue: stored) ?? .apple
    }
}
