//
//  DirectorLogSheet.swift
//  Roamory
//

#if DEBUG
import SwiftUI

/// Debug only: every director request, newest first, with the frames it sent, the model's JSON, and how long the call took.
struct DirectorLogSheet: View {
    @ObservedObject var log: DirectorLog
    @Environment(\.dismiss) private var dismiss
    @State private var exported: URL?
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            Group {
                if log.entries.isEmpty {
                    ContentUnavailableView("No requests yet", systemImage: "film",
                                           description: Text("The director sends its first one \(Int(Director.interval)) s after the camera starts."))
                } else {
                    List(log.entries) { entry in
                        NavigationLink { DirectorEntryView(entry: entry) } label: { row(entry) }
                    }
                }
            }
            .navigationTitle("Director log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { export() } label: { Image(systemName: "square.and.arrow.up") }
                        .disabled(log.entries.isEmpty)
                        .accessibilityLabel("Export log")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: Binding(get: { exported != nil }, set: { if !$0 { exported = nil } })) {
                if let exported { ActivityView(url: exported) }
            }
            .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK") {}
            } message: {
                Text(exportError ?? "")
            }
        }
    }

    /// Zips the log with its frames and offers it to the share sheet.
    private func export() {
        do { exported = try log.exportArchive() } catch { exportError = error.localizedDescription }
    }

    private func row(_ entry: DirectorLog.Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.time, format: .dateTime.hour().minute().second())
                    .font(.footnote.monospacedDigit())
                Spacer()
                Text(String(format: "%.1f s", entry.seconds))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let decision = entry.decision {
                Text("\(decision.action.rawValue.uppercased()) · \(entry.applied ?? "")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(decision.action == .save ? .green : .primary)
                Text(decision.why).font(.footnote).foregroundStyle(.secondary)
            } else {
                Text(entry.error ?? "No answer").font(.footnote).foregroundStyle(.red)
            }
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct DirectorEntryView: View {
    let entry: DirectorLog.Entry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("Result") {
                    if let decision = entry.decision {
                        line("Action", decision.action.rawValue)
                        line("Summary", decision.summary)
                        line("Why", decision.why)
                        line("Applied", entry.applied ?? "")
                    }
                    if let error = entry.error { Text(error).foregroundStyle(.red) }
                    line("API call", String(format: "%.2f s", entry.seconds))
                    if let usage = entry.usage {
                        line("Tokens", "in \(usage.input) · out \(usage.output) · cache read \(usage.cacheRead) · cache write \(usage.cacheWrite)")
                    }
                }
                section("Frames sent (\(entry.frames.count))") {
                    ForEach(Array(entry.frames.enumerated()), id: \.offset) { k, jpeg in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Frame \(k + 1) · \(jpeg.count / 1024) KB").font(.caption).foregroundStyle(.secondary)
                            if let image = UIImage(data: jpeg) {
                                Image(uiImage: image).resizable().scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
                section("Prompt") { Text(entry.prompt).font(.footnote) }
                if let raw = entry.raw { section("Raw reply") { Text(raw).font(.footnote.monospaced()) } }
                section("System prompt") { Text(entry.system).font(.footnote) }
            }
            .textSelection(.enabled)
            .padding()
        }
        .navigationTitle(Text(entry.time, format: .dateTime.hour().minute().second()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
        }
    }
}
#endif
