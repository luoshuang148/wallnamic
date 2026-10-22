import AVFoundation
import WallpaperCore

public enum PlaybackVariantEncoder {
    struct Geometry { let size: CGSize; let transform: CGAffineTransform; let frameDuration: CMTime }
    static func outputGeometry(naturalSize: CGSize, transform: CGAffineTransform, nominalFrameRate: Float) throws -> Geometry {
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(transform).standardized
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0,
              nominalFrameRate.isFinite, nominalFrameRate > 0 else {
            throw WallpaperError.message(L("error.variant.cannotDetermineSizeOrFrameRate"))
        }
        let scale = min(1, 1920 / max(bounds.width, bounds.height))
        // Integral even output dimensions; center the aspect-preserving image.
        let size = CGSize(width: max(2, floor((bounds.width * scale + 0.0001) / 2) * 2),
                          height: max(2, floor((bounds.height * scale + 0.0001) / 2) * 2))
        let fit = min(1, min(size.width / bounds.width, size.height / bounds.height))
        let normalized = transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            .concatenating(CGAffineTransform(scaleX: fit, y: fit))
            .concatenating(CGAffineTransform(translationX: (size.width - bounds.width * fit) / 2,
                                           y: (size.height - bounds.height * fit) / 2))
        let fps = min(30, Double(nominalFrameRate))
        return Geometry(size: size, transform: normalized,
                        frameDuration: CMTime(value: Int64(ceil(60000 / fps)), timescale: 60000))
    }
    public static func encode(source: URL, destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw WallpaperError.message(L("error.variant.noVideoTrack"))
        }
        // HighestQuality may map HDR to SDR. Never silently alter HDR appearance.
        guard !track.hasMediaCharacteristic(.containsHDRVideo) else {
            throw WallpaperError.message(L("error.variant.hdrKeepsOriginal"))
        }
        let size = try await track.load(.naturalSize), transform = try await track.load(.preferredTransform)
        let fps = try await track.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)
        let geometry = try outputGeometry(naturalSize: size, transform: transform, nominalFrameRate: fps)
        try Task.checkCancellation()
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw WallpaperError.message(L("error.variant.cannotCreate"))
        }
        let composition = AVMutableVideoComposition()
        composition.renderSize = geometry.size; composition.frameDuration = geometry.frameDuration
        if let format = try await track.load(.formatDescriptions).first,
           let extensions = CMFormatDescriptionGetExtensions(format) as? [String: Any] {
            composition.colorPrimaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String
            composition.colorTransferFunction = extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String
            composition.colorYCbCrMatrix = extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String
        }
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(geometry.transform, at: .zero)
        instruction.layerInstructions = [layer]; composition.instructions = [instruction]
        export.videoComposition = composition
        export.outputURL = destination; export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = false
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                export.exportAsynchronously {
                    switch export.status {
                    case .completed: continuation.resume()
                    case .cancelled: continuation.resume(throwing: CancellationError())
                    default: continuation.resume(throwing: export.error ?? WallpaperError.message(L("error.variant.failed")))
                    }
                }
            }
            try Task.checkCancellation()
        } onCancel: { export.cancelExport() }
    }
}
