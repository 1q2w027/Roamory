//
//  ContentView.swift
//  Roamary
//
//  Created by Yifan Liu on 10/23/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraService()
    @StateObject private var guidedAccess = GuidedAccessMonitor()
    @State private var pinchStartZoom: CGFloat?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let start = pinchStartZoom ?? camera.zoomFactor
                            pinchStartZoom = start
                            camera.setZoom(start * value.magnification)
                        }
                        .onEnded { _ in pinchStartZoom = nil }
                )

            VStack {
                if let start = camera.recordingStart {
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        Label(timeString(context.date.timeIntervalSince(start)), systemImage: "circle.fill")
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.5), in: Capsule())
                    }
                }
                Spacer()
                if !guidedAccess.isEnabled {
                    guidedAccessHint
                }
                if let message = camera.message {
                    Text(message)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule())
                        .foregroundStyle(.white)
                }
                zoomControl
                recordButton
                    .padding(.bottom, 32)
            }
        }
        .task { await camera.prepare() }
    }

    private var guidedAccessHint: some View {
        VStack(spacing: 4) {
            Label("Turn on Guided Access to keep Roamary in the foreground", systemImage: "lock.open")
                .font(.subheadline.bold())
            Text("One time: Settings > Accessibility > Guided Access > On. Then triple-click the side button in Roamary and tap Start.")
                .font(.caption)
            TripleClickGuide()
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Like the system Camera app: the preset the current zoom falls under shows the live value.
    private var zoomControl: some View {
        let active = camera.zoomPresets.last { $0 <= camera.zoomFactor + 0.05 } ?? camera.zoomPresets.first
        return HStack(spacing: 8) {
            ForEach(camera.zoomPresets, id: \.self) { z in
                let isActive = z == active
                Button { camera.setZoom(z) } label: {
                    Text(isActive ? zoomLabel(camera.zoomFactor) + "x" : String(format: "%g", z))
                        .font(.footnote.bold().monospacedDigit())
                        .foregroundStyle(isActive ? .yellow : .white)
                        .frame(width: isActive ? 44 : 36, height: isActive ? 44 : 36)
                        .background(.black.opacity(0.5), in: Circle())
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: active)
        .padding(.bottom, 12)
    }

    /// "1" at a whole step, otherwise one decimal ("1.7").
    private func zoomLabel(_ zoom: CGFloat) -> String {
        let rounded = (zoom * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(format: "%.0f", rounded) : String(format: "%.1f", rounded)
    }

    private var recordButton: some View {
        Button {
            camera.isRecording ? camera.stopRecording() : camera.startRecording()
        } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 72, height: 72)
                RoundedRectangle(cornerRadius: camera.isRecording ? 6 : 30)
                    .fill(.red)
                    .frame(width: camera.isRecording ? 30 : 60, height: camera.isRecording ? 30 : 60)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: camera.isRecording)
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

#Preview {
    ContentView()
}
