import SwiftData
import SwiftUI

private struct BackgroundContextKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: ModelContext? = nil
}

extension EnvironmentValues {
    var backgroundContext: ModelContext? {
        get { self[BackgroundContextKey.self] }
        set { self[BackgroundContextKey.self] = newValue }
    }
}
