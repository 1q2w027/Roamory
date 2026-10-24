//
//  HeadphoneButton.swift
//  Roamory
//

import AVFoundation
import MediaPlayer
import UIKit

/// A press on the AirPods stem (or any Bluetooth headphone's play/pause button) calls `onPress`.
/// iOS only sends those presses to the Now Playing app, so while headphones are connected we play silence
/// and take the media remote commands. With no headphones connected nothing is held.
@MainActor
final class HeadphoneButton {
    var onPress: (() -> Void)?

    private var player: AVAudioPlayer?
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var routeObserver: NSObjectProtocol?

    /// Starts watching the audio route. `CameraService.prepare()` sets up the audio session.
    func start() {
        guard routeObserver == nil else { return }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        update()
    }

    func update() {
        if headphonesConnected { listen() } else { stopListening() }
    }

    private var headphonesConnected: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains {
            [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0.portType)
        }
    }

    private func listen() {
        guard commandTargets.isEmpty else { return }
        if player == nil {
            player = try? AVAudioPlayer(data: Self.silence)
            player?.numberOfLoops = -1
        }
        player?.play()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Roamory",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        MPNowPlayingInfoCenter.default().playbackState = .playing

        // The stem sends pause while we report playing and play after that, so all three mean "toggle".
        let center = MPRemoteCommandCenter.shared()
        for command in [center.togglePlayPauseCommand, center.playCommand, center.pauseCommand] {
            command.isEnabled = true
            let target = command.addTarget { [weak self] _ in
                Task { @MainActor in self?.pressed() }
                return .success
            }
            commandTargets.append((command, target))
        }
    }

    private func stopListening() {
        guard !commandTargets.isEmpty else { return }
        for (command, target) in commandTargets { command.removeTarget(target) }
        commandTargets = []
        player?.stop()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func pressed() {
        // Keep reporting "playing" so the next press arrives as a command again.
        MPNowPlayingInfoCenter.default().playbackState = .playing
        if player?.isPlaying == false { player?.play() }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        onPress?()
    }

    /// One second of 16-bit mono silence as a WAV file.
    private static let silence: Data = {
        let rate: UInt32 = 8000
        let bytes = rate * 2
        var wav = Data()
        func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        wav.append(contentsOf: Array("RIFF".utf8)); put(36 + bytes)
        wav.append(contentsOf: Array("WAVEfmt ".utf8)); put(UInt32(16))
        put(UInt16(1)); put(UInt16(1)); put(rate); put(bytes); put(UInt16(2)); put(UInt16(16))
        wav.append(contentsOf: Array("data".utf8)); put(bytes)
        wav.append(Data(count: Int(bytes)))
        return wav
    }()
}
