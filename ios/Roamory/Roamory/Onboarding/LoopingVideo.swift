import AVFoundation
import SwiftUI

/// A muted clip that loops forever. One player can be shown by several `LoopingVideo`s, so a card keeps playing while
/// it moves between the grid and fullscreen.
final class LoopingPlayer {
    let player = AVQueuePlayer()
    private let looper: AVPlayerLooper

    init(url: URL) {
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.isMuted = true
        player.play()
    }
}

struct LoopingVideo: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
