//
//  CameraService.swift
//  Roamory
//

import AVFoundation
import Combine
import os
import Photos
import RoamoryKit
import UIKit

/// Owns the capture session. Once `startFilming()` is called, frames feed a rolling buffer of the last seconds;
/// `startSaving()` writes the buffer and everything after it to a file, `stopSaving()` closes the file and saves it
/// to Photos, and `stopFilming()` ends the film and empties the buffer.
final class CameraService: NSObject, ObservableObject,
                           AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    /// True once the session is running and the preview is live.
    @Published private(set) var isReady = false
    /// True from `startFilming()` to `stopFilming()`: the buffer fills and the director decides. While it is false
    /// the camera only shows the preview and every frame is dropped.
    @Published private(set) var isFilming = false
    /// True while `stopFilming()` closes a clip and empties the buffer.
    @Published private(set) var isEnding = false
    @Published private(set) var isSaving = false
    /// When the saved clip would have started if it ran in real time, so `now - savingStart` is its length.
    @Published private(set) var savingStart: Date?
    @Published private(set) var message: String?
    /// The director's last decision in a line, for the debug badge.
    @Published private(set) var directorLine: String?
    /// Every director request with its frames and timing, for the debug log.
    let directorLog = DirectorLog()
    /// Zoom as shown to the user: 1 is the main camera, 0.5 the ultra-wide (when the device has one).
    @Published private(set) var zoomFactor: CGFloat = 1
    @Published private(set) var minZoom: CGFloat = 1
    @Published private(set) var maxZoom: CGFloat = 1
    /// Quick-select zoom levels, including the points where the system switches lenses.
    @Published private(set) var zoomPresets: [CGFloat] = []
    /// The format this session records in, fixed when it starts (TRD 4.1).
    @Published private(set) var captureOrientation = CaptureOrientation.portrait
    /// The capture rotation the session records at (degrees, horizon-level), fixed when it starts; the level and the
    /// landscape layout follow it.
    @Published private(set) var captureRotationAngle: Double?
    /// How the phone is held now, as a horizon-level capture angle in degrees, for the "turn the phone" hint.
    @Published private(set) var heldAngle: Double?
    /// The rear camera once the session is configured, for the preview's rotation.
    @Published private(set) var device: AVCaptureDevice?

    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated let recorder = RollingRecorder()
    nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private let audioOutput = AVCaptureAudioDataOutput()
    nonisolated(unsafe) private var videoDevice: AVCaptureDevice?
    /// The rotation `configure` applied to the video output.
    nonisolated(unsafe) private var appliedRotationAngle: Double?
    /// displayZoom = videoZoomFactor * multiplier. A virtual multi-camera starts at the ultra-wide, so this is 0.5 there.
    nonisolated(unsafe) private var zoomMultiplier: CGFloat = 1
    nonisolated private let sessionQueue = DispatchQueue(label: "roamory.camera.session")
    /// Camera frames and microphone buffers for the buffer arrive here, in order.
    nonisolated private let sampleQueue = DispatchQueue(label: "roamory.camera.samples")
    private var isStopping = false
    /// Whether camera frames and microphone buffers reach the recorder; read on `sampleQueue`.
    nonisolated private let feedsBuffer = OSAllocatedUnfairLock(initialState: false)
    private var directorTask: Task<Void, Never>?
    /// True while the clip being saved was started by the director, which may then end it. A clip started by hand is left alone.
    private var directorOwnsSave = false
    /// What the director's windows showed in the clip being saved, and one summary per clip saved this trip.
    private var clipWindows: [String] = []
    private var clipSummaries: [String] = []
    /// The director's running notes: written before filming starts, then rewritten with every answer.
    private var directorNotes = Director.Notes()
    /// What the web search found about the event before filming; part of every request's system prompt.
    private var eventBrief: String?
    private var warnedNoKey = false
    private static let directorErrorPrefix = "Director: "
    /// Touched only on `sampleQueue`.
    nonisolated(unsafe) private var settleGate = SettleGate()
    /// Digital zoom beyond this looks too soft to be useful.
    private let zoomLimit: CGFloat = 10
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var heldAngleObservation: NSKeyValueObservation?

    /// Asks for camera permission, then configures and starts the session recording in `orientation`, turned
    /// whichever way the phone is held. The orientation stays for as long as the session runs.
    func prepare(orientation: CaptureOrientation) async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            message = "Camera access is required. Enable it in Settings."
            return
        }
        // Microphone is optional: without it we still record video.
        let hasMic = await AVCaptureDevice.requestAccess(for: .audio)
        if !hasMic { message = "Microphone access is off. The video will have no sound." }
        // Set the audio session ourselves so Bluetooth headphones stay as output (A2DP) while the built-in mic records,
        // and so `HeadphoneButton` can play silence to receive the AirPods stem press.
        // The audio session calls can block, so they run on the session queue rather than the main thread.
        session.automaticallyConfiguresApplicationAudioSession = false
        recorder.onError = { [weak self] error in
            Task { @MainActor [weak self] in self?.message = error.localizedDescription }
        }
        recorder.onSaveEnded = { [weak self] result in
            Task { @MainActor [weak self] in await self?.saveEndedByItself(result) }
        }
        let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            sessionQueue.async {
                let audio = AVAudioSession.sharedInstance()
                try? audio.setCategory(.playAndRecord, mode: .videoRecording, options: [.allowBluetoothA2DP])
                try? audio.setActive(true)
                let ok = self.configure(orientation: orientation)
                if ok { self.session.startRunning() }
                cont.resume(returning: ok)
            }
        }
        if !ok { message = "Unable to open the rear camera." }
        // A second call finds the session running and keeps the orientation it started with.
        if ok && !isReady {
            captureOrientation = orientation
            captureRotationAngle = appliedRotationAngle
        }
        isReady = ok
        // The buffer fills for as long as the app is open, so the screen must not lock.
        UIApplication.shared.isIdleTimerDisabled = true
        if let device = videoDevice {
            self.device = device
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            rotationCoordinator = coordinator
            heldAngleObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] c, _ in
                let angle = c.videoRotationAngleForHorizonLevelCapture
                Task { @MainActor [weak self] in self?.heldAngle = angle }
            }
            minZoom = device.minAvailableVideoZoomFactor * zoomMultiplier
            maxZoom = min(device.activeFormat.videoMaxZoomFactor * zoomMultiplier, zoomLimit)
            let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) * zoomMultiplier }
            let candidates = [0.5, 1, 2, 5] + switchOvers
            var presets: [CGFloat] = []
            for z in candidates.map({ ($0 * 10).rounded() / 10 }).sorted()
            where z >= minZoom - 0.01 && z <= maxZoom + 0.01 && !presets.contains(z) {
                presets.append(z)
            }
            zoomPresets = presets
        }
    }

    /// Stops the camera for good, before going back to trip setup. The next trip makes a new `CameraService`.
    func shutdown() async {
        directorTask?.cancel()
        directorTask = nil
        isFilming = false
        if isSaving { stopSaving() }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                self.session.stopRunning()
                cont.resume()
            }
        }
        isReady = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Sets the displayed zoom (1 = main camera), clamped to what the camera supports. Works while recording.
    /// On a multi-camera device the system switches lenses as the zoom crosses their switch-over points.
    func setZoom(_ factor: CGFloat) {
        let clamped = min(max(factor, minZoom), maxZoom)
        zoomFactor = clamped
        sessionQueue.async {
            guard let device = self.videoDevice, (try? device.lockForConfiguration()) != nil else { return }
            device.videoZoomFactor = clamped / self.zoomMultiplier
            device.unlockForConfiguration()
        }
    }

    nonisolated private func configure(orientation: CaptureOrientation) -> Bool {
        guard !session.isRunning, session.inputs.isEmpty else { return true }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high
        // Prefer a virtual multi-camera so the system switches lenses while zooming.
        let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera,
                                                   .builtInDualCamera, .builtInWideAngleCamera]
        guard let device = types.lazy.compactMap({ AVCaptureDevice.default($0, for: .video, position: .back) }).first,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(videoOutput) else { return false }
        session.addInput(input)
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: sampleQueue)
        session.addOutput(videoOutput)
        // Deliver upright frames in the style's format, so the clip needs no rotation and the edit no crop.
        let held = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil).videoRotationAngleForHorizonLevelCapture
        let angle = orientation.rotationAngle(near: held)
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
                appliedRotationAngle = angle
            }
            // The strongest stabilization the format allows; the default is off.
            let modes: [AVCaptureVideoStabilizationMode] = [.cinematicExtendedEnhanced, .cinematicExtended, .cinematic, .standard]
            if let mode = modes.first(where: device.activeFormat.isVideoStabilizationModeSupported) {
                connection.preferredVideoStabilizationMode = mode
            }
            #if DEBUG
            print("Stabilization: \(connection.activeVideoStabilizationMode.rawValue) (preferred \(connection.preferredVideoStabilizationMode.rawValue))")
            #endif
        }
        videoDevice = device
        zoomMultiplier = device.displayVideoZoomFactorMultiplier
        // Start at the main camera (1x), not the ultra-wide.
        if (try? device.lockForConfiguration()) != nil {
            device.videoZoomFactor = 1 / zoomMultiplier
            device.unlockForConfiguration()
        }

        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
           let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micInput),
           session.canAddOutput(audioOutput) {
            session.addInput(micInput)
            audioOutput.setSampleBufferDelegate(self, queue: sampleQueue)
            session.addOutput(audioOutput)
        }
        return true
    }

    /// Saves the whole buffer and everything captured from now on, until `stopSaving()`.
    func startSaving(byDirector: Bool = false) {
        guard isFilming, !isSaving else { return }
        isSaving = true
        directorOwnsSave = byDirector
        clipWindows = []
        message = nil
        Task {
            do {
                let preroll = try await recorder.start()
                savingStart = Date().addingTimeInterval(-preroll)
            } catch {
                isSaving = false
                directorOwnsSave = false
                clipWindows = []
                message = error.localizedDescription
            }
        }
    }

    /// Starts the film: the buffer begins to fill and the director goes to work. The buttons, volume keys and
    /// AirPods can save clips from now on.
    func startFilming() {
        guard isReady, !isFilming, !isEnding else { return }
        isFilming = true
        feedsBuffer.withLock { $0 = true }
        startDirector()
    }

    /// Ends the film: the director stops, a clip being saved is closed and goes to Photos, then the whole buffer is
    /// emptied. The preview stays on. The notes and the summaries of the clips saved so far stay for the next start.
    func stopFilming() async {
        guard isFilming, !isEnding else { return }
        isEnding = true
        isFilming = false
        directorTask?.cancel()
        directorTask = nil
        // The clip needs frames to end on a whole group of pictures, so they keep coming until it is closed.
        if isSaving {
            if !isStopping {
                isStopping = true
                await closeClip()
            } else {
                while isStopping { try? await Task.sleep(for: .milliseconds(100)) }
            }
        }
        feedsBuffer.withLock { $0 = false }
        recorder.reset()
        clipWindows = []
        directorLine = nil
        isEnding = false
    }

    /// Starts the director: first the event is looked up and the notes are written from what the traveler said and
    /// what was found, then every `Director.interval` seconds the frames since its last answer go to Claude, which
    /// decides whether to save the buffer or let it go. Does nothing without an API key.
    func startDirector() {
        guard directorTask == nil else { return }
        directorTask = Task { [weak self] in
            await self?.researchEvent()
            await self?.seedNotes()
            let clock = ContinuousClock()
            while !Task.isCancelled {
                let next = clock.now + .seconds(Director.interval)
                try? await Task.sleep(until: next, clock: clock)
                guard !Task.isCancelled, let self else { return }
                await self.directTick()
            }
        }
    }

    /// Looks the event up on the web before filming, when the traveler described one. Without a result the notes are
    /// written from the description alone; the failure only shows in the debug log.
    private func researchEvent() async {
        guard APIKeyStore.load() != nil, Director.searchUses > 0, TripSettings.details() != nil, eventBrief == nil else { return }
        let request = Director.researchRequest()
        var entry = DirectorLog.Entry(time: .now, frames: [], system: request.system, prompt: request.prompt,
                                      wasSaving: false)
        entry.kind = .research
        directorLine = "researching the event…"
        let started = ContinuousClock().now
        do {
            let reply = try await AnthropicAPI.exchangeResumingPauses(request.body, timeout: 40)
            entry.seconds = Self.seconds(since: started)
            entry.usage = reply.usage
            guard !reply.text.isEmpty else { throw Director.Failure(errorDescription: "The search gave no answer.") }
            entry.raw = reply.text
            guard !Task.isCancelled else { return }
            eventBrief = reply.text
            directorLine = "research · \(String(format: "%.1f", entry.seconds)) s"
        } catch {
            guard !Task.isCancelled else { return }
            if entry.seconds == 0 { entry.seconds = Self.seconds(since: started) }
            entry.error = error.localizedDescription
            directorLine = "research error · \(error.localizedDescription)"
        }
        directorLog.record(entry)
    }

    /// Writes the director's first notes, with the checklist, from the trip's details and what the search found. If
    /// that fails the director starts with empty notes and writes them itself from the first frames.
    private func seedNotes() async {
        guard APIKeyStore.load() != nil, directorNotes.isEmpty else { return }
        let request = Director.seedRequest(brief: eventBrief)
        var entry = DirectorLog.Entry(time: .now, frames: [], system: request.system, prompt: request.prompt,
                                      wasSaving: false)
        entry.kind = .notes
        let started = ContinuousClock().now
        do {
            let reply = try await AnthropicAPI.exchange(request.body, timeout: 30)
            entry.seconds = Self.seconds(since: started)
            entry.raw = reply.text
            entry.usage = reply.usage
            let notes = try Director.parseNotes(reply)
            guard !Task.isCancelled else { return }
            directorNotes = notes
            entry.notes = notes
            directorLine = "notes · \(String(format: "%.1f", entry.seconds)) s · \(notes.checklist.count) items"
        } catch {
            guard !Task.isCancelled else { return }
            if entry.seconds == 0 { entry.seconds = Self.seconds(since: started) }
            entry.error = error.localizedDescription
            directorLine = "notes error · \(error.localizedDescription)"
        }
        directorLog.record(entry)
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let d = start.duration(to: .now)
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    private func directTick() async {
        // A clip being closed is neither saving nor idle; the next tick sees the settled state.
        guard isReady, isFilming, !isStopping else { return }
        guard APIKeyStore.load() != nil else {
            if !warnedNoKey {
                warnedNoKey = true
                message = "Add an Anthropic API key in Ask so the director can choose what to save."
            }
            return
        }
        let frames: [Data]
        let through: Double
        do { (frames, through) = try recorder.peekFrames(count: Director.frameCount) } catch { return }

        let state = Director.State(isSaving: isSaving, savingSeconds: savingStart.map { Date().timeIntervalSince($0) } ?? 0,
                                   clipSoFar: clipWindows, clips: clipSummaries, notes: directorNotes,
                                   brief: eventBrief)
        let request = Director.request(frames: frames, state: state)
        var entry = DirectorLog.Entry(time: .now, frames: frames, system: request.system, prompt: request.prompt,
                                      wasSaving: state.isSaving)
        let started = ContinuousClock().now
        func elapsed() -> Double { Self.seconds(since: started) }
        do {
            let reply = try await AnthropicAPI.exchange(request.body, timeout: 15)
            entry.seconds = elapsed()
            entry.raw = reply.text
            entry.usage = reply.usage
            let decision = try Director.parse(reply)
            entry.decision = decision
            // The trip may have ended while the request was out; then there is nothing left to decide.
            guard !Task.isCancelled, isReady else { return }
            // Only an answer uses the frames up; after a failure the next request sends them again.
            recorder.discardFrames(through: through)
            directorNotes = decision.notes
            entry.notes = decision.notes
            entry.applied = apply(decision)
            directorLine = "\(decision.action.rawValue) · \(String(format: "%.1f", entry.seconds)) s · \(decision.why)"
            if message?.hasPrefix(Self.directorErrorPrefix) == true { message = nil }
        } catch {
            guard !Task.isCancelled else { return }
            if entry.seconds == 0 { entry.seconds = elapsed() }
            entry.error = error.localizedDescription
            directorLine = "error · \(error.localizedDescription)"
            // Release builds have no log, so a failing director (bad key, no network) has to show up here.
            message = Self.directorErrorPrefix + error.localizedDescription
        }
        directorLog.record(entry)
    }

    /// Acts on a decision and says what it did.
    private func apply(_ decision: Director.Decision) -> String {
        // The answer may arrive while the clip is being closed (by hand, or by the camera stopping).
        guard !isStopping else { return "clip was closing" }
        switch decision.action {
        case .save:
            if isSaving {
                clipWindows.append(decision.summary)
                return directorOwnsSave ? "kept saving" : "kept saving (started by hand)"
            }
            startSaving(byDirector: true)
            clipWindows = [decision.summary]
            return "started saving"
        case .skip:
            if isSaving && directorOwnsSave {
                stopSaving()
                return "stopped saving"
            }
            guard isSaving else { return "not saving" }
            // A clip started by hand goes on, so what these frames show still belongs to it.
            clipWindows.append(decision.summary)
            return "kept saving (started by hand)"
        }
    }

    /// Ends the director's bookkeeping for the clip being closed and returns its summary. The summary only joins
    /// `clipSummaries` once the clip is really saved, so the director never remembers a clip that was lost.
    private func takeClip() -> String {
        let summary = clipWindows.isEmpty ? "Saved by hand, not described." : Director.condense(clipWindows)
        clipWindows = []
        directorOwnsSave = false
        return summary
    }

    func toggleSaving() {
        if isSaving { stopSaving() } else { startSaving() }
    }

    /// Closes the saved clip, keeps it for the trip and puts it in Photos. The buffer keeps running.
    func stopSaving() {
        guard isSaving, !isStopping else { return }
        isStopping = true
        Task { await closeClip() }
    }

    /// The closing of a clip, with `isStopping` already set by the caller.
    private func closeClip() async {
        let summary = takeClip()
        let start = savingStart ?? .now
        defer {
            isStopping = false
            isSaving = false
            savingStart = nil
        }
        do {
            let file = try await recorder.stop()
            clipSummaries.append(summary)
            await saveToPhotos(file, recordedAt: start)
        } catch {
            message = "Recording failed: \(error.localizedDescription)"
        }
    }

    /// The clip ended without `stopSaving()`: capture was interrupted (we keep what was recorded) or writing failed.
    private func saveEndedByItself(_ result: Result<URL, Error>) async {
        let start = savingStart ?? .now
        // While `stopSaving()` is closing the clip it has already taken the summary.
        let summary = isStopping ? nil : takeClip()
        isSaving = false
        savingStart = nil
        switch result {
        case .success(let url):
            if let summary { clipSummaries.append(summary) }
            await saveToPhotos(url, recordedAt: start)
        case .failure(let error): message = "Recording failed: \(error.localizedDescription)"
        }
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard feedsBuffer.withLock({ $0 }) else { return }
        if output === videoOutput {
            let isAdjusting = videoDevice.map { $0.isAdjustingWhiteBalance || $0.isAdjustingExposure } ?? false
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            guard settleGate.admit(at: time, isAdjusting: isAdjusting) else { return }
            recorder.handle(video: sampleBuffer)
        } else {
            recorder.handle(audio: sampleBuffer)
        }
    }

    /// Keeps the clip for Roamory Studio (`TripClips`), then adds a copy to Photos.
    private func saveToPhotos(_ file: URL, recordedAt: Date) async {
        // If it cannot be kept, Photos still gets it and the temporary file goes afterwards.
        let kept = try? TripClips.keep(file, recordedAt: recordedAt)
        let url = kept?.url ?? file
        defer { if kept == nil { try? FileManager.default.removeItem(at: file) } }
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized else {
            message = "Photos access is required to save the video."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            message = "Saved to Photos"
        } catch {
            message = "Save failed: \(error.localizedDescription)"
        }
    }
}
