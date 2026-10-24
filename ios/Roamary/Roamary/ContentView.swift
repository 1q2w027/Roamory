//
//  ContentView.swift
//  Roamary
//
//  Created by Yifan Liu on 10/23/26.
//

import AVKit
import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraService()
    @StateObject private var guidedAccess = GuidedAccessMonitor()
    @State private var pinchStartZoom: CGFloat?
    @State private var dragStartZoom: CGFloat?
    @State private var showDial = false
    @State private var hideDial: Task<Void, Never>?
    @State private var status: String?

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
                if let message = camera.message ?? status {
                    Text(message)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule())
                        .foregroundStyle(.white)
                }
                zoomControl
                controls
                    .padding(.bottom, 32)
            }
        }
        .task { await camera.prepare() }
        // Volume keys, which Bluetooth shutter remotes send, and Camera Control mark a moment while recording (TRD 7).
        .onCameraCaptureEvent(isEnabled: camera.isRecording) { event in
            if event.phase == .ended { camera.markMoment() }
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: camera.buttonPressesMs.count) { _, new in new > 0 }
        .onChange(of: camera.isRecording) { _, recording in
            if recording { status = nil }
        }
        .onChange(of: camera.finishedRecording) { _, recording in
            guard let recording else { return }
            camera.finishedRecording = nil
            Task {
                status = await PhotoLibrary.saveVideo(recording.url)
                try? FileManager.default.removeItem(at: recording.url)
            }
        }
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

    private var controls: some View {
        ZStack {
            recordButton
            if camera.isRecording {
                HStack {
                    Spacer()
                    markButton
                }
                .padding(.horizontal, 32)
            }
        }
    }

    /// The on-screen stand-in for the Bluetooth button; the badge counts this recording's marks.
    private var markButton: some View {
        Button { camera.markMoment() } label: {
            Image(systemName: "star.fill")
                .font(.title2)
                .foregroundStyle(.yellow)
                .frame(width: 56, height: 56)
                .background(.black.opacity(0.5), in: Circle())
                .overlay(alignment: .topTrailing) {
                    if !camera.buttonPressesMs.isEmpty {
                        Text("\(camera.buttonPressesMs.count)")
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.yellow, in: Capsule())
                    }
                }
        }
        .accessibilityLabel("Mark moment")
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
