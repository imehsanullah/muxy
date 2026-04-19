import SwiftUI

private struct OverlayActiveEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var overlayActive: Bool {
        get { self[OverlayActiveEnvironmentKey.self] }
        set { self[OverlayActiveEnvironmentKey.self] = newValue }
    }
}
