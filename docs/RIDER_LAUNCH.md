# FOTIQ Rider launch implementation — pending native visual acceptance

Source: https://dribbble.com/shots/6991913-Rider-Launch-Transition

The public video was played in the browser on 2026-11-10 (Dubai time), downloaded for local analysis, and decoded: 800×600, 60 fps, 361 frames, 6.016667 seconds. No reference video, designer source, Uber artwork, or extracted frame is bundled or committed. This implementation uses the existing original FOTIQ bitmap with native Core Animation masks and transforms.

## Observations and adaptation

| Reference frame/time | Observed behavior | FOTIQ implementation |
|---|---|---|
| 0–39 / 0–0.650 s | Stationary full wordmark on dark field | Stationary original F and green dot |
| 40–63 / 0.667–1.050 s | Staggered erasure follows letter strokes, with colored leading edges | Four independent masks follow the upper arm, stem, middle arm and dot; original white/green colors retained |
| 64–71 / 1.067–1.183 s | Dark field contracts rapidly to a centered disk; destination appears outside it | Static circular cover, compositor scale; measured radius fit |
| 70–90 / about 1.167–1.500 s | Smaller center disk changes color; larger translucent disk contracts around it | Navy disk clears over a green translucent contraction; no permanent location marker |
| About 78–108 / 1.300–1.800 s | Map detail and bottom destination panel settle | Existing destination is already laid out; no changes to its layout or native Liquid Glass |
| Remainder of 6 s clip | Map hold, then fade/reset to loop | Excluded from app startup |

No camera rotation, perspective zoom, or shot change occurs in the entrance itself. The late fade in the public clip resets its presentation loop, so it is not reproduced as an app entrance.

The exact designer easing is unavailable. A fitted exponential through the dark-disk centerline radii in frames 65–71 has RMS error 0.00644 viewport widths: `radius/width = 1.00878844 * exp(-14.52129531*(t-65/60))`. Those measured radii are 225, 180, 138, 108, 86, 69 and 52 pixels, with viewport width 224 px. Erasure easing uses a bounded smoothstep; segmentation and color behavior are an explicit adaptation to a different mark, not a claim of pixel equivalence.

## Attached logo measurement

The supplied image is 1320×2868. Its background's modal RGB is (7,11,17), now used by a launch-only color asset; the existing onboarding background is unchanged. Its visible mark spans approximately x=562–759, y=1322–1546, depending on antialias threshold. Height is 224 px and the center is (660,1434), the full-screen center. This happens to be close to the former 15% width; the implementation is calculated from the supplied pixel measurement instead of increasing it arbitrarily.

The existing source artwork is 1024×1024, with an approximately 453×512 visible silhouette. A launch-only crop with a one-pixel antialias margin is generated at project generation: 455×514, original x=285/y=255. Both the storyboard and native layer use that same image, aspect ratio and full-screen center. The original source and other pages' BrandMark stay unchanged. White (#FFFFFF) and green (#00C46A) retain the source artwork's native values; decoded video RGB values are not a lossless verification of the source colors. Source pixel assertions and original asset bytes are retained separately from codec output.

## Runtime behavior and measurement

Each new app process creates the entrance once. Tab changes and background resume retain the existing LaunchFlow state. Incomplete onboarding goes to its existing selection flow; completed onboarding opens Home. Network consumers resume through a cancellation-aware, event-driven LaunchGate. Before mounting Home, the launch coordinator restores only a same-backend local snapshot younger than 120 seconds and decodes locally cached logos off the main actor. Expired or absent snapshots use redacted native loading cards, never fabricated scores. The existing Home loader refreshes after launch; readiness never waits for a remote response. Only visible Home rows are initially constructed. While the destination is covered, its insertion transaction disables implicit animations; the original native Liquid Glass and normal page animations remain enabled after launch. Reduce Motion keeps the stationary logo and short opacity-only fallback.

Animation geometry is prepared once, and Core Animation interpolates layer transforms. The stationary logo time already spent preparing the destination is credited up to reference frame 40 (0.666667 s), without skipping any erasure, contraction or pulse. Core Animation completion replaces the previous 8 ms completion poll. The nominal timeline remains 1.8 seconds; when the full hold is credited, the active transaction is approximately 1.133 seconds. This does not claim that OS launch-screen time or prewarming now equals the reference hold. CADisplayLink collects main-thread callback intervals, not actual compositor presentation FPS. The current `FRAME_STATS` also includes the final completion interval used to close the monotonic clock; reported conservative display-callback counts exclude that extra sample. Neither rate certifies displayed FPS. `STARTUP appInitToFinish`, the recording harness's `launchRequestToObservedFinishSeconds`, and kernel process birth to the app completion callback are separate from animation duration. A host-side libproc helper reads the simulator process birth without adding a private API to the app. Simulator boot is measured independently and excluded. `MOTION committedToCompletion` records active motion separately from credited static time. These completion timestamps are not a claim that a final GPU frame has been presented. `maxCallbackGapIncludingPreparation` additionally covers callbacks while prewarming the destination, so pre-animation stalls are not discarded. The first callback delay is logged separately. ProMotion is enabled in Info.plist and both display-link and CAAnimation receive 60–120 Hz hints; actual refresh remains system-controlled. The launch-request measurement still includes simctl overhead and up to 10 ms observation uncertainty; only `processBirthToFinishSeconds` uses the kernel birth timestamp and the app's logged completion epoch.

The measured-reference timeline replaces the old 1.4 s target with 1.8 s. CI duration bounds are 1.8–2.0 s (0.8–1.0 s Reduce Motion). Cadence acceptance is stricter than the inherited 250 ms gap: maximum 50 ms, mean callback rate >=58 Hz, p95 <=20 ms. A passing callback check alone does not imply a visually smooth 60 fps result.

Native capture uses an optimized Release build (`ENABLE_TESTABILITY=NO`, simulator active architecture only). Unit-test compilation separately enables testability. Intel and Apple Silicon evidence are retained separately; runner allocation and OS boot are never counted as app launch time. GitHub repository metadata confirms this repository is public, and standard public macOS runners are free under GitHub's published policy. No paid larger runner is enabled. Earlier Debug recordings are diagnostic evidence only and cannot substitute for the newest commit. First-launch and repeated-launch clips are also published before the remaining profiling steps finish. The capture display is kept awake and Simulator is foregrounded before recording. Unrelated live score-association UI tests are not run for this dedicated launch branch.

## Native evidence required before approval

- Fresh install -> clubs, original uncut MP4.
- Saved onboarding -> process reopen, original uncut MP4.
- Five distinct process restarts in one original MP4.
- System Reduce Motion recording.
- Offline routing, background resume, covered accessibility and all unit checks.
- Instruments Time Profiler / Animation Hitches when supported by the runner.
- Decode the NEW recordings and inspect logo continuity, erasure, disk contraction, pulse and destination presentation.

Remaining differences by design: F has different strokes from Uber's wordmark; FOTIQ retains green instead of Uber's blue; its existing Home/onboarding replaces the map and bottom panel. Current native build, recordings, timing outcomes and residual problems must be reported from the actual run. No visual approval or main merge is authorized.

## Final refinement architecture

- `LaunchContainerController` owns the original Core Animation cover and a child `UIHostingController` containing the real destination. The cover's first callback starts local preparation; there is no polling task or SwiftUI `destinationMounted` state. Finishing removes native views and enables destination interaction without replacing the SwiftUI launch hierarchy. The destination receives the current SwiftUI environment, including scene and accessibility changes, throughout launch and normal use.
- Onboarding prepares its locally cached club images before first layout, using the same immutable image environment as Home. The original six local club identities have bundled provider PNGs, and previously downloaded photos/logos use a bounded launch-owned disk cache (32 MB, 256 entries, 2 MB each, 24-hour maximum age). Byte provenance is in `docs/launch-club-assets.json`. Cached-image fallback publication, initial club search publication and the live-pill pulse wait for the launch gate. No network response is required to start or finish the entrance.
- Destination readiness observes UIKit `afterCATransactionCommit`, so a display callback before commit does not stand in for a completed layout commit.
- Core Animation tracks are prepared before the motion clock starts and submitted during `beforeCATransactionCommit`. `TRACKS setupSeconds` and `COMMIT submissionToCommit` retain both costs. No forced transaction flush is used.
- The local image plan follows actual favorites/upcoming/important fixture order and includes player photos and team badges. Prepared values are merged into the forwarded `EnvironmentValues` before the destination is rendered: an inner full-environment modifier previously erased an outer prepared-image key, which real native footage exposed despite successful cache tests. An immutable environment image map supplies cached, off-main decoded images during the first destination body evaluation, avoiding a separate state update for each cached logo.
- Logo and player photo cache misses wait for the launch gate before starting network/decode work. Crop, size, placeholder, surrounding cards and native Liquid Glass remain unchanged. Missing or expired local content still cannot be supplied without the network; it never delays the entrance.
- Completion checks the real monotonic deadline after the CA completion signal. If CA calls back slightly early, the next display callback completes the launch. Recorded durations are never rounded upward to satisfy a test.
- Validation adds independent native HEVC and ScreenCaptureKit window capture, as well as Time Profiler with and without simultaneous recording. Original MP4s remain unchanged.

## Current native validation — not accepted

Application source: `63fba21c0e3e78f3d01c1f3ae153b68720dba91d`. The later host-capabilities workflow and this documentation do not change application sources. The completed native run is https://github.com/633uae-collab/barq-football-ios/actions/runs/42864709795 (iPhone 17 Pro, iOS 26.2, Xcode 26.3, Release, standard macOS 15 Intel). Its final result is **failure**, because cadence and original-video phase requirements failed. Their thresholds have not been weakened.

111 unit tests, all four launch UI cases, three offline repetitions and the real-onboarding recording setup passed. These establish routing and behavior, not visual smoothness. Five recorded restarts have five distinct process IDs; the quick-reopen measurements below refer to the second opening in that uncut video.

| Capture | Kernel process birth → finish | App init → finish | Active motion | Callback rate* | p95 callback gap | Maximum callback gap |
|---|---:|---:|---:|---:|---:|---:|
| First install | 12.434 s | 8.571 s | 1.150 s | 52.16 Hz | 26.827 ms | 95.470 ms |
| Actual reopen | 6.566 s | 4.199 s | 1.150 s | 54.79 Hz | 23.079 ms | 69.805 ms |
| repeat-1 | 7.039 s | 3.909 s | 1.151 s | 50.41 Hz | 38.524 ms | 93.106 ms |
| repeat-2 | 8.153 s | 4.594 s | 1.150 s | 48.70 Hz | 40.927 ms | 58.928 ms |
| repeat-3 | 6.837 s | 3.788 s | 1.149 s | 49.60 Hz | 50.277 ms | 65.776 ms |
| repeat-4 | 7.594 s | 4.421 s | 1.149 s | 42.64 Hz | 52.857 ms | 176.502 ms |
| repeat-5 | 7.428 s | 4.468 s | 1.141 s | 49.07 Hz | 43.000 ms | 91.685 ms |
| Reduce Motion | 7.413 s | 3.587 s | 0.318 s | 44.05 Hz | 34.000 ms | 66.020 ms |

*Conservative CADisplayLink callback count divided by active duration, excluding the extra completion sample; **not presented FPS**. Simulator boot took 357.832 seconds and is excluded from every app duration above. Nominal elapsed includes up to 0.666667 seconds of credited static hold (0.5 seconds for Reduce Motion). The broader 21-launch timing set, including UI-driven and offline runs, reached **1,279.917 ms**, and one nominal launch took 2.006371 seconds. Neither that failure nor preparation stalls is excluded from the raw timing report.

### Original frame review

- First launch: 40 encoded frames, zero partial-erasure states. A 3.018333-second timestamp jump separates the last full mark from the revealed page/green pulse; it spans preparation and transition, not solely active animation. The first captured app frame contains F, but sparse capture cannot prove absence of an unsampled blank. Six bundled club logos are visible at first reveal.
- Actual reopen: zero substantial partial-erasure states; a thin remaining stroke is followed by Home. The first visible Home already contains cached match cards and available local logos. Unavailable images keep the existing placeholder; the entrance does not wait for their network response.
- Five restarts: 4, 4, 6, 3 and 4 partial-erasure frames, with 4, 3, 6, 3 and 4 distinct pixel states respectively. Encoded gaps in the review window around reveal are 190.000, 181.667, 128.334, 98.334 and 200.000 ms. This window includes several post-reveal frames. Observed full-mark hold is at least 3.640–6.193 seconds, still materially longer than the reference's roughly 0.667 seconds.
- Independent ScreenCaptureKit window recording: six partial-erasure states, maximum nearby encoded gap 136.667 ms. Independent HEVC contains only eight frames and does not capture the reveal, so it cannot establish visual acceptance. These are separate original captures, not retimed substitutes for the requested recordings.
- Reduce Motion visibly uses an opacity-only fade without radial contraction. Its native maximum callback gap is 66.020 ms; its sparse MP4 does not establish smoothness.
- The new original recording measures the mark at 180×204 pixels, centered exactly at (603,1311) on a 1206×2622 screen. Attachment-derived expected height is 204.65 pixels; compressed antialias edges affect the threshold by about a pixel. Original artwork and source colors remain unchanged. Codec RGB is not a lossless color check.

The prepared-image environment correction is confirmed in actual reveal frames. The final application change also defers ClubPickStep's initial prefetch, which had bypassed the gate applied to visible RemoteImage misses. All observed standalone captures log zero covered-root and motion-root replacements.

### Instruments and the remaining boundary

The plain Time Profiler trace covers the active motion: 170 ms of sampled main-thread CPU within 1.149 seconds, including 114 ms inclusive in SwiftUI graph/layout and 54 ms in material/animation stacks. A 100.070 ms callback gap contains 48 ms of sampled main-thread CPU, including 40 ms in SwiftUI. Destination preparation contains 602 ms of sampled main CPU, 521 ms inclusive in SwiftUI; before app init, 1,256 ms of sampled CPU appears in dyld stacks. Inclusive categories overlap and must not be summed as exclusive CPU or wall time. These are concrete app/framework costs, not evidence that every hitch is caused by the host.

The simultaneous recorded profiler started slowly: its exported samples end at trace time 48.146 seconds, before motion starts at 50.505 seconds. Its motion interval therefore has **no sample coverage**, not zero CPU usage. The complete plain trace supplies the usable correlation. The original recorded trace and MP4 are retained with this limitation. Animation Hitches explicitly reports that Hitches is unsupported on this platform.

The Intel host has four cores, 14 GB memory, Apple Paravirtualized Graphics Device with 64 MB VRAM, Metal 2 and a 30 Hz virtual display. Read-only capability run https://github.com/633uae-collab/barq-football-ios/actions/runs/42865889515 enumerated all three supported display modes: every mode is 1920×1080 at 30 Hz; no 60 Hz mode exists. The virtual Metal device reports neither mac2 nor apple7 support. No display setting was changed.

Standard macOS 15 ARM and macOS 26 ARM attempts failed before allocation. The final-source ARM run https://github.com/633uae-collab/barq-football-ios/actions/runs/42864335600 likewise failed after 15m 3s with an unacquired hosted runner, an internal server error and arm64 capacity notices; no build or test step ran. Its application source `0ff0b3` is identical to `63fba21` (workflow-only difference). The smaller SE simulator, native H.264/HEVC/window capture and plain/recorded profiling were tried. The local environment is Linux and cannot run Xcode or a physical iPhone. A functioning accelerated Mac/iPhone environment is still needed to establish presented 60 FPS and finish residual tuning; none of the available evidence permits approval.

The real destination remains live under the original cover. Snapshot handoffs added 0.2–0.79 seconds of preparation without proving smoother footage, and the extra opaque-field experiment also failed to establish a benefit; both were removed. Native Liquid Glass remains intact. The final documentation does not initiate another full native run for unchanged application bytes. Scope comparison against PR #7 has no changed-file overlap. No API/Groq/analyst edits, paid service, main merge or visual approval occurred.
