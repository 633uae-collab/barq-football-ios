import SwiftUI
import UIKit

/// Removes only the original bitmap's dark matte, once, without redrawing the mark.
enum TransparentBrandMark {
    static let image: UIImage = {
        guard let source = UIImage(named: "SplashMark"), let cg = source.cgImage else { return UIImage() }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return source }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Source matte is RGB 8/11/18. Recover edge coverage against the original
        // white letter or green dot, then remove the matte from antialiased edges.
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
            let green = g > r * 1.5 && g > b
            let coverage = min(1, max(0, green ? (g - 11) / (196 - 11) : (r - 8) / (255 - 8)))
            pixels[i] = UInt8(min(255, max(0, r - 8 * (1 - coverage))))
            pixels[i + 1] = UInt8(min(255, max(0, g - 11 * (1 - coverage))))
            pixels[i + 2] = UInt8(min(255, max(0, b - 18 * (1 - coverage))))
            pixels[i + 3] = UInt8((coverage * 255).rounded())
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let output = CGImage(width: width, height: height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return source }
        return UIImage(cgImage: output, scale: source.scale, orientation: source.imageOrientation)
    }()
}

struct BrandMark: View {
    var height: CGFloat = 28
    var body: some View {
        Image(uiImage: TransparentBrandMark.image).resizable().interpolation(.high)
            .frame(width: height * 2, height: height * 2)
            .frame(width: height * 0.90, height: height).clipped()
            .accessibilityLabel("FOTIQ")
    }
}

struct BrandHeading: View {
    var symbol: String? = nil
    var title: LocalizedStringKey? = nil
    var body: some View {
        HStack(spacing: 8) {
            BrandMark()
            if let symbol { Image(systemName: symbol).foregroundStyle(Color.accentColor) }
            if let title { Text(title).font(.headline) }
        }
    }
}

/// The original analyst hero emblem and 14-second rotation, shared by both placements.
/// No repeat-forever animation survives scrolling off screen or backgrounding.
struct AnalystEmblem: View {
    var size: CGFloat = 170
    /// Tab-bar labels are always on screen, while the larger hero should animate
    /// only while its scroll position is visible. Both placements still pause in
    /// the background and for Reduce Motion.
    var alwaysAnimate = false
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    @State private var start = Date()
    var body: some View {
        TimelineView(.animation(
            minimumInterval: size <= 32 ? 1.0 / 24 : 1.0 / 30,
            paused: !(alwaysAnimate || visible) || phase != .active || reduceMotion
        )) { context in
            let angle = reduceMotion ? 0 : context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: 14) / 14 * 360
            ZStack {
                Circle().fill(RadialGradient(colors: [.cyan.opacity(0.6), .purple.opacity(0.3), .clear], center: .center, startRadius: 4, endRadius: 90)).frame(width: 170, height: 170).blur(radius: 8)
                Image(systemName: "circle.hexagongrid").resizable().scaledToFit().frame(width: 140).foregroundStyle(.cyan.opacity(0.35)).rotationEffect(.degrees(angle))
                Image(systemName: "soccerball").resizable().scaledToFit().frame(width: 74).foregroundStyle(.white).shadow(color: .cyan, radius: 18)
                    .rotation3DEffect(.degrees(angle), axis: (x: 0.3, y: 1, z: 0))
            }.frame(width: 170, height: 170).scaleEffect(size / 170)
        }
        .frame(width: size, height: size)
        .onScrollVisibilityChange(threshold: 0.1) { visible = $0 }
        .onDisappear { visible = false }
        .accessibilityLabel("التحليل المباشر")
    }
}

/// Installs a live copy of the exact hero emblem inside the native analyst tab
/// button. iOS 26 snapshots custom `Tab` labels, so putting TimelineView directly
/// in the label produces a static icon. This bridge leaves UITabBar, its Liquid
/// Glass material, dimensions, ordering, text, hit testing and accessibility fully
/// system-owned; it hides only the analyst button's placeholder UIImageView.
struct AnalystTabBarEmblemInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.onWindowChange = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.scheduleInstall(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        context.coordinator.scheduleInstall(from: uiView)
    }

    static func dismantleUIView(_ uiView: ProbeView, coordinator: Coordinator) {
        coordinator.removeInstalledEmblem()
    }

    final class ProbeView: UIView {
        var onWindowChange: (() -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChange?()
        }
    }

    @MainActor final class Coordinator {
        private weak var analystButton: UIControl?
        private weak var placeholderImage: UIImageView?
        private weak var parentController: UIViewController?
        private var host: UIHostingController<AnyView>?
        private var installTask: Task<Void, Never>?

        func scheduleInstall(from probe: UIView) {
            guard host == nil else { return }
            installTask?.cancel()
            installTask = Task { @MainActor [weak self, weak probe] in
                // The system creates UITabBar after the TabView hierarchy appears.
                // This bounded wait runs only at installation, never per animation frame.
                for _ in 0..<30 where !Task.isCancelled {
                    guard let self, let probe, let root = probe.window else { return }
                    if self.install(in: root) { return }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }

        private func install(in root: UIView) -> Bool {
            guard let tabBar = root.firstDescendant(of: UITabBar.self) else { return false }
            let buttons = tabBar.allDescendants(of: UIControl.self)
            guard let button = buttons.first(where: {
                ($0.accessibilityLabel == "المحلل") || ($0.accessibilityIdentifier == "المحلل")
            }) else { return false }
            guard let imageView = button.allDescendants(of: UIImageView.self).first(where: { !$0.isHidden }) else {
                return false
            }

            imageView.isHidden = true
            // The visible ring occupies 140/170 of the artwork. At 30 points its
            // visible diameter is ~25 points, matching the native soccerball.
            let emblem = AnalystEmblem(size: 30, alwaysAnimate: true)
                .accessibilityHidden(true)
            let controller = UIHostingController(rootView: AnyView(emblem))
            controller.view.backgroundColor = .clear
            controller.view.isUserInteractionEnabled = false
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            let parent = button.nearestViewController
            parent?.addChild(controller)
            button.addSubview(controller.view)
            NSLayoutConstraint.activate([
                controller.view.widthAnchor.constraint(equalToConstant: 30),
                controller.view.heightAnchor.constraint(equalToConstant: 30),
                controller.view.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
                controller.view.centerYAnchor.constraint(equalTo: imageView.centerYAnchor)
            ])
            controller.didMove(toParent: parent)

            analystButton = button
            placeholderImage = imageView
            parentController = parent
            host = controller
            return true
        }

        func removeInstalledEmblem() {
            installTask?.cancel()
            host?.willMove(toParent: nil)
            host?.view.removeFromSuperview()
            host?.removeFromParent()
            placeholderImage?.isHidden = false
            host = nil
            analystButton = nil
            parentController = nil
        }
    }
}

private extension UIView {
    var nearestViewController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }

    func firstDescendant<T: UIView>(of type: T.Type) -> T? {
        if let match = self as? T { return match }
        for child in subviews {
            if let match = child.firstDescendant(of: type) { return match }
        }
        return nil
    }

    func allDescendants<T: UIView>(of type: T.Type) -> [T] {
        var result = self is T ? [self as! T] : []
        for child in subviews { result.append(contentsOf: child.allDescendants(of: type)) }
        return result
    }
}
