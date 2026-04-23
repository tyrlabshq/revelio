import SwiftUI

// MARK: - Streak DTO

/// Mirrors the backend `/streaks/me` response. Keys are in camelCase; the
/// history decoder uses `.convertFromSnakeCase`, but streaks ship camelCase
/// already.
struct StreakState: Codable {
    let currentStreakDays: Int
    let longestStreakDays: Int
    let lastScanDate: String?
    let weeklyGoal: Int
    let weeklyProgress: Int
    let remainingToGoal: Int
}

// MARK: - StreakHeaderView

/// Compact horizontal card shown at the top of HistoryView. Refetches whenever
/// the auth user changes. Gracefully hides itself while loading the initial
/// value so the list above doesn't shift.
struct StreakHeaderView: View {
    @State private var streak: StreakState?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let streak {
                card(for: streak)
            } else if isLoading {
                placeholder
            } else {
                EmptyView()
            }
        }
        .task {
            await load()
        }
    }

    // MARK: Card

    private func card(for s: StreakState) -> some View {
        let goal = max(s.weeklyGoal, 1)
        let progressFraction = min(Double(s.weeklyProgress) / Double(goal), 1.0)
        let remaining = max(s.remainingToGoal, 0)

        return HStack(alignment: .center, spacing: 14) {
            // Flame + streak count
            VStack(spacing: 2) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(s.currentStreakDays > 0 ? .orange : Theme.textDim)
                    .accessibilityHidden(true)
                Text("\(s.currentStreakDays)")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
            }
            .frame(width: 52)

            VStack(alignment: .leading, spacing: 6) {
                Text(streakTitle(for: s.currentStreakDays))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.surfaceElevated)
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.accent)
                            .frame(width: geo.size.width * progressFraction, height: 6)
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)

                Text(goalText(remaining: remaining, goal: goal, progress: s.weeklyProgress))
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(14)
        .background(Theme.surface)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(streakTitle(for: s.currentStreakDays)). \(goalText(remaining: remaining, goal: goal, progress: s.weeklyProgress))")
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Theme.surface)
            .frame(height: 76)
            .overlay(ProgressView())
    }

    // MARK: - Copy

    private func streakTitle(for days: Int) -> String {
        switch days {
        case 0: return "Start your streak today"
        case 1: return "1-day streak"
        default: return "\(days)-day streak"
        }
    }

    private func goalText(remaining: Int, goal: Int, progress: Int) -> String {
        if remaining == 0 {
            return "Weekly goal hit! \(progress)/\(goal) scans"
        }
        if remaining == 1 {
            return "You're 1 scan from your weekly goal!"
        }
        return "You're \(remaining) scans from your weekly goal!"
    }

    // MARK: - Loading

    @MainActor
    private func load() async {
        guard streak == nil else { return }
        isLoading = true
        defer { isLoading = false }

        let apiBase = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app"
        guard let url = URL(string: "\(apiBase)/streaks/me"),
              let token = UserDefaults.standard.string(forKey: "auth_token"),
              !token.isEmpty else {
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let decoded = try JSONDecoder().decode(StreakState.self, from: data)
            self.streak = decoded
        } catch {
            // Silent failure — the header simply won't appear.
        }
    }
}

#Preview {
    StreakHeaderView()
        .padding()
        .background(Theme.background)
}
