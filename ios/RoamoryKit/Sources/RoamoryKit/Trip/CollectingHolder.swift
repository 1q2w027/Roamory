import Foundation

/// Stands in for the rolling buffer when detection runs over a finished recording: remembers each hold and release.
public actor CollectingHolder: MomentHolder {
    public struct Hold: Sendable, Equatable {
        public var momentId: String
        public var triggerMs: Int
        public var source: MomentSource
    }

    public enum Event: Sendable {
        case hold(Hold)
        case release(momentId: String)
    }

    public private(set) var holds: [Hold] = []
    public private(set) var released: Set<String> = []
    private let onEvent: (@Sendable (Event) -> Void)?

    /// - Parameter onEvent: called as each hold or release arrives, e.g. for a log.
    public init(onEvent: (@Sendable (Event) -> Void)? = nil) {
        self.onEvent = onEvent
    }

    public func hold(momentId: String, triggerMs: Int, source: MomentSource) {
        let hold = Hold(momentId: momentId, triggerMs: triggerMs, source: source)
        holds.append(hold)
        onEvent?(.hold(hold))
    }

    public func release(_ momentId: String) {
        released.insert(momentId)
        onEvent?(.release(momentId: momentId))
    }
}
