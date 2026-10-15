import Foundation
import AppKit
import Combine
import WallpaperCore

public enum WorkshopImportResult: Equatable { case imported, existing }
private struct WorkshopPreferences: Codable { var account: String; var toolPath: String? }

@MainActor public final class WorkshopModel: ObservableObject {
    public typealias ItemLoader = ([WorkshopID]) async throws -> [WorkshopItem]
    @Published public var input = ""
    @Published public var account = ""
    @Published public private(set) var tool: URL?
    @Published public private(set) var accounts: [String] = []
    @Published public private(set) var candidates: [WorkshopItem] = []
    @Published public var selected: Set<WorkshopID> = []
    @Published public private(set) var isBusy = false
    @Published public private(set) var status = "就绪"
    @Published public private(set) var completed = 0
    @Published public private(set) var total = 0
    @Published public private(set) var failures: [String] = []
    @Published public var errorMessage: String?
    private let library: LibraryModel
    private let preferencesURL: URL
    private let itemLoader: ItemLoader
    private var operation: Task<Void, Never>?
    public init(library: LibraryModel, preferencesURL: URL? = nil,
                itemLoader: @escaping ItemLoader = { try await WorkshopModel.fetchItems($0) }) {
        self.library = library
        self.itemLoader = itemLoader
        self.preferencesURL = preferencesURL ?? library.storeURL.deletingLastPathComponent().appendingPathComponent("workshop.json")
        let saved = (try? Data(contentsOf: self.preferencesURL)).flatMap { try? JSONDecoder().decode(WorkshopPreferences.self, from: $0) }
        tool = saved?.toolPath.map { URL(fileURLWithPath: $0) } ?? SteamPaths.discoverTool()
        accounts = SteamPaths.cachedAccounts()
        account = saved?.account ?? accounts.last ?? ""
    }
    public var selectedBytes: Int64 { candidates.filter { selected.contains($0.id) }.reduce(0) { total, item in let sum = total.addingReportingOverflow(item.bytes); return sum.overflow ? Int64.max : sum.partialValue } }
    public func refreshAccounts() { accounts = SteamPaths.cachedAccounts() }
    public func chooseTool(_ url: URL) { tool = url; savePreferences() }
    public func savePreferences() {
        do {
            let data = try JSONEncoder().encode(WorkshopPreferences(account: account, toolPath: tool?.path))
            try FileManager.default.createDirectory(at: preferencesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: preferencesURL, options: .atomic)
        } catch { errorMessage = "无法保存下载设置：\(error.localizedDescription)" }
    }
    public func loginInTerminal() {
        do {
            let tool = try requireTool(); try SteamPaths.validateAccount(account); savePreferences()
            let dir = tool.deletingLastPathComponent().path
            let q = SteamPaths.shellQuote
            let script = """
            #!/bin/bash
            cd \(q(dir)) || exit 1
            export DYLD_LIBRARY_PATH=\(q(dir))
            export DYLD_FRAMEWORK_PATH=\(q(dir))
            ulimit -n 2048
            echo '请在 Valve SteamCMD 中登录。密码和 Steam Guard 验证码只在此终端输入。'
            attempts=0
            while true; do
              ./steamcmd +login \(q(account)) +quit
              code=$?
              if [ "$code" -ne 42 ] || [ "$attempts" -ge 3 ]; then break; fi
              attempts=$((attempts+1))
            done
            echo '登录操作结束。请回到视频壁纸 App 重试下载。'
            read -r -p '按回车关闭此窗口…'
            """
            let file = preferencesURL.deletingLastPathComponent().appendingPathComponent("SteamLogin.command")
            try Data(script.utf8).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            NSWorkspace.shared.open([file], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            status = "请在终端完成 Steam 登录，再回到这里下载。"
        } catch { errorMessage = error.localizedDescription }
    }
    private func requireTool() throws -> URL {
        guard let tool, tool.lastPathComponent == "steamcmd", FileManager.default.isExecutableFile(atPath: tool.path) else {
            throw WallpaperError.message("找不到 SteamCMD。请将 SteamTools 与 App 放在一起，或选择 SteamCMD 可执行文件。")
        }
        return tool
    }
    public func cancel() { operation?.cancel() }
    public func shutdown() { operation?.cancel() }
    private func start(_ work: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil; failures = []; completed = 0; total = 0
        operation = Task { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false; self.operation = nil }
            do { try await work() }
            catch is CancellationError { self.status = "已取消。已完成的导入保留。" }
            catch { self.errorMessage = error.localizedDescription; self.status = "操作未完成，可重试。" }
        }
    }
    public func downloadInput() {
        let requested = input
        start { [self] in
            try await downloadVerified(WorkshopID(requested))
        }
    }
    public func downloadItem(_ id: WorkshopID) { start { [self] in try await downloadVerified(id) } }
    private func downloadVerified(_ id: WorkshopID) async throws {
        status = "正在检查壁纸类型…"
        let items = try await itemLoader([id])
        try Task.checkCancellation()
        guard items.count == 1, let item = items.first, item.id == id else {
            throw WallpaperError.message("Steam 返回的作品信息与下载编号不匹配。")
        }
        guard item.isVideo else { throw WallpaperError.message("这项作品不是可访问的 Wallpaper Engine 视频壁纸（可能是场景、网页或已删除）。") }
        try await download([item])
    }
    public func downloadSelected() { let items = candidates.filter { selected.contains($0.id) }; guard !items.isEmpty else { return }; start { [self] in try await download(items) } }
    public func loadSubscriptions(_ ids: [WorkshopID]) { start { [self] in try await loadCandidates(ids) } }
    public func loadManifest(_ file: URL) {
        start { [self] in
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size < 10_000_000 else { throw WallpaperError.message("清单文件过大。请选择 appworkshop_431960.acf。") }
            try await loadCandidates(SteamKeyValues.installedIDs(String(contentsOf: file, encoding: .utf8)))
        }
    }
    private func loadCandidates(_ ids: [WorkshopID]) async throws {
        let ids = Array(Set(ids)).sorted { $0.rawValue < $1.rawValue }
        guard ids.count <= 10000 else { throw WallpaperError.message("订阅超过 10000 项，本次未读取。") }
        status = "正在读取 \(ids.count) 项作品信息…"; total = ids.count
        var all: [WorkshopItem] = []
        for offset in stride(from: 0, to: ids.count, by: 100) {
            try Task.checkCancellation()
            let batch = Array(ids[offset..<min(offset+100, ids.count)])
            all += try await itemLoader(batch)
            completed += batch.count; status = "正在筛选视频：\(completed)/\(total)…"
        }
        try Task.checkCancellation()
        let videos = all.filter(\.isVideo)
        candidates = videos; selected = Set(videos.filter { !alreadyImported($0.id) }.map(\.id))
        status = "共 \(ids.count) 项，找到 \(videos.count) 个视频；其余为非视频或不可访问作品。"
    }
    public static func fetchItems(_ ids: [WorkshopID]) async throws -> [WorkshopItem] {
        guard !ids.isEmpty else { return [] }
        var request = URLRequest(url: URL(string: "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/")!)
        request.httpMethod = "POST"; request.timeoutInterval = 45
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((["itemcount=\(ids.count)"] + ids.enumerated().map { "publishedfileids%5B\($0.offset)%5D=\($0.element.rawValue)" }).joined(separator: "&").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 8_000_000 else { throw WallpaperError.message("Steam 壁纸信息请求失败，请检查网络后重试。") }
        let decoded = try WorkshopItem.decodeResponse(data)
        guard decoded.count == ids.count, Set(decoded.map(\.id)) == Set(ids) else { throw WallpaperError.message("Steam 返回的作品列表不完整，已保留之前的列表。") }
        let byID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }
    public func alreadyImported(_ id: WorkshopID) -> Bool {
        library.state.projects.contains { project in
            (try? WorkshopID(URL(fileURLWithPath: project.folderPath).lastPathComponent)) == id &&
            (try? WallpaperProject.load(folder: URL(fileURLWithPath: project.folderPath))) != nil
        }
    }
    @discardableResult public func importVideo(_ folder: URL) async throws -> WorkshopImportResult {
        _ = try WallpaperProject.load(folder: folder)
        if let id = try? WorkshopID(folder.lastPathComponent), alreadyImported(id) { library.refreshArtwork(); return .existing }
        try Task.checkCancellation()
        // Library restore/apply owns its generation until finished. Do not supersede it.
        while library.isBusy { try await Task.sleep(for: .milliseconds(100)) }
        try Task.checkCancellation()
        let imported = await library.importFolder(folder) { [weak self] message in self?.status = message }
        try Task.checkCancellation()
        guard imported != nil else { throw WallpaperError.message(library.errorMessage ?? "导入被其他操作中断，请重试。") }
        return .imported
    }
    private func download(_ items: [WorkshopItem]) async throws {
        let tool = try requireTool(); try SteamPaths.validateAccount(account); savePreferences()
        total = items.count
        var added = 0; var skipped = 0
        for item in items {
            try Task.checkCancellation()
            if alreadyImported(item.id) { skipped += 1; completed += 1; continue }
            do {
                status = "\(completed+1)/\(total) 正在下载：\(item.title)（连接或下载中，请稍候）"
                var result: SteamProcessResult?
                for attempt in 0..<4 {
                    let value = try await SteamRunner.run(executable: tool, arguments: ["+@NoPromptForPassword", "1", "+login", account, "+workshop_download_item", "431960", item.id.rawValue, "+quit"], environment: SteamPaths.environment(tool: tool))
                    result = value
                    if value.exitCode != 42 || attempt == 3 { break }
                    status = "SteamCMD 已更新，正在重新连接…"
                }
                let resultValue = result!
                let folder = try SteamDownloadResult.folder(output: resultValue.output, exitCode: resultValue.exitCode, id: item.id)
                try SteamPaths.validateDownloadFolder(folder, id: item.id, roots: SteamPaths.contentRoots(tool: tool))
                status = "正在校验并导入：\(item.title)"
                let imported = try await importVideo(folder)
                if imported == .imported { added += 1 } else { skipped += 1 }
            } catch is CancellationError { throw CancellationError() }
            catch { failures.append("\(item.title)（\(item.id.rawValue)）：\(error.localizedDescription)") }
            completed += 1
        }
        status = "完成：导入 \(added) 个，已在库中 \(skipped) 个，失败 \(failures.count) 个。"
    }
    public func scanLocal(_ selectedRoot: URL? = nil) {
        start { [self] in
            let roots = selectedRoot.map { [$0] } ?? SteamPaths.contentRoots(tool: tool)
            var folders: [URL] = []
            for root in roots where FileManager.default.fileExists(atPath: root.path) { folders += try SteamPaths.folders(in: root) }
            total = folders.count; var added = 0; var skipped = 0; var nonVideo = 0
            for folder in folders {
                try Task.checkCancellation(); status = "正在检查本地壁纸 \(completed+1)/\(total)…"
                do {
                    guard let json = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("project.json"))) as? [String: Any], (json["type"] as? String)?.lowercased() == "video" else { nonVideo += 1; completed += 1; continue }
                    let result = try await importVideo(folder)
                    if result == .imported { added += 1 } else { skipped += 1 }
                } catch is CancellationError { throw CancellationError() }
                catch { failures.append("\(folder.lastPathComponent)：\(error.localizedDescription)") }
                completed += 1
            }
            status = "本地扫描完成：导入 \(added) 个，已有 \(skipped) 个，非视频 \(nonVideo) 个，失败 \(failures.count) 个。"
        }
    }
}
