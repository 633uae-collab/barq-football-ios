import SwiftUI
import UIKit
import os

/// Rider Launch Transition sequence: stationary mark, staggered erase, then
/// the dark field contracts to a central dot over the prepared destination.
/// Reference: https://dribbble.com/shots/6991913-Rider-Launch-Transition
/// The FOTIQ artwork, green accent and native destination remain original.
enum PremiumLaunchTrack {
    static let duration = 1.4
    static func smooth(_ t: Double) -> CGFloat {
        let x = min(1, max(0, t))
        return CGFloat(x * x * (3 - 2 * x))
    }
    static func progress(_ time: Double, from start: Double, to end: Double) -> CGFloat {
        smooth((time - start) / (end - start))
    }
    static func coverRadius(at time: Double, in size: CGSize) -> CGFloat {
        let full = hypot(size.width, size.height) / 2 + 2
        let t = min(1, max(0, (time - 0.82) / 0.36))
        return full * CGFloat(pow(1 - t, 3))
    }
    static func circlePath(radius: CGFloat, in size: CGSize) -> CGPath {
        CGPath(ellipseIn: CGRect(x: size.width / 2 - radius, y: size.height / 2 - radius,
                                width: radius * 2, height: radius * 2), transform: nil)
    }
    static func markPath(at time: Double, in size: CGSize) -> CGPath {
        let path = CGMutablePath()
        // Fixed topology permits compositor interpolation. Alternating erasure
        // breaks the silhouette into short strokes without moving the logo.
        for row in 0..<8 {
            let width = size.width * markWidth(at: time, row: row)
            path.addRect(CGRect(x: row.isMultiple(of: 2) ? 0 : size.width - width,
                                y: size.height * CGFloat(row) / 8,
                                width: width, height: size.height / 8))
        }
        return path
    }
    static func markWidth(at time: Double, row: Int) -> CGFloat {
        let start = 0.42 + Double(row % 3) * 0.035
        return 1 - progress(time, from: start, to: start + 0.29)
    }
    static func pulseRadius(at time: Double, in size: CGSize) -> CGFloat {
        let full = hypot(size.width, size.height) / 2
        let t = min(1, max(0, (time - 0.88) / 0.46))
        return 5 + (full - 5) * CGFloat(pow(1 - t, 3))
    }
    static func pulseOpacity(at time: Double) -> Float {
        Float(progress(time, from: 0.86, to: 0.96) * (1 - progress(time, from: 1.23, to: duration))) * 0.22
    }
}

/// Core Animation owns motion; CADisplayLink measures main-thread cadence only.
struct PremiumLaunchSurface: UIViewRepresentable {
    let clock: SplashClock
    let reduceMotion: Bool
    func makeUIView(context: Context) -> PremiumLaunchLayer { PremiumLaunchLayer(clock: clock, reduceMotion: reduceMotion) }
    func updateUIView(_ view: PremiumLaunchLayer, context: Context) {}
    static func dismantleUIView(_ view: PremiumLaunchLayer, coordinator: ()) {
        view.stop()
        view.restoreAccessibility()
    }
}

final class PremiumLaunchLayer: UIView {
    private let cover = CAShapeLayer(), pulse = CAShapeLayer(), mark = CALayer()
    private let markMask = CALayer()
    private let markBands = (0..<8).map { _ in CALayer() }
    private let clock: SplashClock
    private let reduceMotion: Bool
    private var link: CADisplayLink?
    private var prepared = false, started = false
    private var tracks: [(CALayer, CAKeyframeAnimation)] = []
    private weak var accessibilityWindow: UIWindow?
    private var previousAccessibilityElements: [Any]?
    init(clock: SplashClock, reduceMotion: Bool) {
        self.clock = clock
        self.reduceMotion = reduceMotion
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        isAccessibilityElement = true
        accessibilityIdentifier = "splash"
        accessibilityLabel = "FOTIQ"
        accessibilityViewIsModal = true
        clipsToBounds = true
        cover.fillColor = UIColor(named: "LaunchBackground")!.cgColor
        pulse.fillColor = UIColor(red: 0, green: 196 / 255, blue: 106 / 255, alpha: 1).cgColor
        pulse.opacity = 0
        mark.contents = TransparentBrandMark.image.cgImage
        mark.contentsGravity = .resizeAspect
        for band in markBands {
            band.backgroundColor = UIColor.black.cgColor
            markMask.addSublayer(band)
        }
        layer.addSublayer(pulse)
        layer.addSublayer(cover)
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
        for (row, band) in markBands.enumerated() {
            band.bounds = CGRect(x: 0, y: 0, width: mark.bounds.width, height: mark.bounds.height / 8)
            band.anchorPoint = CGPoint(x: row.isMultiple(of: 2) ? 0 : 1, y: 0.5)
            band.position = CGPoint(x: row.isMultiple(of: 2) ? 0 : mark.bounds.width,
                                    y: mark.bounds.height * (CGFloat(row) + 0.5) / 8)
        }
        // Keep geometry static: changing shape paths can require fresh
        // rasterization. The e83 recording skipped most of the reveal despite
        // a small main-thread gap; transforms remove that possible source of
        // render-server work without treating display-link cadence as proof.
        cover.path = PremiumLaunchTrack.circlePath(radius: PremiumLaunchTrack.coverRadius(at: 0, in: bounds.size), in: bounds.size)
        pulse.path = PremiumLaunchTrack.circlePath(radius: PremiumLaunchTrack.pulseRadius(at: 0, in: bounds.size), in: bounds.size)
        applyState(at: 0)
        prepareAnimations()
        CATransaction.commit()
        let display = CADisplayLink(target: self, selector: #selector(frameTick))
        display.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        display.add(to: .main, forMode: .common); link = display
    }
    func stop() { link?.invalidate(); link = nil }
    private func applyState(at time: Double) {
        let motionTime = reduceMotion ? 0 : time
        let coverScale = PremiumLaunchTrack.coverRadius(at: motionTime, in: bounds.size) / PremiumLaunchTrack.coverRadius(at: 0, in: bounds.size)
        cover.transform = CATransform3DMakeScale(coverScale, coverScale, 1)
        for (row, band) in markBands.enumerated() {
            band.transform = CATransform3DMakeScale(PremiumLaunchTrack.markWidth(at: motionTime, row: row), 1, 1)
        }
        if reduceMotion {
            let opacity = Float(LaunchPresentation.opacity(at: time))
            cover.opacity = opacity; mark.opacity = opacity; pulse.opacity = 0
        } else {
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
        animation.calculationMode = .linear
        tracks.append((target, animation))
    }
    private func prepareAnimations() {
        let duration = reduceMotion ? LaunchPresentation.duration : PremiumLaunchTrack.duration
        let times = (0...168).map { Double($0) / 168 * duration }
        if reduceMotion {
            let values = times.map { LaunchPresentation.opacity(at: $0) }
            track(cover, "opacity", values, duration: duration)
            track(mark, "opacity", values, duration: duration)
        } else {
            let coverRadius = PremiumLaunchTrack.coverRadius(at: 0, in: bounds.size)
            let pulseRadius = PremiumLaunchTrack.pulseRadius(at: 0, in: bounds.size)
            track(cover, "transform.scale", times.map { PremiumLaunchTrack.coverRadius(at: $0, in: bounds.size) / coverRadius }, duration: duration)
            for (row, band) in markBands.enumerated() {
                track(band, "transform.scale.x", times.map { PremiumLaunchTrack.markWidth(at: $0, row: row) }, duration: duration)
            }
            track(pulse, "transform.scale", times.map { PremiumLaunchTrack.pulseRadius(at: $0, in: bounds.size) / pulseRadius }, duration: duration)
            track(pulse, "opacity", times.map { PremiumLaunchTrack.pulseOpacity(at: $0) }, duration: duration)
        }
    }
    @objc private func frameTick(_ display: CADisplayLink) {
        if started { _ = clock.tick(); return }
        guard window?.windowScene?.activationState == .foregroundActive, SplashClock.nextReady else {
            _ = clock.tick(active: false); return
        }
        SplashDiag.log.notice("VISIBLE launch scene active +\(Int(Date().timeIntervalSince(SplashDiag.processStart) * 1000), privacy: .public)ms")
        started = true
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let duration = reduceMotion ? LaunchPresentation.duration : PremiumLaunchTrack.duration
        if let held = UserDefaults.standard.string(forKey: "splashHold") {
            applyState(at: held == "start" ? 0 : (held == "fade" ? duration * 0.75 : duration))
            CATransaction.commit(); stop(); return
        }
        CATransaction.setCompletionBlock { [weak self] in self?.clock.animationCompleted = true }
        applyState(at: duration)
        for (target, animation) in tracks { target.add(animation, forKey: animation.keyPath) }
        CATransaction.commit()
        _ = clock.tick()
    }
}

/// Wait for the destination's actual layout and two display opportunities, not
/// merely a queued SwiftUI state update. This keeps first text/glass layout out
/// of the animated interval. No remote data is involved in readiness.
struct LaunchDestinationReadiness: UIViewRepresentable {
    func makeUIView(context: Context) -> ReadinessProbe { ReadinessProbe() }
    func updateUIView(_ uiView: ReadinessProbe, context: Context) {}
    static func dismantleUIView(_ view: ReadinessProbe, coordinator: ()) { view.stop() }
    final class ReadinessProbe: UIView {
        private var link: CADisplayLink?
        private var previous: CFTimeInterval?
        private var done = false
        override func layoutSubviews() {
            super.layoutSubviews()
            guard !done, link == nil, window != nil else { return }
            let display = CADisplayLink(target: self, selector: #selector(destinationFrameDidDisplay(_:)))
            display.add(to: .main, forMode: .common); link = display
        }
        func stop() { link?.invalidate(); link = nil }
        @objc private func destinationFrameDidDisplay(_ display: CADisplayLink) {
            guard window?.windowScene?.activationState == .foregroundActive else {
                previous = nil
                return
            }
            guard let previous, display.timestamp - previous < 0.05 else {
                previous = display.timestamp
                return
            }
            done = true; stop()
            SplashDiag.log.notice("NEXT layout committed in active scene")
            SplashClock.nextReady = true
        }
    }
}
