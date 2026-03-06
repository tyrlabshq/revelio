import SwiftUI
struct HistoryView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ContentUnavailableView(
                    "No scans yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Products you scan will appear here")
                )
            }
            .navigationTitle("History")
        }
    }
}
