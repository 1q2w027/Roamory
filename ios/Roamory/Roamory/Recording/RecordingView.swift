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
    /// Off for debugging: no dark curtain, so the screen keeps its brightness and the camera UI takes touches.
    private static let curtainEnabled = false
    @State private var showSettings = false
    @State private var showStudio = false
    @State private var showFrames = false
    /// The mount level: shown when the camera opens, gone once the phone is level, back from the level button.
    @StateObject private var level = LevelMonitor()
    @State private var showLevel = false
    @State private var fadeLevel: Task<Void, Never>?
    /// Compact height: the interface is landscape (a 16:9 trip, see `OrientationLock`).
    @Environment(\.verticalSizeClass) private var verticalSizeClass

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

            if showLevel {
                LevelOverlay(pose: level.pose, isLevel: level.isLevel, bubbleRangeDeg: level.bubbleRangeDeg,
                             toleranceDeg: level.toleranceDeg, aimToleranceDeg: level.aimToleranceDeg)
                    .transition(.opacity)
            }

            if verticalSizeClass == .compact {
                landscapeChrome
            } else {
                portraitChrome
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
            // The level must be visible while it shows, so the curtain waits until it is gone.
            if Self.curtainEnabled, camera.isReady, !showLevel {
                RecordingCurtain(savingStart: camera.savingStart, awake: $curtainAwake, lastTouch: lastTouch,
                                 paused: confirmBack || showSettings || showStudio || showFrames || showLevel)
                    .transition(.opacity)
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in lastTouch = .now })
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .sheet(isPresented: $showStudio) { StudioSheet() }
        .sheet(isPresented: $showFrames) {
            if let evaluation = camera.evaluation { SentFramesSheet(evaluation: evaluation) }
        }
        // Closing the Back dialog restarts the 10 s countdown rather than going dark at once.
        .onChange(of: confirmBack) { lastTouch = .now }
        .onChange(of: showLevel) { _, on in
            if on, let angle = camera.captureRotationAngle { level.start(captureAngle: angle) } else { level.stop() }
        }
        // Once level, the level stays a moment and fades; leaving level again (a warning) keeps it up.
        .onChange(of: level.isLevel) { _, isLevel in
            fadeLevel?.cancel()
            guard isLevel else { return }
            fadeLevel = Task {
                try? await Task.sleep(for: .seconds(level.fadeDelay))
                if !Task.isCancelled { withAnimation { showLevel = false } }
            }
        }
        .onDisappear {
            level.stop()
            OrientationLock.set(.portrait)
        }
        // Volume keys and Bluetooth shutter remotes start or stop saving, like the on-screen button.
        .onCameraCaptureEvent { event in
            if event.phase == .ended { camera.toggleSaving() }
        }
        .task {
            // The style picks the format (Reels 9:16, the others 16:9), fixed before capture starts (TRD 4.1).
            let style = TripSettings.style()
            let orientation = (try? StylePresets.bundled()).map { CaptureOrientation(preset: $0[style]) } ?? .portrait
            await camera.prepare(orientation: orientation)
            // A 16:9 trip lays the screen out in landscape, turned to the side the camera records.
            if let angle = camera.captureRotationAngle {
                OrientationLock.set(CaptureOrientation.interfaceSide(forCaptureAngle: angle))
            }
            // Level the phone on its mount first; the buffer is already recording.
            if hasLevel { showLevel = true }
            // AirPods stem press starts or stops saving, like the on-screen button.
            headphones.onPress = { [camera] in camera.toggleSaving() }
            headphones.start()
        }
    }

    /// An upright phone (Reels): status at the top, buttons along the bottom.
    private var portraitChrome: some View {
        VStack {
            savingTimer
            formatBadge
            Spacer()
            // Cards would cover the level, so they wait until it is gone.
            if !showLevel {
                if !guidedAccess.isEnabled {
                    guidedAccessHint
                }
                summaryCard
            }
            messageText
            zoomControl
            // The debug buttons sit top right: one row of all five is wider than the phone.
            HStack(spacing: 12) {
                saveButton
                studioButton
                if hasLevel { levelButton }
            }
            .padding(.bottom, 32)
        }
        #if DEBUG
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                evaluateButton
                settingsButton
            }
            .padding(.trailing, 16)
        }
        #endif
    }

    /// A phone on its side (16:9): status and debug buttons top left, the zoom presets and the main buttons in
    /// columns along the right edge (one column of everything is taller than a landscape phone).
    private var landscapeChrome: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    savingTimer
                    formatBadge
                    #if DEBUG
                    evaluateButton
                    settingsButton
                    #endif
                }
                .padding(.leading, 60)
                Spacer()
                // Cards would cover the level, so they wait until it is gone.
                if !showLevel {
                    if !guidedAccess.isEnabled {
                        guidedAccessHint.frame(maxWidth: 420)
                    }
                    summaryCard.frame(maxWidth: 420, alignment: .leading)
                }
                messageText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                zoomColumn
                VStack(spacing: 12) {
                    if hasLevel { levelButton }
                    saveButton
                    studioButton
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.trailing, 16)
    }

    @ViewBuilder
    private var savingTimer: some View {
        if let start = camera.savingStart {
            TimelineView(.periodic(from: start, by: 1)) { context in
                Label(timeString(context.date.timeIntervalSince(start)), systemImage: "circle.fill")
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.5), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var summaryCard: some View {
        if let summary = camera.summary {
            VStack(alignment: .leading, spacing: 8) {
                Text(summary)
                if let evaluation = camera.evaluation {
                    Button { showFrames = true } label: {
                        Label("View the \(evaluation.frames.count) frames sent", systemImage: "photo.on.rectangle")
                            .font(.footnote.weight(.semibold))
                    }
                }
            }
                .font(.callout)
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .onTapGesture { camera.summary = nil }
        }
    }

    @ViewBuilder
    private var messageText: some View {
        if let message = camera.message {
            Text(message)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.5), in: Capsule())
                .foregroundStyle(.white)
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
            showLevel = false
            level.stop()
            await camera.shutdown()
            OrientationLock.set(.portrait)
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
        let activeIndex = activeZoomIndex
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
                zoomPresetButton(z, isActive: index == activeIndex, size: sizes[index])
            }
        }
        .offset(x: total / 2 - activeCenter)
        .frame(maxWidth: .infinity, minHeight: 44)
        .animation(.easeInOut(duration: 0.15), value: activeIndex)
    }

    /// The lens buttons in a column, for the landscape layout; no rotary dial there (pinch still zooms).
    private var zoomColumn: some View {
        let activeIndex = activeZoomIndex
        return VStack(spacing: 8) {
            ForEach(Array(camera.zoomPresets.enumerated()), id: \.offset) { index, z in
                zoomPresetButton(z, isActive: index == activeIndex, size: index == activeIndex ? 44 : 36)
            }
        }
        .sensoryFeedback(.selection, trigger: activeIndex)
        .animation(.easeInOut(duration: 0.15), value: activeIndex)
    }

    private var activeZoomIndex: Int {
        camera.zoomPresets.lastIndex { $0 <= camera.zoomFactor + 0.05 } ?? 0
    }

    /// One lens button; the active one shows the live value.
    private func zoomPresetButton(_ zoom: CGFloat, isActive: Bool, size: CGFloat) -> some View {
        Button { camera.setZoom(zoom) } label: {
            Text(isActive ? ZoomDial.label(camera.zoomFactor) + "x" : String(format: "%g", zoom))
                .font(.footnote.bold().monospacedDigit())
                .foregroundStyle(isActive ? .yellow : .white)
                .frame(width: size, height: size)
                .background(.black.opacity(0.5), in: Circle())
        }
    }

    /// Saves the buffer and what follows until tapped again. Volume keys, shutter remotes and AirPods do the same.
    private var saveButton: some View {
        Button {
            camera.toggleSaving()
        } label: {
            Label(camera.isSaving ? "Stop saving" : "Save buffer",
                  systemImage: camera.isSaving ? "stop.fill" : "record.circle")
                .font(.headline)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(camera.isSaving ? .red : .black.opacity(0.5), in: Capsule())
        }
        .animation(.easeInOut(duration: 0.15), value: camera.isSaving)
    }

    /// Make video: Claude Code on a Mac running Roamory Studio edits this trip's clips.
    private var studioButton: some View {
        Button { showStudio = true } label: {
            Image(systemName: "film.stack")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.5), in: Circle())
        }
        .accessibilityLabel("Make video")
    }

    /// The mount level needs a motion sensor and the angle the session records at.
    private var hasLevel: Bool { level.isAvailable && camera.captureRotationAngle != nil }

    /// Shows the mount level again, for when the mount slips, or closes it.
    private var levelButton: some View {
        Button { withAnimation { showLevel.toggle() } } label: {
            Image(systemName: "level")
                .font(.headline)
                .foregroundStyle(showLevel ? .black : .white)
                .padding(12)
                .background(showLevel ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.black.opacity(0.5)), in: Circle())
        }
        .accessibilityLabel(showLevel ? "Close the level" : "Level the phone")
    }

    #if DEBUG
    private var evaluateButton: some View {
        // If the chosen model is not ready (no API key, Apple Intelligence off), open settings first.
        Button { if SummarySettings.isReady { camera.evaluate() } else { showSettings = true } } label: {
            Label(camera.isEvaluating ? "Evaluating…" : "Evaluate", systemImage: "wand.and.sparkles")
                .font(.headline)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.black.opacity(0.5), in: Capsule())
        }
    }

    private var settingsButton: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape")
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
