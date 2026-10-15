import Foundation
import Observation

/// Root app state: the safety acknowledgement and user settings, persisted in
/// UserDefaults. Nothing here leaves the phone.
@MainActor
@Observable
final class AppModel {
    private let defaults = UserDefaults.standard

    var safetyAccepted: Bool {
        didSet { defaults.set(safetyAccepted, forKey: Keys.safety) }
    }

    /// Lens-to-eye distance in cm (set by the eyecup).
    var workingDistanceCm: Double {
        didSet { defaults.set(workingDistanceCm, forKey: Keys.distance) }
    }

    /// Torch level during baseline, 0…1.
    var torchBaseline: Float {
        didSet { defaults.set(torchBaseline, forKey: Keys.torch) }
    }

    /// Shared so the Camera Report and the live view see the same camera.
    let camera = CameraController()

    init() {
        safetyAccepted = defaults.bool(forKey: Keys.safety)
        let d = defaults.double(forKey: Keys.distance)
        workingDistanceCm = d > 0 ? d : Tuning.defaultWorkingDistanceCm
        let t = defaults.float(forKey: Keys.torch)
        torchBaseline = t > 0 ? t : Tuning.defaultTorchBaseline
    }

    private enum Keys {
        static let safety = "safetyAccepted.v1"
        static let distance = "workingDistanceCm"
        static let torch = "torchBaseline"
    }
}
