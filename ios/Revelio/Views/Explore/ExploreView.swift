import SwiftUI

struct ExploreView: View {
    @State private var query = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                
                if query.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 56, weight: .light))
                            .foregroundColor(Theme.textDim)
                        Text("Search for products")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(Theme.textPrimary)
                        Text("Find products to explore")
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                    }
                } else {
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundColor(Theme.textDim)
                            TextField("Search products, brands...", text: $query)
                                .foregroundColor(Theme.textPrimary)
                        }
                        .padding(12)
                        .background(Theme.surface)
                        .cornerRadius(10)
                        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
                        .padding(.horizontal)
                        
                        Spacer()
                        
                        Image(systemName: "magnifyingglass.circle")
                            .font(.system(size: 48))
                            .foregroundColor(Theme.textDim)
                        Text("Search coming soon")
                            .font(.headline)
                            .foregroundColor(Theme.textSecondary)
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Explore")
        }
    }
}

#Preview {
    ExploreView()
}
