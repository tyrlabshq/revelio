import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            List {
                // Account header
                Section {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Theme.accent.opacity(0.2))
                                .frame(width: 48, height: 48)
                            Image(systemName: "person.fill")
                                .foregroundColor(Theme.accent)
                                .font(.title2)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(authViewModel.currentUser?.phone ?? "—")
                                    .font(.headline)
                                    .foregroundColor(Theme.textPrimary)

                                if authViewModel.currentUser?.isPro == true {
                                    ProBadge()
                                }
                            }
                            Text(authViewModel.currentUser?.tier == "pro" ? "Pro Member" : "Free Plan")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }

                        Spacer()

                        Button {
                            authViewModel.signOut()
                        } label: {
                            Text("Sign Out")
                                .font(.caption)
                                .foregroundColor(Theme.danger)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Scan usage
                if let user = authViewModel.currentUser, !user.isPro {
                    Section("Daily Scans") {
                        let used = user.dailyScansUsed ?? 0
                        let limit = user.dailyScansLimit ?? 10
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(used) of \(limit) scans used today")
                                    .font(.subheadline)
                                    .foregroundColor(Theme.textPrimary)
                                Spacer()
                                Text("\(limit - used) left")
                                    .font(.caption)
                                    .foregroundColor(used >= limit ? Theme.danger : Theme.textSecondary)
                            }
                            ProgressView(value: Double(used), total: Double(limit))
                                .tint(used >= limit ? Theme.danger : Theme.accent)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Goals") {
                    Label("My Priorities", systemImage: "target").foregroundColor(Theme.textPrimary)
                    Label("Family Profiles", systemImage: "person.2").foregroundColor(Theme.textPrimary)
                }

                if authViewModel.currentUser?.isPro != true {
                    Section("Upgrade") {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(Theme.accent)
                                Text("Upgrade to Pro")
                                    .foregroundColor(Theme.textPrimary)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("$4.99/mo")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(Theme.accent)
                                    Text("or $34.99/yr")
                                        .font(.caption2)
                                        .foregroundColor(Theme.textSecondary)
                                }
                            }
                        }
                    }
                }

                Section("Creator Program") {
                    Label("Become a Creator", systemImage: "megaphone").foregroundColor(Theme.textPrimary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Profile")
            .onAppear {
                Task { await authViewModel.refreshUser() }
            }
            .sheet(isPresented: $showPaywall) {
                NavigationStack {
                    PaywallView()
                }
            }
        }
    }
}
