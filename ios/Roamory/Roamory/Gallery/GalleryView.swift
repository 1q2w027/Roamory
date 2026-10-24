import AVKit
import RoamoryKit
import SwiftUI

/// A video on the phone that the Gallery shows: a finished video or a clip saved during the trip.
struct GalleryItem: Identifiable, Hashable {
    let url: URL
    let title: String
    let date: Date

    var id: URL { url }

    /// Where Roamory Studio's finished video for a trip goes: `Documents/trips/{tripId}/video/{tripId}_{style}.mp4`.
    static func videoURL(tripID: String, style: String) -> URL {
        URL.documentsDirectory
            .appending(path: "trips/\(tripID)/video", directoryHint: .isDirectory)
            .appending(path: "\(tripID)_\(style).mp4")
    }

    /// Every finished video, newest first. A trip made in several styles gives one video per style.
    static func videos() -> [GalleryItem] {
        let trips = URL.documentsDirectory.appending(path: "trips", directoryHint: .isDirectory)
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: trips, includingPropertiesForKeys: nil) else { return [] }
        return folders.flatMap { folder -> [GalleryItem] in
            let video = folder.appending(path: "video", directoryHint: .isDirectory)
            let files = (try? fm.contentsOfDirectory(at: video, includingPropertiesForKeys: [.creationDateKey])) ?? []
            return files.filter { $0.pathExtension == "mp4" }.map { url in
                let name = url.deletingPathExtension().lastPathComponent
                let style = name.split(separator: "_").last.flatMap { Style(rawValue: String($0)) }
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return GalleryItem(url: url, title: style?.title ?? "Highlight", date: date)
            }
        }
        .sorted { $0.date > $1.date }
    }

    /// This trip's saved clips (`TripClips`), newest first.
    static func clips() -> [GalleryItem] {
        TripClips.all().enumerated()
            .map { GalleryItem(url: $1.url, title: "Clip \($0 + 1)", date: $1.recordedAt) }
            .reversed()
    }
}

/// The home tab: the finished videos, then this trip's saved clips, as grids of tall thumbnails. Tapping one plays it.
struct GalleryView: View {
    var onCreate: () -> Void

    @State private var videos: [GalleryItem] = []
    @State private var clips: [GalleryItem] = []
    @State private var playing: GalleryItem?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if videos.isEmpty && clips.isEmpty {
                        emptyState
                    } else {
                        section("Videos", items: videos, empty: "Make a video from the camera screen's film button.")
                        section("Clips", items: clips, empty: "Clips you save while recording show up here.")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            videos = GalleryItem.videos()
            clips = GalleryItem.clips()
        }
        .fullScreenCover(item: $playing) { item in
            VideoPlayerScreen(item: item) { playing = nil }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("YOUR TRIP")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundStyle(Theme.accent2)
            Text(summary)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var summary: String {
        if videos.isEmpty && clips.isEmpty { return "Nothing here yet" }
        return "\(videos.count) video\(videos.count == 1 ? "" : "s") · \(clips.count) clip\(clips.count == 1 ? "" : "s")"
    }

    private func section(_ title: String, items: [GalleryItem], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            if items.isEmpty {
                Text(empty)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(items) { item in
                        Button { playing = item } label: { VideoTile(item: item) }
                            .buttonStyle(PressableStyle(scale: 0.96))
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "film.stack")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(Theme.accentGradient)
                .padding(.top, 60)
            Text("Film a trip and save the moments you love. They'll wait for you here.")
                .font(.body)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            AccentButton(title: "Start a trip", action: onCreate)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }
}

/// A video's first frame, tall like a phone, with its title, date and length.
private struct VideoTile: View {
    let item: GalleryItem
    @State private var thumbnail: UIImage?
    @State private var duration: Double?

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Theme.card)
            .aspectRatio(9 / 14, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else {
                    Image(systemName: "film").font(.title).foregroundStyle(Theme.secondaryText)
                }
            }
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.subheadline.weight(.bold))
                    Text(item.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .opacity(0.75)
                }
                .foregroundStyle(.white)
                .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                if let duration {
                    Label(Self.time(duration), systemImage: "play.fill")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.accentInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.accentGradient, in: Capsule())
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .task(id: item.url) { await load() }
    }

    private func load() async {
        let asset = AVURLAsset(url: item.url)
        duration = try? await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 700)
        if let image = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image {
            thumbnail = UIImage(cgImage: image)
        }
    }

    static func time(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Full-screen playback with Save and Share.
private struct VideoPlayerScreen: View {
    let item: GalleryItem
    var onClose: () -> Void

    @State private var player: AVPlayer
    @State private var saveMessage: String?

    init(item: GalleryItem, onClose: @escaping () -> Void) {
        self.item = item
        self.onClose = onClose
        _player = State(initialValue: AVPlayer(url: item.url))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player).ignoresSafeArea(edges: .horizontal)
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.headline).foregroundStyle(.white).frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Close")
                Spacer()
                Button {
                    Task { saveMessage = await PhotoLibrary.saveVideo(item.url) }
                } label: {
                    Image(systemName: saveMessage == "Saved to Photos" ? "checkmark" : "square.and.arrow.down")
                        .font(.headline).foregroundStyle(.white).frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Save to Photos")
                ShareLink(item: item.url) {
                    Image(systemName: "square.and.arrow.up").font(.headline).foregroundStyle(.white).frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
            }
            .padding(.horizontal, 16)
        }
        .onAppear { player.play() }
        .onDisappear { player.pause() }
    }
}
