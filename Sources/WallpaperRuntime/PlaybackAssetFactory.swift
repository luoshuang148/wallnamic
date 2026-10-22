import AVFoundation
import WallpaperCore

/// A video-only composition removes audio from permanently silent previews
/// without re-encoding video or activating an audio-rendering pipeline.
enum PlaybackAssetFactory {
    static func makeAsset(url: URL, includeAudio: Bool) async throws -> AVAsset {
        let source = AVURLAsset(url: url)
        if includeAudio { return source }
        guard let video = try await source.loadTracks(withMediaType: .video).first else {
            throw WallpaperError.message("文件没有可播放的视频轨道。")
        }
        let range = try await video.load(.timeRange)
        let transform = try await video.load(.preferredTransform)
        try Task.checkCancellation()
        let composition = AVMutableComposition()
        guard let target = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw WallpaperError.message("无法准备视频预览。")
        }
        try target.insertTimeRange(range, of: video, at: range.start)
        target.preferredTransform = transform
        return composition
    }
}
