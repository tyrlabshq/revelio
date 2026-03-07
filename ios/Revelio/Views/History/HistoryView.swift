import SwiftUI

struct HistoryView: View {
    @State private var scans: [ScanResult] = []
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                
                if scans.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.system(size: 56, weight: .light))
                            .foregroundColor(Theme.textDim)
                        Text("No scans yet")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(Theme.textPrimary)
                        Text("Start scanning to see your history")
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                    }
                } else {
                    List(scans) { scan in
                        HistoryRow(scan: scan)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
        }
    }
}

struct HistoryRow: View {
    let scan: ScanResult
    
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: scan.imageUrl ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.surfaceElevated)
                    .overlay(Image(systemName: "photo").foregroundColor(Theme.textDim))
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(scan.productName)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Text(scan.brand)
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }
            
            Spacer()
            
            GradeBadge(grade: scan.grade, score: scan.displayScore, size: .small)
        }
        .padding(.vertical, 8)
        .background(Theme.surface)
    }
}

#Preview {
    HistoryView()
}
