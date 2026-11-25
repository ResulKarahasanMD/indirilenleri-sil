import Foundation
import Synchronization

/// Runs blocking work on its own thread so a test can watch it from outside.
final class BackgroundRun<Value: Sendable>: Sendable {
    private let value = Mutex<Value?>(nil)
    private let finished = DispatchSemaphore(value: 0)

    init(_ work: @escaping @Sendable () -> Value) {
        Thread.detachNewThread { [self] in
            let result = work()
            value.withLock { $0 = result }
            finished.signal()
        }
    }

    /// The result, or nil when the work is still running after `seconds`.
    func result(within seconds: Double) -> Value? {
        guard finished.wait(timeout: .now() + seconds) == .success else { return nil }
        finished.signal()
        return value.withLock { $0 }
    }
}

/// Holds the run lock the way another running copy of the tool would.
final class HeldLock: Sendable {
    private let descriptor: Int32

    init(_ url: URL) {
        descriptor = open(url.path, O_CREAT | O_RDWR, 0o644)
        precondition(descriptor >= 0 && flock(descriptor, LOCK_EX | LOCK_NB) == 0, "test could not take the lock")
    }

    func release() {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

/// Collects values from any thread.
final class Collected<Element: Sendable>: Sendable {
    private let elements = Mutex<[Element]>([])
    func add(_ element: Element) { elements.withLock { $0.append(element) } }
    var all: [Element] { elements.withLock { $0 } }
}

final class Flag: Sendable {
    private let value = Mutex(false)
    var isSet: Bool { value.withLock { $0 } }
    func set() { value.withLock { $0 = true } }
}
