import WidgetKit
import SwiftUI

/// Widget bundle entry point for the Revelio home-screen widgets and
/// Live Activities. Bundles are the single `@main` per extension —
/// adding a new Widget means adding it to `body` here.
@main
struct RevelioWidgetBundle: WidgetBundle {
    var body: some Widget {
        HouseholdScoreWidget()
        ScanLiveActivity()
    }
}
