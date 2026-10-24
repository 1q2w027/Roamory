import AVKit
import RoamoryKit
import SwiftUI

/// A finished highlight video on the phone: `Documents/trips/{tripId}/video/{tripId}_{style}.mp4`.
struct Reel: Identifiable, Hashable {
    let url: URL
    let style: Style?
    let createdAt: Date

    var id: URL { url }

    /// Every rendered video, newest first. A trip rendered in several styles gives one reel per style.
    static func loadAll() -> [Reel] {
        let trips = URL.documentsDirectory.appending(path: "trips", directoryHint: .isDirectory)
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: trips, includingPropertiesForKeys: nil) else { return [] }
        return folders.flatMap { folder -> [Reel] in
            let video = folder.appending(path: "video", directoryHint: .isDirectory)
            let files = (try? fm.contentsOfDirectory(at: video, includingPropertiesForKeys: [.creationDateKey])) ?? []
            return files.filter { $0.pathExtension == "mp4" }.map { url in
                let name = url.deletingPathExtension().lastPathComponent
                let style = name.split(separator: "_").last.flatMap { Style(rawValue: String($0)) }
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return Reel(url: url, style: style, createdAt: date)
            }
        }
        .sorted { $0.createdAt > $1.createdAt }
    }
}

/// The home tab: the reels made so far as a grid of tall thumbnails, like a profile page. Tapping one plays it.
struct GalleryView: View {
    var onCreate: () -> Void

    @State private var reels: [Reel] = []
    @State private var playing: Reel?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if reels.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                                  spacing: 10) {
                            ForEach(reels) { reel in
                                Button { playing = reel } label: { ReelTile(reel: reel) }
                                    .buttonStyle(PressableStyle(scale: 0.96))
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .onAppear { reels = Reel.loadAll() }
        .fullScreenCover(item: $playing) { reel in
            ReelPlayer(reel: reel) { playing = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR REELS")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .tracking(2)
                    .foregroundStyle(Theme.accent2)
                Text(reels.isEmpty ? "Nothing here yet" : "\(reels.count) highlight\(reels.count == 1 ? "" : "s")")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            RoamyMascot(mood: .happy, size: 54)
                .frame(width: 76, height: 66)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            RoamyMascot(mood: .sleepy, size: 130)
                .padding(.top, 40)
            Text("Your highlight reels will live here")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Film a trip and I'll cut the best moments into a video for you.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            AccentButton(title: "Create my first reel", action: onCreate)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }
}

/// A reel's first frame, tall like a phone, with its style and length.
private struct ReelTile: View {
    let reel: Reel
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
                    Text(reel.style?.title ?? "Highlight")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                    Text(reel.createdAt, format: .dateTime.month(.abbreviated).day())
                        .font(.system(.caption, design: .rounded))
                        .opacity(0.75)
                }
                .foregroundStyle(.white)
                .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                if let duration {
                    Label(Self.time(duration), systemImage: "play.fill")
                        .font(.system(.caption2, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.accentInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.accent, in: Capsule())
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .task(id: reel.url) { await load() }
    }

    private func load() async {
        let asset = AVURLAsset(url: reel.url)
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
private struct ReelPlayer: View {
    let reel: Reel
    var onClose: () -> Void

    @State private var player: AVPlayer
    @State private var saveMessage: String?

    init(reel: Reel, onClose: @escaping () -> Void) {
        self.reel = reel
        self.onClose = onClose
        _player = State(initialValue: AVPlayer(url: reel.url))
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
                    Task { saveMessage = await PhotoLibrary.saveVideo(reel.url) }
                } label: {
                    Image(systemName: saveMessage == "Saved to Photos" ? "checkmark" : "square.and.arrow.down")
                        .font(.headline).foregroundStyle(.white).frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Save to Photos")
                ShareLink(item: reel.url) {
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
