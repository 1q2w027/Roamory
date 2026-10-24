import XCTest
@testable import RoamoryKit

private final class FakeRecorder: ClipRecorder, @unchecked Sendable {
    private let lock = NSLock()
    private var startFailures: Int
    private(set) var startCalls = 0
    private(set) var stopCalls = 0
    let preroll: TimeInterval
    let file: URL
    /// Runs inside `startSaving`, to model time passing while a save waits its turn.
    var duringStart: (() -> Void)?

    init(startFailures: Int = 0, preroll: TimeInterval = 30, file: URL) {
        self.startFailures = startFailures
        self.preroll = preroll
        self.file = file
    }

    func startSaving() async throws -> TimeInterval {
        let fail: Bool = lock.withLock {
            startCalls += 1
            if startFailures > 0 { startFailures -= 1; return true }
            return false
        }
        if fail { throw NSError(domain: "fake", code: 1) }
        duringStart?()
        return preroll
    }

    func stopSaving() async throws -> URL {
        lock.withLock { stopCalls += 1 }
        return file
    }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int
    init(_ value: Int) { self.value = value }
    func set(_ new: Int) { lock.withLock { value = new } }
    var now: Int { lock.withLock { value } }
}

final class OneStepSaverTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "saver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func tempClip() throws -> URL {
        let url = folder.appending(path: "buffer-\(UUID().uuidString).mp4")
        try Data("clip".utf8).write(to: url)
        return url
    }

    private func saver(_ recorder: FakeRecorder, clock: Clock, retryDelay: Duration = .zero) -> OneStepSaver {
        OneStepSaver(
            recorder: recorder, tripFolder: folder.appending(path: "Trip"), sessionId: "s_1",
            clock: { clock.now }, retryDelay: retryDelay, inspect: { _ in (durationS: 45, hasAudio: false) }
        )
    }

    private let moment = KeptMoment(id: "m_1", source: .button, triggerMs: 25_000, tripId: "t_1")

    private func sidecar(_ result: Result<URL, Error>) throws -> ClipSidecar {
        let clip = try result.get()
        return try JSONDecoder().decode(ClipSidecar.self, from: Data(contentsOf: clip.deletingPathExtension().appendingPathExtension("json")))
    }

    func testFromMsUsesTheClockAfterStartReturns() async throws {
        let clock = Clock(40_000) // when the keep was decided
        let recorder = FakeRecorder(preroll: 30, file: try tempClip())
        recorder.duringStart = { clock.set(50_000) } // the save waited its turn for 10 s
        let result = await saver(recorder, clock: clock).save(moment)
        let sidecar = try sidecar(result)
        XCTAssertEqual(sidecar.fromMs, 20_000) // 50 s now minus 30 s of preroll, not 40 s minus 30 s
        XCTAssertEqual(sidecar.triggerMs, 25_000)
        XCTAssertEqual(sidecar.clipPath, "clips/m_1.mp4")
    }

    func testRetriesOnceWhenStartFailsThenSaves() async throws {
        let recorder = FakeRecorder(startFailures: 1, file: try tempClip())
        let result = await saver(recorder, clock: Clock(40_000)).save(moment)
        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(recorder.startCalls, 2)
        XCTAssertEqual(recorder.stopCalls, 1)
    }

    func testFailsAfterOneRetryAndNeverStops() async throws {
        let recorder = FakeRecorder(startFailures: 2, file: try tempClip())
        let result = await saver(recorder, clock: Clock(40_000)).save(moment)
        XCTAssertThrowsError(try result.get())
        XCTAssertEqual(recorder.startCalls, 2)
        XCTAssertEqual(recorder.stopCalls, 0)
    }

    func testClipAndSidecarLandInTheTripFolder() async throws {
        let recorder = FakeRecorder(file: try tempClip())
        let clip = try await saver(recorder, clock: Clock(40_000)).save(moment).get()
        XCTAssertEqual(clip, folder.appending(path: "Trip/clips/m_1.mp4"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.path))
    }
}
