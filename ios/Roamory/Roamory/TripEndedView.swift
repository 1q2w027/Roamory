//
//  TripEndedView.swift
//  Roamory
//

import RoamoryKit
import SwiftUI

/// After End trip: the trip's clips, each with its Stage 2 fields, ready for editing.
///
/// Video generation (Ian) starts here: `EditCoordinator(trip: trip, clips: clips,
/// outputDirectory: folder.appending(path: "video"), presets: try .bundled(), config: try .bundled(), service: …)`.
struct TripEndedView: View {
    let trip: TripContext
    let folder: URL
    let clips: [ClipInfo]
    let onDone: () -> Void

    var body: some View {
        List {
            Section {
                Text("\(clips.count) clips ready").font(.headline)
                Text("\(trip.style.rawValue.capitalized) · \([trip.destination.city, trip.destination.country].compactMap { $0 }.joined(separator: ", "))")
                Text(trip.tripId).font(.caption).foregroundStyle(.secondary)
            }
            if clips.isEmpty {
                Text("No moments were kept on this trip.")
            } else {
                Section("Moments") {
                    ForEach(clips) { clip in
                        HStack(alignment: .top, spacing: 8) {
                            Text(clip.isButton ? "●" : "○")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(clip.description ?? "No description")
                                Text(details(clip)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Trip ended")
        .toolbar { Button("Done", action: onDone) }
    }

    private func details(_ clip: ClipInfo) -> String {
        [clip.eventType?.rawValue, clip.score.map { String(format: "%.2f", $0) }, String(format: "%.1f s", clip.durationS)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
