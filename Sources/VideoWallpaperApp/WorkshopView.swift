import SwiftUI
import AppKit
import WebKit
import WallpaperCore
import WallpaperRuntime

struct WorkshopView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var model: WorkshopModel
    @ObservedObject var library: LibraryModel
    let onImportFolder: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var syncRequest = 0
    @State private var showsSyncSuccess = false
    @State private var successTask: Task<Void, Never>?
    @State private var showsBrowser = false
    @State private var showsLinkDownload = false
    @State private var showsAccount = false
    @State private var accountAvatar: NSImage?
    @State private var search = ""
    @State private var filter = 0
    private let accent = Color(red: 0.12, green: 0.48, blue: 0.52)
    private var isBusy: Bool { model.isBusy || library.isBusy }
    private var blocksBrowsing: Bool { (model.isBusy && !model.isSynchronizing) || library.isBusy }
    private var visibleItems: [WorkshopItem] {
        model.candidates.filter { item in
            (search.isEmpty || item.title.localizedCaseInsensitiveContains(search) || item.id.rawValue.contains(search)) &&
            (filter == 0 || (filter == 1 && !model.alreadyImported(item.id)) || (filter == 2 && model.alreadyImported(item.id)))
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(L("workshop.ui.collection")).font(.title2.bold())
                    Spacer()
                    Button(L("settings.done")) { dismiss() }.keyboardShortcut(.cancelAction)
                }.padding(24)
                HStack(spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(L("library.searchByNameOrID"), text: $search).textFieldStyle(.plain)
                        if !search.isEmpty {
                            Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).accessibilityLabel(L("library.clearSearch"))
                        }
                    }.padding(10).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    Picker("", selection: $filter) {
                        Text(L("workshop.ui.all")).tag(0)
                        Text(L("workshop.ui.pending")).tag(1)
                        Text(L("workshop.imported")).tag(2)
                    }.pickerStyle(.segmented).frame(width: 230)
                }.padding(.horizontal, 24).padding(.bottom, 16)
                HStack {
                    Text(String(format: L("workshop.videoWallpapers"), String(visibleItems.count)))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("workshop.selectAllNotImported")) {
                        model.selected.formUnion(visibleItems.filter { !model.alreadyImported($0.id) }.map(\.id))
                    }
                    Button(L("workshop.deselectAll")) { model.selected = [] }
                }.buttonStyle(.borderless).font(.caption).disabled(blocksBrowsing)
                    .padding(.horizontal, 24).padding(.bottom, 12)
                if visibleItems.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: model.candidates.isEmpty ? "square.grid.2x2" : "magnifyingglass")
                            .font(.system(size: 40, weight: .ultraLight)).foregroundStyle(accent)
                        Text(L(model.candidates.isEmpty ? "workshop.ui.empty" : "library.noMatchingWallpapers"))
                            .font(.title3.weight(.semibold))
                        if model.candidates.isEmpty {
                            Button(L("workshop.ui.sync")) { syncRequest += 1 }
                                .buttonStyle(.borderedProminent).disabled(isBusy)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 16)], spacing: 18) {
                            ForEach(visibleItems) { item in wallpaperCard(item) }
                        }.padding(.horizontal, 24).padding(.bottom, 20)
                    }.frame(maxHeight: .infinity)
                }
                downloadBar
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 1000, height: 720).tint(accent)
        .onAppear { model.refreshAccounts() }
        .task(id: "\(model.account)|\(syncRequest)") {
            showsSyncSuccess = false
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await model.synchronizeSubscriptions()
        }
        .onChange(of: model.syncCompletion) { _, _ in
            successTask?.cancel()
            showsSyncSuccess = true
            successTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(1300)) } catch { return }
                showsSyncSuccess = false
            }
        }
        .onDisappear { successTask?.cancel() }
        .sheet(isPresented: $showsBrowser) { WorkshopBrowserView(model: model, library: library) }
        .sheet(isPresented: $showsLinkDownload) { WorkshopLinkDownloadView(model: model, library: library) }
        .task(id: model.account) {
            accountAvatar = nil
            let account = model.account
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            let data = await SteamAccountAvatar.data(account: account)
            guard !Task.isCancelled, account == model.account else { return }
            accountAvatar = data.flatMap(NSImage.init(data:))
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("library.workshop"), systemImage: "square.stack.3d.up")
                .font(.headline).padding(.bottom, 24).padding(.top, 8)
            Button { showsBrowser = true } label: {
                Label(L("workshop.ui.discover"), systemImage: "safari").frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }.disabled(blocksBrowsing)
            Label(L("workshop.ui.collection"), systemImage: "square.grid.2x2.fill")
                .fontWeight(.medium).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .foregroundStyle(accent).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            Button { syncRequest += 1 } label: {
                Label {
                    Text(L(showsSyncSuccess && !model.isSynchronizing ? "workshop.ui.synced" : "workshop.ui.sync"))
                } icon: {
                    WorkshopSyncIcon(syncing: model.isSynchronizing, completed: showsSyncSuccess && !model.isSynchronizing)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }.disabled(isBusy)
            Divider().padding(.vertical, 12)
            Button { showsLinkDownload = true } label: {
                Label(L("workshop.downloadFromLink"), systemImage: "link")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }.disabled(blocksBrowsing)
            Menu {
                Button(L("workshop.importWallpaperFolder"), action: onImportFolder)
                Button(L("workshop.importLocalDownloads")) { model.scanLocal() }
                Button(L("workshop.selectSteamVideoFolder"), action: chooseLocal)
                Button(L("workshop.readWindowsDownloadManifest"), action: chooseManifest)
            } label: {
                Label(L("workshop.otherSources"), systemImage: "folder.badge.plus")
            }.menuStyle(.borderlessButton).padding(10).disabled(blocksBrowsing)
            Spacer()
            Button { showsAccount = true } label: {
                HStack(spacing: 10) {
                    Group {
                        if let accountAvatar {
                            Image(nsImage: accountAvatar).resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle").resizable().scaledToFit().foregroundStyle(.secondary)
                        }
                    }.frame(width: 30, height: 30).clipShape(Circle())
                    Text(model.account.isEmpty ? L("workshop.downloadAccount") : model.account).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "gearshape").foregroundStyle(.secondary)
                }.padding(10)
            }.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .popover(isPresented: $showsAccount, attachmentAnchor: .point(.topTrailing), arrowEdge: .top) { accountSettings }
        }.buttonStyle(.plain).padding(16).frame(width: 204)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func wallpaperCard(_ item: WorkshopItem) -> some View {
        let imported = model.alreadyImported(item.id)
        let selected = model.selected.contains(item.id) && !imported
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                guard !imported else { return }
                if selected { model.selected.remove(item.id) } else { model.selected.insert(item.id) }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Rectangle().fill(Color(nsColor: .underPageBackgroundColor))
                    GeometryReader { geometry in
                        AsyncImage(url: item.previewURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "play.rectangle").font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
                        }.frame(width: geometry.size.width, height: 125).clipped()
                    }
                    Image(systemName: imported ? "checkmark.seal.fill" : selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(selected ? accent : .white)
                        .padding(7).background(.black.opacity(0.45), in: Circle()).padding(8)
                }.frame(height: 125).clipped()
            }.buttonStyle(.plain).disabled(blocksBrowsing)
                .accessibilityLabel(item.title).accessibilityValue(imported ? L("workshop.imported") : selected ? L("workshop.ui.selected") : L("workshop.ui.pending"))
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(2).frame(height: 32, alignment: .topLeading)
                HStack {
                    Text(imported ? L("workshop.imported") : ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Link(destination: item.id.url) { Image(systemName: "arrow.up.right") }
                        .help(L("workshop.details")).accessibilityLabel(L("workshop.details"))
                }.font(.caption)
            }.padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? accent : Color(nsColor: .separatorColor).opacity(0.35), lineWidth: selected ? 2 : 1))
    }

    private var downloadBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.errorMessage { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if !model.failures.isEmpty {
                DisclosureGroup(String(format: L("workshop.browser.itemsIncompleteExpandForDetails"), String(model.failures.count))) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(model.failures.enumerated()), id: \.offset) { _, failure in Text(failure).font(.caption).textSelection(.enabled) }
                        }
                    }.frame(maxHeight: 80)
                }
            }
            HStack(spacing: 12) {
                if isBusy { ProgressView().controlSize(.small) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: L("workshop.selectedAbout"), String(model.selected.count), ByteCountFormatter.string(fromByteCount: model.selectedBytes, countStyle: .file))).font(.callout.weight(.medium))
                    Text(library.importStatus ?? model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                }
                Spacer()
                if model.isBusy { Button(L("workshop.browser.cancelTask")) { model.cancel() } }
                Button(L("workshop.downloadSelectedVideos")) { model.downloadSelected() }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(blocksBrowsing || model.selected.isEmpty)
            }
            if model.isBusy && model.total > 0 { ProgressView(value: Double(model.completed), total: Double(model.total)) }
        }.padding(18).background(.bar).overlay(alignment: .top) { Divider() }
    }

    private var accountSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("workshop.downloadAccount")).font(.headline)
            TextField(L("workshop.steamLoginAccountName"), text: $model.account).textFieldStyle(.roundedBorder).onSubmit { model.savePreferences() }
            HStack {
                if !model.accounts.isEmpty {
                    Menu(L("workshop.signedInAccounts")) {
                        ForEach(model.accounts, id: \.self) { name in Button(name) { model.account = name; model.savePreferences() } }
                    }
                }
                Button(L("workshop.signInToDownload")) { model.loginInTerminal() }
            }
            Button(L("workshop.ui.webSignIn")) { showsAccount = false; showsBrowser = true }
            Divider()
            Text(L(model.tool == nil ? "workshop.steamcmdNotFound" : "workshop.steamcmdReady")).font(.caption).foregroundStyle(.secondary)
            Button(L("workshop.chooseTool"), action: chooseTool)
        }.padding(20).frame(width: 350).disabled(blocksBrowsing)
    }
    private func chooseTool() {
        let panel = NSOpenPanel(); panel.title = L("workshop.selectTheSteamCMDExecutableSteamcmd"); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.chooseTool(url) }
    }
    private func chooseLocal() {
        let panel = NSOpenPanel(); panel.title = L("workshop.selectContent431960ContainingNumberedWallpaperFolders"); panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { model.scanLocal(url) }
    }
    private func chooseManifest() {
        let panel = NSOpenPanel(); panel.title = L("workshop.selectWindowsAppworkshop431960Acf"); panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { model.loadManifest(url) }
    }
}

private struct WorkshopLinkDownloadView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var model: WorkshopModel
    @ObservedObject var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    private var isBusy: Bool { (model.isBusy && !model.isSynchronizing) || library.isBusy }
    private var canDownload: Bool { !isBusy && !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("workshop.downloadFromLinkTitle")).font(.title2.bold())
                Spacer()
                Button(L("workshop.browser.close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                TextField(L("workshop.pasteASteamWorkshopLinkOrNumericID"), text: $model.input)
                    .textFieldStyle(.roundedBorder).disabled(isBusy)
                    .onSubmit { if canDownload { model.downloadInput() } }
                Button(L("workshop.downloadAndImport")) { model.downloadInput() }
                    .buttonStyle(.borderedProminent).disabled(!canDownload)
            }
            if let error = model.errorMessage ?? library.errorMessage {
                Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
            }
            if !model.failures.isEmpty {
                DisclosureGroup(String(format: L("workshop.browser.itemsIncompleteExpandForDetails"), String(describing: model.failures.count))) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(model.failures.enumerated()), id: \.offset) { _, failure in
                                Text(failure).font(.caption).textSelection(.enabled)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 100)
                }
            }
            Divider()
            HStack {
                if isBusy { ProgressView().controlSize(.small) }
                Text(library.importStatus ?? (library.isBusy ? L("workshop.importing") : model.status))
                    .font(.callout).lineLimit(3).textSelection(.enabled)
                Spacer()
                if model.isBusy { Button(L("workshop.browser.cancelTask")) { model.cancel() } }
            }
            if model.isBusy, model.total > 0 { ProgressView(value: Double(model.completed), total: Double(model.total)) }
        }.padding(24).frame(width: 620)
    }
}
