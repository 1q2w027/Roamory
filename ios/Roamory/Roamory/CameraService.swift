//
//  CameraService.swift
//  Roamory
//

import AVFoundation
import Combine
import Photos
import RoamoryKit
import UIKit

/// Owns the capture session. Frames feed a rolling buffer of the last seconds from the moment the camera is
/// ready; `startSaving()` writes the buffer and everything after it to a file, `stopSaving()` closes the file
/// and saves it to Photos.
final class CameraService: NSObject, ObservableObject,
                           AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    /// True once the session is running, which is when the buffer starts filling.
    @Published private(set) var isReady = false
    @Published private(set) var isSaving = false
    /// When the saved clip would have started if it ran in real time, so `now - savingStart` is its length.
    @Published private(set) var savingStart: Date?
    @Published private(set) var message: String?
    /// Zoom as shown to the user: 1 is the main camera, 0.5 the ultra-wide (when the device has one).
    @Published private(set) var zoomFactor: CGFloat = 1
    @Published private(set) var minZoom: CGFloat = 1
    @Published private(set) var maxZoom: CGFloat = 1
    /// Quick-select zoom levels, including the points where the system switches lenses.
    @Published private(set) var zoomPresets: [CGFloat] = []
    /// The format this session records in, fixed when it starts (TRD 4.1).
    @Published private(set) var captureOrientation = CaptureOrientation.portrait
    /// How the phone is held now, as a horizon-level capture angle in degrees, for the "turn the phone" hint.
    @Published private(set) var heldAngle: Double?
    /// The rear camera once the session is configured, for the preview's rotation.
    @Published private(set) var device: AVCaptureDevice?

    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated let recorder = RollingRecorder()
    nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private let audioOutput = AVCaptureAudioDataOutput()
    nonisolated(unsafe) private var videoDevice: AVCaptureDevice?
    /// displayZoom = videoZoomFactor * multiplier. A virtual multi-camera starts at the ultra-wide, so this is 0.5 there.
    nonisolated(unsafe) private var zoomMultiplier: CGFloat = 1
    nonisolated private let sessionQueue = DispatchQueue(label: "roamory.camera.session")
    /// Camera frames and microphone buffers for the buffer arrive here, in order.
    nonisolated private let sampleQueue = DispatchQueue(label: "roamory.camera.samples")
    private var isStopping = false
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
        if ok && !isReady { captureOrientation = orientation }
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
        if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
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
    func startSaving() {
        guard !isSaving else { return }
        isSaving = true
        message = nil
        Task {
            do {
                let preroll = try await recorder.start()
                savingStart = Date().addingTimeInterval(-preroll)
            } catch {
                isSaving = false
                message = error.localizedDescription
            }
        }
    }

    /// Debug stand-in for the trigger that will ask the cloud to evaluate the moment. Intentionally empty.
    func evaluate() {
        // TODO
    }

    func toggleSaving() {
        if isSaving { stopSaving() } else { startSaving() }
    }

    /// Closes the saved clip and puts it in Photos. The buffer keeps running.
    func stopSaving() {
        guard isSaving, !isStopping else { return }
        isStopping = true
        Task {
            defer {
                isStopping = false
                isSaving = false
                savingStart = nil
            }
            do {
                await saveToPhotos(try await recorder.stop())
            } catch {
                message = "Recording failed: \(error.localizedDescription)"
            }
        }
    }

    /// The clip ended without `stopSaving()`: capture was interrupted (we keep what was recorded) or writing failed.
    private func saveEndedByItself(_ result: Result<URL, Error>) async {
        isSaving = false
        savingStart = nil
        switch result {
        case .success(let url): await saveToPhotos(url)
        case .failure(let error): message = "Recording failed: \(error.localizedDescription)"
        }
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        if output === videoOutput {
            let isAdjusting = videoDevice.map { $0.isAdjustingWhiteBalance || $0.isAdjustingExposure } ?? false
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            guard settleGate.admit(at: time, isAdjusting: isAdjusting) else { return }
            recorder.handle(video: sampleBuffer)
        } else {
            recorder.handle(audio: sampleBuffer)
        }
    }

    private func saveToPhotos(_ url: URL) async {
        defer { try? FileManager.default.removeItem(at: url) }
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
