import WidgetKit
import SwiftUI
import ActivityKit

@main
struct BARQWidgetsBundle: WidgetBundle {
    var body: some Widget { MatchLiveActivity() }
}

struct MatchLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MatchActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "barq://match/\(context.attributes.fixtureId)"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.homeShort).font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.awayShort).font(.headline)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.state.homeGoals) - \(context.state.awayGoals)")
                        .font(.title2.bold()).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        Label("\(context.state.minute)'", systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption).foregroundStyle(.red)
                        if let ev = context.state.lastEvent { Text(ev).font(.caption2).lineLimit(1) }
                        if let ins = context.state.insight {
                            Label(ins, systemImage: "brain.head.profile").font(.caption2).lineLimit(2)
                        }
                    }
                }
            } compactLeading: {
                Text("\(context.attributes.homeShort) \(context.state.homeGoals)").font(.caption.bold()).monospacedDigit()
            } compactTrailing: {
                Text("\(context.state.awayGoals) \(context.attributes.awayShort)").font(.caption.bold()).monospacedDigit()
            } minimal: {
                Text("\(context.state.homeGoals)-\(context.state.awayGoals)").font(.caption2.bold()).monospacedDigit()
            }
            .widgetURL(URL(string: "barq://match/\(context.attributes.fixtureId)"))
        }
    }
}

struct LockScreenView: View {
    let context: ActivityViewContext<MatchActivityAttributes>
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "soccerball").foregroundStyle(.blue)
                Text(context.attributes.league).font(.caption).lineLimit(1)
                Spacer()
                Label(context.state.status == "FT" ? "انتهت" : "\(context.state.minute)'", systemImage: "circle.fill")
                    .font(.caption.bold()).foregroundStyle(context.state.status == "FT" ? .secondary : Color.red)
            }
            HStack {
                Text(context.attributes.homeName).font(.headline).lineLimit(1).frame(maxWidth: .infinity)
                Text("\(context.state.homeGoals) - \(context.state.awayGoals)").font(.title.bold()).monospacedDigit()
                Text(context.attributes.awayName).font(.headline).lineLimit(1).frame(maxWidth: .infinity)
            }
            if let ins = context.state.insight {
                Label(ins, systemImage: "brain.head.profile").font(.caption).lineLimit(2)
            }
        }
        .padding()
        .environment(\.layoutDirection, .rightToLeft)
    }
}
