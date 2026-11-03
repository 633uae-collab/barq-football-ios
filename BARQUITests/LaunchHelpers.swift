import XCTest

extension XCUIApplication {
    /// FOTIQ app for pre-existing UI tests: first-launch onboarding is bypassed (env survives launchArguments reassignment).
    /// Onboarding itself is covered by OnboardingUITests, which launch without this.
    static func fotiq() -> XCUIApplication {
        let a = XCUIApplication(); a.launchEnvironment["FOTIQ_SKIP_ONBOARDING"] = "1"; a.launchEnvironment["FOTIQ_UI_TEST"] = "1"; return a
    }
}
