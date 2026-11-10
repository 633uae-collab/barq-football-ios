import SwiftUI
import UIKit
import os

/// A native launch boundary keeps the animated cover outside the destination's
/// SwiftUI graph. The real destination stays mounted throughout the reveal;
/// finishing launch changes UIKit interaction, not the entire root view value.
struct LaunchContainer<Destination: View>: UIViewControllerRepresentable {
    let firstLaunch: Bool
    let revision: String
    let prepare: (CGSize) async -> Void
    @ViewBuilder var destination: () -> Destination

    private func renderer(_ environment: EnvironmentValues) -> () -> AnyView {
        let destination = destination
        return {
            // A full environment assignment must include prepared pixels;
            // otherwise it overwrites an outer prepared-image modifier.
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
    private let prepare: (CGSize) async -> Void
    private var render: () -> AnyView
    private let clock = SplashClock()
    private var surface: PremiumLaunchLayer?
    private var destination: LaunchDestinationController?
    private var readiness: LaunchDestinationReadiness.ReadinessProbe?
    private var preparation: Task<Void, Never>?
    private var released = false
    private var coveredRootUpdates = 0
    private var motionRootUpdates = 0

    init(firstLaunch: Bool, reduceMotion: Bool, revision: String,
         prepare: @escaping (CGSize) async -> Void, render: @escaping () -> AnyView) {
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
        if !released {
            coveredRootUpdates += 1
            if clock.elapsed > 0 { motionRootUpdates += 1 }
        }
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
            await prepare(view.bounds.size)
            guard !Task.isCancelled else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            let host = withTransaction(transaction) {
                LaunchDestinationController(rootView: render())
            }
            // Resolve the real destination's first layout while still covered.
            // A sibling probe's commit alone does not drain pending host layout.
            // Scope UIKit animation suppression to insertion only; native glass
            // and subsequent page interactions retain their normal behavior.
            UIView.performWithoutAnimation {
                withTransaction(transaction) {
                    host.view.backgroundColor = .clear
                    host.view.frame = view.bounds
                    host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    host.view.isUserInteractionEnabled = false
                    host.view.accessibilityElementsHidden = true
                    addChild(host)
                    view.insertSubview(host.view, at: 0)
                    host.didMove(toParent: self)
                    host.view.setNeedsLayout()
                    host.view.layoutIfNeeded()
                }
            }
            destination = host
            let probe = LaunchDestinationReadiness.ReadinessProbe()
            probe.layoutGeneration = { [weak host] in host?.layoutGeneration ?? 0 }
            probe.isUserInteractionEnabled = false
            probe.frame = view.bounds
            probe.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.insertSubview(probe, belowSubview: surface!)
            readiness = probe
            view.setNeedsLayout()
        }
    }

    private func finish() {
        guard !released else { return }
        released = true
        os_signpost(.end, log: SplashDiag.points, name: "Rider motion")
        SplashDiag.log.notice("FINISH firstLaunch=\(self.firstLaunch, privacy: .public) elapsed=\(self.clock.elapsed, privacy: .public) ready=\(SplashClock.nextReady, privacy: .public) maxFrameGap=\(self.clock.largestFrameGap, privacy: .public) mode=\(self.reduceMotion ? "reduced" : "premium", privacy: .public)")
        SplashDiag.log.notice("MOTION committedToCompletion=\(self.clock.activeDuration, privacy: .public) creditedStaticHold=\(self.clock.timelineOffset, privacy: .public) finishEpoch=\(Date().timeIntervalSince1970, privacy: .public)")
        SplashDiag.log.notice("STARTUP appInitToFinish=\(Date().timeIntervalSince(SplashDiag.processStart), privacy: .public) maxCallbackGapIncludingPreparation=\(self.clock.startupLargestFrameGap, privacy: .public)")
        SplashDiag.log.notice("FRAME_STATS samples=\(self.clock.sampledFrames, privacy: .public) mean=\(self.clock.meanFrameGap, privacy: .public) p95=\(self.clock.percentile95Gap, privacy: .public)")
        SplashDiag.log.notice("CONTAINER coveredRootUpdates=\(self.coveredRootUpdates, privacy: .public) motionRootUpdates=\(self.motionRootUpdates, privacy: .public)")
        SplashDiag.log.notice("DESTINATION layoutPasses=\(self.destination?.layoutGeneration ?? 0, privacy: .public) motionLayoutPasses=\(self.destination?.motionLayoutPasses ?? 0, privacy: .public)")
        surface?.restoreAccessibility()
        surface?.removeFromSuperview()
        surface = nil
        readiness?.stop()
        readiness?.removeFromSuperview()
        readiness = nil
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

/// Observes the actual hosting view rather than treating commits of an empty
/// sibling as evidence that SwiftUI has completed its destination layout.
private final class LaunchDestinationController: UIHostingController<AnyView> {
    private(set) var layoutGeneration = 0
    private(set) var motionLayoutPasses = 0
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutGeneration += 1
        if SplashClock.nextReady && !LaunchGate.open { motionLayoutPasses += 1 }
    }
}
