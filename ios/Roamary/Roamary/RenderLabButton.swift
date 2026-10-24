import SwiftUI
#if DEBUG
import CoreTransferable
import PhotosUI
import RoamoryKit
import UniformTypeIdentifiers
#endif

extension View {
    /// Debug builds get a corner menu: Render Lab, to try the on-phone and laptop renderers, and a video from
    /// Photos run through the whole trip pipeline in place of a recording (replay mode, TRD 12.4).
    func renderLabButton() -> some View {
        #if DEBUG
        modifier(RenderLabButton())
        #else
        self
        #endif
    }
}

#if DEBUG
private struct RenderLabButton: ViewModifier {
    @State private var showLab = false
    @State private var showPicker = false
    @State private var picked: PhotosPickerItem?
    @State private var trip: TripPipeline?
    @State private var loadError: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                Menu {
                    Button("Render Lab", systemImage: "film.stack") { showLab = true }
                    Button("Make video from Photos", systemImage: "photo.on.rectangle") { showPicker = true }
                } label: {
                    Image(systemName: "film.stack")
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .padding(.trailing, 16)
            }
            .sheet(isPresented: $showLab) {
                NavigationStack { RenderLabView() }
            }
            .photosPicker(isPresented: $showPicker, selection: $picked, matching: .videos)
            .onChange(of: picked) { _, item in
                guard let item else { return }
                picked = nil
                Task { await start(item) }
            }
            .fullScreenCover(isPresented: Binding(get: { trip != nil }, set: { if !$0 { trip = nil } })) {
                if let trip {
                    TripFlowView(pipeline: trip) { self.trip = nil }
                }
            }
            .alert("Could not load the video", isPresented: Binding(get: { loadError != nil }, set: { if !$0 { loadError = nil } })) {
                Button("OK") {}
            } message: {
                Text(loadError ?? "")
            }
    }

    /// A picked video has no marks, so its moments come from detection alone; demo footage wants cloud analysis on.
    private func start(_ item: PhotosPickerItem) async {
        do {
            guard let video = try await item.loadTransferable(type: PickedVideo.self) else {
                loadError = "Photos returned no file."
                return
            }
            let pipeline = TripPipeline(settings: TripSettings.load())
            trip = pipeline
            await pipeline.start(video: video.url)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// A video from Photos, copied to a temporary file the pipeline then moves into the trip folder.
private struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let copy = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString).appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedVideo(url: copy)
        }
    }
}
#endif
