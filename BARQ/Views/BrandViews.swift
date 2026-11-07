import SwiftUI

/// Uses the existing original bitmap, cropped only to its transparent/ navy margins.
struct BrandMark: View {
    var height: CGFloat = 28
    var body: some View {
        Image("SplashMark").resizable().interpolation(.high)
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

/// Compact form of the exact same analyst emblem used by the AI hero.
/// It intentionally keeps the native Tab label and Liquid Glass container.
struct AnalystTabLabel: View {
    var body: some View {
        Label {
            Text("المحلل")
        } icon: {
            AnalystEmblem(size: 24, alwaysAnimate: true)
                .accessibilityHidden(true)
                .accessibilityIdentifier("analyst-tab-emblem")
        }
    }
}
