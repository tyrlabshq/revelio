import WidgetKit
import SwiftUI

/// Widget bundle entry point for the Revelio home-screen widgets.
/// Currently hosts the household-score widget; additional widgets should be added here.
@main
struct RevelioWidgetBundle: WidgetBundle {
    var body: some Widget {
        HouseholdScoreWidget()
    }
}
