import Foundation

public enum FitMode: String, Codable, CaseIterable { case fill, fit }
public struct Assignment: Codable, Equatable {
    public var projectID: String
    public var fit: FitMode
    public init(projectID: String, fit: FitMode = .fill) { self.projectID = projectID; self.fit = fit }
}
public enum AutomaticPauseReason: String, Hashable { case occluded, battery, lowPowerMode, appInFront }
public enum PlaybackQualityMode: String, Codable, CaseIterable {
    case original, energySaving
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .original
    }
}
public struct PerformanceSettings: Codable, Equatable {
    public var pauseWhenOccluded = true
    public var pauseOnBattery = false
    public var pauseInLowPowerMode = true
    public var pauseWhenAnyAppInFront = false
    public var qualityMode: PlaybackQualityMode = .original
    public init() {}
    private enum CodingKeys: String, CodingKey { case pauseWhenOccluded, pauseOnBattery, pauseInLowPowerMode, pauseWhenAnyAppInFront, qualityMode }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pauseWhenOccluded = try values.decodeIfPresent(Bool.self, forKey: .pauseWhenOccluded) ?? true
        pauseOnBattery = try values.decodeIfPresent(Bool.self, forKey: .pauseOnBattery) ?? false
        pauseInLowPowerMode = try values.decodeIfPresent(Bool.self, forKey: .pauseInLowPowerMode) ?? true
        pauseWhenAnyAppInFront = try values.decodeIfPresent(Bool.self, forKey: .pauseWhenAnyAppInFront) ?? false
        qualityMode = try values.decodeIfPresent(PlaybackQualityMode.self, forKey: .qualityMode) ?? .original
    }
    public func pauseReasons(onBattery: Bool, lowPowerMode: Bool, occluded: Bool, appInFront: Bool = false) -> Set<AutomaticPauseReason> {
        var reasons: Set<AutomaticPauseReason> = []
        if pauseWhenOccluded && occluded { reasons.insert(.occluded) }
        if pauseOnBattery && onBattery { reasons.insert(.battery) }
        if pauseInLowPowerMode && lowPowerMode { reasons.insert(.lowPowerMode) }
        if pauseWhenAnyAppInFront && appInFront { reasons.insert(.appInFront) }
        return reasons
    }
}
public struct AppState: Codable, Equatable {
    public var projects: [WallpaperProject] = []
    public var assignments: [String: Assignment] = [:]
    public var defaultAssignment: Assignment?
    public var manuallyPaused = false
    public var isMuted = false
    public var performance = PerformanceSettings()
    public var organization = LibraryOrganization()
    public var playlist = PlaylistSettings()
    public var applicationRules: [ApplicationRule] = []
    public init() {}
    private enum CodingKeys: String, CodingKey { case projects, assignments, defaultAssignment, manuallyPaused, isMuted, performance, organization, playlist, applicationRules }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        projects = try values.decode([WallpaperProject].self, forKey: .projects)
        assignments = try values.decode([String: Assignment].self, forKey: .assignments)
        defaultAssignment = try values.decodeIfPresent(Assignment.self, forKey: .defaultAssignment)
        manuallyPaused = try values.decode(Bool.self, forKey: .manuallyPaused)
        isMuted = try values.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        performance = try values.decodeIfPresent(PerformanceSettings.self, forKey: .performance) ?? PerformanceSettings()
        organization = try values.decodeIfPresent(LibraryOrganization.self, forKey: .organization) ?? LibraryOrganization()
        playlist = try values.decodeIfPresent(PlaylistSettings.self, forKey: .playlist) ?? PlaylistSettings()
        applicationRules = try values.decodeIfPresent([ApplicationRule].self, forKey: .applicationRules) ?? []
    }
    public func assignment(for displayID: String) -> Assignment? { assignments[displayID] ?? defaultAssignment }
    public mutating func applyToAll(_ assignment: Assignment, displays: [String]) {
        defaultAssignment = assignment
        for id in displays { assignments[id] = assignment }
    }
    public mutating func remove(projectID: String) {
        projects.removeAll { $0.id == projectID }
        organization.removeProject(projectID)
        playlist.projectIDs.removeAll { $0 == projectID }
        if playlist.dayProjectID == projectID { playlist.dayProjectID = nil }
        if playlist.nightProjectID == projectID { playlist.nightProjectID = nil }
        if (try? playlist.validate(availableIDs: Set(projects.map(\.id)))) == nil { playlist.enabled = false }
        assignments = assignments.filter { $0.value.projectID != projectID }
        if defaultAssignment?.projectID == projectID { defaultAssignment = nil }
    }
}
public struct PlaybackIntent {
    public var manuallyPaused = false
    public var suspensions: Set<String> = []
    public init() {}
    public var shouldPlay: Bool { !manuallyPaused && suspensions.isEmpty }
}
public enum StateStore {
    public static func save(_ state: AppState, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
    public static func load(from url: URL) throws -> AppState {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppState() }
        return try JSONDecoder().decode(AppState.self, from: Data(contentsOf: url))
    }
}
