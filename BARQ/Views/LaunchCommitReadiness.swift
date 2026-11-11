/// Readiness follows committed layout, not the host's frame rate. Requiring two
/// commits less than 50 ms apart could hold a fully laid-out destination forever
/// on a busy or low-refresh display. Cadence is measured independently.
struct LaunchCommitReadiness {
    private var previousGeneration: Int?
    private var previousUpdateTime: Double?

    mutating func observe(layoutGeneration: Int, isActive: Bool, updateTime: Double) -> Bool {
        guard isActive, layoutGeneration > 0, updateTime.isFinite else {
            previousGeneration = nil
            previousUpdateTime = nil
            return false
        }
        let stable = previousGeneration == layoutGeneration
            && previousUpdateTime.map { updateTime > $0 } == true
        previousUpdateTime = updateTime
        previousGeneration = layoutGeneration
        return stable
    }
}
