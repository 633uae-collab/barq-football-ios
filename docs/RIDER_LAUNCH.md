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

### Committed-layout readiness follow-up — awaiting native validation

The readiness probe previously rejected two identical hosted-layout generations when their completed commits were 50 ms or more apart. On a loaded host, that could repeatedly reset readiness even though layout was already stable, adding avoidable stationary-logo time. Readiness now requires two active-scene commits with the same **nonzero** hosted-layout generation, independently of callback spacing. A changed layout, inactive scene or unlaid-out destination resets the observation. `READINESS observedCommits` and `firstCommitToReady` retain the actual wait cost in diagnostics.

Five regression tests cover stable commits, changing layout, inactive/reactivated scenes, no layout and destination replacement. The same tests run with SwiftPM on the native macOS host before simulator boot as well as within the iOS unit-test target. Host tests do not certify UIKit integration, visual smoothness or device FPS. The 50 ms **motion acceptance** limit, all other cadence/video gates, animation tracks, native Liquid Glass and startup timing remain unchanged. No new performance result is claimed until this source is built and recorded.

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

## Latest refinement and native validation — not accepted

Recorded application source: `f47f8f725bbb7c99449c4ad8e3fd52b38b0bd1e6`. The following evidence-only documentation commit does not change application bytes. Native run [#87](https://github.com/633uae-collab/barq-football-ios/actions/runs/42894309624), completed 2026-11-10 UTC / 2026-11-11 Dubai, is **failure**: cadence and first-video erasure requirements remain unmet. Thresholds have not been weakened. No merge or visual approval is authorized.

The follow-up bounds onboarding image decoding to the initial viewport plus an overscan row, keeping selected clubs first. The native unit tests cover portrait, compact and landscape viewports, deduplication and bundled clubs. The profiled cached directory prepares **27** images instead of all 56; fresh install prepares all six bundled identities. Destination insertion resolves actual hosted layout with UIKit animations disabled only for that insertion. Readiness now requires consecutive commits with an unchanged hosted layout generation. Animation tracks, easing, mark, colors and Liquid Glass are unchanged.

115 unit tests, four launch UI cases, three offline repetitions and the real-onboarding setup passed. Five standalone restarts have distinct process IDs. Behavior tests establish routing, persistence, accessibility hiding and background-resume behavior, not visual smoothness.

| Capture | Kernel process birth → finish | App init → finish | Active motion | Callback rate* | p95 callback gap | Maximum callback gap |
|---|---:|---:|---:|---:|---:|---:|
| First install | 5.465 s | 2.718 s | 1.150 s | 53.94 Hz | 28.371 ms | 66.512 ms |
| Actual reopen | 6.831 s | 3.885 s | 1.149 s | 53.08 Hz | 27.989 ms | 116.332 ms |
| repeat-1 | 6.580 s | 3.730 s | 1.149 s | 39.15 Hz | 49.298 ms | 182.302 ms |
| repeat-2 | 6.061 s | 4.253 s | 1.149 s | 54.82 Hz | 33.300 ms | 34.305 ms |
| repeat-3 | 6.616 s | 4.935 s | 1.149 s | 52.24 Hz | 33.393 ms | 64.877 ms |
| repeat-4 | 5.170 s | 2.834 s | 1.150 s | 41.75 Hz | 66.082 ms | 88.237 ms |
| repeat-5 | 5.621 s | 3.524 s | 1.150 s | 52.18 Hz | 33.594 ms | 61.223 ms |
| Reduce Motion | 6.859 s | 3.229 s | 0.317 s | 41.04 Hz | 50.053 ms | 57.136 ms |

*Conservative display-link callback count divided by active motion duration, excluding the extra completion sample; **not presented FPS**. Simulator boot was **253.344 s**, independently measured and excluded. Nominal elapsed includes credited static hold: up to 0.666667 s, or 0.5 s for Reduce Motion. Completion is an app callback, not a final-frame presentation acknowledgement.

The broader 21-launch timing set, including UI/offline runs, has a maximum callback gap of **341.483 ms**, maximum nominal elapsed of **1.970304 s**, and 40 cadence-rule failures. Standalone preparation callback gaps reach **2.239447 s** before active motion. These failures and preparation costs remain in the raw evidence.

Previous recorded source `63fba21` had first-install process time 12.434 s / maximum motion gap 95.470 ms, reopen 6.566 s / 69.805 ms, and worst standalone restart gap 176.502 ms. The new first capture is shorter, but reopen/individual restart gaps remain variable and can be worse. These shared-host observations are not a controlled causal performance comparison and do not establish stable 60 FPS.

### Original frame review

- First install: 115 encoded frames; three substantial partial-erasure states, followed by a wide navy contraction, smaller navy disk and green pulse. Maximum nearby encoded gap is 135 ms. The stage sequence is present, but too few intermediate erasure frames satisfy the existing visual gate.
- Actual reopen (second opening in its uncut MP4): four partial-erasure frames, maximum nearby encoded gap 150 ms. The wide contracting-disk stage is missing in this recording and remains blank in the comparison. Cached match cards and available local logos are already present at first Home reveal; unavailable images retain existing placeholders.
- Five restarts: **3/5/5/5/3** partial-erasure frames, **3/3/5/5/3** distinct decoded pixel states. Manually inspected reveal-window maximum encoded gaps: **211.666/205.000/143.333/220.000/191.666 ms**. The fourth automatic eight-post-erasure-frame window reaches app termination and includes a 1.653334 s gap; the original metric is retained, but that shutdown gap is not attributed to motion.
- Minimum observed full-mark hold remains **3.367 s** first install, **5.130 s** actual reopen, and **2.832–4.983 s** across five restarts, materially longer than the reference's approximately 0.667 s. These include OS launch-screen and preparation time; they are not just the scheduled animation duration.
- ScreenCaptureKit's independent original window MP4 contains five partial-erasure states and a 150 ms nearby encoded gap. Only its analysis frames are cropped to the phone viewport; its source MP4 is untouched. Independent HEVC has seven frames and misses the reveal, so it cannot establish acceptance.
- Reduce Motion visibly uses opacity-only fading with no radial contraction. Active fade 0.316790 s, maximum callback gap 57.136 ms; smoothness still unproved.
- The mark's decoded bounds are approximately 182×204 px, centered within half a pixel of (603,1311) on the 1206×2622 screen. Attachment-derived height is 204.787 px. Codec/antialias thresholds change detected edges; original bitmap, source colors and geometry are unchanged.
- No >=250 ms near-black viewport was detected. That narrow automated check cannot establish absence of an unsampled blank or a navy-only frame. All primary videos are original byte-identical captures, with no retiming, interpolation, cuts or generated frames.

### Instruments: usable fallback and retained failure

The 30-second plain recording reached its time limit but did not finish saving before the six-minute step timeout; `recorded` never started. GitHub's normalized step list reports success because of `continue-on-error`, but the raw job log explicitly records the timeout. The incomplete `plain.trace` is retained and is **not** used as performance evidence. No claim of a successful simultaneous profiler/video capture is made for this source.

The independent fallback **Time Profiler** did save/export successfully. Its PID **82022** is isolated from the surviving timing stream. Samples cover trace time **1.133762–13.154786 s**, including the entire **6.725–7.865 s** motion. Native `prepareAnimations` and `finish` stack samples align with these log boundaries within **1 ms**; retrospective `log show` timestamps differ and are not substituted for the verified stream alignment.

Within the 1.140 s motion, sampled main CPU is **166 ms**, including **117 ms** inclusive SwiftUI graph/layout and **57 ms** material/animation. The **99.728 ms** callback gap contains **51 ms** sampled main CPU, **41 ms** inclusive SwiftUI. Preparation contains **568 ms** sampled main CPU, **477 ms** inclusive SwiftUI and **128 ms** protocol conformance. Before app init, **1,548 ms** sampled CPU appears in dyld. Inclusive categories overlap; sampled CPU is neither total wall time nor presentation FPS.

`GlassEffectBackdropObserver`, `GraphHost`, `SDFLayer` and `FluidSpringAnimation` remain in sampled stacks. Root replacements are zero, but internal SwiftUI/material work remains. The diagnostic named `motionLayoutPasses` counts from destination readiness until the data gate opens, including a small pre-motion/post-motion interval; it is not a precise motion-only CPU counter. Animation Hitches explicitly reports unsupported on this platform.

### Remaining validation boundary and scope

The current [read-only host capability run](https://github.com/633uae-collab/barq-football-ios/actions/runs/42894310518) again enumerates only **30 Hz** display modes, with Apple Paravirtualized Graphics, 64 MB VRAM and no mac2/apple7 GPU-family support. This prevents presented-60-FPS certification and does not establish that every hitch is host-caused: the profile demonstrates concrete framework CPU work.

Standard macOS 15 ARM and macOS 26 ARM attempts previously failed before allocation. The latest same-app ARM attempt before this follow-up, [run 42864335600](https://github.com/633uae-collab/barq-football-ios/actions/runs/42864335600), failed after 15m 3s with an unacquired runner and arm64 capacity/internal-error notices. Smaller-SE, H.264, HEVC, window capture, plain profiling and the independent profiler fallback were tried. The local workspace is Linux, with no Xcode or attached iPhone. A functioning accelerated Mac or real iPhone environment is still required to finish residual tuning and validate the requested cadence; this PR is not ready for approval.

The live destination remains under the cover. Earlier snapshot handoffs added 0.2–0.79 s preparation without demonstrated benefit and were removed; the additional opaque-field experiment was also removed. Native Liquid Glass remains intact. No paid larger runner or service was activated.

This six-file follow-up has no overlap with PR #7's changed files. The **whole PR histories do share `.github/workflows/ios.yml`**, solely in their pre-existing branch-specific `branches-ignore` edits. That file is untouched by this follow-up; both exclusions must be preserved in any eventual authorized integration. No API/Groq/analyst files were changed, and PR #7 remains untouched. This corrects the earlier overly broad zero-overlap wording.

Original complete evidence artifact: **13803605134**, SHA-256 `267f273849e0eae3860d810a498de66fed135d6b8284e18c706c5c831c2a3045`, retained by GitHub until 2026-11-24. First and repeated clips were also published separately. The evidence-only commit skips duplicate CI for unchanged application bytes, without skipping or relaxing an app acceptance requirement.
