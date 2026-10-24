import Photos

enum PhotoLibrary {
    /// Adds a video file to Photos and returns a message for the user. The file stays where it is.
    static func saveVideo(_ url: URL) async -> String {
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized else {
            return "Photos access is required to save the video."
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            return "Saved to Photos"
        } catch {
            return "Save failed: \(error.localizedDescription)"
        }
    }
}
