import ActivityKit
import WidgetKit
import SwiftUI

struct SportsAppWidgetExtensionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties like score
        var homeScore: Int
        var awayScore: Int
        var minute: String
        var status: String
    }

    // Fixed non-changing properties about that activity
    var matchId: String
    var homeTeamName: String
    var awayTeamName: String
    var homeTeamLogo: String
    var awayTeamLogo: String
}

struct SportsAppWidgetExtensionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SportsAppWidgetExtensionAttributes.self) { context in
            // Lock screen/banner UI
            VStack {
                HStack {
                    VStack(alignment: .leading) {
                        Text(context.attributes.homeTeamName)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Text("\(context.state.homeScore) - \(context.state.awayScore)")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(red: 0.3, green: 0.9, blue: 0.5)) // Neon Green
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(context.attributes.awayTeamName)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                
                HStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("\(context.state.minute) • \(context.state.status.uppercased())")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .activityBackgroundTint(Color(red: 0.05, green: 0.05, blue: 0.05))
            .activitySystemActionForegroundColor(Color.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("\(context.attributes.homeTeamName)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.attributes.awayTeamName)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.state.homeScore) - \(context.state.awayScore)")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(red: 0.3, green: 0.9, blue: 0.5))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("\(context.state.minute) • \(context.state.status.uppercased())")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
            } compactLeading: {
                Text("\(context.state.homeScore)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.3, green: 0.9, blue: 0.5))
            } compactTrailing: {
                Text("\(context.state.awayScore)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.3, green: 0.9, blue: 0.5))
            } minimal: {
                Text("\(context.state.homeScore)-\(context.state.awayScore)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.3, green: 0.9, blue: 0.5))
            }
            .widgetURL(URL(string: "sportsapp://match/\(context.attributes.matchId)"))
            .keylineTint(Color(red: 0.3, green: 0.9, blue: 0.5))
        }
    }
}
