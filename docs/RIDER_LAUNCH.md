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

The supplied image is 1320×2868. Its background's modal RGB is (7,11,17), now used by the launch background. Its visible mark spans approximately x=562–759, y=1322–1546, depending on antialias threshold. Height is 224 px and the center is (660,1434), the full-screen center. This happens to be close to the former 15% width; the implementation is calculated from the supplied pixel measurement instead of increasing it arbitrarily.

The existing source artwork is 1024×1024, with an approximately 453×512 visible silhouette. A launch-only crop with a one-pixel antialias margin is generated at project generation: 455×514, original x=285/y=255. Both the storyboard and native layer use that same image, aspect ratio and full-screen center. The original source and other pages' BrandMark stay unchanged. White (#FFFFFF) and green (#00C46A) retain the source artwork's native values; screenshot color capture differs by about 1–2 channel values.

## Runtime behavior and measurement

Each new app process creates the entrance once. Tab changes and background resume retain the existing LaunchFlow state. Incomplete onboarding goes to its existing selection flow; completed onboarding opens Home. Data work remains behind the existing LaunchGate; readiness depends on layout/display opportunities, never remote responses. Reduce Motion keeps the stationary logo and short opacity-only fallback.

Animation geometry is prepared once, and Core Animation interpolates layer transforms. CADisplayLink collects main-thread callback intervals, not actual compositor presentation FPS. `STARTUP appInitToFinish` and the recording harness's `launchRequestToObservedFinishSeconds` are separate from animation duration. `maxCallbackGapIncludingPreparation` additionally covers callbacks while prewarming the destination, so pre-animation stalls are not discarded. The first callback delay is logged separately. ProMotion is enabled in Info.plist and both display-link and CAAnimation receive 60–120 Hz hints; actual refresh remains system-controlled. The latter includes simctl overhead and up to 10 ms observation uncertainty; it must not be labelled kernel process-birth time.

The measured-reference timeline replaces the old 1.4 s target with 1.8 s. CI duration bounds are 1.8–2.0 s (0.8–1.0 s Reduce Motion). Cadence acceptance is stricter than the inherited 250 ms gap: maximum 50 ms, mean callback rate >=58 Hz, p95 <=20 ms. A passing callback check alone does not imply a visually smooth 60 fps result.

## Native evidence required before approval

- Fresh install -> clubs, original uncut MP4.
- Saved onboarding -> process reopen, original uncut MP4.
- Five distinct process restarts in one original MP4.
- System Reduce Motion recording.
- Offline routing, background resume, covered accessibility and all unit checks.
- Instruments Time Profiler / Animation Hitches when supported by the runner.
- Decode the NEW recordings and inspect logo continuity, erasure, disk contraction, pulse and destination presentation.

Remaining differences by design: F has different strokes from Uber's wordmark; FOTIQ retains green instead of Uber's blue; its existing Home/onboarding replaces the map and bottom panel. Current native build, recordings, timing outcomes and residual problems must be reported from the actual run. No visual approval or main merge is authorized.
