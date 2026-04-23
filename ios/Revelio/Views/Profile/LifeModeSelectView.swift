import SwiftUI

// MARK: - LifeMode model
//
// Mirrors shared/scoring.ts's `LifeMode` type. A profile can be in at most
// one mode at a time (or "off"). Changing the selection syncs to the server
// via PATCH /profiles/:id — same pattern PersonalizationStore already uses
// for goals/allergies.

enum LifeMode: String, CaseIterable, Identifiable {
    case off
    case pregnancy
    case menstrualCycle = "menstrual_cycle"
    case teen
    case senior

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .pregnancy: return "Pregnancy"
        case .menstrualCycle: return "Cycle"
        case .teen: return "Teen"
        case .senior: return "Senior"
        }
    }

    var emoji: String {
        switch self {
        case .off: return "×"
        case .pregnancy: return "🤰"
        case .menstrualCycle: return "🩷"
        case .teen: return "🧒"
        case .senior: return "👴"
        }
    }

    /// Value sent to the server. `off` clears the mode — we send explicit
    /// null so the PATCH handler's `life_mode` validator accepts it.
    var apiValue: Any {
        switch self {
        case .off: return NSNull()
        default: return rawValue
        }
    }

    var accentColor: Color {
        switch self {
        case .off: return Theme.textDim
        case .pregnancy: return Color(hex: "F472B6")
        case .menstrualCycle: return Color(hex: "EC4899")
        case .teen: return Color(hex: "8B5CF6")
        case .senior: return Color(hex: "0EA5E9")
        }
    }
}

// MARK: - LifeModeSelectView

struct LifeModeSelectView: View {
    let profileId: String

    @State private var selected: LifeMode = .off
    private let defaultsKey = "revelio_life_mode_v1"
    private let apiBase: String

    init(profileId: String) {
        self.profileId = profileId
        self.apiBase = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Amplify flags that matter right now. Switch back to Off any time.")
                .font(Theme.fontCaption)
                .foregroundColor(Theme.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(LifeMode.allCases) { mode in
                        LifeModeChip(mode: mode, isSelected: selected == mode) {
                            select(mode)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .onAppear(perform: loadLocal)
    }

    // MARK: - Persistence

    private func loadLocal() {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey),
           let mode = LifeMode(rawValue: raw) {
            selected = mode
        }
    }

    private func select(_ mode: LifeMode) {
        selected = mode
        UserDefaults.standard.set(mode.rawValue, forKey: defaultsKey)
        syncToServer(mode)
    }

    private func syncToServer(_ mode: LifeMode) {
        guard let url = URL(string: "\(apiBase)/profiles/\(profileId)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["life_mode": mode.apiValue]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req).resume()
    }
}

// MARK: - LifeModeChip

private struct LifeModeChip: View {
    let mode: LifeMode
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(mode.emoji)
                    .font(.system(size: 18))
                Text(mode.label)
                    .font(Theme.fontCaption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? mode.accentColor.opacity(0.15) : Theme.surface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? mode.accentColor : Color.gray.opacity(0.2), lineWidth: 1.5)
            )
        }
        .foregroundColor(isSelected ? mode.accentColor : Theme.textPrimary)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityLabel("\(mode.label) life mode")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
