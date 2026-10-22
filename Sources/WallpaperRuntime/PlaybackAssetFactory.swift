import AVFoundation
import WallpaperCore

/// A video-only composition removes audio from permanently silent previews
/// without re-encoding video or activating an audio-rendering pipeline.
enum PlaybackAssetFactory {
    static func makeAsset(url: URL, includeAudio: Bool) async throws -> AVAsset {
        let source = AVURLAsset(url: url)
        if includeAudio { return source }
        guard let video = try await source.loadTracks(withMediaType: .video).first else {
            throw WallpaperError.message(L("error.media.theFileHasNoPlayableVideoTrack"))
        }
        let range = try await video.load(.timeRange)
        let transform = try await video.load(.preferredTransform)
        try Task.checkCancellation()
        let composition = AVMutableComposition()
        guard let target = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw WallpaperError.message(L("error.variant.previewPrepareFailed"))
        }
        try target.insertTimeRange(range, of: video, at: range.start)
        target.preferredTransform = transform
        return composition
    }
}
