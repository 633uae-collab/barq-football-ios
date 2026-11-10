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

Native capture uses an optimized Release build (`ENABLE_TESTABILITY=NO`, simulator active architecture only). Unit-test compilation separately enables testability. Intel evidence is retained; the latest comparison uses standard Apple Silicon. GitHub repository metadata confirms this repository is public, and standard public macOS runners are free under GitHub's published policy. No paid larger runner is enabled. Earlier Debug recordings are diagnostic evidence only and cannot substitute for the newest commit. First-launch and repeated-launch clips are also published before the remaining profiling steps finish. The capture display is kept awake and Simulator is foregrounded before recording. Unrelated live score-association UI tests are not run for this dedicated launch branch.

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

- Destination readiness observes UIKit `afterCATransactionCommit`, so a display callback before commit does not stand in for a completed layout commit.
- Core Animation tracks are prepared before the motion clock starts and submitted during `beforeCATransactionCommit`. `TRACKS setupSeconds` and `COMMIT submissionToCommit` retain both costs. No forced transaction flush is used.
- The local image plan follows actual favorites/upcoming/important fixture order and includes player photos and team badges. An immutable environment image map supplies cached, off-main decoded images during the first destination body evaluation, avoiding a separate state update for each cached logo.
- Player photo cache misses wait for the launch gate. Crop, size, placeholder, surrounding cards and native Liquid Glass remain unchanged. Missing or expired local content still cannot be supplied without the network; it never delays the entrance.
- Completion checks the real monotonic deadline after the CA completion signal. If CA calls back slightly early, the next display callback completes the launch. Recorded durations are never rounded upward to satisfy a test.
- Validation adds independent native HEVC and ScreenCaptureKit window capture, as well as Time Profiler with and without simultaneous recording. Original MP4s remain unchanged.

## Latest verified evidence — 2026-11-10, build 8a73594

Run: https://github.com/633uae-collab/barq-football-ios/actions/runs/42783787296

**Not complete or visually accepted. Keep draft; do not merge.** Recorded source is `8a7359474bcf84a2817346044e0d90eaf0f09a31`; app source last changed at `6e9d05d`. Xcode 26.3 / iOS 26.2 / iPhone 17 Pro, standard Apple Silicon macOS 15.8.2, production Release with testability disabled. Unit-test compilation separately enables testability. Actual native videos and traces are in the run artifacts, with unchanged MP4 hashes in the delivered provenance manifest.

| Standalone capture | Kernel process birth → completion | App init → completion | Active motion | Conservative callbacks / active second | Max motion callback gap |
|---|---:|---:|---:|---:|---:|
| First install → clubs | 3.708 s | 2.321 s | 1.271 s | 59.02 Hz | 33.321 ms |
| Actual reopen → Home | 3.082 s | 2.179 s | 1.147 s | 58.39 Hz | 33.620 ms |
| repeat-1 | 3.297 s | 2.368 s | 1.150 s | 59.14 Hz | 33.413 ms |
| repeat-2 | 3.157 s | 2.171 s | 1.150 s | 59.14 Hz | 33.389 ms |
| repeat-3 | 3.149 s | 2.221 s | 1.150 s | 58.26 Hz | 33.469 ms |
| repeat-4 | 3.610 s | 2.525 s | 1.150 s | 59.99 Hz | 18.391 ms |
| repeat-5 | 3.294 s | 2.260 s | 1.149 s | 59.16 Hz | 32.785 ms |
| System Reduce Motion | 2.589 s | 1.529 s | 0.316 s | 56.89 Hz | 33.254 ms |

Simulator boot was 103.798 s and is excluded. Nominal premium timelines were 1.814–1.817 s including credited static hold. Callback Hz is **not presented FPS**. Completion means the app callback, not proven final-frame presentation. Unit tests: 106 passed. Launch UI tests: 3/4 passed; background resume and covered accessibility passed. The offline onboarding completion test remained on the competition picker after the start action and failed its 20 s Home assertion. The separate interrupted-onboarding/setup journey passed. This failure is retained, not bypassed or reclassified as passing.

Cadence and encoded phase gates failed without changing thresholds. UI automation reached a 118.787 ms motion callback gap. Standalone first-launch MP4 has three partial-erasure frames, no recorded wide-disk stage, a minimum visible full-mark hold of 1.475 s versus the reference's 0.667 s, and a 128.333 ms encoded interval after erasure starts. Actual reopen has ten partial frames (including similar states), a 1.205 s minimum hold, and a 121.667 ms encoded interval. Five restart partial-frame counts are 6/6/10/4/4; after-erasure-start reveal-region intervals are 85/71.666/73.333/98.333/68.333 ms. Restart four also has a 433.333 ms interval from the last full mark to the first partial mark, which includes static-to-motion onset and must not all be assigned to active motion.

Original simctl recordings contain backward timestamp jumps, outside the reviewed launch segment for first/reopen/five, and within the static hold for the separate HEVC clip. No video was retimed to conceal this. Cross-jump durations are invalid. HEVC preserves eight partial-erasure frames with a 65 ms interval. Independent ScreenCaptureKit window recording has no backward timestamps, six partial-erasure frames, a 3.268 s full-mark hold, and a 105 ms reveal-region interval, despite a 33.286 ms native callback maximum. Thus simctl encoding alone is not an established explanation. No ≥250 ms near-black viewport interval was detected; this is not a smoothness certificate.

Warm Home cards, available team badges and the player photo are visible beneath the contracting cover. Absent/expired snapshots and absent cached images still produce placeholders followed by real network content. No fabricated scores or network dependency was added. The logo center measured (602.5,1310.5) against screen center (603,1311), and visible height 204 px against 204.65 px from the supplied screenshot ratio; the small difference is within threshold/antialias/compression limits.

### Instruments and remaining diagnostic limit

Both Time Profiler runs cover preparation and motion on this build. Without recording, an 83.031 ms callback gap contains 36 ms sampled main CPU, including 30 ms inclusive SwiftUI graph/layout. With simultaneous original video, a 61.760 ms gap contains 37 ms sampled main CPU, including 26 ms graph/layout. Recorded destination preparation lasts 1.499 s with 604 ms sampled CPU (513 ms inclusive graph/layout). Active motion contains 103 ms sampled CPU, including 66 ms graph/layout and 27 ms material/animation. Inclusive categories overlap. These are real overlapping stacks, not proof of the sole cause of the old 166 ms gap or all unobserved time.

Animation Hitches explicitly reports `Hitches is not supported on this platform`. Intel/Apple Silicon, iOS 26.2/26.5, production Release, native H264/HEVC and independent window capture have been examined. Stable presented 60 FPS is still unverified. No interactive Mac or physical iPhone is connected to this session for render-server/GPU frame correlation and direct reproduction of the offline start-action failure. That is the remaining validation access needed; no paid runner/service was enabled. The refinement file audit against PR #7 has zero overlap, and API/Groq/analyst source files were not changed.
