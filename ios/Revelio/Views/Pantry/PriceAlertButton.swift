// REV-20: Price-alert toggle for pantry swap-cart rows.
//
// Compact bell button. First tap prompts the user for a percent-drop threshold
// and POSTs /price-alerts; subsequent tap DELETEs (soft-deactivates) the alert.
// The button assumes the caller passes the user's bearer token — if nil, the
// button still renders but any action returns a silent error since the API
// requires auth.

import SwiftUI

struct PriceAlertButton: View {
    let barcode: String
    let authToken: String?

    @State private var isEnabled: Bool = false
    @State private var alertId: String?
    @State private var isWorking: Bool = false
    @State private var showThresholdPrompt: Bool = false
    @State private var thresholdPctText: String = "15"
    @State private var errorMessage: String?

    private let baseURL: String =
        ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app"

    var body: some View {
        Button {
            guard !isWorking else { return }
            if isEnabled {
                Task { await disable() }
            } else {
                showThresholdPrompt = true
            }
        } label: {
            Image(systemName: isEnabled ? "bell.fill" : "bell")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isEnabled ? Theme.accent : Theme.textSecondary)
                .padding(6)
                .background(
                    Circle()
                        .fill(isEnabled ? Theme.accent.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(isWorking || authToken == nil)
        .accessibilityLabel(isEnabled ? "Disable price drop alert" : "Enable price drop alert")
        .accessibilityHint(isEnabled
            ? "Stops sending notifications when this product's price drops"
            : "Asks for a percent-off threshold, then notifies you when the price drops that far")
        .alert("Alert me when the price drops", isPresented: $showThresholdPrompt) {
            TextField("Percent off", text: $thresholdPctText)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) { }
            Button("Track") {
                Task { await enable() }
            }
        } message: {
            Text("You'll get a push when this product drops by this percent.")
        }
        .alert("Couldn't update alert", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await loadState()
        }
    }

    // MARK: - Networking

    private func loadState() async {
        guard let token = authToken,
              let url = URL(string: "\(baseURL)/price-alerts") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
            struct ListResp: Decodable {
                struct Row: Decodable {
                    let id: String
                    let barcode: String
                    let active: Bool
                }
                let data: [Row]
            }
            let decoded = try JSONDecoder().decode(ListResp.self, from: data)
            if let match = decoded.data.first(where: { $0.barcode == barcode && $0.active }) {
                isEnabled = true
                alertId = match.id
            }
        } catch {
            // Silent — button stays off if we can't load.
        }
    }

    private func enable() async {
        guard let token = authToken else { return }
        guard let pct = Int(thresholdPctText), pct >= 1, pct <= 99 else {
            errorMessage = "Percent must be between 1 and 99."
            return
        }
        guard let url = URL(string: "\(baseURL)/price-alerts") else { return }

        isWorking = true
        defer { isWorking = false }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "barcode": barcode,
            "thresholdPct": pct,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status) else {
                errorMessage = "Couldn't save alert (\(status))."
                return
            }
            struct CreateResp: Decodable { let id: String }
            let decoded = try JSONDecoder().decode(CreateResp.self, from: data)
            alertId = decoded.id
            isEnabled = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func disable() async {
        guard let token = authToken, let id = alertId,
              let url = URL(string: "\(baseURL)/price-alerts/\(id)") else { return }

        isWorking = true
        defer { isWorking = false }

        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status) else {
                errorMessage = "Couldn't remove alert (\(status))."
                return
            }
            isEnabled = false
            alertId = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    PriceAlertButton(barcode: "0000000000017", authToken: "preview-token")
        .padding()
        .background(Theme.surface)
}
