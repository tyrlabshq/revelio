// REV-T3.3: 7-day meal plan view.
// Displays each day's breakfast/lunch/dinner plus per-day shopping list and a
// "Send shopping list to Instacart" button that — per plan — opens the
// current Amazon affiliate search URL as a simple stand-in.

import SwiftUI

// MARK: - Models

struct MealPlanDay: Identifiable, Decodable {
    let day: Int
    let breakfast: String
    let lunch: String
    let dinner: String
    let shoppingList: [String]
    var id: Int { day }
}

struct MealPlan: Decodable {
    let summary: String?
    let days: [MealPlanDay]
}

// MARK: - ViewModel

@MainActor
final class MealPlanViewModel: ObservableObject {
    @Published var plan: MealPlan?
    @Published var isLoading = false
    @Published var error: String?
    @Published var paywallRequired = false

    private let baseURL: String

    init(baseURL: String = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app") {
        self.baseURL = baseURL
    }

    func load(token: String?) async {
        isLoading = true
        error = nil
        paywallRequired = false
        defer { isLoading = false }

        guard let url = URL(string: "\(baseURL)/meal-plan") else {
            error = "Invalid URL"
            return
        }
        var req = URLRequest(url: url)
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status == 402 {
                paywallRequired = true
                return
            }
            guard status == 200 else {
                error = "Unable to load meal plan"
                return
            }
            plan = try JSONDecoder().decode(MealPlan.self, from: data)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - View

struct MealPlanView: View {
    @StateObject private var vm = MealPlanViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.openURL) private var openURL
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if vm.isLoading {
                    ProgressView("Generating your week…")
                } else if vm.paywallRequired {
                    paywallState
                } else if let plan = vm.plan {
                    content(plan)
                } else if let err = vm.error {
                    errorState(err)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Meal Plan")
            .task {
                await vm.load(token: authViewModel.loadToken())
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView().environmentObject(authViewModel)
            }
        }
    }

    private func content(_ plan: MealPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let summary = plan.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                ForEach(plan.days) { day in
                    DayCard(day: day)
                        .padding(.horizontal, 16)
                }

                Button {
                    let list = plan.days
                        .flatMap { $0.shoppingList }
                        .prefix(20)
                        .joined(separator: " ")
                    let encoded = list.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    // Per plan: open the current Amazon affiliate URL for simplicity.
                    if let url = URL(string: "https://www.amazon.com/s?k=\(encoded)&tag=revelio-20") {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "cart.fill")
                        Text("Send shopping list to Instacart")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .cornerRadius(14)
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 12)
            }
        }
    }

    private var paywallState: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.accent)
            Text("Meal Plans are a Pro feature")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)
            Text("Upgrade to get a personalized 7-day plan built from your pantry.")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showPaywall = true
            } label: {
                Text("Upgrade")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .cornerRadius(12)
            }
        }
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(Theme.warning)
            Text(msg).font(.subheadline).foregroundColor(Theme.textSecondary)
            Button("Retry") {
                Task { await vm.load(token: authViewModel.loadToken()) }
            }
            .foregroundColor(Theme.accent)
        }
    }
}

// MARK: - Day card

private struct DayCard: View {
    let day: MealPlanDay

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Day \(day.day)")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Theme.accent)

            mealRow(icon: "sun.max.fill", label: "Breakfast", meal: day.breakfast)
            mealRow(icon: "fork.knife", label: "Lunch", meal: day.lunch)
            mealRow(icon: "moon.stars.fill", label: "Dinner", meal: day.dinner)

            if !day.shoppingList.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shopping list")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.textDim)
                    Text(day.shoppingList.joined(separator: ", "))
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private func mealRow(icon: String, label: String, meal: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(Theme.textSecondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.textDim)
                Text(meal)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
            }
        }
    }
}

#Preview {
    MealPlanView()
        .environmentObject(AuthViewModel())
}
