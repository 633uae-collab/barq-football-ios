# BARQ Football — native iOS (SwiftUI, iOS 26 Liquid Glass)
Native SwiftUI app using real iOS 26 APIs (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`, `Tab`, `tabBarMinimizeBehavior`), SF Symbols only, Arabic/RTL.
Data comes from the existing BARQ Node backend (API key stays server-side). Base URL is read from `https://koora-ae.surge.sh/config.json` (override in Settings).

Build: `brew install xcodegen && xcodegen generate` then open `BARQFootball.xcodeproj`. CI: `.github/workflows/ios.yml` (free `macos-26` runner, unsigned simulator build + tests + screenshot).

## Needs Apple Developer Program ($99/yr)
- Installing on a real iPhone via TestFlight (enable `testflight` job, add secrets listed there).
- APNs push (closed-app AI alerts) and remote Live Activity updates: create APNs .p8 key, enable `backend-addons/push.js`.
- Free Apple ID "personal team" can sideload 7-day builds only from a Mac with Xcode — no TestFlight, no push.
