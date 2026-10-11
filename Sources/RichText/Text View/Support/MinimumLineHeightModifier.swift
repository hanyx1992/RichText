import SwiftUI

extension View {
    /// Sets a minimum line height without limiting taller text or embedded views.
    public nonisolated func richTextMinimumLineHeight(_ height: CGFloat) -> some View {
        environment(\.richTextMinimumLineHeight, height)
    }
}

private struct MinimumLineHeightEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var richTextMinimumLineHeight: CGFloat {
        get { self[MinimumLineHeightEnvironmentKey.self] }
        set { self[MinimumLineHeightEnvironmentKey.self] = newValue }
    }
}
