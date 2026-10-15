# SynapseLab

Research prototype that measures the pupillary light reflex from iPhone
camera video. **Research prototype. Not for diagnosis or clinical decisions.**

Built one milestone at a time from the "Synapse Prototype — Claude Code
Prompt" spec. Current state: **Milestone 1 — Camera core.**

## Open and run

1. **Get the code on your Mac.** Clone the repo, or use GitHub's Code › Download ZIP.
2. **Open the project.** Double-click `SynapseLab.xcodeproj`. You need
   Xcode 26 or later.
3. **Set up signing.** Select the SynapseLab target › Signing & Capabilities,
   pick your **Team** (your Apple ID), and if Xcode says the bundle ID is
   taken, change it (e.g. `com.yourname.SynapseLab`).
4. **Run on your phone.** Plug in your iPhone, select it as the run
   destination, and press ⌘R. The first time, enable Developer Mode on the
   phone (Settings › Privacy & Security) and trust your developer certificate
   (Settings › General › VPN & Device Management).

The project is already set up:
- **Build settings:** iOS 18 deployment target, Swift 6, strict concurrency
  Complete, Default Actor Isolation MainActor.
- **Camera permission:** the usage text is in place.
- **Files:** `SynapseLab/` and `SynapseLabTests/` are synchronised folders, so
  any file added there is built automatically.

Every push is also compiled and unit-tested on GitHub's macOS runners
(`.github/workflows/build.yml`).

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
