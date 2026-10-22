import Foundation
import CryptoKit

public struct WallpaperProject: Codable, Identifiable, Equatable {
    public var id: String { sourceFolderPath ?? folderPath }
    public private(set) var sourceFolderPath: String? = nil
    public func identifyingSourceFolder(_ path: String?) -> WallpaperProject {
        var copy = self
        copy.sourceFolderPath = path
        return copy
    }
    public let folderPath: String
    public let title: String
    public let videoPath: String
    public let previewPath: String?
    /// Materialize a self-contained project folder for a plain video file
    /// (hard-link when possible, otherwise copy) so the existing folder pipeline works.
    public static func makeImportFolder(forVideo video: URL, under root: URL) throws -> (folder: URL, sourcePath: String) {
        let fm = FileManager.default
        let src = video.resolvingSymlinksInPath().standardizedFileURL
        let values = try src.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
            throw WallpaperError.message(String(format: L("error.project.validFileNotFound"), String(describing: src.lastPathComponent)))
        }
        var fingerprint = Data(src.path.utf8)
        fingerprint.append(Data("\n\(values.fileSize ?? 0)\n\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)\nimport-video-v1".utf8))
        let key = SHA256.hash(data: fingerprint).map { String(format: "%02x", $0) }.joined()
        let folder = root.appendingPathComponent(String(key.prefix(16)), isDirectory: true)
        let ext = src.pathExtension.lowercased()
        let videoName = "source." + (ext.isEmpty ? "mp4" : ext)
        let destVideo = folder.appendingPathComponent(videoName)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        if fm.fileExists(atPath: destVideo.path) { try fm.removeItem(at: destVideo) }
        do { try fm.linkItem(at: src, to: destVideo) }
        catch { try fm.copyItem(at: src, to: destVideo) }
        let title = src.deletingPathExtension().lastPathComponent
        let json: [String: Any] = ["type": "video", "file": videoName, "title": title]
        try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            .write(to: folder.appendingPathComponent("project.json"), options: .atomic)
        return (folder, src.path)
    }

    public static func load(folder: URL) throws -> WallpaperProject {
        let base = folder.resolvingSymlinksInPath().standardizedFileURL
        let manifest = try containedFile("project.json", in: base)
        let data = try Data(contentsOf: manifest)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WallpaperError.message(L("error.project.theProjectJsonFormatIsInvalid"))
        }
        guard (json["type"] as? String)?.lowercased() == "video" else {
            throw WallpaperError.message(L("error.project.thisIsNotAVideoWallpaperSelectA"))
        }
        guard let file = json["file"] as? String, !file.isEmpty else {
            throw WallpaperError.message(L("error.project.theConfigurationIsMissingTheVideoFilePath"))
        }
        let video = try containedFile(file, in: base)
        let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = (json["preview"] as? String).flatMap { try? containedFile($0, in: base) }
        return WallpaperProject(folderPath: base.path, title: title.flatMap { $0.isEmpty ? nil : $0 } ?? base.lastPathComponent,
                                videoPath: video.path, previewPath: preview?.path)
    }

    private static func containedFile(_ relative: String, in base: URL) throws -> URL {
        guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.contains("\\") else {
            throw WallpaperError.message(L("error.project.theConfiguredFilePathIsInvalid"))
        }
        let candidate = base.appendingPathComponent(relative).resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path.hasPrefix(base.path + "/") else {
            throw WallpaperError.message(L("error.project.theConfigurationReferencesAFileOutsideTheWallpaper"))
        }
        let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
            throw WallpaperError.message(String(format: L("error.project.validFileNotFound"), String(describing: relative)))
        }
        return candidate
    }
}

public enum WallpaperError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
