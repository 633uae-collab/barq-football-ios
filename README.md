# FOTIQ — native iOS (SwiftUI, iOS 26 Liquid Glass)
Native SwiftUI app using real iOS 26 APIs (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`, `Tab`, `tabBarMinimizeBehavior`), SF Symbols only, Arabic/RTL.
Data comes from the FOTIQ Node backend (API key stays server-side). Base URL is read from `https://koora-ae.surge.sh/config.json` (override in Settings).

Build: `brew install xcodegen && xcodegen generate` then open `BARQFootball.xcodeproj`. XcodeGen prepares the unchanged original logo’s transparent RGBA resource at build time; the app no longer processes its million pixels during launch. CI: `.github/workflows/ios.yml` (free `macos-26` runner, unsigned simulator build + tests + screenshot).

## Needs Apple Developer Program ($99/yr)
- Installing on a real iPhone via TestFlight (enable `testflight` job, add secrets listed there).
- APNs push (closed-app AI alerts) and remote Live Activity updates: create APNs .p8 key, enable `backend-addons/push.js`.
- Free Apple ID "personal team" can sideload 7-day builds only from a Mac with Xcode — no TestFlight, no push.

Brand: **FOTIQ**. Icon source: `design/fotiq-icon-original.png` (user-supplied), flattened onto its own background #080B12 for the 1024 App Store icon (no alpha). Brand green `#00C46A` sampled from the icon dot (`BrandGreen` / `AccentColor`). Internal target names, bundle id `ae.barq.football` and repo name are unchanged on purpose (changing them would break the App ID/signing setup); nothing user-visible says BARQ.
