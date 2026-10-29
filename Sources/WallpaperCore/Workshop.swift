import Foundation

public struct WorkshopID: Hashable, Codable, Identifiable, Sendable {
    public let rawValue: String
    public var id: String { rawValue }
    public var url: URL { URL(string: "https://steamcommunity.com/sharedfiles/filedetails/?id=\(rawValue)")! }
    public init(_ input: String) throws {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let number: String
        if input.hasPrefix("https://") {
            guard let c = URLComponents(string: input), c.scheme == "https", c.host?.lowercased() == "steamcommunity.com",
                  c.user == nil, c.password == nil, c.port == nil,
                  ["/sharedfiles/filedetails", "/workshop/filedetails"].contains(c.path.trimmingCharacters(in: CharacterSet(charactersIn: "/" )).withLeadingSlash),
                  let ids = c.queryItems?.filter({ $0.name == "id" }), ids.count == 1, let value = ids[0].value else {
                throw WallpaperError.message(L("error.workshop.pasteASteamWorkshopItemLinkOrA"))
            }
            number = value
        } else { number = input }
        guard !number.isEmpty, number.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }), let value = UInt64(number), value > 0 else {
            throw WallpaperError.message(L("error.workshop.theWorkshopIDMustBeAValidPositive"))
        }
        rawValue = String(value)
    }
}
private extension String { var withLeadingSlash: String { "/" + self } }

public struct WorkshopItem: Identifiable, Equatable, Sendable {
    public let id: WorkshopID
    public let title: String
    public let bytes: Int64
    public let result: Int
    public let appID: Int
    public let tags: [String]
    public var previewURL: URL? = nil
    public var isVideo: Bool { result == 1 && appID == 431960 && tags.contains { $0.lowercased() == "video" } }
    public static func decodeResponse(_ data: Data) throws -> [WorkshopItem] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let response = json["response"] as? [String: Any],
              let details = response["publishedfiledetails"] as? [[String: Any]] else { throw WallpaperError.message(L("error.workshop.steamReturnedUnrecognizedWallpaperInformation")) }
        return try details.map { d in
            let id = try WorkshopID(d["publishedfileid"] as? String ?? "")
            var item = WorkshopItem(id: id, title: d["title"] as? String ?? String(format: L("error.workshop.id"), String(describing: id.rawValue)),
                                bytes: max(0, Int64(String(describing: d["file_size"] ?? "0")) ?? 0),
                                result: d["result"] as? Int ?? 0, appID: d["consumer_app_id"] as? Int ?? 0,
                                tags: (d["tags"] as? [[String: Any]] ?? []).compactMap { $0["tag"] as? String })
            if let raw = d["preview_url"] as? String, let url = URL(string: raw), url.scheme == "https",
               let host = url.host?.lowercased(),
               host == "steamusercontent.com" || host.hasSuffix(".steamusercontent.com") || host == "steamuserimages-a.akamaihd.net" {
                item.previewURL = url
            }
            return item
        }
    }
}

public enum SteamDownloadResult {
    public static func folder(output: String, exitCode: Int32, id: WorkshopID) throws -> URL {
        let pattern = "(?m)^Success\\. Downloaded item " + id.rawValue + " to \\\"([^\\\"\\r\\n]+)\\\""
        let regex = try NSRegularExpression(pattern: pattern)
        guard exitCode == 0, let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output), output[range].hasPrefix("/") else {
            throw WallpaperError.message(L("error.workshop.steamDidNotConfirmTheDownloadUseSign"))
        }
        return URL(fileURLWithPath: String(output[range]), isDirectory: true)
    }
}

public indirect enum SteamKeyValues {
    case string(String)
    case entries([(String, SteamKeyValues)])
    public var keys: [String] { if case let .entries(e) = self { return e.map(\.0) }; return [] }
    public func object(_ key: String) -> SteamKeyValues? {
        if case let .entries(e) = self { return e.first { $0.0.caseInsensitiveCompare(key) == .orderedSame }?.1 }; return nil
    }
    public var value: String? { if case let .string(s) = self { return s }; return nil }
    public static func parse(_ text: String) throws -> SteamKeyValues {
        var scanner = Scanner(Array(text))
        return .entries(try scanner.entries(nested: false))
    }
    public static func installedIDs(_ text: String) throws -> [WorkshopID] {
        let root = try parse(text).object("AppWorkshop")
        guard root?.object("appid")?.value == "431960", let installed = root?.object("WorkshopItemsInstalled") else {
            throw WallpaperError.message(L("error.workshop.selectTheWallpaperEngineAppworkshop431960AcfManifest"))
        }
        return try installed.keys.map(WorkshopID.init)
    }
    private struct Scanner {
        let chars: [Character]; var i = 0
        init(_ chars: [Character]) { self.chars = chars }
        mutating func skip() {
            while i < chars.count {
                if chars[i].isWhitespace { i += 1 }
                else if i+1 < chars.count && chars[i] == "/" && chars[i+1] == "/" {
                    while i < chars.count && chars[i] != "\n" { i += 1 }
                } else { break }
            }
        }
        mutating func token() throws -> String {
            skip(); guard i < chars.count, chars[i] != "}", chars[i] != "{" else { throw invalid }
            var result = ""
            if chars[i] == "\"" {
                i += 1
                while i < chars.count {
                    let c = chars[i]; i += 1
                    if c == "\"" { return result }
                    if c == "\\", i < chars.count {
                        let next = chars[i]; i += 1
                        result.append(next == "n" ? "\n" : next == "t" ? "\t" : next)
                    } else { result.append(c) }
                }
                throw invalid
            }
            while i < chars.count && !chars[i].isWhitespace && chars[i] != "}" && chars[i] != "{" { result.append(chars[i]); i += 1 }
            return result
        }
        mutating func entries(nested: Bool, depth: Int = 0) throws -> [(String, SteamKeyValues)] {
            guard depth < 32 else { throw invalid }
            var result: [(String, SteamKeyValues)] = []
            while true {
                skip()
                if i == chars.count { if nested { throw invalid }; return result }
                if chars[i] == "}" { guard nested else { throw invalid }; i += 1; return result }
                let key = try token(); skip()
                if i < chars.count && chars[i] == "{" { i += 1; result.append((key, .entries(try entries(nested: true, depth: depth+1)))) }
                else { result.append((key, .string(try token()))) }
            }
        }
        var invalid: WallpaperError { .message(L("error.workshop.theSteamManifestIsCorruptedAndCannotBe")) }
    }
}
