import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WallpaperCore
import WallpaperRuntime

@MainActor
struct FeatureSettingsView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var model: LibraryModel
    @ObservedObject var startup: LoginStartupModel
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @State private var newGroupName = ""
    @State private var groupNames: [String: String] = [:]
    @State private var playlist = PlaylistSettings()
    @State private var loadedDraft = false
    @State private var playlistSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("settings.libraryAutoplay")).font(.title2.weight(.semibold))
            TabView {
                groupsTab.tabItem { Label(L("settings.groups"), systemImage: "folder") }
                playlistTab.tabItem { Label(L("settings.rotationDayNight"), systemImage: "repeat") }
                rulesTab.tabItem { Label(L("settings.applicationRules"), systemImage: "app.badge") }
                startupTab.tabItem { Label(L("settings.launchAtLogin"), systemImage: "power") }
            }
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3).textSelection(.enabled)
            }
            if !embedded {
                HStack {
                    Spacer()
                    Button(L("settings.done")) { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width:650,height:embedded ? 520 : 560)
        .onAppear {
            if !loadedDraft {
                playlist = model.state.playlist
                groupNames = Dictionary(uniqueKeysWithValues: model.state.organization.groups.map { ($0.id, $0.name) })
                loadedDraft = true
            }
            startup.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            startup.refresh()
        }
        .onChange(of: playlist) { _, _ in playlistSaved = false }
    }

    private var groupsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    TextField(L("settings.newGroupName"), text: $newGroupName).textFieldStyle(.roundedBorder)
                        .onSubmit(addGroup)
                    Button(L("settings.addGroup"), action: addGroup)
                        .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if model.state.organization.groups.isEmpty {
                    Text(L("settings.noGroupsYet"))
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 20)
                }
                ForEach(model.state.organization.groups) { group in
                    HStack(spacing: 10) {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        TextField(L("settings.groupName"), text: Binding(
                            get: { groupNames[group.id] ?? group.name },
                            set: { groupNames[group.id] = $0 }
                        )).textFieldStyle(.roundedBorder)
                        Button(L("settings.rename")) { renameGroup(group.id) }
                        Button(L("settings.delete"), role: .destructive) {
                            var value = model.state.organization
                            value.deleteGroup(group.id)
                            model.setOrganization(value)
                            groupNames.removeValue(forKey: group.id)
                        }
                    }
                }
            }.padding(18)
        }
    }

    private var playlistTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(L("settings.enableAutomaticSwitching"), isOn: $playlist.enabled).toggleStyle(.switch)
                Picker(L("settings.switchingMode"), selection: $playlist.mode) {
                    Text(L("settings.rotateAtIntervals")).tag(PlaylistMode.interval)
                    Text(L("settings.switchByDayNight")).tag(PlaylistMode.dayNight)
                }.pickerStyle(.segmented)
                displayPicker
                if playlist.mode == .interval { intervalOptions }
                else { dayNightOptions }
                HStack {
                    if playlistSaved {
                        Label(L("settings.rotationSettingsSaved"), systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("settings.saveRotationSettings")) {
                        model.setPlaylist(playlist)
                        playlistSaved = model.state.playlist == playlist
                    }.buttonStyle(.borderedProminent).disabled(model.isBusy)
                }
            }.padding(18)
        }
    }

    private var displayPicker: some View {
        Picker(L("settings.targetDisplay"), selection: $playlist.targetDisplayID) {
            Text(L("settings.allDisplays")).tag(nil as String?)
            ForEach(model.displays) { display in Text(display.name).tag(Optional(display.id)) }
            if let id = playlist.targetDisplayID, !model.displays.contains(where: { $0.id == id }) {
                Text(L("settings.disconnectedDisplay")).tag(Optional(id))
            }
        }
    }

    private var intervalOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("settings.switchingInterval"))
                TextField(L("settings.minutes"), value: $playlist.intervalMinutes, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 70)
                Text(L("settings.intervalMinutesRange")).foregroundStyle(.secondary)
                Spacer()
            }
            Picker(L("settings.playbackOrder"), selection: $playlist.order) {
                Text(L("settings.inListOrder")).tag(PlaylistOrder.sequential)
                Text(L("settings.shuffle")).tag(PlaylistOrder.random)
            }
            Text(L("settings.selectAtLeastTwoWallpapers")).font(.callout.weight(.medium))
            if model.state.projects.isEmpty {
                Text(L("settings.importWallpapersFirst")) .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(model.state.projects) { project in
                Toggle(model.displayName(for:project), isOn: Binding(
                    get: { playlist.projectIDs.contains(project.id) },
                    set: { included in
                        if included {
                            if !playlist.projectIDs.contains(project.id) { playlist.projectIDs.append(project.id) }
                        } else { playlist.projectIDs.removeAll { $0 == project.id } }
                    }
                )).toggleStyle(.checkbox)
            }
        }
    }

    private var dayNightOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            projectPicker(L("settings.daytimeWallpaper"), selection: $playlist.dayProjectID)
            DatePicker(L("settings.dayStarts"), selection: timeBinding(\.dayStartMinute), displayedComponents: .hourAndMinute)
            Divider()
            projectPicker(L("settings.nighttimeWallpaper"), selection: $playlist.nightProjectID)
            DatePicker(L("settings.nightStarts"), selection: timeBinding(\.nightStartMinute), displayedComponents: .hourAndMinute)
        }
    }

    private func projectPicker(_ title: String, selection: Binding<String?>) -> some View {
        Picker(title, selection: selection) {
            Text(L("settings.selectAWallpaper")).tag(nil as String?)
            ForEach(model.state.projects) { project in Text(model.displayName(for:project)).tag(Optional(project.id)) }
            if let id = selection.wrappedValue, !model.state.projects.contains(where: { $0.id == id }) {
                Text(L("settings.wallpaperRemovedSelectAnother")).tag(Optional(id))
            }
        }
    }

    private func timeBinding(_ key: WritableKeyPath<PlaylistSettings, Int>) -> Binding<Date> {
        Binding(get: {
            let minute = playlist[keyPath: key]
            return Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 15, hour: minute / 60, minute: minute % 60)) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            playlist[keyPath: key] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        })
    }

    private var rulesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer()
                    Button(L("settings.addApplication"), action: addApplication)
                }
                if model.state.applicationRules.isEmpty {
                    Text(L("settings.noApplicationRulesYet"))
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 20)
                }
                ForEach(model.state.applicationRules) { rule in ruleRow(rule) }
            }.padding(18)
        }
    }

    private func ruleRow(_ rule: ApplicationRule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle(rule.name, isOn: ruleBinding(rule.id, \.enabled, fallback: rule.enabled)).toggleStyle(.checkbox)
                Spacer()
                Button(L("settings.delete"), role: .destructive) {
                    model.setApplicationRules(model.state.applicationRules.filter { $0.id != rule.id })
                }
            }
            HStack(spacing: 14) {
                Picker(L("settings.whenApplication"), selection: ruleBinding(rule.id, \.condition, fallback: rule.condition)) {
                    Text(L("settings.isRunning")).tag(ApplicationRuleCondition.running)
                    Text(L("settings.isInForeground")).tag(ApplicationRuleCondition.frontmost)
                }
                Picker(L("settings.wallpaper"), selection: ruleBinding(rule.id, \.action, fallback: rule.action)) {
                    Text(L("settings.mute")).tag(ApplicationRuleAction.mute)
                    Text(L("settings.pause")).tag(ApplicationRuleAction.pause)
                    Text(L("settings.stopAndFreeResources")).tag(ApplicationRuleAction.stop)
                }
            }
        }.padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func ruleBinding<Value>(_ id: String, _ key: WritableKeyPath<ApplicationRule, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: {
            model.state.applicationRules.first(where: { $0.id == id })?[keyPath: key] ?? fallback
        }, set: { value in
            var rules = model.state.applicationRules
            guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
            rules[index][keyPath: key] = value
            model.setApplicationRules(rules)
        })
    }

    private var startupTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle(L("settings.playWallpapersAutomaticallyAfterLoggingInToYour"), isOn: Binding(
                get: { startup.enabled || startup.needsApproval },
                set: { startup.setEnabled($0) }
            )).toggleStyle(.switch)
            if startup.needsApproval {
                Label(L("settings.allowLaunchAtLoginInSystemSettings"), systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                Button(L("settings.openLoginItemsSettings")) { startup.openSettings() }
            } else {
                Label(startup.enabled ? L("settings.launchAtLoginEnabled") : L("settings.launchAtLoginDisabled"), systemImage: startup.enabled ? "checkmark.circle" : "minus.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let error = startup.errorMessage {
                Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
            }
            Spacer()
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addGroup() {
        var value = model.state.organization
        do {
            let id = try value.addGroup(newGroupName)
            model.setOrganization(value)
            if model.state.organization.groups.contains(where: { $0.id == id }) {
                groupNames[id] = value.groups.first(where: { $0.id == id })?.name
                newGroupName = ""
            }
        } catch { model.errorMessage = error.localizedDescription }
    }

    private func renameGroup(_ id: String) {
        var value = model.state.organization
        do {
            try value.renameGroup(id, name: groupNames[id] ?? "")
            model.setOrganization(value)
        } catch { model.errorMessage = error.localizedDescription }
    }

    private func addApplication() {
        let panel = NSOpenPanel()
        panel.title = L("settings.selectApplication")
        panel.prompt = L("settings.addRule")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !id.isEmpty else {
                    model.errorMessage = L("settings.theSelectedApplicationCouldNotBeIdentifiedSelect")
                    return
                }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                var rules = model.state.applicationRules
                rules.append(ApplicationRule(bundleID: id, name: name))
                model.setApplicationRules(rules)
            }
        }
    }
}
