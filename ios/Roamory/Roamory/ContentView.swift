//
//  ContentView.swift
//  Roamory
//
//  Created by Yifan Liu on 10/23/26.
//

import AVKit
import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraService()
    @StateObject private var guidedAccess = GuidedAccessMonitor()
    @StateObject private var detection = DetectionController()
    @State private var showDetectionSettings = false
    @State private var pinchStartZoom: CGFloat?
    @State private var dragStartZoom: CGFloat?
    @State private var showDial = false
    @State private var hideDial: Task<Void, Never>?

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
                if let start = camera.savingStart {
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        Label(timeString(context.date.timeIntervalSince(start)), systemImage: "circle.fill")
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.5), in: Capsule())
                    }
                }
                if detection.isRunning {
                    detectionStatus
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
                #if DEBUG
                debugSaveButton
                    .overlay(alignment: .trailing) {
                        if detection.isRunning { keepMomentButton.offset(x: 96) }
                    }
                    .padding(.bottom, 32)
                #endif
            }
        }
        .overlay(alignment: .topLeading) { detectionSettingsButton }
        .sheet(isPresented: $showDetectionSettings, onDismiss: {
            // Detection reads its settings when it starts, so a changed setting needs a restart.
            Task {
                await detection.stop()
                detection.start(.current(), recorder: camera.recorder)
            }
        }) {
            NavigationStack { DetectionSettingsView(backend: detection.backend) }
        }
        // Volume keys and Bluetooth shutter remotes (TRD §7) keep the current moment.
        .onCameraCaptureEvent { event in
            if event.phase == .ended { detection.buttonPressed() }
        }
        // Detection runs for as long as the camera does, like the buffer.
        .onChange(of: camera.isReady) { _, ready in
            if ready { detection.start(.current(), recorder: camera.recorder) }
        }
        .task {
            camera.frameInterval = detection.frameInterval
            let sink = detection.sink
            camera.onFrame = { sink.handle($0) }
            await camera.prepare()
        }
    }

    /// Detection status while recording: holds, then what was kept and released.
    private var detectionStatus: some View {
        let s = detection.summary
        return VStack(spacing: 2) {
            Text("Holds \(s.holds) · kept \(s.keptAI + s.keptButton + s.keptFallback) · released \(s.released) · saved \(s.saved)\(s.saveFailed > 0 ? " · \(s.saveFailed) failed" : "")\(s.cloud ? "" : " · offline")")
                .font(.caption.monospacedDigit())
            if let last = s.lastDescription {
                Text(last).font(.caption2).lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.5), in: Capsule())
    }

    /// Keeps the current moment, like the Bluetooth button.
    private var keepMomentButton: some View {
        Button { detection.buttonPressed() } label: {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.black.opacity(0.5), in: Circle())
        }
        .accessibilityLabel("Keep this moment")
    }

    private var detectionSettingsButton: some View {
        Button { showDetectionSettings = true } label: {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.5), in: Circle())
        }
        .padding(.leading, 16)
        .accessibilityLabel("Moment detection settings")
    }

    private var guidedAccessHint: some View {
        VStack(spacing: 4) {
            Label("Turn on Guided Access to keep Roamory in the foreground", systemImage: "lock.open")
                .font(.subheadline.bold())
            Text("One time: Settings > Accessibility > Guided Access > On. Then triple-click the side button in Roamory and tap Start.")
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

    /// Like the system Camera app: a row of lens buttons that turns into a rotary dial while you swipe on it.
    private var zoomControl: some View {
        let activeIndex = camera.zoomPresets.lastIndex { $0 <= camera.zoomFactor + 0.05 } ?? 0
        return ZStack(alignment: .bottom) {
            zoomPicker(activeIndex: activeIndex)
                .opacity(showDial ? 0 : 1)
                .allowsHitTesting(!showDial)
            ZoomDial(zoom: camera.zoomFactor, minZoom: camera.minZoom, maxZoom: camera.maxZoom,
                     presets: camera.zoomPresets)
                .opacity(showDial ? 1 : 0)
        }
        .frame(height: ZoomDial.height, alignment: .bottom)
        // Only the picker (or the whole dial while it shows) takes touches; the rest passes through to pinch.
        .contentShape(BottomStrip(height: showDial ? ZoomDial.height : 44))
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    hideDial?.cancel()
                    showDial = true
                    let start = dragStartZoom ?? camera.zoomFactor
                    dragStartZoom = start
                    // Swipe left to zoom in.
                    camera.setZoom(start * pow(2, -value.translation.width / ZoomDial.pointsPerDoubling))
                }
                .onEnded { _ in
                    dragStartZoom = nil
                    hideDial = Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        if !Task.isCancelled { showDial = false }
                    }
                }
        )
        .animation(.easeInOut(duration: 0.2), value: showDial)
        .sensoryFeedback(.selection, trigger: activeIndex)
        .padding(.bottom, 12)
    }

    /// The active lens button stays centered and shows the live value.
    private func zoomPicker(activeIndex: Int) -> some View {
        let presets = camera.zoomPresets
        let spacing: CGFloat = 8
        let sizes: [CGFloat] = presets.indices.map { $0 == activeIndex ? 44 : 36 }
        let total = sizes.reduce(0, +) + spacing * CGFloat(max(presets.count - 1, 0))
        let activeCenter = sizes.isEmpty ? 0
            : sizes.prefix(activeIndex).reduce(0, +) + spacing * CGFloat(activeIndex) + sizes[activeIndex] / 2
        return HStack(spacing: spacing) {
            ForEach(Array(presets.enumerated()), id: \.offset) { index, z in
                let isActive = index == activeIndex
                Button { camera.setZoom(z) } label: {
                    Text(isActive ? ZoomDial.label(camera.zoomFactor) + "x" : String(format: "%g", z))
                        .font(.footnote.bold().monospacedDigit())
                        .foregroundStyle(isActive ? .yellow : .white)
                        .frame(width: sizes[index], height: sizes[index])
                        .background(.black.opacity(0.5), in: Circle())
                }
            }
        }
        .offset(x: total / 2 - activeCenter)
        .frame(maxWidth: .infinity, minHeight: 44)
        .animation(.easeInOut(duration: 0.15), value: activeIndex)
    }

    /// Stand-in for the trigger that will come from the agent: saves the buffer and what follows until tapped again.
    private var debugSaveButton: some View {
        Button {
            camera.isSaving ? camera.stopSaving() : camera.startSaving()
        } label: {
            Label(camera.isSaving ? "Stop saving" : "Save buffer",
                  systemImage: camera.isSaving ? "stop.fill" : "record.circle")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(camera.isSaving ? .red : .black.opacity(0.5), in: Capsule())
        }
        .animation(.easeInOut(duration: 0.15), value: camera.isSaving)
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// A full-width strip along the bottom of its container, used to limit where a view takes touches.
private struct BottomStrip: Shape {
    var height: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.maxY - height, width: rect.width, height: height))
    }
}

#Preview {
    ContentView()
}
