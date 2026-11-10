import SwiftUI
import UIKit
import os

/// A native launch boundary keeps the animated cover outside the destination's
/// SwiftUI graph. The real destination stays mounted throughout the reveal;
/// finishing launch changes UIKit interaction, not the entire root view value.
struct LaunchContainer<Destination: View>: UIViewControllerRepresentable {
    let firstLaunch: Bool
    let revision: String
    let prepare: () async -> Void
    @ViewBuilder var destination: () -> Destination

    private func renderer(_ environment: EnvironmentValues) -> () -> AnyView {
        let destination = destination
        return {
            // Install one coherent environment. An inner ".environment(\.self)"
            // would overwrite an outer prepared-image key and leave the first
            // rendered destination showing placeholders despite cache hits.
            var preparedEnvironment = environment
            preparedEnvironment.launchPreparedImages = LaunchHomePreparation.images
            return AnyView(destination()
                .environment(\.self, preparedEnvironment)
                .transaction { transaction in
                    if !LaunchGate.open {
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                })
        }
    }
    func makeUIViewController(context: Context) -> LaunchContainerController {
        LaunchContainerController(firstLaunch: firstLaunch,
                                  reduceMotion: context.environment.accessibilityReduceMotion,
                                  revision: revision, prepare: prepare,
                                  render: renderer(context.environment))
    }
    func updateUIViewController(_ controller: LaunchContainerController, context: Context) {
        controller.update(revision: revision, render: renderer(context.environment), transaction: context.transaction)
    }
    static func dismantleUIViewController(_ controller: LaunchContainerController, coordinator: ()) {
        controller.stop()
    }
}

final class LaunchContainerController: UIViewController {
    private let firstLaunch: Bool
    private let reduceMotion: Bool
    private var revision: String
    private let prepare: () async -> Void
    private var render: () -> AnyView
    private let clock = SplashClock()
    private var surface: PremiumLaunchLayer?
    private var destination: UIHostingController<AnyView>?
    private var readiness: LaunchDestinationReadiness.ReadinessProbe?
    private var transitionSnapshot: UIView?
    private var preparation: Task<Void, Never>?
    private var released = false

    init(firstLaunch: Bool, reduceMotion: Bool, revision: String,
         prepare: @escaping () async -> Void, render: @escaping () -> AnyView) {
        self.firstLaunch = firstLaunch
        self.reduceMotion = reduceMotion
        self.revision = revision
        self.prepare = prepare
        self.render = render
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(named: "RiderLaunchBackground")
        let cover = PremiumLaunchLayer(clock: clock, reduceMotion: reduceMotion) { [weak self] in self?.finish() }
        cover.frame = view.bounds
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(cover)
        surface = cover
        clock.onFirstFrame = { [weak self] in self?.prepareDestination() }
    }

    func update(revision: String, render: @escaping () -> AnyView, transaction: Transaction) {
        self.render = render
        // Forward environment changes even while covered: in particular the
        // initial inactive -> active scene change must reach Home's refresh and
        // visibility rules. The native animation does not publish SwiftUI state
        // every frame, and finishing it does not call this update method.
        self.revision = revision
        guard let destination else { return }
        withTransaction(transaction) { destination.rootView = render() }
    }

    private func prepareDestination() {
        guard preparation == nil else { return }
        preparation = Task { @MainActor [weak self] in
            // Let UIKit submit the lightweight F before SwiftUI constructs the
            // destination. No polling task wakes the main actor every 8 ms.
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            os_signpost(.begin, log: SplashDiag.points, name: "Rider destination preparation")
            await prepare()
            guard !Task.isCancelled else { return }
            let host = UIHostingController(rootView: render())
            host.view.backgroundColor = .clear
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.view.isUserInteractionEnabled = false
            host.view.accessibilityElementsHidden = true
            addChild(host)
            view.insertSubview(host.view, at: 0)
            host.didMove(toParent: self)
            destination = host
            let probe = LaunchDestinationReadiness.ReadinessProbe()
            probe.onReady = { [weak self] in
                // Snapshot only after the real destination has committed. Avoid
                // re-entering a UIKit commit from its completion phase.
                DispatchQueue.main.async { self?.prepareTransitionSnapshot() }
            }
            probe.isUserInteractionEnabled = false
            probe.frame = view.bounds
            probe.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.insertSubview(probe, belowSubview: surface!)
            readiness = probe
            view.setNeedsLayout()
        }
    }

    private func prepareTransitionSnapshot() {
        guard !released, let destination, let surface else { return }
        let started = CACurrentMediaTime()
        view.layoutIfNeeded()
        destination.view.layoutIfNeeded()
        // UIKit captures the original, already-rendered native interface. This
        // is a temporary transition view, not a substitute design or a video.
        // Parking the live hierarchy avoids backdrop/material recomposition
        // while the dark cover contracts. No image is stored on disk.
        if let snapshot = destination.view.snapshotView(afterScreenUpdates: true) {
            snapshot.frame = destination.view.frame
            snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            snapshot.isUserInteractionEnabled = false
            snapshot.accessibilityElementsHidden = true
            view.insertSubview(snapshot, belowSubview: surface)
            transitionSnapshot = snapshot
            destination.view.isHidden = true
        }
        SplashDiag.log.notice("TRANSITION snapshot=\(self.transitionSnapshot != nil, privacy: .public) prepareSeconds=\(CACurrentMediaTime() - started, privacy: .public)")
        readiness?.stop()
        readiness?.removeFromSuperview()
        let probe = LaunchDestinationReadiness.ReadinessProbe()
        probe.frame = view.bounds
        probe.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        probe.isUserInteractionEnabled = false
        view.insertSubview(probe, belowSubview: surface)
        readiness = probe
    }

    private func finish() {
        guard !released else { return }
        released = true
        os_signpost(.end, log: SplashDiag.points, name: "Rider motion")
        surface?.restoreAccessibility()
        surface?.removeFromSuperview()
        surface = nil
        readiness?.stop()
        readiness?.removeFromSuperview()
        readiness = nil
        guard transitionSnapshot != nil, let destination else { completeHandoff(); return }
        let started = CACurrentMediaTime()
        // Keep the identical snapshot above the live native view until UIKit
        // commits its return. It prevents a blank frame at the handoff.
        UIView.performWithoutAnimation { destination.view.isHidden = false }
        let probe = LaunchDestinationReadiness.ReadinessProbe()
        probe.frame = view.bounds
        probe.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        probe.isUserInteractionEnabled = false
        probe.onReady = { [weak self] in
            guard let self else { return }
            SplashDiag.log.notice("HANDOFF nativeViewCommitSeconds=\(CACurrentMediaTime() - started, privacy: .public)")
            self.transitionSnapshot?.removeFromSuperview()
            self.transitionSnapshot = nil
            self.readiness?.removeFromSuperview()
            self.readiness = nil
            self.completeHandoff()
        }
        view.addSubview(probe)
        readiness = probe
        view.setNeedsLayout()
    }

    private func completeHandoff() {
        SplashDiag.log.notice("FINISH firstLaunch=\(self.firstLaunch, privacy: .public) elapsed=\(self.clock.elapsed, privacy: .public) ready=\(SplashClock.nextReady, privacy: .public) maxFrameGap=\(self.clock.largestFrameGap, privacy: .public) mode=\(self.reduceMotion ? "reduced" : "premium", privacy: .public)")
        SplashDiag.log.notice("MOTION committedToCompletion=\(self.clock.activeDuration, privacy: .public) creditedStaticHold=\(self.clock.timelineOffset, privacy: .public) finishEpoch=\(Date().timeIntervalSince1970, privacy: .public)")
        SplashDiag.log.notice("STARTUP appInitToFinish=\(Date().timeIntervalSince(SplashDiag.processStart), privacy: .public) maxCallbackGapIncludingPreparation=\(self.clock.startupLargestFrameGap, privacy: .public)")
        SplashDiag.log.notice("FRAME_STATS samples=\(self.clock.sampledFrames, privacy: .public) mean=\(self.clock.meanFrameGap, privacy: .public) p95=\(self.clock.percentile95Gap, privacy: .public)")
        destination?.view.accessibilityElementsHidden = false
        destination?.view.isUserInteractionEnabled = true
        // Opening the data gate does not reconstruct the root or its glass.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            LaunchGate.open = true
        }
    }

    func stop() {
        preparation?.cancel()
        clock.onFirstFrame = nil
        surface?.stop()
        surface?.restoreAccessibility()
        readiness?.stop()
    }
}
