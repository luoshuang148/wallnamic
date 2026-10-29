import Foundation
import WallpaperCore

/// Resolves only the selected download account's public identity and avatar.
public enum SteamAccountAvatar {
    static func steamID(account: String, config: String?, loginUsers: String?) -> String? {
        guard !account.isEmpty else { return nil }
        if let config, let root = try? SteamKeyValues.parse(config),
           let accounts = root.object("InstallConfigStore")?.object("Software")?.object("Valve")?.object("Steam")?.object("Accounts"),
           let id = accounts.object(account)?.object("SteamID")?.value, validID(id) { return id }
        if let loginUsers, let users = try? SteamKeyValues.parse(loginUsers).object("users") {
            return users.keys.first { id in
                validID(id) && users.object(id)?.object("AccountName")?.value?.caseInsensitiveCompare(account) == .orderedSame
            }
        }
        return nil
    }

    public static func steamID(account: String, directory: URL = SteamPaths.steamDirectory) -> String? {
        steamID(account: account,
                config: try? String(contentsOf: directory.appendingPathComponent("config/config.vdf"), encoding: .utf8),
                loginUsers: try? String(contentsOf: directory.appendingPathComponent("config/loginusers.vdf"), encoding: .utf8))
    }

    private static func validID(_ id: String) -> Bool {
        id.count == 17 && id.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }

    static func avatarURL(profileXML: Data) -> URL? {
        guard profileXML.count < 1_000_000 else { return nil }
        let delegate = AvatarXMLParser()
        let parser = XMLParser(data: profileXML)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), let url = URL(string: delegate.avatar.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased(),
              host == "avatars.steamstatic.com" || host == "avatars.akamai.steamstatic.com" || host == "avatars.cloudflare.steamstatic.com" || host == "avatars.fastly.steamstatic.com" || host == "cdn.akamai.steamstatic.com" else { return nil }
        return url
    }

    public static func data(account: String, directory: URL = SteamPaths.steamDirectory) async -> Data? {
        let config = try? String(contentsOf: directory.appendingPathComponent("config/config.vdf"), encoding: .utf8)
        let users = try? String(contentsOf: directory.appendingPathComponent("config/loginusers.vdf"), encoding: .utf8)
        guard let id = steamID(account: account, config: config, loginUsers: users) else { return nil }
        let cached = directory.appendingPathComponent("config/avatarcache/\(id).png")
        if let size = try? cached.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 2_000_000,
           let data = try? Data(contentsOf: cached), !data.isEmpty { return data }
        do {
            let request = URLRequest(url: URL(string: "https://steamcommunity.com/profiles/\(id)/?xml=1")!, timeoutInterval: 15)
            let (xml, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard (response as? HTTPURLResponse)?.statusCode == 200, let url = avatarURL(profileXML: xml) else { return nil }
            let (data, imageResponse) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15))
            try Task.checkCancellation()
            guard (imageResponse as? HTTPURLResponse)?.statusCode == 200, data.count < 2_000_000 else { return nil }
            return data
        } catch { return nil }
    }
}

private final class AvatarXMLParser: NSObject, XMLParserDelegate {
    var avatar = ""
    private var reading = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        reading = elementName == "avatarFull"
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if reading { avatar += string } }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { if reading { avatar += String(decoding: CDATABlock, as: UTF8.self) } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { reading = false }
}
