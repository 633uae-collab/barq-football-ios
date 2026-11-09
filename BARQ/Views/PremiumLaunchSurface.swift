import SwiftUI
import UIKit
import os

/// A single 1.4-second camera track, independent of refresh rate. Coordinates
/// describe the existing bitmap; the aperture stays inside the F's actual gap.
enum PremiumLaunchTrack {
    static let duration = 1.4
    static let aperture = CGRect(x: 0.43, y: 0.386, width: 0.13, height: 0.057)
    struct Pose {
        var scale: CGFloat
        var pitch: CGFloat
        var yaw: CGFloat
        var center: CGPoint
        var opens: Bool
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
        let approach = smooth((elapsed - 0.12) / 0.60)
        let orbit = sin(Double(approach) * .pi)
        let travel = smooth((elapsed - 0.72) / (duration - 0.72))
        let fullScale = max((size.width + 80) / (rect.width * aperture.width),
                            (size.height + 80) / (rect.height * aperture.height))
        // Move towards the gap while the perspective settles; then continue
        // through that same gap. No crossfade, replacement image or page cut.
        return Pose(scale: 1 + approach * 0.7 + travel * travel * (fullScale - 1.7),
                    pitch: CGFloat(orbit) * 0.10,
                    yaw: CGFloat(orbit) * -0.30,
                    center: CGPoint(x: start.x + (target.x - start.x) * approach,
                                    y: start.y + (target.y - start.y) * approach),
                    opens: elapsed >= 0.72)
    }
    static func transform(_ pose: Pose) -> CATransform3D {
        var matrix = CATransform3DIdentity
        matrix.m34 = -1 / 700
        matrix = CATransform3DRotate(matrix, pose.yaw, 0, 1, 0)
        matrix = CATransform3DRotate(matrix, pose.pitch, 1, 0, 0)
        return CATransform3DScale(matrix, pose.scale, pose.scale, 1)
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

/// All motion lives in Core Animation's compositor. SwiftUI and the destination
/// are not recomputed for every frame. CADisplayLink only measures main-thread
/// cadence; it does not drive the logo's position or the reveal mask.
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
    private let cover = CALayer(), plane = CATransformLayer(), mark = CALayer()
    private let apertureMask = CAShapeLayer()
    private let clock: SplashClock
    private let reduceMotion: Bool
    private var link: CADisplayLink?
    private var prepared = false, started = false
    private var opacityAnimation: CAKeyframeAnimation?
    private var transformAnimation: CAKeyframeAnimation?
    private var positionAnimation: CAKeyframeAnimation?
    private var revealAnimation: CAKeyframeAnimation?
    private var finalPose: PremiumLaunchTrack.Pose?
    private var finalMaskPath: CGPath?
    private weak var accessibilityWindow: UIWindow?
    private var previousAccessibilityElements: [Any]?
    init(clock: SplashClock, reduceMotion: Bool) {
        self.clock = clock
        self.reduceMotion = reduceMotion
        super.init(frame: .zero)
        // The cover owns touch and VoiceOver until the destination is revealed.
        // SwiftUI's accessibilityHidden alone does not hide native nav/tab bars.
        isUserInteractionEnabled = true
        isAccessibilityElement = true
        accessibilityIdentifier = "splash"
        accessibilityLabel = "FOTIQ"
        accessibilityViewIsModal = true
        cover.backgroundColor = UIColor(named: "LaunchBackground")!.cgColor
        // The original texture is used initially, matching LaunchScreen exactly.
        // Initial layout installs the transparent texture and depth stack while
        // stationary, before the foreground readiness wait and timed track.
        mark.contents = UIImage(named: "SplashMark")?.cgImage
        mark.contentsGravity = .resizeAspect
        plane.addSublayer(mark); cover.addSublayer(plane); layer.addSublayer(cover)
        apertureMask.fillRule = .evenOdd
        apertureMask.fillColor = UIColor.black.cgColor
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
        guard !prepared, bounds.width > 0 else { return }
        prepared = true
        let rect = LaunchPresentation.logoRect(in: bounds.size)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        cover.frame = bounds
        plane.bounds = CGRect(origin: .zero, size: rect.size)
        plane.anchorPoint = CGPoint(x: PremiumLaunchTrack.aperture.midX, y: PremiumLaunchTrack.aperture.midY)
        plane.position = PremiumLaunchTrack.pose(at: 0, in: bounds.size).center
        mark.frame = plane.bounds
        apertureMask.frame = bounds
        prepareAnimations()
        if !reduceMotion {
            // Establish the masked compositing surface while the initial logo
            // is held, before readiness starts the timed camera movement.
            apertureMask.path = maskPath(at: 0)
            cover.mask = apertureMask
        }
        CATransaction.commit()
        let dl = CADisplayLink(target: self, selector: #selector(frameTick))
        dl.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        dl.add(to: .main, forMode: .common); link = dl
    }
    func stop() { link?.invalidate(); link = nil }
    private func maskPath(at time: Double) -> CGPath {
        let path = CGMutablePath()
        path.addRect(bounds)
        // A degenerate hole before reveal retains an identical CGPath topology
        // for interpolation, without showing the page early.
        let corners = PremiumLaunchTrack.apertureCorners(at: time, in: bounds.size)
        let center = PremiumLaunchTrack.pose(at: time, in: bounds.size).center
        let opening = PremiumLaunchTrack.smooth((time - 0.72) / 0.08)
        let points = corners.map { CGPoint(x: center.x + ($0.x - center.x) * opening,
                                          y: center.y + ($0.y - center.y) * opening) }
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }
    private func keyframes(_ property: String, values: [Any], duration: Double) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: property)
        animation.values = values
        animation.keyTimes = values.indices.map { NSNumber(value: Double($0) / Double(values.count - 1)) }
        animation.duration = duration
        animation.calculationMode = .linear
        return animation
    }
    private func prepareAnimations() {
        // Allocate the geometry, texture and keyframes while the original mark
        // is still held. Starting the clock before this work shortened the
        // visible track and could remove the cover before its reveal finished.
        if reduceMotion {
            let duration = LaunchPresentation.duration
            opacityAnimation = keyframes("opacity", values: (0...96).map {
                LaunchPresentation.opacity(at: Double($0) / 96 * duration)
            }, duration: duration)
            return
        }
        let image = TransparentBrandMark.image.cgImage
        // Commit the actual moving texture and visible depth stack in the
        // initial stationary frame. Hidden layers are not a render warm-up:
        // unhiding them at start can defer texture upload/compositing until
        // after the timed animation has begun.
        mark.contents = image
        for slice in 1...6 {
            let depth = CALayer()
            depth.frame = plane.bounds
            depth.contents = image
            depth.opacity = 0.35
            depth.zPosition = -CGFloat(slice) * 0.45
            plane.insertSublayer(depth, below: mark)
        }
        let duration = PremiumLaunchTrack.duration
        let times = (0...168).map { Double($0) / 168 * duration }
        let poses = times.map { PremiumLaunchTrack.pose(at: $0, in: bounds.size) }
        finalPose = poses.last
        finalMaskPath = maskPath(at: duration)
        transformAnimation = keyframes("transform", values: poses.map {
            NSValue(caTransform3D: PremiumLaunchTrack.transform($0))
        }, duration: duration)
        positionAnimation = keyframes("position", values: poses.map {
            NSValue(cgPoint: $0.center)
        }, duration: duration)
        revealAnimation = keyframes("path", values: times.map { maskPath(at: $0) }, duration: duration)
    }
    private func add(_ animation: CAAnimation?, to layer: CALayer, key: String) {
        guard let animation else { return }
        // Let the same CA transaction resolve the start time for every track.
        // An explicit process-clock timestamp left the simulator's presentation
        // frozen until the cover was removed in run 42648693096.
        layer.add(animation, forKey: key)
    }
    @objc private func frameTick(_ dl: CADisplayLink) {
        if started {
            _ = clock.tick()
            return
        }
        // A laid-out window can still be underneath iOS's launch snapshot.
        // Do not consume the camera track while that scene is inactive. The
        // readiness probe also requires two foreground display opportunities.
        guard window?.windowScene?.activationState == .foregroundActive,
              SplashClock.nextReady else {
            _ = clock.tick(active: false)
            return
        }
        SplashDiag.log.notice("VISIBLE launch scene active +\(Int(Date().timeIntervalSince(SplashDiag.processStart) * 1000), privacy: .public)ms")
        started = true
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if let held = UserDefaults.standard.string(forKey: "splashHold") {
            // Preserve the existing real-frame capture harness. A held frame
            // renders the same track state, without starting an animation.
            if reduceMotion {
                let time = held == "start" ? 0 : (held == "fade" ? 0.65 : LaunchPresentation.duration)
                cover.opacity = Float(LaunchPresentation.opacity(at: time))
            } else {
                let time = held == "start" ? 0 : (held == "fade" ? 1.0 : PremiumLaunchTrack.duration)
                let pose = PremiumLaunchTrack.pose(at: time, in: bounds.size)
                mark.contents = TransparentBrandMark.image.cgImage
                plane.transform = PremiumLaunchTrack.transform(pose)
                plane.position = pose.center
                cover.mask = apertureMask
                apertureMask.path = maskPath(at: time)
            }
            CATransaction.commit()
            stop()
            return
        }
        CATransaction.setCompletionBlock { [weak self] in
            self?.clock.animationCompleted = true
        }
        if reduceMotion {
            cover.opacity = 0
            add(opacityAnimation, to: cover, key: "reducedLaunch")
        } else {
            // Six shallow slices give the original silhouette real perspective
            // thickness; the original alpha channel preserves both F and dot.
            if let finalPose {
                plane.transform = PremiumLaunchTrack.transform(finalPose)
                plane.position = finalPose.center
            }
            add(transformAnimation, to: plane, key: "cameraPerspective")
            add(positionAnimation, to: plane, key: "cameraPath")
            cover.mask = apertureMask
            apertureMask.path = finalMaskPath
            add(revealAnimation, to: apertureMask, key: "gapReveal")
        }
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
