import SwiftUI
import AppKit
import WallpaperCore
import WallpaperRuntime

struct LibraryView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var workshop: WorkshopModel
    @ObservedObject var startup: LoginStartupModel
    @ObservedObject var exit: ManagementExitCoordinator
    @State private var selectedID: String?
    @State private var revealRequest = 0
    @State private var renamingProject: WallpaperProject?
    @State private var target = "all"
    @State private var fit: FitMode = .fill
    @State private var showsWorkshop = false
    @State private var searchText = ""
    @State private var showsSettings = false
    @State private var favoritesOnly = false
    @State private var groupID: String?
    @FocusState private var searchFocused: Bool
    private let accent = Color(red: 0.12, green: 0.48, blue: 0.52)
    private var project: WallpaperProject? { model.state.projects.first { $0.id == selectedID } }
    private var visibleProjects: [WallpaperProject] { model.state.organization.filterAndSort(model.state.projects, query: searchText, favoritesOnly:favoritesOnly, groupID:groupID) }
    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isFiltered: Bool { isSearching || favoritesOnly || groupID != nil }
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 236)
            Divider()
            VStack(alignment: .leading, spacing: 20) {
                header
                if let project { detail(project) }
                else if isFiltered { searchEmptyState }
                else { emptyState }
                if let status = model.importStatus {
                    Text(status).font(.callout).foregroundStyle(.secondary)
                }
                if let message = model.errorMessage {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(message).font(.callout).textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button { model.errorMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }
                    .padding(12).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                }
            }.padding(28).contentShape(Rectangle()).onTapGesture { searchFocused = false }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 880, minHeight: 610)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
        .sheet(item:$renamingProject) { project in RenameWallpaperView(model:model,project:project) }
        .sheet(isPresented: $showsSettings) { SettingsView(model:model,startup:startup,exit:exit) }
        .sheet(isPresented: $showsWorkshop) { WorkshopView(model:workshop,library:model,onImportFolder:importFolder) }
        .onAppear { selectedID = visibleProjects.first?.id; searchFocused = false }
        .onChange(of: model.state.organization.groups.map(\.id)) { _, ids in
            if let selected = groupID, !ids.contains(selected) { groupID = nil }
        }
        .onChange(of: visibleProjects.map(\.id)) { _, ids in
            if selectedID == nil || !ids.contains(selectedID ?? "") { selectedID = ids.first }
        }
        .onChange(of: model.displays.map(\.id)) { _, ids in
            if target != "all" && !ids.contains(target) { target = "all" }
        }
        .onChange(of: target) { _, _ in updateFit() }
        .onChange(of: selectedID) { _, _ in updateFit() }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "play.rectangle.fill").font(.title2).foregroundStyle(accent)
                Text("Wallnamic").font(.headline)
            }.padding(.horizontal, 22).padding(.top, 28).padding(.bottom, 30)
            HStack {
                Text(L("library.myWallpapers")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(isFiltered ? "\(visibleProjects.count)/\(model.state.projects.count)" : "\(model.state.projects.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(.horizontal, 22).padding(.bottom, 10)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("library.searchByNameOrID"), text: $searchText)
                    .textFieldStyle(.plain).focused($searchFocused).accessibilityLabel(L("library.searchMyWallpapers"))
                if !searchText.isEmpty {
                    Button { searchText = ""; searchFocused = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel(L("library.clearSearch"))
                }
            }.font(.system(size: 12)).padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16).padding(.bottom, 12)
            libraryFilters.padding(.horizontal,16).padding(.bottom,10)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(visibleProjects) { item in
                            Button { selectedID = item.id; searchFocused = false } label: {
                                HStack(spacing: 10) {
                                    Thumbnail(path: item.previewPath, revision: model.artworkRevision).frame(width: 58, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(model.displayName(for:item)).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                        if let groupName = model.state.organization.memberships[item.id].flatMap({ id in model.state.organization.groups.first { $0.id == id }?.name }) {
                                            Text(groupName).font(.system(size:10)).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    if model.state.organization.favorites.contains(item.id) { Image(systemName:"star.fill").font(.caption).foregroundStyle(.orange) }
                                }.padding(9).contentShape(Rectangle())
                                    .background(selectedID == item.id ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain).id(item.id)
                            .contextMenu {
                                Button(L("library.rename")) { searchFocused = false; renamingProject = item }
                                Button(model.state.organization.favorites.contains(item.id) ? L("library.removeFromFavorites") : L("library.favoriteWallpaper")) { toggleFavorite(item.id) }
                                Menu(L("library.moveToGroup")) {
                                    Button(L("library.ungrouped")) { moveToGroup(item.id,group:nil) }
                                    ForEach(model.state.organization.groups) { group in
                                        Button(group.name) { moveToGroup(item.id,group:group.id) }
                                    }
                                }
                                Divider()
                                Button(L("library.showInFinder")) { NSWorkspace.shared.selectFile(item.folderPath, inFileViewerRootedAtPath: "") }
                                Button(L("library.removeFromList"), role: .destructive) { model.remove(projectID: item.id) }.disabled(model.isBusy)
                            }
                        }
                    }.padding(.horizontal, 12)
                }
                .onChange(of: revealRequest) { _, _ in
                    if let selectedID { proxy.scrollTo(selectedID) }
                }
            }
            Spacer(minLength: 12)
            Button { showsWorkshop = true } label: {
                Label(L("library.workshop"), systemImage: "arrow.down.circle").frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).padding(.horizontal, 22).padding(.bottom, 16)
            Divider().padding(.horizontal, 16)
            Button { searchFocused = false; showsSettings = true } label: {
                Label(L("library.settings"),systemImage:"gearshape").frame(maxWidth:.infinity,alignment:.leading)
            }.buttonStyle(.plain).padding(.horizontal,22).padding(.top,16).padding(.bottom,22)
        }.background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
    }
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("settings.wallpaper")).font(.system(size: 23, weight: .semibold))
                Text(String(format: L("library.displaysConnected"), String(describing: model.displays.count)))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.togglePause() } label: {
                Label(model.state.manuallyPaused ? L("menu.resumePlayback") : L("menu.pauseAll"), systemImage: model.state.manuallyPaused ? "play.fill" : "pause.fill")
            }.controlSize(.large).disabled(model.state.projects.isEmpty)
        }
    }
    private func detail(_ project: WallpaperProject) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 10) {
                WallpaperPreview(project:project,revision:model.artworkRevision,active:!showsSettings && !showsWorkshop && renamingProject == nil)
                HStack {
                    Spacer()
                    if let info = model.mediaInfo[project.id] {
                        Text(String(format: L("library.videoMetadata"), String(describing: info.width), String(describing: info.height), String(describing: String(format: "%.1f", info.duration)))).font(.caption.monospacedDigit())
                    }
                }.foregroundStyle(.secondary)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.displayName(for:project)).font(.title3.weight(.semibold)).lineLimit(2)
                }
                Spacer()
                Button { searchFocused = false; renamingProject = project } label: { Image(systemName:"pencil") }
                    .buttonStyle(.borderless).help(L("library.renameWallpaper")).accessibilityLabel(L("library.renameWallpaper"))
                Button { toggleFavorite(project.id) } label: {
                    Image(systemName:model.state.organization.favorites.contains(project.id) ? "star.fill" : "star")
                        .foregroundStyle(model.state.organization.favorites.contains(project.id) ? .orange : .secondary)
                }.buttonStyle(.borderless).help(L("library.favoriteWallpaper"))
                if model.isBusy { ProgressView().controlSize(.small).padding(.top, 5) }
            }
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("library.applyTo")).font(.caption).foregroundStyle(.secondary)
                    Picker(L("library.applyTo"), selection: $target) {
                        Text(L("settings.allDisplays")).tag("all")
                        ForEach(model.displays) { display in Text(display.name).tag(display.id) }
                    }.labelsHidden().frame(width:140)
                }.disabled(model.isBusy)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("library.scaling")).font(.caption).foregroundStyle(.secondary)
                    Picker(L("library.scaling"), selection: $fit) {
                        Text(L("library.fillDisplay")).tag(FitMode.fill)
                        Text(L("library.fitToDisplay")).tag(FitMode.fit)
                    }.labelsHidden().frame(width:115)
                }.disabled(model.isBusy)
                VStack(alignment:.leading,spacing:6) {
                    Text(L("library.sound")).font(.caption).foregroundStyle(.secondary)
                    Picker(L("library.sound"),selection:Binding(get:{model.state.isMuted},set:{model.setMuted($0)})) {
                        Text(L("library.playSound")).tag(false)
                        Text(L("settings.mute")).tag(true)
                    }.labelsHidden().frame(width:100)
                }
                Spacer(minLength: 0)
                Button {
                    Task { await model.apply(projectID: project.id, target: target == "all" ? nil : target, fit: fit) }
                } label: { Label(target == "all" ? L("library.applyToAllDisplays") : L("library.applyToSelectedDisplay"), systemImage: "desktopcomputer").padding(.horizontal, 4) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .fixedSize(horizontal:true,vertical:false).layoutPriority(1)
                    .disabled(model.isBusy || model.displays.isEmpty)
            }
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                ForEach(model.displays) { display in
                    let assignment = model.state.assignment(for: display.id)
                    let assignedProject = model.state.projects.first { $0.id == assignment?.projectID }
                    HStack(spacing: 9) {
                        Image(systemName: "display").foregroundStyle(.secondary)
                        Text(display.name).font(.caption.weight(.medium))
                        Spacer()
                        if let assignedProject {
                            Button { revealProject(assignedProject.id) } label: {
                                Text(model.displayName(for: assignedProject)).font(.caption).lineLimit(1)
                            }
                            .buttonStyle(.plain).foregroundStyle(accent)
                            .help(L("library.viewWallpaperDetails"))
                            .accessibilityLabel(String(format: L("library.viewWallpaperDetailsNamed"), String(describing: model.displayName(for: assignedProject))))
                        } else {
                            Text(L("library.systemWallpaper")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "play.rectangle.on.rectangle").font(.system(size: 52, weight: .ultraLight)).foregroundStyle(accent)
            Text(L("library.noWallpapersYet")).font(.title2.weight(.medium))
            Button(L("library.addWallpaper")) { showsWorkshop = true }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.isBusy)
            if model.isBusy { ProgressView(model.importStatus == nil ? L("library.checkingVideo") : L("library.preparingVideo")).font(.caption) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var searchEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass").font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text(L("library.noMatchingWallpapers")).font(.title2)
            Button(L("library.showAllWallpapers")) { searchText = ""; favoritesOnly = false; groupID = nil; searchFocused = false }.buttonStyle(.bordered)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var libraryFilters: some View {
        HStack(spacing:6) {
            Menu {
                Button(L("library.allWallpapers")) { favoritesOnly = false; groupID = nil; searchFocused = false }
                Toggle(L("library.favoritesOnly"),isOn:$favoritesOnly)
                Divider()
                ForEach(model.state.organization.groups) { group in
                    Button(group.name) { groupID = group.id; searchFocused = false }
                }
            } label: {
                Label(groupID.flatMap { id in model.state.organization.groups.first { $0.id == id }?.name } ?? (favoritesOnly ? L("library.myFavorites") : L("library.allWallpapers")),systemImage:favoritesOnly ? "star" : "line.3.horizontal.decrease")
            }.menuStyle(.borderlessButton).lineLimit(1)
            Spacer(minLength:0)
            Menu {
                Picker(L("library.sort"),selection:Binding(get:{ model.state.organization.sort },set:{ sort in
                    var next = model.state.organization; next.sort = sort; model.setOrganization(next)
                })) {
                    Text(L("library.importOrder")).tag(LibrarySort.added)
                    Text(L("library.newestFirst")).tag(LibrarySort.newest)
                    Text(L("library.name")).tag(LibrarySort.title)
                    Text(L("library.favoritesFirst")).tag(LibrarySort.favoritesFirst)
                }
            } label: { Image(systemName:"arrow.up.arrow.down") }.menuStyle(.borderlessButton).fixedSize().help(L("library.sortWallpapers"))
        }.font(.caption)
    }
    private func toggleFavorite(_ id:String) {
        var next = model.state.organization; next.toggleFavorite(id); model.setOrganization(next)
    }
    private func moveToGroup(_ id:String,group:String?) {
        var next = model.state.organization; next.memberships[id] = group; model.setOrganization(next)
    }
    private func updateFit() {
        let assignment = target == "all" ? model.state.defaultAssignment : model.state.assignment(for: target)
        fit = assignment?.projectID == selectedID ? (assignment?.fit ?? .fill) : .fill
    }
    private func revealProject(_ id: String) {
        if !visibleProjects.contains(where: { $0.id == id }) {
            searchText = ""
            favoritesOnly = false
            groupID = nil
        }
        selectedID = id
        revealRequest += 1
        searchFocused = false
    }
    private func importFolder() {
        let panel = NSOpenPanel()
        panel.title = L("library.selectVideoWallpaperFolder")
        panel.message = L("library.selectTheEntireWallpaperFolderContainingProjectJson")
        panel.prompt = L("library.import")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                if let id = await model.importFolder(url) {
                    searchText = ""; favoritesOnly = false; groupID = nil; selectedID = id
                    showsWorkshop = false; searchFocused = false
                }
            }
        }
    }
}

struct PerformanceView: View {
    @ObservedObject var model: LibraryModel
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    private func setting(_ key: WritableKeyPath<PerformanceSettings, Bool>) -> Binding<Bool> {
        Binding(get: { model.state.performance[keyPath: key] }, set: { value in
            var next = model.state.performance
            next[keyPath: key] = value
            model.setPerformance(next)
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "leaf.fill").foregroundStyle(.teal).font(.title2)
                Text(L("library.performancePower")).font(.title2.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: 20) {
                Picker(L("settings.qualityMode"), selection: Binding(get: { model.state.performance.qualityMode }, set: { value in
                    var settings = model.state.performance; settings.qualityMode = value; model.setPerformance(settings)
                })) {
                    Text(L("settings.qualityOriginal")).tag(PlaybackQualityMode.original)
                    Text(L("settings.qualityEnergySaving")).tag(PlaybackQualityMode.energySaving)
                }
                if let message = model.variantStatus { Text(message).font(.caption).foregroundStyle(.secondary) }
                Divider()
                option(L("library.pauseWhenTheDesktopIsFullyCovered"), binding: setting(\.pauseWhenOccluded))
                Divider()
                option(L("library.pauseOnBatteryPower"), binding: setting(\.pauseOnBattery))
                Divider()
                option(L("library.pauseInLowPowerMode"), binding: setting(\.pauseInLowPowerMode))
            }.padding(20).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            if let message = model.errorMessage {
                Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if !embedded {
                HStack { Spacer(); Button(L("settings.done")) { dismiss() }.keyboardShortcut(.defaultAction) }
            }
        }.padding(28).frame(width:510)
    }
    private func option(_ title: String, binding: Binding<Bool>) -> some View {
        Toggle(title, isOn: binding).toggleStyle(.switch)
    }
}

private struct WallpaperPreview: View {
    let project: WallpaperProject
    let revision: Int
    let active: Bool
    @StateObject private var preview = VideoPreviewModel()
    @State private var frameReady = false
    @State private var surfaceVisible = false
    @State private var poster: CGImage?
    var body: some View {
        let posterRatio = poster.map { Double($0.width) / Double($0.height) } ?? 16.0/9.0
        let ratio = frameReady ? (preview.aspectRatio ?? posterRatio) : posterRatio
        GeometryReader { geometry in
            let height = min(248,geometry.size.width/ratio)
            ZStack {
                if let poster { Image(decorative: poster, scale: 1).resizable().scaledToFit() }
                else { Thumbnail(path:nil) }
                VideoPreviewSurface(player:preview.player,onVisibility:{ visible in
                    surfaceVisible = visible
                    preview.setVisible(visible && active)
                },onReady:{ frameReady = $0 })
                    .opacity(frameReady ? 1 : 0)
                if let message = preview.errorMessage {
                    VStack { HStack { Spacer(); Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.orange).help(message) }; Spacer() }.padding(10)
                }
            }
            .frame(width:height*ratio,height:height)
            .clipShape(RoundedRectangle(cornerRadius:14))
            .shadow(color:.black.opacity(0.1),radius:10,y:3)
            .frame(width:geometry.size.width,height:geometry.size.height)
        }.frame(height:248)
        .task(id: (project.previewPath ?? "") + "\0" + String(revision)) {
            poster = nil
            guard let path = project.previewPath else { return }
            let result = await ThumbnailStore.shared.image(url: URL(fileURLWithPath: path), maximumPixelSize: 1024)
            guard !Task.isCancelled else { return }
            poster = result
        }
        .onAppear { preview.setProject(project) }
        .onChange(of:project.id + "\n" + project.videoPath) { _,_ in frameReady = false; preview.setProject(project) }
        .onChange(of:active) { _,value in preview.setVisible(surfaceVisible && value) }
        .onDisappear { preview.stop() }
    }
}

private struct Thumbnail: View {
    let path: String?
    var revision = 0
    var fit: FitMode = .fill
    @State private var image: CGImage?
    var body: some View {
        GeometryReader { geometry in
            if let image {
                Image(decorative: image, scale: 1).resizable()
                    .aspectRatio(contentMode: fit == .fit ? .fit : .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(.black).clipped()
            } else {
                ZStack {
                    Color(nsColor: .underPageBackgroundColor)
                    Image(systemName: "film").font(.title).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: (path ?? "") + "\0" + String(revision)) {
            image = nil
            guard let path else { return }
            let result = await ThumbnailStore.shared.image(url: URL(fileURLWithPath: path), maximumPixelSize: 256)
            guard !Task.isCancelled else { return }
            image = result
        }
    }
}

private struct RenameWallpaperView: View {
    @ObservedObject var model: LibraryModel
    let project: WallpaperProject
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    @FocusState private var nameFocused: Bool
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text(L("library.renameWallpaper")).font(.title2.weight(.semibold))
            TextField(L("library.wallpaperName"),text:$name).textFieldStyle(.roundedBorder).focused($nameFocused)
                .accessibilityLabel(L("library.wallpaperName")).onSubmit(save)
            Text(String(format: L("library.originalName"), project.title)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button(L("library.restoreOriginalName")) {
                    if model.rename(projectID:project.id,name:nil) { dismiss() } else { error = model.errorMessage }
                }.disabled(model.state.organization.customNames[project.id] == nil)
                Spacer()
                Button(L("library.cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("library.save"),action:save).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width:430)
        .onAppear { name = model.displayName(for:project); nameFocused = true }
    }
    private func save() {
        if model.rename(projectID:project.id,name:name) { dismiss() } else { error = model.errorMessage }
    }
}
