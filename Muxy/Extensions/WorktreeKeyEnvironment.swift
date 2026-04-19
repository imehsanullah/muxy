import SwiftUI

private struct ActiveWorktreeKeyEnvironmentKey: EnvironmentKey {
    static let defaultValue: WorktreeKey? = nil
}

extension EnvironmentValues {
    var activeWorktreeKey: WorktreeKey? {
        get { self[ActiveWorktreeKeyEnvironmentKey.self] }
        set { self[ActiveWorktreeKeyEnvironmentKey.self] = newValue }
    }
}
