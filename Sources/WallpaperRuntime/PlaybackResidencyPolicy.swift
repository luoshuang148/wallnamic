import Foundation

public enum PlaybackResidencyDecision { case retain, release, restore }
public enum PlaybackResidencyPolicy {
    public static func decision(now: Date, hiddenSince: Date?, occlusionPauseEnabled: Bool,
                                systemSuspended: Bool, manuallyPaused: Bool, visible: Bool,
                                isResident: Bool = true) -> PlaybackResidencyDecision {
        if systemSuspended { return isResident ? .release : .retain }
        if visible || !occlusionPauseEnabled { return isResident ? .retain : .restore }
        if let hiddenSince, now.timeIntervalSince(hiddenSince) >= 30 { return isResident ? .release : .retain }
        // A manual pause on a visible desktop retains the original displayed frame.
        return .retain
    }
}
