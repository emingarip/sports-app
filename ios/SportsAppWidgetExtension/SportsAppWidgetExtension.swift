import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    // This integrates with home_widget package to read shared preference UserDefaults
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), homeTeam: "Team A", awayTeam: "Team B", homeScore: 0, awayScore: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = getEntryFromUserDefaults()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entry = getEntryFromUserDefaults()
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }
    
    // Custom function to fetch data from home_widget UserDefaults
    func getEntryFromUserDefaults() -> SimpleEntry {
        // Find the user defaults group matching the app bundle identifier + .homeWidget
        // Note: You must ensure an App Group is configured in Xcode for passing data if necessary.
        let userDefaults = UserDefaults(suiteName: "group.com.boskale.sportsapp") ?? UserDefaults.standard
        let homeTeam = userDefaults.string(forKey: "widget_home_team") ?? "Home"
        let awayTeam = userDefaults.string(forKey: "widget_away_team") ?? "Away"
        let homeScore = userDefaults.integer(forKey: "widget_home_score")
        let awayScore = userDefaults.integer(forKey: "widget_away_score")

        return SimpleEntry(date: Date(), homeTeam: homeTeam, awayTeam: awayTeam, homeScore: homeScore, awayScore: awayScore)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let homeTeam: String
    let awayTeam: String
    let homeScore: Int
    let awayScore: Int
}

struct SportsAppWidgetExtensionEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        VStack {
            Text("Günün Maçı")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.bottom, 2)
                
            HStack {
                Text(entry.homeTeam)
                    .font(.headline)
                    .bold()
                Spacer()
                Text("\(entry.homeScore)")
                    .font(.title)
                    .bold()
            }
            
            HStack {
                Text(entry.awayTeam)
                    .font(.headline)
                    .bold()
                Spacer()
                Text("\(entry.awayScore)")
                    .font(.title)
                    .bold()
            }
        }
        .padding()
    }
}

struct SportsAppWidgetExtension: Widget {
    let kind: String = "SportsAppWidgetExtension"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            SportsAppWidgetExtensionEntryView(entry: entry)
        }
        .configurationDisplayName("Günün Maçları")
        .description("Canlı maçları ana ekranından takip et.")
    }
}
