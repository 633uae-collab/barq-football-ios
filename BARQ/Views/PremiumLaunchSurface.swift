import SwiftUI
import UIKit
import os

/// Rider Launch Transition sequence: stationary mark, staggered erase, then
/// the dark field contracts to a central dot over the prepared destination.
/// Reference: https://dribbble.com/shots/6991913-Rider-Launch-Transition
/// The FOTIQ artwork, green accent and native destination remain original.
enum PremiumLaunchTrack {
    // Measured from the 361-frame, 60 Hz public reference. The final map hold
    // and loop reset are not part of an application launch. See docs/RIDER_LAUNCH.md.
    static let duration = 1.8
    static let firstErase = 40.0 / 60
    /// Preparation already displays the exact stationary artwork. Credit only
    /// that static part; never skip an erasure, contraction or pulse frame.
    static func holdCredit(displayedFor seconds: Double, reduceMotion: Bool) -> Double {
        min(max(0, seconds), reduceMotion ? LaunchPresentation.hold : firstErase)
    }
    static func smooth(_ t: Double) -> CGFloat {
        let x = min(1, max(0, t))
        return CGFloat(x * x * (3 - 2 * x))
    }
    static func progress(_ time: Double, from start: Double, to end: Double) -> CGFloat {
        smooth((time - start) / (end - start))
    }
    // Centerline radii in the 224 px wide Rider viewport, sampled at 60 Hz.
    // Interpolate in screen widths so the logo and the circles share a center.
    private static let diskSamples: [CGFloat] = [225, 180, 138, 108, 86, 69, 56, 45, 37, 30, 24, 19, 15, 11, 8, 5, 1, 0]
    private static let haloSamples: [CGFloat] = [234, 189, 155, 127, 107, 91, 77, 65, 55, 47, 40, 34, 29, 23, 18, 13, 5, 0]
    private static func radius(_ samples: [CGFloat], firstFrame: Int, at time: Double, in size: CGSize) -> CGFloat {
        let full = hypot(size.width, size.height) / 2 + 2
        let frame = time * 60 - Double(firstFrame)
        guard frame > -1 else { return full }
        let unit = size.width / 224
        if frame < 0 { return full + CGFloat(frame + 1) * (min(full, samples[0] * unit) - full) }
        guard frame < Double(samples.count - 1) else { return samples.last! * unit }
        let index = Int(frame)
        let interpolated = samples[index] + CGFloat(frame - Double(index)) * (samples[index + 1] - samples[index])
        return min(full, interpolated * unit)
    }
    static func coverRadius(at time: Double, in size: CGSize) -> CGFloat {
        radius(diskSamples, firstFrame: 65, at: time, in: size)
    }
    static func circlePath(radius: CGFloat, in size: CGSize) -> CGPath {
        CGPath(ellipseIn: CGRect(x: size.width / 2 - radius, y: size.height / 2 - radius,
                                width: radius * 2, height: radius * 2), transform: nil)
    }
    struct Segment {
        let rect: CGRect
        let anchor: CGPoint
        let axis: String
        let start: Double
        let end: Double
    }
    // Masks expose the ORIGINAL raster pixels; they never redraw or deform F.
    // Coordinates refer to the 455x514 tight launch crop of the existing artwork.
    static let segments = [
        Segment(rect: CGRect(x: 0, y: 0, width: 405, height: 124), anchor: CGPoint(x: 0, y: 0.5), axis: "x", start: 40.0/60, end: 56.0/60),
        Segment(rect: CGRect(x: 0, y: 124, width: 132, height: 390), anchor: CGPoint(x: 0.5, y: 0), axis: "y", start: 48.0/60, end: 63.0/60),
        Segment(rect: CGRect(x: 132, y: 216, width: 168, height: 116), anchor: CGPoint(x: 0, y: 0.5), axis: "x", start: 44.0/60, end: 60.0/60),
        Segment(rect: CGRect(x: 330, y: 205, width: 125, height: 135), anchor: CGPoint(x: 0.5, y: 1), axis: "y", start: 42.0/60, end: 61.0/60)
    ]
    static func remaining(at time: Double, segment: Int) -> CGFloat {
        let item = segments[segment]
        return 1 - progress(time, from: item.start, to: item.end)
    }
    static func pulseRadius(at time: Double, in size: CGSize) -> CGFloat {
        radius(haloSamples, firstFrame: 71, at: time, in: size)
    }
    static func pulseOpacity(at time: Double) -> Float {
        Float(progress(time, from: 69.0/60, to: 76.0/60) * (1 - progress(time, from: 85.0/60, to: 88.0/60))) * 0.32
    }
    static func coverOpacity(at time: Double) -> Float {
        Float(1 - progress(time, from: 79.0/60, to: 82.0/60))
    }
    static let accent = UIColor(red: 0, green: 196 / 255, blue: 106 / 255, alpha: 1)
    private static let navyComponents: (CGFloat, CGFloat, CGFloat) = {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        UIColor(named: "RiderLaunchBackground")!.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }()
    static func diskColor(at time: Double) -> CGColor {
        let mix = progress(time, from: 69.0/60, to: 78.0/60)
        let (r, g, b) = navyComponents
        return UIColor(red: r * (1 - mix), green: g + (196 / 255 - g) * mix,
                       blue: b + (106 / 255 - b) * mix, alpha: 1).cgColor
    }
    static func edgeOpacity(at time: Double) -> Float {
        Float(progress(time, from: firstErase, to: 42.0/60) * (1 - progress(time, from: 62.0/60, to: 64.0/60)))
    }

}

/// Core Animation owns motion; CADisplayLink measures main-thread cadence only.
struct PremiumLaunchSurface: UIViewRepresentable {
    let clock: SplashClock
    let reduceMotion: Bool
    let onComplete: () -> Void
    func makeUIView(context: Context) -> PremiumLaunchLayer { PremiumLaunchLayer(clock: clock, reduceMotion: reduceMotion, onComplete: onComplete) }
    func updateUIView(_ view: PremiumLaunchLayer, context: Context) {}
    static func dismantleUIView(_ view: PremiumLaunchLayer, coordinator: ()) {
        view.stop()
        view.restoreAccessibility()
    }
}

final class PremiumLaunchLayer: UIView {
    private let cover = CAShapeLayer(), pulse = CAShapeLayer(), mark = CALayer()
    private let markMask = CALayer()
    // The trailing silhouette sits behind the white artwork for two reference frames.
    // Both masks use the original image alpha, including the green dot.
    private let edge = CALayer(), edgeSilhouette = CALayer()
    private let edgeBands = PremiumLaunchTrack.segments.map { _ in CALayer() }
    private let markBands = PremiumLaunchTrack.segments.map { _ in CALayer() }
    private let clock: SplashClock
    private let reduceMotion: Bool
    private let onComplete: () -> Void
    private var link: CADisplayLink?
    private var commitLink: UIUpdateLink?
    private var preparedOffset: Double?
    var clubsPresentationBoundary: (() -> CFTimeInterval?)?
    private var submittedAt: CFTimeInterval?
    private var prepared = false, started = false, finished = false
    private var tracks: [(CALayer, CAKeyframeAnimation)] = []
    private weak var accessibilityWindow: UIWindow?
    private var previousAccessibilityElements: [Any]?
    init(clock: SplashClock, reduceMotion: Bool, onComplete: @escaping () -> Void) {
        self.clock = clock
        self.reduceMotion = reduceMotion
        self.onComplete = onComplete
        super.init(frame: .zero)
        // The contracting cover reveals the native view beneath this surface.
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = true
        isAccessibilityElement = true
        accessibilityIdentifier = "splash"
        accessibilityLabel = "FOTIQ"
        accessibilityViewIsModal = true
        clipsToBounds = true
        cover.fillColor = UIColor(named: "RiderLaunchBackground")!.cgColor
        pulse.fillColor = UIColor(red: 0, green: 196 / 255, blue: 106 / 255, alpha: 1).cgColor
        pulse.opacity = 0
        mark.contents = UIImage(named: "RiderLaunchMark")?.cgImage
        mark.contentsGravity = .resizeAspect
        for band in markBands {
            band.backgroundColor = UIColor.black.cgColor
            markMask.addSublayer(band)
        }
        layer.addSublayer(pulse)
        layer.addSublayer(cover)
        edge.opacity = 0
        edgeSilhouette.contents = mark.contents
        edgeSilhouette.contentsGravity = .resizeAspect
        edge.mask = edgeSilhouette
        for band in edgeBands {
            band.backgroundColor = PremiumLaunchTrack.accent.cgColor
            edge.addSublayer(band)
        }
        layer.addSublayer(edge)
        layer.addSublayer(mark)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        restoreAccessibility()
        guard let window else { return }
        accessibilityWindow = window
        previousAccessibilityElements = window.accessibilityElements
        window.accessibilityElements = [self]
    }
    func restoreAccessibility() {
        if let window = accessibilityWindow,
           let elements = window.accessibilityElements,
           elements.count == 1, let view = elements.first as? UIView, view === self {
            window.accessibilityElements = previousAccessibilityElements
        }
        previousAccessibilityElements = nil
        accessibilityWindow = nil
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard !prepared, bounds.width > 0, bounds.height > 0 else { return }
        prepared = true
        CATransaction.begin(); CATransaction.setDisableActions(true)
        cover.frame = bounds; pulse.frame = bounds
        mark.frame = LaunchPresentation.logoRect(in: bounds.size)
        markMask.frame = mark.bounds
        mark.mask = markMask
        edge.frame = mark.frame
        edgeSilhouette.frame = edge.bounds
        for (index, band) in markBands.enumerated() {
            let segment = PremiumLaunchTrack.segments[index]
            let factor = mark.bounds.width / 455
            let rect = segment.rect.applying(CGAffineTransform(scaleX: factor, y: factor))
            band.bounds = CGRect(origin: .zero, size: rect.size)
            band.anchorPoint = segment.anchor
            band.position = CGPoint(x: rect.minX + rect.width * segment.anchor.x,
                                    y: rect.minY + rect.height * segment.anchor.y)
            edgeBands[index].bounds = band.bounds
            edgeBands[index].anchorPoint = band.anchorPoint
            edgeBands[index].position = band.position
        }
        // Static paths and compositor-only transforms avoid rebuilding geometry
        // or publishing SwiftUI state on every display frame.
        cover.path = PremiumLaunchTrack.circlePath(radius: PremiumLaunchTrack.coverRadius(at: 0, in: bounds.size), in: bounds.size)
        pulse.path = PremiumLaunchTrack.circlePath(radius: PremiumLaunchTrack.pulseRadius(at: 0, in: bounds.size), in: bounds.size)
        applyState(at: 0)
        CATransaction.commit()
        let display = CADisplayLink(target: self, selector: #selector(frameTick))
        display.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        display.add(to: .main, forMode: .common); link = display
        let updates = UIUpdateLink(view: self)
        updates.addAction(to: .beforeCATransactionCommit) { [weak self] _, _ in self?.submitIfReady() }
        updates.addAction(to: .afterCATransactionCommit) { [weak self] update, _ in
            guard let self, let submittedAt = self.submittedAt else { return }
            SplashDiag.log.notice("COMMIT submissionToCommit=\(CACurrentMediaTime() - submittedAt, privacy: .public)")
            update.isEnabled = false
        }
        // UIKit requires an associated phase action before continuous updates.
        updates.requiresContinuousUpdates = true
        updates.isEnabled = true
        commitLink = updates
    }
    func stop() {
        link?.invalidate(); link = nil
        commitLink?.isEnabled = false; commitLink = nil
    }
    private func applyState(at time: Double) {
        let motionTime = reduceMotion ? 0 : time
        let coverScale = PremiumLaunchTrack.coverRadius(at: motionTime, in: bounds.size) / PremiumLaunchTrack.coverRadius(at: 0, in: bounds.size)
        cover.transform = CATransform3DMakeScale(coverScale, coverScale, 1)
        for (index, band) in markBands.enumerated() {
            let value = PremiumLaunchTrack.remaining(at: motionTime, segment: index)
            let horizontal = PremiumLaunchTrack.segments[index].axis == "x"
            band.transform = CATransform3DMakeScale(horizontal ? value : 1, horizontal ? 1 : value, 1)
            let trailing = PremiumLaunchTrack.remaining(at: motionTime - 2.0 / 60, segment: index)
            edgeBands[index].transform = CATransform3DMakeScale(horizontal ? trailing : 1, horizontal ? 1 : trailing, 1)
        }
        edge.opacity = PremiumLaunchTrack.edgeOpacity(at: motionTime)
        cover.fillColor = PremiumLaunchTrack.diskColor(at: motionTime)
        if reduceMotion {
            let opacity = Float(LaunchPresentation.opacity(at: time))
            cover.opacity = opacity; mark.opacity = opacity; pulse.opacity = 0
        } else {
            cover.opacity = PremiumLaunchTrack.coverOpacity(at: time)
            let scale = PremiumLaunchTrack.pulseRadius(at: time, in: bounds.size) / PremiumLaunchTrack.pulseRadius(at: 0, in: bounds.size)
            pulse.transform = CATransform3DMakeScale(scale, scale, 1)
            pulse.opacity = PremiumLaunchTrack.pulseOpacity(at: time)
        }
    }
    private func track(_ target: CALayer, _ property: String, _ values: [Any], duration: Double) {
        let animation = CAKeyframeAnimation(keyPath: property)
        animation.values = values
        animation.keyTimes = values.indices.map { NSNumber(value: Double($0) / Double(values.count - 1)) }
        animation.duration = duration
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        animation.calculationMode = .linear
        tracks.append((target, animation))
    }
    private func prepareAnimations(offset: Double) {
        let end = reduceMotion ? LaunchPresentation.duration : PremiumLaunchTrack.duration
        let duration = end - offset
        let count = Int(ceil(duration * 120))
        let times = (0...count).map { offset + Double($0) / Double(count) * duration }
        if reduceMotion {
            let values = times.map { LaunchPresentation.opacity(at: $0) }
            track(cover, "opacity", values, duration: duration)
            track(mark, "opacity", values, duration: duration)
        } else {
            let coverRadius = PremiumLaunchTrack.coverRadius(at: 0, in: bounds.size)
            let pulseRadius = PremiumLaunchTrack.pulseRadius(at: 0, in: bounds.size)
            track(cover, "transform.scale", times.map { PremiumLaunchTrack.coverRadius(at: $0, in: bounds.size) / coverRadius }, duration: duration)
            track(cover, "opacity", times.map { PremiumLaunchTrack.coverOpacity(at: $0) }, duration: duration)
            track(cover, "fillColor", times.map { PremiumLaunchTrack.diskColor(at: $0) }, duration: duration)
            track(edge, "opacity", times.map { PremiumLaunchTrack.edgeOpacity(at: $0) }, duration: duration)
            for (index, band) in markBands.enumerated() {
                track(edgeBands[index], "transform.scale." + PremiumLaunchTrack.segments[index].axis,
                      times.map { PremiumLaunchTrack.remaining(at: $0 - 2.0 / 60, segment: index) }, duration: duration)
                track(band, "transform.scale." + PremiumLaunchTrack.segments[index].axis,
                      times.map { PremiumLaunchTrack.remaining(at: $0, segment: index) }, duration: duration)
            }
            track(pulse, "transform.scale", times.map { PremiumLaunchTrack.pulseRadius(at: $0, in: bounds.size) / pulseRadius }, duration: duration)
            track(pulse, "opacity", times.map { PremiumLaunchTrack.pulseOpacity(at: $0) }, duration: duration)
        }
    }
    @objc private func frameTick(_ display: CADisplayLink) {
        if started {
            _ = clock.tick()
            finishIfReady()
            return
        }
        _ = clock.tick(active: false)
        guard preparedOffset == nil, SplashClock.nextReady,
              window?.windowScene?.activationState == .foregroundActive else { return }
        // Two layout commits on a cold install can arrive within the same refresh.
        // Let the clubs host appear and cross a display refresh after that commit.
        if let boundary = clubsPresentationBoundary {
            guard let readyAt = boundary(), display.timestamp > readyAt else { return }
            SplashDiag.log.notice("CLUBS readyToRefresh=\(display.timestamp - readyAt, privacy: .public)")
        }
        let setupStart = CACurrentMediaTime()
        let offset = PremiumLaunchTrack.holdCredit(displayedFor: clock.displayedFor(at: setupStart), reduceMotion: reduceMotion)
        prepareAnimations(offset: offset)
        preparedOffset = offset
        SplashDiag.log.notice("TRACKS setupSeconds=\(CACurrentMediaTime() - setupStart, privacy: .public)")
    }
    private func finishIfReady() {
        let end = reduceMotion ? LaunchPresentation.duration : PremiumLaunchTrack.duration
        // CA may deliver completion just before the monotonic deadline. Keep
        // the already-revealed destination until the next real display callback;
        // never round the measured duration up or release network work early.
        guard clock.animationCompleted, clock.elapsed >= end, !finished else { return }
        finished = true
        stop()
        onComplete()
    }
    private func submitIfReady() {
        guard !started, let offset = preparedOffset else { return }
        guard window?.windowScene?.activationState == .foregroundActive, SplashClock.nextReady else {
            return
        }
        SplashDiag.log.notice("VISIBLE launch scene active +\(Int(Date().timeIntervalSince(SplashDiag.processStart) * 1000), privacy: .public)ms")
        started = true
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let duration = reduceMotion ? LaunchPresentation.duration : PremiumLaunchTrack.duration
        if let held = UserDefaults.standard.string(forKey: "splashHold") {
            applyState(at: held == "start" ? 0 : (held == "fade" ? duration * 0.75 : duration))
            CATransaction.commit(); stop(); return
        }
        let now = CACurrentMediaTime()
        submittedAt = now
        // Submit just before UIKit's normal commit, after display-link callbacks.
        // Preparation no longer consumes the already-running erasure timeline.
        // Never force-flush unrelated SwiftUI transactions or hide their cost:
        // COMMIT and startup timing include any remaining commit work.
        clock.begin(at: now, timelineOffset: offset)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            _ = self.clock.tick()
            self.clock.animationCompleted = true
            self.finishIfReady()
        }
        applyState(at: duration)
        for (target, animation) in tracks {
            // Use the same animation clock for Clubs and Home. The cold Clubs
            // host still crosses its readiness boundary before tracks are prepared.
            animation.beginTime = target.convertTime(now, from: nil)
            target.add(animation, forKey: animation.keyPath)
        }
        CATransaction.commit()
        _ = clock.tick(now)
    }
}

/// Observe completed UIKit commits after actual destination layout. Display-link
/// callbacks alone run before commit and cannot establish that layout was sent.
/// No remote data is involved in readiness.
struct LaunchDestinationReadiness: UIViewRepresentable {
    func makeUIView(context: Context) -> ReadinessProbe { ReadinessProbe() }
    func updateUIView(_ uiView: ReadinessProbe, context: Context) {}
    static func dismantleUIView(_ view: ReadinessProbe, coordinator: ()) { view.stop() }
    final class ReadinessProbe: UIView {
        var layoutGeneration: () -> Int = { 0 }
        private var link: UIUpdateLink?
        private var readiness = LaunchCommitReadiness()
        private var firstCommitAt: CFTimeInterval?
        private(set) var committedAt: CFTimeInterval?
        private var observedCommits = 0
        private var done = false
        override func layoutSubviews() {
            super.layoutSubviews()
            guard !done, link == nil, window != nil else { return }
            let updates = UIUpdateLink(view: self)
            updates.addAction(to: .afterCATransactionCommit) { [weak self] _, info in self?.destinationDidCommit(updateTime: info.modelTime) }
            updates.requiresContinuousUpdates = true
            updates.isEnabled = true
            link = updates
        }
        func stop() { link?.isEnabled = false; link = nil }
        private func destinationDidCommit(updateTime: Double) {
            guard !done else { return }
            let now = CACurrentMediaTime()
            if firstCommitAt == nil { firstCommitAt = now }
            observedCommits += 1
            guard readiness.observe(layoutGeneration: layoutGeneration(),
                                    isActive: window?.windowScene?.activationState == .foregroundActive,
                                    updateTime: updateTime) else { return }
            committedAt = now
            done = true; stop()
            os_signpost(.end, log: SplashDiag.points, name: "Rider destination preparation")
            SplashDiag.log.notice("READINESS observedCommits=\(self.observedCommits, privacy: .public) firstCommitToReady=\(now - (self.firstCommitAt ?? now), privacy: .public)")
            SplashDiag.log.notice("NEXT layout committed in active scene")
            SplashClock.nextReady = true
        }
    }
}
