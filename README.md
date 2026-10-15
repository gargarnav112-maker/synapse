# SynapseLab

Research prototype that measures the pupillary light reflex from iPhone
camera video. **Research prototype. Not for diagnosis or clinical decisions.**

Built one milestone at a time from the "Synapse Prototype — Claude Code
Prompt" spec. Current state: **Milestone 1 — Camera core.**

## Add these files to your Xcode project

The files here were written without Xcode, so your first build is their
first compile.

1. **Create the project.** If you haven't already: in Xcode, File › New ›
   Project › iOS App, named **SynapseLab**, with Interface **SwiftUI**,
   Language **Swift**, Storage **None**, and **Include Tests** checked.
2. **Copy the files in.** Copy `SynapseLab/` from this repo over the
   project's `SynapseLab/` folder, and `SynapseLabTests/FormatSelectorTests.swift`
   into the project's test folder. Delete Xcode's template
   `SynapseLabApp.swift` and `ContentView.swift`; this repo has its own
   `App/SynapseLabApp.swift`. New Xcode projects use synchronised folders, so
   the files appear in the build automatically.
3. **Set the build settings** on the SynapseLab target:
   - **iOS Deployment Target:** 18.0.
   - **Swift Language Version:** Swift 6.
   - **Strict Concurrency Checking:** Complete.
   - **Default Actor Isolation:** MainActor is fine. The capture types are
     marked `nonisolated`, which needs Swift 6.2 (Xcode 26).
4. **Add the camera permission.** In the target's **Info** tab, add
   *Privacy - Camera Usage Description* with this text: "SynapseLab films your
   eye to measure how your pupil reacts to light."
5. **Build** with ⌘B and fix or report every error and warning. From
   Terminal:
   ```
   xcodebuild -project SynapseLab.xcodeproj -scheme SynapseLab \
     -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
   ```
6. **Run the unit tests** with ⌘U on any Simulator.

## Milestone 1 — what's in it

| File | Does |
| --- | --- |
| `App/SynapseLabApp.swift`, `App/AppModel.swift` | App entry; safety acceptance and settings (UserDefaults) |
| `App/Tuning.swift` | Every tunable constant, each with why it has its value |
| `Capture/FormatSelector.swift` | Lists every camera and format; picks ≥ 120 fps (else 60 fps with a warning), focus distance ≤ working distance, highest resolution up to 1080p |
| `Capture/CameraEngine.swift` | Capture session (input priority, 1/120 s frame duration, BGRA). Stabilisation, HDR, low-light boost, auto frame rate and subject-area monitoring are off. Also: fps and dropped-frame counting, settle-and-lock, torch baseline and the 200 ms flash with safety guards, thermal blocking and interruption handling |
| `Capture/CameraController.swift` | Main-actor bridge for SwiftUI; copies stats at 10 Hz |
| `UI/HomeView.swift`, `UI/SafetySheet.swift` | Home with mode cards; first-launch safety sheet |
| `UI/OperatorLiveView.swift`, `UI/CameraPreview.swift` | Live back-camera preview, Lock / Unlock, Flash, 30 s fps check |
| `UI/LabHUDView.swift` | fps vs target, drops, exposure, ISO, lens, torch, thermal, locked values and drift |
| `UI/SettingsView.swift`, `UI/CameraReportView.swift` | Working distance and torch baseline; Camera Report with every candidate and why it was or wasn't chosen (shareable as text) |
| `SynapseLabTests/FormatSelectorTests.swift` | Format-selection rules and safety constants |

Settle and lock works like this:

1. Autofocus and auto-exposure run once on the frame centre.
2. Focus locks at the current lens position.
3. Exposure is set to at most 1/240 s, with ISO raised by the same factor to
   keep brightness the same.
4. White balance locks at its current gains.

The HUD then shows the locked values next to the live ones and highlights any
drift.

The flash steps the torch to full for 200 ms, then back to the baseline level
(not off). Two rules are enforced in code: at least 20 s between flashes, and
no more than 10 flashes in 10 minutes. Both apply globally until per-eye tests
exist.

## Milestone 1 acceptance test (on the iPhone)

1. Accept the safety sheet. Open **Measure someone's eye**.
2. **Frame rate:** tap **fps check** and hold the phone still for 30 s. The
   card must say *passed*: mean ≥ 118 fps and < 1 % dropped.
3. **Lock:** point at something textured about 12 cm away and tap **Lock**.
   The HUD shows *locked exp / ISO / lens*. Move the phone between bright and
   dark areas: **drift** must stay *none* and the live exposure, ISO and lens
   values must not change.
4. **Flash:** tap **Flash**. The torch steps up for 200 ms and drops back to
   the dim baseline, and the HUD's *last flash* reads about 200 ms. A second
   tap within 20 s is refused with a countdown.
5. Settings › **Camera Report** › share icon: send me the text, plus a
   screenshot of the HUD after the fps check.

## Not in Milestone 1

Pupil detection, the frame ring buffer, the video recorder, the test state
machine, Self-test mode, calibration, phantom, history and export arrive in
Milestones 2–5. Their Home tiles are visible but disabled and labelled with
their milestone.
