import Foundation

/// Every tunable constant in one place, each with what it does and how it was
/// chosen. Change a value here, never inline.
nonisolated enum Tuning {
    // MARK: Capture format

    /// Target capture rate. 120 fps gives one diameter sample every 8.3 ms,
    /// enough to resolve a ~200 ms latency to within one frame.
    static let targetFPS: Double = 120

    /// Fallback when no 120 fps format exists; the UI shows a warning badge.
    static let fallbackFPS: Double = 60

    /// Largest frame considered. More pixels than 1080p only slow detection;
    /// the eye fills the frame inside the eyecup.
    static let maxFormatWidth = 1920
    static let maxFormatHeight = 1080

    /// Default lens-to-eye distance (cm). Set by a ~12 cm cardboard eyecup.
    static let defaultWorkingDistanceCm: Double = 12
    static let workingDistanceRangeCm: ClosedRange<Double> = 5...30

    // MARK: Settle and lock

    /// Longest exposure allowed once locked: 1/240 s keeps motion blur under a
    /// pixel for normal hand tremor at the working distance.
    static let maxLockedExposureSeconds: Double = 1.0 / 240

    /// How long to wait for the one-shot autofocus to finish before locking anyway.
    static let focusTimeoutSeconds: Double = 3

    /// How long to wait for auto-exposure to converge on the new point of interest.
    static let exposureSettleTimeoutSeconds: Double = 1.5

    /// Live values that differ from the locked ones by more than this are shown
    /// as drift in the Lab HUD (the lock must hold for the whole test).
    static let driftExposureSeconds: Double = 2e-6
    static let driftISO: Float = 0.5
    static let driftLensPosition: Float = 0.002

    // MARK: Torch and flash (safety rules)

    /// Torch level during baseline: dim enough not to constrict the pupil,
    /// bright enough to see the eye inside the eyecup. Spec default.
    static let defaultTorchBaseline: Float = 0.05
    static let torchBaselineRange: ClosedRange<Float> = 0.01...0.30

    /// Flash width. Capped at 200 ms by the safety rules; never raise it.
    static let flashDurationSeconds: Double = 0.200

    /// At least this long between flashes (safety rule; enforced globally until
    /// per-eye tracking exists in Milestone 3).
    static let minFlashIntervalSeconds: Double = 20

    /// At most this many flashes in any rolling window (safety rule).
    static let maxFlashesPerWindow = 10
    static let flashWindowSeconds: Double = 600

    // MARK: Lab HUD and acceptance check

    /// HUD refresh period (10 Hz is readable and cheap).
    static let hudRefreshSeconds: Double = 0.1

    /// Frames averaged for the live fps readout (~1 s at 120 fps).
    static let fpsWindowFrames = 120

    /// Milestone 1 acceptance: at least 118 fps for 30 s with under 1 % dropped.
    static let fpsCheckSeconds: Double = 30
    static let fpsCheckMinFPS: Double = 118
    static let fpsCheckMaxDropFraction: Double = 0.01
}
