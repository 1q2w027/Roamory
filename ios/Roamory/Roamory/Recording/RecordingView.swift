//
//  RecordingView.swift
//  Roamory
//
//  Created by Yifan Liu on 10/23/26.
//

import AVKit
import RoamoryKit
import SwiftUI

struct RecordingView: View {
    /// Back to trip setup, after the trip has ended and the camera stopped.
    let onBackToSetup: () -> Void
    @StateObject private var camera = CameraService()
    @StateObject private var guidedAccess = GuidedAccessMonitor()
    @State private var headphones = HeadphoneButton()
    @State private var pinchStartZoom: CGFloat?
    @State private var dragStartZoom: CGFloat?
    @State private var showDial = false
    @State private var hideDial: Task<Void, Never>?
    @State private var confirmBack = false
    @State private var isLeaving = false
    /// Recording mode: dark until held, and dark again 10 s after the last touch.
    @State private var curtainAwake = false
    @State private var lastTouch = Date()
    @State private var showKeySheet = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session, device: camera.device)
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
                formatBadge
                Spacer()
                if !guidedAccess.isEnabled {
                    guidedAccessHint
                }
                if let summary = camera.summary {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                        .onTapGesture { camera.summary = nil }
                }
                if let message = camera.message {
                    Text(message)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule())
                        .foregroundStyle(.white)
                }
                zoomControl
                HStack(spacing: 12) {
                    saveButton
                    #if DEBUG
                    evaluateButton
                    keyButton
                    #endif
                }
                .padding(.bottom, 32)
            }
        }
        .overlay(alignment: .topLeading) {
            backButton.disabled(isLeaving)
                .padding(.leading, 16)
        }
        .confirmationDialog("Back to trip setup?", isPresented: $confirmBack, titleVisibility: .visible) {
            Button("Back to setup", role: .destructive, action: backToSetup)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Recording stops and this trip ends. Video already saved stays in Photos.")
        }
        .overlay {
            if camera.isReady {
                RecordingCurtain(savingStart: camera.savingStart, awake: $curtainAwake, lastTouch: lastTouch,
                                 paused: confirmBack || showKeySheet)
                    .transition(.opacity)
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in lastTouch = .now })
        .sheet(isPresented: $showKeySheet) { APIKeySheet() }
        // Closing the Back dialog restarts the 10 s countdown rather than going dark at once.
        .onChange(of: confirmBack) { lastTouch = .now }
        // Volume keys and Bluetooth shutter remotes start or stop saving, like the on-screen button.
        .onCameraCaptureEvent { event in
            if event.phase == .ended { camera.toggleSaving() }
        }
        .task {
            // The style picks the format (Reels 9:16, the others 16:9), fixed before capture starts (TRD 4.1).
            let style = TripSettings.style()
            let orientation = (try? StylePresets.bundled()).map { CaptureOrientation(preset: $0[style]) } ?? .portrait
            await camera.prepare(orientation: orientation)
            // AirPods stem press starts or stops saving, like the on-screen button.
            headphones.onPress = { [camera] in camera.toggleSaving() }
            headphones.start()
        }
    }

    /// The recording format, and a nudge when the phone is turned the other way.
    private var formatBadge: some View {
        Text(formatLine)
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.5), in: Capsule())
    }

    private var formatLine: String {
        let landscape = camera.captureOrientation == .landscape
        let format = landscape ? "16:9" : "9:16"
        guard let held = camera.heldAngle, !camera.captureOrientation.isHeld(at: held) else { return format }
        return format + (landscape ? " · Turn the phone sideways" : " · Hold the phone upright")
    }

    private var backButton: some View {
        Button { confirmBack = true } label: {
            Image(systemName: "chevron.left")
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.5), in: Circle())
        }
        .accessibilityLabel("Back to trip setup")
    }

    /// Stops the camera (a save in progress still goes to Photos), then shows setup again.
    private func backToSetup() {
        isLeaving = true
        Task {
            headphones.stop()
            await camera.shutdown()
            onBackToSetup()
        }
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

    /// Saves the buffer and what follows until tapped again. Volume keys, shutter remotes and AirPods do the same.
    private var saveButton: some View {
        Button {
            camera.toggleSaving()
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

    #if DEBUG
    private var evaluateButton: some View {
        // Without a saved API key, ask for one first.
        Button { if APIKeyStore.load() == nil { showKeySheet = true } else { camera.evaluate() } } label: {
            Label(camera.isEvaluating ? "Evaluating…" : "Evaluate", systemImage: "wand.and.sparkles")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.black.opacity(0.5), in: Capsule())
        }
    }

    private var keyButton: some View {
        Button { showKeySheet = true } label: {
            Image(systemName: "key")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.5), in: Circle())
        }
    }
    #endif

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
    RecordingView {}
}
