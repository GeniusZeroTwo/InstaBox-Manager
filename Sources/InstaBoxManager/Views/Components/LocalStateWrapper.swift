import Combine
import SwiftUI

/// Compatibility `@ViewState` property wrapper backed by `StateObject` + `DynamicProperty`.
/// Works seamlessly across all macOS SDKs (including CommandLineTools 27.x without `libSwiftUIMacros`).
@MainActor
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    @StateObject private var storage: Storage<Value>

    fileprivate final class Storage<T>: ObservableObject {
        @Published var value: T
        init(_ value: T) {
            self.value = value
        }
    }

    init(wrappedValue: Value) {
        _storage = StateObject(wrappedValue: Storage(wrappedValue))
    }

    init(initialValue: Value) {
        _storage = StateObject(wrappedValue: Storage(initialValue))
    }

    var wrappedValue: Value {
        get { storage.value }
        nonmutating set { storage.value = newValue }
    }

    var projectedValue: Binding<Value> {
        Binding(
            get: { storage.value },
            set: { storage.value = $0 }
        )
    }
}
