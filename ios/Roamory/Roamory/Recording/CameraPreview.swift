//
//  CameraPreview.swift
//  Roamory
//

import AVFoundation
import SwiftUI

/// Live camera feed backed by AVCaptureVideoPreviewLayer. The preview follows how the phone is held (a
/// `RotationCoordinator`), so it stays level whether the interface is portrait or turned landscape for a 16:9 style.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// The camera, once configured; until then the preview is upright for a portrait phone.
    var device: AVCaptureDevice?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        view.follow(device)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.follow(device)
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        private var coordinator: AVCaptureDevice.RotationCoordinator?
        private var observation: NSKeyValueObservation?

        /// Starts keeping the preview level for `device`; once per device.
        func follow(_ device: AVCaptureDevice?) {
            guard let device, coordinator?.device != device else { return }
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            self.coordinator = coordinator
            observation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] c, _ in
                let angle = c.videoRotationAngleForHorizonLevelPreview
                Task { @MainActor [weak self] in
                    guard let connection = self?.previewLayer.connection, connection.isVideoRotationAngleSupported(angle) else { return }
                    connection.videoRotationAngle = angle
                }
            }
        }
    }
}
