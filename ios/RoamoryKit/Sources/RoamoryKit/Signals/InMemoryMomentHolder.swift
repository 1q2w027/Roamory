import Foundation

/// A `MomentHolder` that only remembers holds and releases, for the app until the ring buffer (TRD §5) lands,
/// and for the replay tool. It protects no footage. The caller polls `due(atMs:)` and finalizes what it returns.
public actor InMemoryMomentHolder: MomentHolder {
    public private(set) var holds: [(id: String, triggerMs: Int, source: MomentSource)] = []
    public private(set) var released: [String] = []
    private var finalized: Set<String> = []
    /// Seconds kept after the trigger (TRD §5.3 `POST_S`); a moment is due 2 s after its window ends.
    let postS: Int

    public init(postS: Int = 15) {
        self.postS = postS
    }

    public func hold(momentId: String, triggerMs: Int, source: MomentSource) {
        holds.append((momentId, triggerMs, source))
    }

    public func release(_ momentId: String) {
        if !released.contains(momentId) { released.append(momentId) }
    }

    /// Ids whose window closed by `atMs` (trigger + postS + 2 s) and that are not finalized yet, oldest first.
    public func due(atMs: Int) -> [String] {
        holds.filter { !finalized.contains($0.id) && atMs >= $0.triggerMs + (postS + 2) * 1000 }.map(\.id)
    }

    /// Ids not finalized yet, e.g. to finalize everything when recording stops.
    public func pending() -> [String] {
        holds.filter { !finalized.contains($0.id) }.map(\.id)
    }

    public func markFinalized(_ momentId: String) {
        finalized.insert(momentId)
    }
}
