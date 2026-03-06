import SwiftUI
struct PantryView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "Pantry Tracker",
                        systemImage: "house",
                        description: Text("Scan your pantry to get a household health score. Pro feature.")
                    )
                    Label("Upgrade to Pro — $4.99/mo", systemImage: "star.fill")
                        .font(.caption.bold()).foregroundColor(Theme.accent)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.accent.opacity(0.15)).cornerRadius(8)
                }
            }
            .navigationTitle("Pantry")
        }
    }
}
