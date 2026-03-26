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
            // Lock screen/banner UI goes here
            VStack {
                HStack {
                    Text(context.attributes.homeTeamName)
                        .font(.headline)
                    Spacer()
                    Text("\(context.state.homeScore) - \(context.state.awayScore)")
                        .font(.title)
                        .bold()
                    Spacer()
                    Text(context.attributes.awayTeamName)
                        .font(.headline)
                }
                .padding(.horizontal)
                
                Text("\(context.state.minute) • \(context.state.status)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.8))
            .activitySystemActionForegroundColor(Color.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("\(context.attributes.homeTeamName) \(context.state.homeScore)")
                        .bold()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.awayScore) \(context.attributes.awayTeamName)")
                        .bold()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(context.state.minute) • \(context.state.status)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } compactLeading: {
                Text("\(context.attributes.homeTeamName) \(context.state.homeScore)")
                    .foregroundColor(Color.green)
            } compactTrailing: {
                Text("\(context.state.awayScore) \(context.attributes.awayTeamName)")
                    .foregroundColor(Color.green)
            } minimal: {
                Image(systemName: "sportscourt")
                    .foregroundColor(Color.green)
            }
            .widgetURL(URL(string: "sportsapp://match/\(context.attributes.matchId)"))
            .keylineTint(Color.green)
        }
    }
}
