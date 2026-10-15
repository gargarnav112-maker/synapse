import Testing
@testable import SynapseLab

/// Selection rules for the capture format, on synthetic candidates.
struct FormatSelectorTests {
    private func candidate(_ id: Int, _ kind: DeviceKind, _ w: Int, _ h: Int, fps: Double,
                           focusMm: Int = 100, fullRange: Bool = true) -> FormatCandidate {
        FormatCandidate(id: id, deviceName: "Test", deviceKind: kind, width: w, height: h,
                        maxFPS: fps, minimumFocusDistanceMm: focusMm, isFullRange: fullRange)
    }

    @Test func picksHighestResolutionAt120fps() {
        let c = [
            candidate(1, .wide, 1280, 720, fps: 240),
            candidate(2, .wide, 1920, 1080, fps: 120),
            candidate(3, .wide, 3840, 2160, fps: 120),
            candidate(4, .wide, 1920, 1080, fps: 60),
        ]
        let choice = FormatSelector.choose(c, workingDistanceMm: 120)
        #expect(choice.chosen?.id == 2)
        #expect(choice.fps == 120)
        #expect(!choice.usedFallback)
        #expect(choice.rejections[3] != nil) // larger than 1080p
    }

    @Test func rejectsCamerasThatCannotFocusClose() {
        let c = [
            candidate(1, .wide, 1920, 1080, fps: 120, focusMm: 200),
            candidate(2, .ultraWide, 1920, 1080, fps: 120, focusMm: 20),
        ]
        let choice = FormatSelector.choose(c, workingDistanceMm: 120)
        #expect(choice.chosen?.id == 2)
        #expect(choice.rejections[1]?.contains("20 cm") == true)
    }

    @Test func prefersWideOnEqualResolution() {
        let c = [
            candidate(1, .ultraWide, 1920, 1080, fps: 120, focusMm: 20),
            candidate(2, .wide, 1920, 1080, fps: 120, focusMm: 100),
        ]
        #expect(FormatSelector.choose(c, workingDistanceMm: 120).chosen?.id == 2)
    }

    @Test func unknownFocusDistanceIsAllowed() {
        let c = [candidate(1, .wide, 1280, 720, fps: 120, focusMm: -1)]
        #expect(FormatSelector.choose(c, workingDistanceMm: 120).chosen?.id == 1)
    }

    @Test func fallsBackTo60fpsWithWarning() {
        let c = [candidate(1, .wide, 1920, 1080, fps: 60)]
        let choice = FormatSelector.choose(c, workingDistanceMm: 120)
        #expect(choice.chosen?.id == 1)
        #expect(choice.fps == 60)
        #expect(choice.usedFallback)
    }

    @Test func reportsNoCameraWhenNothingQualifies() {
        let c = [candidate(1, .wide, 1920, 1080, fps: 30)]
        let choice = FormatSelector.choose(c, workingDistanceMm: 120)
        #expect(choice.chosen == nil)
    }

    @Test func flashSafetyConstantsAreWithinTheRules() {
        #expect(Tuning.flashDurationSeconds <= 0.200)
        #expect(Tuning.minFlashIntervalSeconds >= 20)
        #expect(Tuning.maxFlashesPerWindow <= 10)
        #expect(Tuning.flashWindowSeconds >= 600)
        #expect(Tuning.maxLockedExposureSeconds <= 1.0 / 240)
    }
}
