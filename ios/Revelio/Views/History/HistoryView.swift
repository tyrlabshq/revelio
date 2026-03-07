import SwiftUI

struct HistoryView: View {
    @ObservedObject private var historyManager = HistoryManager.shared
    @State private var selectedTab = 0
    @State private var selectedScan: ScanResult? = nil
    @EnvironmentObject private var authViewModel: AuthViewModel

    private var displayedScans: [ScanResult] {
        selectedTab == 0 ? historyManager.history : historyManager.favoriteScans
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Segmented control
                    Picker("View", selection: $selectedTab) {
                        Text("History").tag(0)
                        Text("Favorites").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if displayedScans.isEmpty {
                        Spacer()
                        emptyState
                        Spacer()
                    } else {
                        List {
                            ForEach(displayedScans) { scan in
                                Button {
                                    selectedScan = scan
                                } label: {
                                    HistoryRow(scan: scan, isFavorite: historyManager.isFavorite(scan.barcode))
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Theme.surface)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                        }
                        .listStyle(.plain)
                        .background(Theme.background)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedScan) { scan in
                ProductDetailView(scan: scan)
                    .environmentObject(authViewModel)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: selectedTab == 0 ? "clock.badge.questionmark" : "heart.slash")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(Theme.textDim)
            Text(selectedTab == 0 ? "No scans yet" : "No favorites yet")
                .font(.headline.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
            Text(selectedTab == 0 ? "Start scanning to see your history" : "Heart a product to save it here")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
        }
    }
}

struct HistoryRow: View {
    let scan: ScanResult
    var isFavorite: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Product image
            AsyncImage(url: URL(string: scan.imageUrl ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.surfaceElevated)
                    .overlay(Image(systemName: "photo").foregroundColor(Theme.textDim))
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(scan.productName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.pink)
                    }
                }
                Text(scan.brand)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                Text(scan.category.icon + " " + scan.category.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.accent)
                Text(scan.scannedAt, style: .relative)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textDim)
                    + Text(" ago")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textDim)
            }

            Spacer()

            GradeBadge(grade: scan.grade, score: scan.displayScore, size: .small)
        }
        .padding(12)
        .background(Theme.surface)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 1)
    }
}

#Preview {
    HistoryView()
        .environmentObject(AuthViewModel())
}
