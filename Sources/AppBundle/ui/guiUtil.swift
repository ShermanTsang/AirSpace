import SwiftUI

extension View {
    @ViewBuilder func scrollBounceBasedOnSizeCompat() -> some View {
        if #available(macOS 13.3, *) {
            scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }

    @inlinable nonisolated public func onChangeCompat<V>(of value: V, perform action: @escaping (_ newValue: V) -> Void) -> some View where V: Equatable {
        if #available(macOS 14, *) { // #macos14
            return onChange(of: value) { _, new in action(new) }
        } else {
            return onChange(of: value, perform: action)
        }
    }
}

extension Scene {
    @inlinable nonisolated public func onChangeCompat<V>(of value: V, perform action: @escaping (_ newValue: V) -> Void) -> some Scene where V: Equatable {
        if #available(macOS 14, *) { // #macos14
            return onChange(of: value) { _, new in action(new) }
        } else {
            return onChange(of: value, perform: action)
        }
    }
}
