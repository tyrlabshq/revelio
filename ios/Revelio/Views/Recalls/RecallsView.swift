import SwiftUI

// MARK: - DTOs

struct RecallNotification: Codable, Identifiable {
    let notificationId: String
    let barcode: String
    let notifiedAt: Date
    let openedAt: Date?
    let recallId: String
    let recallNumber: String
    let classification: String
    let productDescription: String
    let reasonForRecall: String
    let recallingFirm: String?
    let productType: String
    let recallInitiationDate: String?

    var id: String { notificationId }
    var isUnread: Bool { openedAt == nil }
}

struct RecallsResponse: Codable {
    let data: [RecallNotification]
    let unreadCount: Int
}

// MARK: - RecallsView

struct RecallsView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var items: [RecallNotification] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selected: RecallNotification?

    private var apiBase: String {
        ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app"
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if isLoading && items.isEmpty {
                ProgressView().tint(Theme.accent)
            } else if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
                            Button { selected = item } label: {
                                RecallCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .refreshable { await fetch() }
            }

            if let msg = errorMessage {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Theme.danger)
                        .cornerRadius(10)
                        .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Recalls")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selected) { item in
            RecallDetailSheet(item: item) {
                await markOpened(item)
            }
        }
        .task { await fetch() }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(Theme.success)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            Text("No recalls")
                .font(.headline.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
            Text("We'll alert you if any product you've scanned or added to your pantry is recalled by the FDA.")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Networking

    @MainActor
    func fetch() async {
        guard let token = authViewModel.loadToken(),
              let url = URL(string: "\(apiBase)/recalls/mine") else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 {
                errorMessage = "Sign in to see your recalls."
                return
            }
            if code != 200 {
                errorMessage = "Couldn't load recalls (HTTP \(code))."
                return
            }
            let decoded = try JSONDecoder.revelio.decode(RecallsResponse.self, from: data)
            items = decoded.data
        } catch {
            errorMessage = "Couldn't load recalls: \(error.localizedDescription)"
        }
    }

    @MainActor
    func markOpened(_ item: RecallNotification) async {
        guard let token = authViewModel.loadToken(),
              let url = URL(string: "\(apiBase)/recalls/\(item.recallId)/opened") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 {
                // Patch in memory so the badge count decrements immediately.
                if let idx = items.firstIndex(where: { $0.notificationId == item.notificationId }) {
                    let orig = items[idx]
                    items[idx] = RecallNotification(
                        notificationId: orig.notificationId,
                        barcode: orig.barcode,
                        notifiedAt: orig.notifiedAt,
                        openedAt: Date(),
                        recallId: orig.recallId,
                        recallNumber: orig.recallNumber,
                        classification: orig.classification,
                        productDescription: orig.productDescription,
                        reasonForRecall: orig.reasonForRecall,
                        recallingFirm: orig.recallingFirm,
                        productType: orig.productType,
                        recallInitiationDate: orig.recallInitiationDate
                    )
                }
            }
        } catch {
            // non-fatal; user can retry
        }
    }
}

// MARK: - RecallCard

struct RecallCard: View {
    let item: RecallNotification

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Theme.danger)
                Text(item.classification.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.danger)
                Spacer()
                if item.isUnread {
                    Circle()
                        .fill(Theme.danger)
                        .frame(width: 8, height: 8)
                }
            }

            Text(item.productDescription)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(2)

            if let firm = item.recallingFirm {
                Text(firm)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }

            Text(item.reasonForRecall)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .lineLimit(3)

            HStack(spacing: 8) {
                Text("UPC \(item.barcode)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.textDim)
                Spacer()
                Text(item.notifiedAt, style: .relative)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textDim)
            }
        }
        .padding(14)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.danger, lineWidth: item.isUnread ? 2 : 1)
        )
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
    }
}

// MARK: - Detail sheet

struct RecallDetailSheet: View {
    let item: RecallNotification
    let onMarkAsRead: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isMarking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Theme.danger)
                        Text(item.classification)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Theme.danger)
                    }

                    Text(item.productDescription)
                        .font(.title3.weight(.bold))
                        .foregroundColor(Theme.textPrimary)

                    infoRow(label: "Reason", value: item.reasonForRecall)
                    if let firm = item.recallingFirm {
                        infoRow(label: "Recalling firm", value: firm)
                    }
                    infoRow(label: "Recall number", value: item.recallNumber)
                    infoRow(label: "Product type", value: item.productType.capitalized)
                    infoRow(label: "Matched UPC", value: item.barcode)
                    if let date = item.recallInitiationDate {
                        infoRow(label: "Initiated", value: date)
                    }

                    Button {
                        Task {
                            isMarking = true
                            await onMarkAsRead()
                            isMarking = false
                            dismiss()
                        }
                    } label: {
                        HStack {
                            if isMarking { ProgressView().tint(.white) }
                            Text(item.isUnread ? "Mark as read" : "Read")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(item.isUnread ? Theme.accent : Theme.textDim)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!item.isUnread || isMarking)
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Recall Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Theme.textDim)
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(Theme.textPrimary)
        }
    }
}

#Preview {
    NavigationStack {
        RecallsView()
            .environmentObject(AuthViewModel())
    }
}
