import WidgetKit
import SwiftUI

@main
struct SportsAppWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        SportsAppWidgetExtension()
        SportsAppWidgetExtensionLiveActivity()
    }
}
