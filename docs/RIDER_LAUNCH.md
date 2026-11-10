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

The existing source artwork is 1024×1024, with an approximately 453×512 visible silhouette. A launch-only crop with a one-pixel antialias margin is generated at project generation: 455×514, original x=285/y=255. Both the storyboard and native layer use that same image, aspect ratio and full-screen center. The original source and other pages' BrandMark stay unchanged. White (#FFFFFF) and green (#00C46A) retain the source artwork's native values; screenshot color capture differs by about 1–2 channel values.

## Runtime behavior and measurement

Each new app process creates the entrance once. Tab changes and background resume retain the existing LaunchFlow state. Incomplete onboarding goes to its existing selection flow; completed onboarding opens Home. Network consumers resume through a cancellation-aware, event-driven LaunchGate. Before mounting Home, the launch coordinator restores only a same-backend local snapshot younger than 120 seconds and decodes locally cached logos off the main actor. Expired or absent snapshots use redacted native loading cards, never fabricated scores. The existing Home loader refreshes after launch; readiness never waits for a remote response. Only visible Home rows are initially constructed. While the destination is covered, its insertion transaction disables implicit animations; the original native Liquid Glass and normal page animations remain enabled after launch. Reduce Motion keeps the stationary logo and short opacity-only fallback.

Animation geometry is prepared once, and Core Animation interpolates layer transforms. The stationary logo time already spent preparing the destination is credited up to reference frame 40 (0.666667 s), without skipping any erasure, contraction or pulse. Core Animation completion replaces the previous 8 ms completion poll. The nominal timeline remains 1.8 seconds; when the full hold is credited, the active transaction is approximately 1.133 seconds. This does not claim that OS launch-screen time or prewarming now equals the reference hold. CADisplayLink collects main-thread callback intervals, not actual compositor presentation FPS. The current `FRAME_STATS` also includes the final completion interval used to close the monotonic clock; reported conservative display-callback counts exclude that extra sample. Neither rate certifies displayed FPS. `STARTUP appInitToFinish`, the recording harness's `launchRequestToObservedFinishSeconds`, and kernel process birth to the app completion callback are separate from animation duration. A host-side libproc helper reads the simulator process birth without adding a private API to the app. Simulator boot is measured independently and excluded. `MOTION committedToCompletion` records active motion separately from credited static time. These completion timestamps are not a claim that a final GPU frame has been presented. `maxCallbackGapIncludingPreparation` additionally covers callbacks while prewarming the destination, so pre-animation stalls are not discarded. The first callback delay is logged separately. ProMotion is enabled in Info.plist and both display-link and CAAnimation receive 60–120 Hz hints; actual refresh remains system-controlled. The launch-request measurement still includes simctl overhead and up to 10 ms observation uncertainty; only `processBirthToFinishSeconds` uses the kernel birth timestamp and the app's logged completion epoch.

The measured-reference timeline replaces the old 1.4 s target with 1.8 s. CI duration bounds are 1.8–2.0 s (0.8–1.0 s Reduce Motion). Cadence acceptance is stricter than the inherited 250 ms gap: maximum 50 ms, mean callback rate >=58 Hz, p95 <=20 ms. A passing callback check alone does not imply a visually smooth 60 fps result.

Native capture uses an optimized Release build (testability enabled, simulator active architecture only). Intel evidence is retained; the latest comparison uses standard Apple Silicon. GitHub repository metadata confirms this repository is public, and standard public macOS runners are free under GitHub's published policy. No paid larger runner is enabled. Earlier Debug recordings are diagnostic evidence only and cannot substitute for the newest commit. First-launch and repeated-launch clips are also published before the remaining profiling steps finish. The capture display is kept awake and Simulator is foregrounded before recording. Unrelated live score-association UI tests are not run for this dedicated launch branch.

## Native evidence required before approval

- Fresh install -> clubs, original uncut MP4.
- Saved onboarding -> process reopen, original uncut MP4.
- Five distinct process restarts in one original MP4.
- System Reduce Motion recording.
- Offline routing, background resume, covered accessibility and all unit checks.
- Instruments Time Profiler / Animation Hitches when supported by the runner.
- Decode the NEW recordings and inspect logo continuity, erasure, disk contraction, pulse and destination presentation.

Remaining differences by design: F has different strokes from Uber's wordmark; FOTIQ retains green instead of Uber's blue; its existing Home/onboarding replaces the map and bottom panel. Current native build, recordings, timing outcomes and residual problems must be reported from the actual run. No visual approval or main merge is authorized.


## Correlated profiling added during final refinement

The validation workflow records Time Profiler twice on the same onboarding route: once without video capture and once with simultaneous, original simctl recording. Each callback gap includes monotonic start/end times and a Points of Interest event. The trace, exported CPU samples, signposts, timing logs, and unedited MP4 are retained together. Inclusive CPU sample weights overlap; they must not be added as wall-time measurements.

Diagnostic commit `741e1cd` / run `42756079348` passed 103 unit tests and four journey/accessibility/offline UI tests. Its standalone first launch improved the measured main callback maximum from the prior 166.424 ms to 33.410 ms, but the encoded video omitted the erasure stage and retained a 271.667 ms reveal gap. The cadence and visual gates correctly failed. In the simultaneous Instruments capture, a 50.648 ms callback gap contained 30 ms of sampled main-thread work including SwiftUI graph/layout updates; another 82.431 ms gap contained only 13 ms of sampled main CPU work, so its entire duration cannot be attributed to a specific app stack. Initial material/default animations were still sampled while covered. The final source stages the covered destination without implicit insertion animations in response to this evidence. This diagnostic run is not evidence that the final source passed or reached stable presented 60 FPS.

## Latest native validation — 2026-11-10, source ecf07fd

Run: https://github.com/633uae-collab/barq-football-ios/actions/runs/42760123277

Xcode 26.3, iPhone 17 Pro / iOS 26.2 (23C54), Release, standard Intel Mac mini. All 105 unit tests, four launch UI tests, and the separate real onboarding setup passed. Five distinct processes completed. Background resume and covered accessibility passed. **The cadence and encoded phase-visibility gates failed; this is not visually accepted and must not be merged.**

| Standalone capture | Kernel process birth to completion | App init to completion | Active motion | Conservative callback count / motion second | p95 callback gap | Max callback gap |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| First install | 8.053 s | 4.749 s | 1.144 s | 53.32 Hz | 28.257 ms | 63.031 ms |
| Actual reopen | 5.645 s | 3.848 s | 1.149 s | 55.72 Hz | 24.305 ms | 71.859 ms |
| Restart 1 | 5.281 s | 3.596 s | 1.148 s | 57.50 Hz | 24.767 ms | 35.032 ms |
| Restart 2 | 4.954 s | 3.452 s | 1.150 s | 55.66 Hz | 26.440 ms | 52.080 ms |
| Restart 3 | 5.630 s | 3.972 s | 1.150 s | 58.26 Hz | 20.351 ms | 32.944 ms |
| Restart 4 | 5.481 s | 3.750 s | 1.147 s | 51.43 Hz | 29.456 ms | 130.570 ms |
| Restart 5 | 6.314 s | 4.562 s | 1.150 s | 58.26 Hz | 26.341 ms | 33.487 ms |
| System Reduce Motion | 6.994 s | 3.792 s | 0.306 s | 48.95 Hz | 32.751 ms | 39.610 ms |

The separately measured simulator boot took 273.016 s; none of that interval is included above. These are callback/completion measurements, not displayed FPS. UI-automation recordings are separate: their largest motion callback gap was 780.677 ms and one nominal timeline reached 2.130 s. The full failing timing report is retained rather than selecting only the standalone clips.

Visual review of the original cold clip found only two partial erasure states and a 240 ms encoded gap around reveal. Its full mark persisted for at least 6.105 s including OS startup/preparation, versus the reference's roughly 0.667 s hold. The reopen had four partial erasure states and a 125 ms reveal-region gap; the five restarts had 7/7/7/6/4 partial states and maximum reveal-region encoded gaps of 296.667/188.333/250.000/170.000/115.000 ms. Encoded gaps are not display-link gaps and include the sampled reveal/settling window. The original files remain uncut and unretimed.

Home's cached cards and available images were present under the contracting cover on the actual reopen and all five restarts. The preliminary opening in the reopen clip had no valid snapshot and showed redacted loading cards, then real data. Some team logos still arrived after reveal. Thus full real content at every cache miss is **not** solved; the animation remains independent of the network.

The latest simultaneous Time Profiler recording captured an 83.393 ms callback gap with 64 ms of sampled main-thread CPU work, including 56 ms of inclusive SwiftUI graph/layout work (`GraphHost.flushTransactions`, `ViewGraphRootValueUpdater`, `AG::Subgraph::update`). Another 66.474 ms gap contained only 8 ms of sampled main CPU. The plain trace's maximum was 34.343 ms. Destination preparation used 756 ms sampled main CPU over 1.685 s in the recorded trace. Disabling covered insertion animations did not eliminate all graph/material work. These samples identify real overlapping work but do not prove the sole cause of the earlier 166 ms gap or all unobserved time. Animation Hitches explicitly reports that the simulator platform is unsupported; presented 60 FPS is unverified.

The initial Apple Silicon ref update was rejected over possible compute cost. Subsequent repository metadata confirmed `private=false`, `visibility=public`; GitHub's official runner reference confirms standard `macos-15` is free for public repositories. With that new evidence, the update succeeded and unchanged-app comparison run 42769353643 started. No paid larger runner or billing setting was enabled. Main and the other developer's API/Groq files remain untouched.


## Follow-up under native validation

- Destination readiness now observes UIKit's `afterCATransactionCommit` phase through `UIUpdateLink`, rather than treating a display-link callback that occurs before commit as proof of a completed layout commit.
- Tracks are constructed before starting the animation clock and submitted in `beforeCATransactionCommit`. The measured reference timeline, original mark, and all phase durations remain unchanged. `TRACKS setupSeconds` and `COMMIT submissionToCommit` expose preparation and commit cost separately; neither is removed from full startup measurement. No forced transaction flush is used.
- The local image plan follows actual favorites/upcoming/important fixture order instead of the API response prefix, and includes player team badges. Decoded images enter the first destination body evaluation via an immutable environment value; cached logos no longer trigger one state update per image after layout.
- Player photos use that same launch image cache and publish cache misses only after the entrance. Their crop, size, placeholder and surrounding card are unchanged. Existing standard network refresh and native Liquid Glass remain intact. An empty/expired local data or image cache still cannot supply remote content while offline; it does not delay the entrance.
- These changes require fresh native compilation, recordings, cadence/visual review and profiling. They are not accepted based on source inspection or unit tests.

UIKit documentation: https://developer.apple.com/documentation/uikit/uiupdatelink and https://developer.apple.com/documentation/uikit/uiupdateactionphase . Free standard public-runner policy: https://docs.github.com/en/actions/reference/runners/github-hosted-runners .
