import SwiftUI
struct ProfileView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Account") { Label("Sign In", systemImage: "person.circle").foregroundColor(Theme.textPrimary) }
                Section("Goals") {
                    Label("My Priorities", systemImage: "target").foregroundColor(Theme.textPrimary)
                    Label("Family Profiles", systemImage: "person.2").foregroundColor(Theme.textPrimary)
                }
                Section("Pro") {
                    Label("Upgrade to Pro — $4.99/mo", systemImage: "star.fill").foregroundColor(Theme.accent)
                }
                Section("Creator Program") {
                    Label("Become a Creator", systemImage: "megaphone").foregroundColor(Theme.textPrimary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Profile")
        }
    }
}
