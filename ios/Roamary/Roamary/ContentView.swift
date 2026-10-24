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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

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
                recordButton
                    .padding(.bottom, 32)
            }
        }
        .task { await camera.prepare() }
    }

    private var guidedAccessHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Turn on Guided Access to keep Roamary in the foreground", systemImage: "lock.open")
                .font(.subheadline.bold())
            Text("One time: Settings > Accessibility > Guided Access > On. Then triple-click the side button in Roamary and tap Start.")
                .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
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
