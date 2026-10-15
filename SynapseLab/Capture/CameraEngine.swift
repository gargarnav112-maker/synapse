import AVFoundation
import os

// MARK: - Values shared with the UI

/// Camera values frozen by settle-and-lock, plus the auto values they came from.
nonisolated struct LockedSettings: Sendable, Equatable {
    var autoExposureSeconds: Double
    var autoISO: Float
    var exposureSeconds: Double
    var iso: Float
    var lensPosition: Float
    var whiteBalanceGains: SIMD3<Float>?
}

/// One commanded flash, timed on the capture session's clock (the same clock
/// as frame presentation timestamps).
nonisolated struct FlashRecord: Sendable, Equatable {
    var onTime: Double
    var offTime: Double
    var peakLevel: Float
    var baselineLevel: Float
    var durationMs: Double { (offTime - onTime) * 1000 }
}

/// The 30-second frame-rate acceptance check.
nonisolated struct FPSCheck: Sendable, Equatable {
    var startTime: Double?
    var startDelivered = 0
    var startDropped = 0
    var elapsed: Double = 0
    var meanFPS: Double = 0
    var dropFraction: Double = 0
    var finished = false
    var passed: Bool {
        finished && meanFPS >= Tuning.fpsCheckMinFPS && dropFraction < Tuning.fpsCheckMaxDropFraction
    }
}

/// What the camera found and set, for the Camera Report screen.
nonisolated struct CameraReport: Sendable {
    var backCandidates: [FormatCandidate] = []
    var frontCandidates: [FormatCandidate] = []
    var backChoice: FormatChoice?
    var frontChoice: FormatChoice?
    /// Read back from the device after configuration.
    var applied: [(String, String)] = []
}

/// Everything the Lab HUD shows. Copied out under a lock at 10 Hz.
nonisolated struct CameraStats: Sendable {
    var running = false
    var interrupted = false
    var status = "Idle"
    var deviceName = ""
    var formatLabel = ""
    var targetFPS: Double = 0
    var usedFallbackFPS = false
    var measuredFPS: Double = 0
    var framesDelivered = 0
    var framesDropped = 0
    var exposureSeconds: Double = 0
    var iso: Float = 0
    var lensPosition: Float = 0
    var torchLevel: Float = 0
    var torchAvailable = false
    var isSettling = false
    var locked: LockedSettings?
    var isFlashing = false
    var lastFlash: FlashRecord?
    var flashUptimes: [Double] = []
    var fpsCheck: FPSCheck?
    var thermal: ProcessInfo.ThermalState = .nominal

    var dropFraction: Double {
        let total = framesDelivered + framesDropped
        return total == 0 ? 0 : Double(framesDropped) / Double(total)
    }

    /// Lock drift: any live value that moved away from its locked value.
    var drift: [String] {
        guard let l = locked else { return [] }
        var out: [String] = []
        if abs(exposureSeconds - l.exposureSeconds) > Tuning.driftExposureSeconds { out.append("exposure") }
        if abs(iso - l.iso) > Tuning.driftISO { out.append("ISO") }
        if abs(lensPosition - l.lensPosition) > Tuning.driftLensPosition { out.append("lens") }
        return out
    }
}

nonisolated enum CameraError: LocalizedError {
    case permissionDenied
    case noCamera
    case noTorch
    case notRunning
    case thermal(ProcessInfo.ThermalState)
    case busy(String)
    case flashGuard(String)
    case configuration(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Camera access is off. Turn it on in Settings › Privacy › Camera."
        case .noCamera: "No back camera format reaches 60 fps at this working distance."
        case .noTorch: "This camera has no usable torch right now."
        case .notRunning: "The camera is not running."
        case .thermal: "The phone is too hot. Let it cool down before testing."
        case .busy(let what): "Wait until \(what) finishes."
        case .flashGuard(let why): why
        case .configuration(let why): why
        }
    }
}

// MARK: - Engine

/// Owns the capture session. All configuration runs on `sessionQueue`, frames
/// arrive on `captureQueue`, torch edges run on `flashQueue`, and device
/// configuration from any of them is serialised by `configLock`. The UI reads
/// a copy of `CameraStats` through `snapshot()`.
nonisolated final class CameraEngine: NSObject, @unchecked Sendable,
    AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "synapselab.session", qos: .userInitiated)
    private let captureQueue = DispatchQueue(label: "synapselab.capture", qos: .userInteractive)
    private let flashQueue = DispatchQueue(label: "synapselab.flash", qos: .userInteractive)
    private let configLock = NSLock()
    private let state = OSAllocatedUnfairLock(initialState: CameraStats())
    private let reportState = OSAllocatedUnfairLock(initialState: CameraReport())

    private let videoOutput = AVCaptureVideoDataOutput()
    // Set on sessionQueue during start; read elsewhere only while running.
    private var device: AVCaptureDevice?
    private var torchBaseline: Float = Tuning.defaultTorchBaseline
    private var observers: [NSObjectProtocol] = []

    // captureQueue only.
    private var recentTimes: [Double] = []
    private var frameCounter = 0

    func snapshot() -> CameraStats {
        var s = state.withLock { $0 }
        s.thermal = ProcessInfo.processInfo.thermalState
        return s
    }

    func report() -> CameraReport { reportState.withLock { $0 } }

    // MARK: Start and stop

    /// Configures the back camera for Operator mode and starts it.
    func start(workingDistanceCm: Double, torchBaseline: Float) async throws {
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw CameraError.permissionDenied }
        try await onSessionQueue { [self] in
            try configureAndStart(workingDistanceMm: Int((workingDistanceCm * 10).rounded()),
                                  torchBaseline: torchBaseline)
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            withDevice { d in if d.hasTorch, d.torchMode != .off { d.torchMode = .off } }
            if session.isRunning { session.stopRunning() }
            for o in observers { NotificationCenter.default.removeObserver(o) }
            observers.removeAll()
            state.withLock { s in
                s.running = false
                s.locked = nil
                s.status = "Stopped"
            }
        }
    }

    private func configureAndStart(workingDistanceMm: Int, torchBaseline: Float) throws {
        let back = FormatCatalog.back()
        let front = FormatCatalog.front()
        let choice = FormatSelector.choose(back.candidates, workingDistanceMm: workingDistanceMm)
        let frontChoice = FormatSelector.choose(front.candidates, workingDistanceMm: workingDistanceMm)
        let backCandidates = back.candidates
        let frontCandidates = front.candidates
        reportState.withLock { r in
            r.backCandidates = backCandidates
            r.frontCandidates = frontCandidates
            r.backChoice = choice
            r.frontChoice = frontChoice
        }
        guard let chosen = choice.chosen, let entry = back.entries[chosen.id] else {
            throw CameraError.noCamera
        }
        let (device, format) = entry

        session.beginConfiguration()
        session.sessionPreset = .inputPriority
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }

        let input: AVCaptureDeviceInput
        do { input = try AVCaptureDeviceInput(device: device) } catch {
            session.commitConfiguration()
            throw CameraError.configuration("Could not open the camera: \(error.localizedDescription)")
        }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraError.configuration("The session refused the camera input.")
        }
        session.addInput(input)

        // BGRA, because detection (Milestone 2) uses the red channel.
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw CameraError.configuration("The session refused the video output.")
        }
        session.addOutput(videoOutput)
        if let connection = videoOutput.connection(with: .video),
           connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .off
        }

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(choice.fps))
        do {
            try configure(device) { d in
                d.activeFormat = format
                d.activeVideoMinFrameDuration = frameDuration
                d.activeVideoMaxFrameDuration = frameDuration
                if format.isAutoVideoFrameRateSupported { d.isAutoVideoFrameRateEnabled = false }
                if format.isVideoHDRSupported {
                    d.automaticallyAdjustsVideoHDREnabled = false
                    d.isVideoHDREnabled = false
                }
                if d.isLowLightBoostSupported { d.automaticallyEnablesLowLightBoostWhenAvailable = false }
                d.isSubjectAreaChangeMonitoringEnabled = false
                if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
                if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
                if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    d.whiteBalanceMode = .continuousAutoWhiteBalance
                }
            }
        } catch {
            session.commitConfiguration()
            throw CameraError.configuration("Could not configure the camera: \(error.localizedDescription)")
        }
        session.commitConfiguration()

        self.device = device
        self.torchBaseline = torchBaseline
        recentTimesReset()
        observeSession()
        session.startRunning()
        applyTorchBaseline()

        // Read back what the device actually runs with.
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let maxRate = 1 / device.activeVideoMinFrameDuration.seconds
        let minRate = 1 / device.activeVideoMaxFrameDuration.seconds
        let stab = videoOutput.connection(with: .video)?.activeVideoStabilizationMode
        let applied: [(String, String)] = [
            ("Device", device.localizedName),
            ("Active format", "\(dims.width)×\(dims.height)"),
            ("Frame rate (min…max)", String(format: "%.1f…%.1f fps", minRate, maxRate)),
            ("Pixel output", "32BGRA"),
            ("Session preset", "inputPriority"),
            ("Video stabilisation", stab == .off ? "Off" : "\(String(describing: stab?.rawValue))"),
            ("Video HDR", device.activeFormat.isVideoHDRSupported ? (device.isVideoHDREnabled ? "On" : "Off") : "Not supported"),
            ("Low-light boost", device.isLowLightBoostSupported
                ? (device.automaticallyEnablesLowLightBoostWhenAvailable ? "Auto" : "Off") : "Not supported"),
            ("Auto frame rate", device.activeFormat.isAutoVideoFrameRateSupported
                ? (device.isAutoVideoFrameRateEnabled ? "On" : "Off") : "Not supported"),
            ("Subject-area monitoring", device.isSubjectAreaChangeMonitoringEnabled ? "On" : "Off"),
            ("Torch", device.hasTorch ? "Available" : "None"),
            ("Exposure range", String(format: "%.0f µs…%.0f ms",
                                      device.activeFormat.minExposureDuration.seconds * 1e6,
                                      device.activeFormat.maxExposureDuration.seconds * 1e3)),
            ("ISO range", String(format: "%.0f…%.0f", device.activeFormat.minISO, device.activeFormat.maxISO)),
            ("Minimum focus distance", device.minimumFocusDistance < 0
                ? "Not reported" : "\(device.minimumFocusDistance) mm"),
        ]
        reportState.withLock { $0.applied = applied }

        let label = "\(dims.width)×\(dims.height)"
        let name = device.localizedName
        let fallback = choice.usedFallback
        let fps = choice.fps
        let torch = device.hasTorch && device.isTorchAvailable
        state.withLock { s in
            s.running = true
            s.interrupted = false
            s.status = "Live"
            s.deviceName = name
            s.formatLabel = label
            s.targetFPS = fps
            s.usedFallbackFPS = fallback
            s.framesDelivered = 0
            s.framesDropped = 0
            s.locked = nil
            s.torchAvailable = torch
        }
    }

    private func observeSession() {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        let nc = NotificationCenter.default
        observers = [
            nc.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) {
                [state] _ in state.withLock { s in s.interrupted = true; s.status = "Interrupted" }
            },
            nc.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) {
                [state] _ in state.withLock { s in s.interrupted = false; s.status = "Live" }
            },
            nc.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) {
                [state] _ in state.withLock { s in s.status = "Camera error"; s.running = false }
            },
        ]
    }

    // MARK: Frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let t = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        recentTimes.append(t)
        if recentTimes.count > Tuning.fpsWindowFrames + 1 {
            recentTimes.removeFirst(recentTimes.count - Tuning.fpsWindowFrames - 1)
        }
        let span = (recentTimes.last ?? 0) - (recentTimes.first ?? 0)
        let fps = span > 0 ? Double(recentTimes.count - 1) / span : 0

        // Live device values every 8th frame (~15 Hz), for the HUD and drift check.
        frameCounter += 1
        var live: (Double, Float, Float, Float)?
        if frameCounter % 8 == 0, let d = device {
            live = (d.exposureDuration.seconds, d.iso, d.lensPosition, d.hasTorch ? d.torchLevel : 0)
        }
        let sample = live
        state.withLock { s in
            s.framesDelivered += 1
            s.measuredFPS = fps
            if let (e, i, l, tl) = sample {
                s.exposureSeconds = e
                s.iso = i
                s.lensPosition = l
                s.torchLevel = tl
            }
            if var check = s.fpsCheck, !check.finished {
                if check.startTime == nil {
                    check.startTime = t
                    check.startDelivered = s.framesDelivered
                    check.startDropped = s.framesDropped
                }
                check.elapsed = t - (check.startTime ?? t)
                let delivered = s.framesDelivered - check.startDelivered
                let dropped = s.framesDropped - check.startDropped
                if check.elapsed > 0 { check.meanFPS = Double(delivered) / check.elapsed }
                let total = delivered + dropped
                check.dropFraction = total == 0 ? 0 : Double(dropped) / Double(total)
                if check.elapsed >= Tuning.fpsCheckSeconds { check.finished = true }
                s.fpsCheck = check
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        state.withLock { $0.framesDropped += 1 }
    }

    private func recentTimesReset() {
        captureQueue.sync {
            recentTimes.removeAll()
            frameCounter = 0
        }
    }

    // MARK: Lab checks

    /// Resets counters and measures delivered fps and drops for 30 s.
    func startFPSCheck() {
        state.withLock { $0.fpsCheck = FPSCheck() }
    }

    // MARK: Settle and lock

    /// Focuses and exposes on the frame centre once, then freezes focus,
    /// exposure (≤ 1/240 s, ISO raised to keep brightness) and white balance.
    func settleAndLock() async throws -> LockedSettings {
        try state.withLock { s in
            guard s.running else { throw CameraError.notRunning }
            guard !s.isFlashing else { throw CameraError.busy("the flash") }
            guard !s.isSettling else { throw CameraError.busy("locking") }
            s.isSettling = true
            s.status = "Settling"
        }
        do {
            let locked = try await onSessionQueue { [self] in try performSettleAndLock() }
            state.withLock { s in
                s.isSettling = false
                s.locked = locked
                s.status = "Locked"
            }
            return locked
        } catch {
            state.withLock { s in
                s.isSettling = false
                s.status = "Lock failed"
            }
            throw error
        }
    }

    private func performSettleAndLock() throws -> LockedSettings {
        guard let device else { throw CameraError.notRunning }
        try checkThermal()
        let centre = CGPoint(x: 0.5, y: 0.5)

        // 1. One autofocus and auto-exposure pass on the eye (frame centre).
        try configure(device) { d in
            if d.isFocusPointOfInterestSupported { d.focusPointOfInterest = centre }
            if d.isFocusModeSupported(.autoFocus) { d.focusMode = .autoFocus }
            if d.isExposurePointOfInterestSupported { d.exposurePointOfInterest = centre }
            if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
            if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                d.whiteBalanceMode = .continuousAutoWhiteBalance
            }
        }
        let started = Date()
        Thread.sleep(forTimeInterval: 0.15) // let the focus pass begin
        while device.isAdjustingFocus, Date().timeIntervalSince(started) < Tuning.focusTimeoutSeconds {
            Thread.sleep(forTimeInterval: 0.02)
        }
        let exposureStart = Date()
        while device.isAdjustingExposure,
              Date().timeIntervalSince(exposureStart) < Tuning.exposureSettleTimeoutSeconds {
            Thread.sleep(forTimeInterval: 0.02)
        }

        // 2. Short exposure, same brightness: move exposure time into ISO.
        let format = device.activeFormat
        let autoExposure = device.exposureDuration.seconds
        let autoISO = device.iso
        var exposure = autoExposure
        var iso = autoISO
        if exposure > Tuning.maxLockedExposureSeconds {
            iso *= Float(exposure / Tuning.maxLockedExposureSeconds)
            exposure = Tuning.maxLockedExposureSeconds
        }
        exposure = max(exposure, format.minExposureDuration.seconds)
        iso = min(max(iso, format.minISO), format.maxISO)

        // 3. Freeze focus, exposure and white balance.
        let exposureSet = DispatchSemaphore(value: 0)
        try configure(device) { d in
            if d.isFocusModeSupported(.locked) {
                d.setFocusModeLocked(lensPosition: AVCaptureDevice.currentLensPosition, completionHandler: nil)
            }
            d.setExposureModeCustom(duration: CMTime(seconds: exposure, preferredTimescale: 1_000_000),
                                    iso: iso) { _ in exposureSet.signal() }
            if d.isWhiteBalanceModeSupported(.locked) {
                d.setWhiteBalanceModeLocked(with: AVCaptureDevice.currentWhiteBalanceGains,
                                            completionHandler: nil)
            }
        }
        if exposureSet.wait(timeout: .now() + 1.0) == .timedOut {
            throw CameraError.configuration("The camera did not confirm the custom exposure.")
        }
        Thread.sleep(forTimeInterval: 0.1) // let the frozen values reach the sensor

        let gains = device.deviceWhiteBalanceGains
        return LockedSettings(
            autoExposureSeconds: autoExposure, autoISO: autoISO,
            exposureSeconds: device.exposureDuration.seconds, iso: device.iso,
            lensPosition: device.lensPosition,
            whiteBalanceGains: device.whiteBalanceMode == .locked
                ? SIMD3(gains.redGain, gains.greenGain, gains.blueGain) : nil)
    }

    /// Returns focus, exposure and white balance to continuous auto.
    func unlock() async throws {
        try await onSessionQueue { [self] in
            guard let device else { throw CameraError.notRunning }
            try configure(device) { d in
                if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
                if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
                if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    d.whiteBalanceMode = .continuousAutoWhiteBalance
                }
            }
        }
        state.withLock { s in
            s.locked = nil
            s.status = "Live"
        }
    }

    // MARK: Torch

    func setTorchBaseline(_ level: Float) {
        sessionQueue.async { [self] in
            torchBaseline = level
            applyTorchBaseline()
        }
    }

    private func applyTorchBaseline() {
        let level = min(max(torchBaseline, 0), 1)
        withDevice { d in
            guard d.hasTorch, d.isTorchAvailable else { return }
            if level <= 0 { d.torchMode = .off } else { try? d.setTorchModeOn(level: level) }
        }
    }

    /// Steps the torch to full for 200 ms, then back to the baseline level (not
    /// off, so exposure stays valid). Enforces the flash safety rules.
    func flash() async throws -> FlashRecord {
        try checkThermal()
        let now = ProcessInfo.processInfo.systemUptime
        try state.withLock { s in
            guard s.running else { throw CameraError.notRunning }
            guard !s.isSettling else { throw CameraError.busy("locking") }
            guard !s.isFlashing else { throw CameraError.busy("the flash") }
            if let last = s.flashUptimes.last, now - last < Tuning.minFlashIntervalSeconds {
                let wait = Int((Tuning.minFlashIntervalSeconds - (now - last)).rounded(.up))
                throw CameraError.flashGuard("Wait \(wait) s before the next flash (20 s minimum between flashes).")
            }
            let recent = s.flashUptimes.filter { now - $0 < Tuning.flashWindowSeconds }
            if recent.count >= Tuning.maxFlashesPerWindow {
                throw CameraError.flashGuard("10 flashes in 10 minutes reached. Rest the eye before testing again.")
            }
            s.isFlashing = true
            s.flashUptimes = recent + [now]
        }
        defer { state.withLock { $0.isFlashing = false } }

        guard let torchDevice = device, torchDevice.hasTorch, torchDevice.isTorchAvailable else {
            throw CameraError.noTorch
        }
        let baseline = min(max(torchBaseline, 0), 1)

        // The dispatch closures capture only `self` (Sendable) and plain values;
        // the device and clock are re-read through `self` inside them.
        let record: FlashRecord = try await withCheckedThrowingContinuation { cont in
            flashQueue.async { [self] in
                let peak = AVCaptureDevice.maxAvailableTorchLevel
                do {
                    try configureTorch { d in try d.setTorchModeOn(level: peak) }
                } catch {
                    cont.resume(throwing: CameraError.configuration("Torch did not turn on: \(error.localizedDescription)"))
                    return
                }
                let on = sessionClockSeconds()
                flashQueue.asyncAfter(deadline: .now() + Tuning.flashDurationSeconds) { [self] in
                    do {
                        try configureTorch { d in
                            if baseline <= 0 { d.torchMode = .off } else { try d.setTorchModeOn(level: baseline) }
                        }
                    } catch {
                        // Never leave the torch at full: fall back to off.
                        withDevice { d in d.torchMode = .off }
                    }
                    let off = sessionClockSeconds()
                    cont.resume(returning: FlashRecord(onTime: on, offTime: off,
                                                       peakLevel: peak, baselineLevel: baseline))
                }
            }
        }
        state.withLock { $0.lastFlash = record }
        return record
    }

    // MARK: Helpers

    /// Seconds on the session's clock, the same clock as frame timestamps.
    private func sessionClockSeconds() -> Double {
        CMClockGetTime(session.synchronizationClock ?? CMClockGetHostTimeClock()).seconds
    }

    private func configureTorch(_ body: (AVCaptureDevice) throws -> Void) throws {
        guard let device else { throw CameraError.noTorch }
        try configure(device, body)
    }

    private func checkThermal() throws {
        let t = ProcessInfo.processInfo.thermalState
        if t == .serious || t == .critical { throw CameraError.thermal(t) }
    }

    /// Runs `body` with the device locked for configuration, serialised across queues.
    private func configure(_ device: AVCaptureDevice, _ body: (AVCaptureDevice) throws -> Void) throws {
        configLock.lock()
        defer { configLock.unlock() }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        try body(device)
    }

    private func withDevice(_ body: (AVCaptureDevice) throws -> Void) {
        guard let device else { return }
        try? configure(device, body)
    }

    private func onSessionQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            sessionQueue.async {
                do { cont.resume(returning: try work()) } catch { cont.resume(throwing: error) }
            }
        }
    }
}
