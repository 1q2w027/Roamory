//
//  CameraService.swift
//  Roamary
//

import AVFoundation
import Combine
import Photos
import UIKit

/// Owns the capture session; records one movie file at a time and saves it to Photos.
final class CameraService: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var recordingStart: Date?
    @Published private(set) var message: String?
    /// Zoom as shown to the user: 1 is the main camera, 0.5 the ultra-wide (when the device has one).
    @Published private(set) var zoomFactor: CGFloat = 1
    @Published private(set) var minZoom: CGFloat = 1
    @Published private(set) var maxZoom: CGFloat = 1
    /// Quick-select zoom levels, including the points where the system switches lenses.
    @Published private(set) var zoomPresets: [CGFloat] = []

    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated(unsafe) private let movieOutput = AVCaptureMovieFileOutput()
    nonisolated(unsafe) private var videoDevice: AVCaptureDevice?
    /// displayZoom = videoZoomFactor * multiplier. A virtual multi-camera starts at the ultra-wide, so this is 0.5 there.
    nonisolated(unsafe) private var zoomMultiplier: CGFloat = 1
    nonisolated private let sessionQueue = DispatchQueue(label: "roamary.camera.session")
    /// Digital zoom beyond this looks too soft to be useful.
    private let zoomLimit: CGFloat = 10

    /// Asks for camera permission, then configures and starts the session.
    func prepare() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            message = "Camera access is required. Enable it in Settings."
            return
        }
        // Microphone is optional: without it we still record video.
        let hasMic = await AVCaptureDevice.requestAccess(for: .audio)
        if !hasMic { message = "Microphone access is off. The video will have no sound." }
        let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            sessionQueue.async {
                let ok = self.configure()
                if ok { self.session.startRunning() }
                cont.resume(returning: ok)
            }
        }
        if !ok { message = "Unable to open the rear camera." }
        if let device = videoDevice {
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

    nonisolated private func configure() -> Bool {
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
              session.canAddOutput(movieOutput) else { return false }
        session.addInput(input)
        session.addOutput(movieOutput)
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
           session.canAddInput(micInput) {
            session.addInput(micInput)
        }
        return true
    }

    func startRecording() {
        guard !isRecording else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        message = nil
        sessionQueue.async {
            // The UI is portrait only; rotate the file to match.
            if let connection = self.movieOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
        isRecording = true
        recordingStart = Date()
        // Keep the screen from auto-locking, which would suspend the camera.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stopRecording() {
        guard isRecording else { return }
        sessionQueue.async { self.movieOutput.stopRecording() }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        // AVFoundation reports some errors (e.g. disk nearly full) after a usable file was written.
        let finished = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool
        let failed = error != nil && finished != true
        Task { @MainActor in
            isRecording = false
            recordingStart = nil
            UIApplication.shared.isIdleTimerDisabled = false
            if failed {
                message = "Recording failed: \(error?.localizedDescription ?? "unknown error")"
                try? FileManager.default.removeItem(at: outputFileURL)
            } else {
                await saveToPhotos(outputFileURL)
            }
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
