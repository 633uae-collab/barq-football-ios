/// Readiness follows committed layout, not the host's frame rate. Requiring two
/// commits less than 50 ms apart could hold a fully laid-out destination forever
/// on a busy or low-refresh display. Cadence is measured independently.
struct LaunchCommitReadiness {
    private var previousGeneration: Int?

    mutating func observe(layoutGeneration: Int, isActive: Bool) -> Bool {
        guard isActive, layoutGeneration > 0 else {
            previousGeneration = nil
            return false
        }
        let stable = previousGeneration == layoutGeneration
        previousGeneration = layoutGeneration
        return stable
    }
}
