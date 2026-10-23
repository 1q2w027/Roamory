//
//  CameraService.swift
//  Roamary
//

import AVFoundation
import Combine
import Photos

/// Owns the capture session; records one movie file at a time and saves it to Photos.
final class CameraService: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var recordingStart: Date?
    @Published private(set) var message: String?

    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated(unsafe) private let movieOutput = AVCaptureMovieFileOutput()
    nonisolated private let sessionQueue = DispatchQueue(label: "roamary.camera.session")

    /// Asks for camera permission, then configures and starts the session.
    func prepare() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            message = "需要相机权限，请在设置中开启"
            return
        }
        let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            sessionQueue.async {
                let ok = self.configure()
                if ok { self.session.startRunning() }
                cont.resume(returning: ok)
            }
        }
        if !ok { message = "无法打开后置摄像头" }
    }

    nonisolated private func configure() -> Bool {
        guard !session.isRunning, session.inputs.isEmpty else { return true }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(movieOutput) else { return false }
        session.addInput(input)
        session.addOutput(movieOutput)
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
            if failed {
                message = "录制失败：\(error?.localizedDescription ?? "未知错误")"
                try? FileManager.default.removeItem(at: outputFileURL)
            } else {
                await saveToPhotos(outputFileURL)
            }
        }
    }

    private func saveToPhotos(_ url: URL) async {
        defer { try? FileManager.default.removeItem(at: url) }
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized else {
            message = "需要相册权限才能保存视频"
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            message = "已保存到相册"
        } catch {
            message = "保存失败：\(error.localizedDescription)"
        }
    }
}
