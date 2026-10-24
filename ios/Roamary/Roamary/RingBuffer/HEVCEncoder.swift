//
//  HEVCEncoder.swift
//  Roamary
//

import CoreMedia
import VideoToolbox

/// Hardware HEVC encoder for the camera frames. Call `encode` from one queue only.
/// A failed session is dropped and rebuilt on the next frame, as happens after the app returns from the background.
nonisolated final class HEVCEncoder: @unchecked Sendable {
    nonisolated struct Config {
        var bitrate = 8_000_000
        /// Seconds between keyframes at most.
        var keyframeInterval = 2.0
        var frameRate = 30.0
    }

    private let config: Config
    private let onEncoded: @Sendable (_ sample: CMSampleBuffer, _ isKeyframe: Bool) -> Void
    private let onError: @Sendable (String) -> Void
    private var session: VTCompressionSession?
    private var width: Int32 = 0
    private var height: Int32 = 0
    private let lock = NSLock()
    private var keyframeRequested = false

    init(config: Config,
         onEncoded: @escaping @Sendable (CMSampleBuffer, Bool) -> Void,
         onError: @escaping @Sendable (String) -> Void) {
        self.config = config
        self.onEncoded = onEncoded
        self.onError = onError
    }

    deinit { invalidate() }

    func encode(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        var status = submit(pixelBuffer, at: time)
        if status == kVTInvalidSessionErr {
            // The system took the hardware encoder away (the app was in the background).
            // Start a new session, which opens with a keyframe, and encode this frame again.
            invalidate()
            status = submit(pixelBuffer, at: time)
        }
        if let status, status != noErr {
            onError("Encoder error \(status)")
            invalidate()
        }
    }

    /// Returns nil when there is no session to encode with.
    private func submit(_ pixelBuffer: CVPixelBuffer, at time: CMTime) -> OSStatus? {
        let w = Int32(CVPixelBufferGetWidth(pixelBuffer))
        let h = Int32(CVPixelBufferGetHeight(pixelBuffer))
        if session != nil && (w != width || h != height) { invalidate() }
        if session == nil {
            guard let created = makeSession(width: w, height: h) else { return nil }
            session = created
            width = w
            height = h
        }
        guard let session else { return nil }
        let onEncoded = onEncoded
        lock.lock()
        let forceKeyframe = keyframeRequested
        keyframeRequested = false
        lock.unlock()
        return VTCompressionSessionEncodeFrame(
            session, imageBuffer: pixelBuffer, presentationTimeStamp: time, duration: .invalid,
            frameProperties: forceKeyframe ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil,
            infoFlagsOut: nil
        ) { status, _, sample in
            guard status == noErr, let sample else { return }
            onEncoded(sample, Self.isKeyframe(sample))
        }
    }

    /// Makes the next frame a keyframe. Safe to call from any thread.
    func requestKeyframe() {
        lock.lock()
        keyframeRequested = true
        lock.unlock()
    }

    /// Emits the frames still inside the encoder.
    func flush() {
        guard let session else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
    }

    func invalidate() {
        guard let session else { return }
        VTCompressionSessionInvalidate(session)
        self.session = nil
    }

    private func makeSession(width: Int32, height: Int32) -> VTCompressionSession? {
        var created: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil, width: width, height: height, codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true] as CFDictionary,
            imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &created)
        guard status == noErr, let created else {
            onError("Cannot create the HEVC encoder (\(status))")
            return nil
        }
        let properties: [(CFString, CFTypeRef)] = [
            (kVTCompressionPropertyKey_RealTime, kCFBooleanTrue),
            (kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse),
            (kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main_AutoLevel),
            (kVTCompressionPropertyKey_AverageBitRate, config.bitrate as CFNumber),
            (kVTCompressionPropertyKey_ExpectedFrameRate, config.frameRate as CFNumber),
            (kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, config.keyframeInterval as CFNumber),
        ]
        for (key, value) in properties {
            VTSessionSetProperty(created, key: key, value: value)
        }
        VTCompressionSessionPrepareToEncodeFrames(created)
        return created
    }

    private static func isKeyframe(_ sample: CMSampleBuffer) -> Bool {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
        return !(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
    }
}
