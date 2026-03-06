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
            PantryView()
                .tabItem { Label("Pantry", systemImage: "house") }
                .tag(2)
            ExploreView()
                .tabItem { Label("Explore", systemImage: "magnifyingglass") }
                .tag(3)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(4)
        }
        .tint(Theme.accent)
    }
}
