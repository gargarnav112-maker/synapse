import AVFoundation

/// One capture format on one camera, reduced to the facts the selector needs.
/// Plain values, so the selection rules can be unit-tested without a camera.
nonisolated struct FormatCandidate: Sendable, Identifiable, Hashable {
    let id: Int
    let deviceName: String
    let deviceKind: DeviceKind
    let width: Int
    let height: Int
    let maxFPS: Double
    /// Closest focus distance in mm; -1 when the device does not report it.
    let minimumFocusDistanceMm: Int
    let isFullRange: Bool

    var pixels: Int { width * height }
    var label: String { "\(width)×\(height) @ \(Int(maxFPS.rounded())) fps" }
}

nonisolated enum DeviceKind: String, Sendable, Hashable {
    case wide = "Wide"
    case ultraWide = "Ultra Wide"
    case frontTrueDepth = "Front TrueDepth"
    case frontWide = "Front Wide"

    /// Tie-break order: prefer the wide camera (more resolution per degree).
    var preference: Int {
        switch self {
        case .wide, .frontTrueDepth: 2
        case .ultraWide, .frontWide: 1
        }
    }
}

nonisolated struct FormatChoice: Sendable {
    let chosen: FormatCandidate?
    let fps: Double
    let usedFallback: Bool
    let reason: String
    /// Candidate id → why it was not chosen.
    let rejections: [Int: String]
}

/// Picks the device and format: at least 120 fps (else 60 fps with a warning),
/// a closest focus distance no greater than the working distance, and the
/// highest resolution up to 1920×1080. Ties go to the wide camera, then to the
/// shorter focus distance, then to full-range video.
nonisolated enum FormatSelector {
    static func choose(_ candidates: [FormatCandidate], workingDistanceMm: Int) -> FormatChoice {
        var rejections: [Int: String] = [:]

        func rejection(_ c: FormatCandidate, fps: Double) -> String? {
            if c.width > Tuning.maxFormatWidth || c.height > Tuning.maxFormatHeight {
                return "Larger than \(Tuning.maxFormatWidth)×\(Tuning.maxFormatHeight)"
            }
            if c.maxFPS + 0.5 < fps {
                return "Max \(Int(c.maxFPS.rounded())) fps, below \(Int(fps)) fps"
            }
            if c.minimumFocusDistanceMm > workingDistanceMm {
                return "Focuses no closer than \(c.minimumFocusDistanceMm / 10) cm"
            }
            return nil
        }

        func better(_ a: FormatCandidate, than b: FormatCandidate) -> Bool {
            if a.pixels != b.pixels { return a.pixels > b.pixels }
            if a.deviceKind.preference != b.deviceKind.preference {
                return a.deviceKind.preference > b.deviceKind.preference
            }
            let fa = a.minimumFocusDistanceMm < 0 ? Int.max : a.minimumFocusDistanceMm
            let fb = b.minimumFocusDistanceMm < 0 ? Int.max : b.minimumFocusDistanceMm
            if fa != fb { return fa < fb }
            if a.isFullRange != b.isFullRange { return a.isFullRange }
            return a.id < b.id
        }

        for (pass, fps) in [Tuning.targetFPS, Tuning.fallbackFPS].enumerated() {
            var best: FormatCandidate?
            for c in candidates {
                if let why = rejection(c, fps: fps) {
                    if pass == 0 { rejections[c.id] = why }
                    continue
                }
                if best == nil || better(c, than: best!) { best = c }
            }
            if let best {
                for c in candidates where c.id != best.id && rejections[c.id] == nil {
                    rejections[c.id] = "Lower priority (resolution, then camera, then focus distance)"
                }
                let focus = best.minimumFocusDistanceMm < 0
                    ? "focus distance not reported"
                    : "focuses from \(best.minimumFocusDistanceMm / 10) cm"
                let reason = "\(best.deviceKind.rawValue), \(best.label), \(focus); "
                    + "highest resolution meeting \(Int(fps)) fps at \(workingDistanceMm / 10) cm."
                return FormatChoice(chosen: best, fps: fps, usedFallback: pass > 0,
                                    reason: reason, rejections: rejections)
            }
        }
        return FormatChoice(chosen: nil, fps: 0, usedFallback: true,
                            reason: "No format reaches \(Int(Tuning.fallbackFPS)) fps at this working distance.",
                            rejections: rejections)
    }
}

/// The real formats on this phone, with handles back to AVFoundation objects.
/// Used only on the camera engine's session queue.
nonisolated struct FormatCatalog {
    var candidates: [FormatCandidate] = []
    var entries: [Int: (AVCaptureDevice, AVCaptureDevice.Format)] = [:]

    static func back() -> FormatCatalog {
        build(types: [(.builtInWideAngleCamera, .wide), (.builtInUltraWideCamera, .ultraWide)],
              position: .back, firstID: 0)
    }

    static func front() -> FormatCatalog {
        build(types: [(.builtInTrueDepthCamera, .frontTrueDepth), (.builtInWideAngleCamera, .frontWide)],
              position: .front, firstID: 10_000)
    }

    private static func build(types: [(AVCaptureDevice.DeviceType, DeviceKind)],
                              position: AVCaptureDevice.Position, firstID: Int) -> FormatCatalog {
        var catalog = FormatCatalog()
        var nextID = firstID
        var seen = Set<String>()
        for (type, kind) in types {
            let devices = AVCaptureDevice.DiscoverySession(
                deviceTypes: [type], mediaType: .video, position: position).devices
            for device in devices {
                // Prefer full-range (420f) when the same size and rate exist twice.
                let formats = device.formats.sorted { fullRange($0) && !fullRange($1) }
                for format in formats {
                    let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                    let maxFPS = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
                    let key = "\(device.uniqueID)-\(dims.width)x\(dims.height)-\(Int(maxFPS))"
                    guard maxFPS > 0, seen.insert(key).inserted else { continue }
                    let c = FormatCandidate(
                        id: nextID, deviceName: device.localizedName, deviceKind: kind,
                        width: Int(dims.width), height: Int(dims.height), maxFPS: maxFPS,
                        minimumFocusDistanceMm: device.minimumFocusDistance,
                        isFullRange: fullRange(format))
                    catalog.candidates.append(c)
                    catalog.entries[nextID] = (device, format)
                    nextID += 1
                }
            }
        }
        return catalog
    }

    private static func fullRange(_ format: AVCaptureDevice.Format) -> Bool {
        CMFormatDescriptionGetMediaSubType(format.formatDescription)
            == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    }
}
