import SwiftUI
import UIKit
import os

/// A single 1.5-second camera track, independent of refresh rate. Coordinates
/// describe the existing bitmap; the aperture stays inside the F's actual gap.
enum PremiumLaunchTrack {
    static let duration = 1.5
    static let hold = 0.30
    static let passage = 0.90

    static func holdCredit(displayedFor seconds: Double, reduceMotion: Bool) -> Double {
        min(max(0, seconds), reduceMotion ? LaunchPresentation.hold : hold)
    }
    static let aperture = CGRect(x: 0.35, y: 0.28, width: 0.27, height: 0.10)
    struct Pose {
        var scale: CGFloat
        var pitch: CGFloat
        var yaw: CGFloat
        var center: CGPoint
    }
    static func smooth(_ t: Double) -> CGFloat {
        let x = min(1, max(0, t))
        return CGFloat(x * x * (3 - 2 * x))
    }
    static func pose(at elapsed: Double, in size: CGSize) -> Pose {
        let rect = LaunchPresentation.logoRect(in: size)
        let start = CGPoint(x: rect.minX + rect.width * aperture.midX,
                            y: rect.minY + rect.height * aperture.midY)
        let target = CGPoint(x: size.width / 2, y: size.height / 2)
        let approach = smooth((elapsed - hold) / (passage - hold))
        let firstAngle = sin(.pi * smooth((elapsed - hold) / 0.34))
        let reverseAngle = sin(.pi * smooth((elapsed - hold - 0.34) / (passage - hold - 0.34)))
        let travel = smooth((elapsed - passage) / (duration - passage))
        let fullScale = max((size.width + 80) / (rect.width * aperture.width),
                            (size.height + 80) / (rect.height * aperture.height))
        // Move towards the gap while the perspective settles; then continue
        // through that same gap. No crossfade, replacement image or page cut.
        return Pose(scale: 1 + approach * 0.7 + travel * travel * (fullScale - 1.7),
                    pitch: firstAngle * 0.14 - reverseAngle * 0.06,
                    yaw: firstAngle * -0.40 + reverseAngle * 0.20,
                    center: CGPoint(x: start.x + (target.x - start.x) * approach,
                                    y: start.y + (target.y - start.y) * approach))
    }
    static func transform(_ pose: Pose) -> CATransform3D {
        var matrix = CATransform3DIdentity
        matrix.m34 = -1 / 700
        matrix = CATransform3DRotate(matrix, pose.yaw, 0, 1, 0)
        matrix = CATransform3DRotate(matrix, pose.pitch, 1, 0, 0)
        return CATransform3DScale(matrix, pose.scale, pose.scale, 1)
    }
    /// Project one texture at its physical depth onto the screen. Keeping the
    /// output Z at zero prevents the navy cover from clipping half a tilted F.
    static func faceTransform(_ camera: CATransform3D, depth: CGFloat) -> CATransform3D {
        let w = camera.m44 + depth * camera.m34
        var flat = CATransform3DIdentity
        flat.m11 = camera.m11 / w
        flat.m12 = camera.m12 / w
        flat.m21 = camera.m21 / w
        flat.m22 = camera.m22 / w
        flat.m14 = camera.m14 / w
        flat.m24 = camera.m24 / w
        flat.m41 = (camera.m41 + depth * camera.m31) / w
        flat.m42 = (camera.m42 + depth * camera.m32) / w
        return flat
    }
    static func apertureCorners(at elapsed: Double, in size: CGSize) -> [CGPoint] {
        let pose = pose(at: elapsed, in: size)
        let rect = LaunchPresentation.logoRect(in: size)
        let matrix = transform(pose)
        return [CGPoint(x: aperture.minX, y: aperture.minY),
                CGPoint(x: aperture.maxX, y: aperture.minY),
                CGPoint(x: aperture.maxX, y: aperture.maxY),
                CGPoint(x: aperture.minX, y: aperture.maxY)].map { point in
            let x = (point.x - aperture.midX) * rect.width
            let y = (point.y - aperture.midY) * rect.height
            let w = x * matrix.m14 + y * matrix.m24 + matrix.m44
            return CGPoint(x: pose.center.x + (x * matrix.m11 + y * matrix.m21 + matrix.m41) / w,
                           y: pose.center.y + (x * matrix.m12 + y * matrix.m22 + matrix.m42) / w)
        }
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
    private let cover = CALayer(), plane = CALayer(), mark = CALayer()
    private let bevel = CALayer()
    private var faces: [(layer: CALayer, depth: CGFloat)] = []
    private let apertureMask = CAShapeLayer()
    private let clock: SplashClock
    private let reduceMotion: Bool
    private let onComplete: () -> Void
    private var link: CADisplayLink?
    private var commitLink: UIUpdateLink?
    private var preparedOffset: Double?
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
        // The aperture in the cover reveals the native view beneath this surface.
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = true
        isAccessibilityElement = true
        accessibilityIdentifier = "splash"
        accessibilityLabel = "FOTIQ"
        accessibilityViewIsModal = true
        clipsToBounds = true
        cover.backgroundColor = UIColor(named: "RiderLaunchBackground")!.cgColor
        mark.contents = UIImage(named: "RiderLaunchMark")?.cgImage
        mark.contentsGravity = .resizeAspect
        apertureMask.fillRule = .evenOdd
        apertureMask.fillColor = UIColor.black.cgColor
        layer.addSublayer(cover)
        layer.addSublayer(plane)
        plane.addSublayer(bevel)
        plane.addSublayer(mark)
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
        let rect = LaunchPresentation.logoRect(in: bounds.size)
        cover.frame = bounds
        plane.bounds = CGRect(origin: .zero, size: rect.size)
        plane.anchorPoint = CGPoint(x: PremiumLaunchTrack.aperture.midX, y: PremiumLaunchTrack.aperture.midY)
        bevel.frame = plane.bounds
        mark.anchorPoint = plane.anchorPoint
        mark.frame = plane.bounds
        faces = [(mark, 0)]
        if !reduceMotion {
            apertureMask.frame = cover.bounds
            cover.mask = apertureMask
            // The faces of the bevel use the original alpha, including the dot.
            for slice in (1...4).reversed() {
                let side = CAGradientLayer()
                side.anchorPoint = plane.anchorPoint
                side.frame = plane.bounds
                let depth = -CGFloat(slice) * rect.width * 0.012
                side.colors = [UIColor(white: 0.20, alpha: 1).cgColor,
                               UIColor(white: 0.76, alpha: 1).cgColor,
                               UIColor(white: 0.29, alpha: 1).cgColor]
                side.startPoint = CGPoint(x: 0, y: 0)
                side.endPoint = CGPoint(x: 1, y: 1)
                let silhouette = CALayer()
                silhouette.frame = side.bounds
                silhouette.contents = mark.contents
                side.mask = silhouette
                bevel.addSublayer(side)
                faces.append((side, depth))
            }
        }
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
    private func maskPath(at time: Double) -> CGPath {
        let path = CGMutablePath()
        path.addRect(bounds)
        // A degenerate hole before reveal retains an identical CGPath topology
        // for interpolation, without showing the page early.
        let corners = PremiumLaunchTrack.apertureCorners(at: time, in: bounds.size)
        let center = PremiumLaunchTrack.pose(at: time, in: bounds.size).center
        let opening = PremiumLaunchTrack.smooth((time - PremiumLaunchTrack.passage) / 0.08)
        let points = corners.map { CGPoint(x: center.x + ($0.x - center.x) * opening,
                                          y: center.y + ($0.y - center.y) * opening) }
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }
    private func applyState(at time: Double) {
        let pose = PremiumLaunchTrack.pose(at: reduceMotion ? 0 : time, in: bounds.size)
        plane.position = pose.center
        let camera = PremiumLaunchTrack.transform(pose)
        for face in faces {
            face.layer.transform = PremiumLaunchTrack.faceTransform(camera, depth: face.depth)
        }
        bevel.opacity = bevelOpacity(pose)
        if reduceMotion {
            let opacity = Float(LaunchPresentation.opacity(at: time))
            cover.opacity = opacity
            mark.opacity = opacity
        } else {
            apertureMask.path = maskPath(at: time)
        }
    }
    private func bevelOpacity(_ pose: PremiumLaunchTrack.Pose) -> Float {
        Float(min(1, (abs(pose.yaw) + abs(pose.pitch)) * 12))
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
            let poses = times.map { PremiumLaunchTrack.pose(at: $0, in: bounds.size) }
            track(plane, "position", poses.map { NSValue(cgPoint: $0.center) }, duration: duration)
            let cameras = poses.map(PremiumLaunchTrack.transform)
            for face in faces {
                let frames = cameras.map { NSValue(caTransform3D: PremiumLaunchTrack.faceTransform($0, depth: face.depth)) }
                track(face.layer, "transform", frames, duration: duration)
            }
            track(bevel, "opacity", poses.map(bevelOpacity), duration: duration)
            track(apertureMask, "path", times.map { maskPath(at: $0) }, duration: duration)
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
        // Preparation no longer consumes the camera timeline.
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
            done = true; stop()
            os_signpost(.end, log: SplashDiag.points, name: "Rider destination preparation")
            SplashDiag.log.notice("READINESS observedCommits=\(self.observedCommits, privacy: .public) firstCommitToReady=\(now - (self.firstCommitAt ?? now), privacy: .public)")
            SplashDiag.log.notice("NEXT layout committed in active scene")
            SplashClock.nextReady = true
        }
    }
}
