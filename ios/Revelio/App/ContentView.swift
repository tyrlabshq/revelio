import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ScanView()
                .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }
                .tag(0)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
                .tag(1)
            NutritionTrendsView()
                .tabItem { Label("Trends", systemImage: "chart.bar.fill") }
                .tag(2)
            PantryView()
                .tabItem { Label("Pantry", systemImage: "refrigerator") }
                .tag(3)
            ExploreView()
                .tabItem { Label("Explore", systemImage: "magnifyingglass") }
                .tag(4)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(5)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(6)
        }
        .tint(Theme.accent)
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            // Subtle top border for tab bar
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 0.5)
                .offset(y: -49) // Position just above tab bar
        }
    }
}

#Preview {
    ContentView()
}
