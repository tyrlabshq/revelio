import SwiftUI
struct ExploreView: View {
    @State private var query = ""
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(Theme.textDim)
                        TextField("Search products, brands...", text: $query)
                            .foregroundColor(Theme.textPrimary)
                    }
                    .padding(12).background(Theme.surfaceElevated).cornerRadius(10).padding(.horizontal)
                    ContentUnavailableView("Search coming soon", systemImage: "magnifyingglass.circle")
                }
            }
            .navigationTitle("Explore")
        }
    }
}
