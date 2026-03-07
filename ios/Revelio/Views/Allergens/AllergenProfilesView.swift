import SwiftUI

// ─── Allergen Profiles Root View ──────────────────────────────────────────────

struct AllergenProfilesView: View {
    @ObservedObject private var manager = AllergenProfileManager.shared
    @State private var showAddProfile = false
    @State private var newProfileName = ""
    @State private var selectedProfile: AllergenProfile?

    var body: some View {
        List {
            Section {
                ForEach(manager.profiles) { profile in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(profile.name)
                                    .font(.headline)
                                    .foregroundColor(Theme.textPrimary)
                                if manager.activeProfileId == profile.id {
                                    Text("ACTIVE")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(Theme.accent)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Theme.accent.opacity(0.15))
                                        .cornerRadius(4)
                                }
                            }
                            Text("\(profile.allergens.count) allergen\(profile.allergens.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                        Spacer()
                        Button("Edit") {
                            selectedProfile = profile
                        }
                        .font(.caption.bold())
                        .foregroundColor(Theme.accent)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        manager.setActiveProfile(profile.id)
                    }
                }
                .onDelete { indexSet in
                    indexSet.forEach { i in
                        let profile = manager.profiles[i]
                        if manager.profiles.count > 1 {
                            manager.deleteProfile(profile)
                        }
                    }
                }
            } header: {
                Text("Profiles")
            } footer: {
                Text("Tap a profile to make it active. Allergens from the active profile are checked when scanning products.")
                    .font(.caption)
            }

            Section {
                Button {
                    newProfileName = ""
                    showAddProfile = true
                } label: {
                    Label("Add Profile", systemImage: "person.badge.plus")
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Allergen Profiles")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedProfile) { profile in
            NavigationStack {
                AllergenEditView(profile: profile)
            }
        }
        .alert("New Profile", isPresented: $showAddProfile) {
            TextField("Name (e.g. Mom, Kids)", text: $newProfileName)
            Button("Add") {
                let name = newProfileName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { manager.addProfile(name: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// ─── Allergen Edit View ───────────────────────────────────────────────────────

struct AllergenEditView: View {
    let profile: AllergenProfile
    @ObservedObject private var manager = AllergenProfileManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showAdd = false
    @State private var newAllergenName = ""
    @State private var newAllergenSeverity: AllergenSeverity = .avoid

    private var currentProfile: AllergenProfile {
        manager.profiles.first { $0.id == profile.id } ?? profile
    }

    var body: some View {
        List {
            Section {
                if currentProfile.allergens.isEmpty {
                    Text("No allergens added yet. Tap + to add one.")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(currentProfile.allergens) { allergen in
                        HStack(spacing: 12) {
                            Text(allergen.severity.emoji)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(allergen.name.capitalized)
                                    .font(.subheadline)
                                    .foregroundColor(Theme.textPrimary)
                                Text(allergen.severity.label)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hex: allergen.severity.colorHex))
                            }

                            Spacer()

                            // Severity picker inline
                            Picker("", selection: Binding(
                                get: { allergen.severity },
                                set: { newSev in
                                    var updated = allergen
                                    updated.severity = newSev
                                    manager.updateAllergen(updated, in: profile.id)
                                }
                            )) {
                                ForEach(AllergenSeverity.allCases, id: \.self) { sev in
                                    Text(sev.label).tag(sev)
                                }
                            }
                            .pickerStyle(.menu)
                            .font(.caption)
                            .foregroundColor(Theme.accent)
                        }
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { i in
                            let allergen = currentProfile.allergens[i]
                            manager.removeAllergen(allergen, from: profile.id)
                        }
                    }
                }
            } header: {
                Text("Allergens for \(currentProfile.name)")
            } footer: {
                Text("Swipe left to delete. Tap the severity to change it.")
                    .font(.caption)
            }

            Section {
                Button {
                    newAllergenName = ""
                    newAllergenSeverity = .avoid
                    showAdd = true
                } label: {
                    Label("Add Allergen", systemImage: "plus.circle")
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(currentProfile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .foregroundColor(Theme.accent)
            }
        }
        .sheet(isPresented: $showAdd) {
            AddAllergenSheet(profileId: profile.id, isPresented: $showAdd)
        }
    }
}

// ─── Add Allergen Sheet ───────────────────────────────────────────────────────

struct AddAllergenSheet: View {
    let profileId: String
    @Binding var isPresented: Bool
    @ObservedObject private var manager = AllergenProfileManager.shared

    @State private var name = ""
    @State private var severity: AllergenSeverity = .avoid
    @FocusState private var nameFocused: Bool

    // Common allergen suggestions
    private let suggestions = [
        "peanuts", "tree nuts", "milk", "eggs", "wheat", "gluten",
        "soy", "fish", "shellfish", "sesame", "sulfites", "mustard",
        "celery", "lupin", "molluscs"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Allergen Name") {
                    TextField("e.g. peanuts, gluten, dairy", text: $name)
                        .focused($nameFocused)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section("Quick Add") {
                    let filtered = suggestions.filter { s in
                        name.isEmpty || s.contains(name.lowercased())
                    }
                    if !filtered.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(filtered, id: \.self) { suggestion in
                                    Button(suggestion) {
                                        name = suggestion
                                    }
                                    .font(.caption.bold())
                                    .foregroundColor(Theme.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Theme.accent.opacity(0.1))
                                    .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                Section("Severity") {
                    ForEach(AllergenSeverity.allCases, id: \.self) { sev in
                        Button {
                            severity = sev
                        } label: {
                            HStack(spacing: 12) {
                                Text(sev.emoji).font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sev.label)
                                        .font(.subheadline.bold())
                                        .foregroundColor(Color(hex: sev.colorHex))
                                    Text(severityDescription(sev))
                                        .font(.caption)
                                        .foregroundColor(Theme.textSecondary)
                                }
                                Spacer()
                                if severity == sev {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Theme.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Add Allergen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            manager.addAllergen(to: profileId, name: trimmed, severity: severity)
                            isPresented = false
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .foregroundColor(Theme.accent)
                }
            }
            .onAppear { nameFocused = true }
        }
    }

    private func severityDescription(_ sev: AllergenSeverity) -> String {
        switch sev {
        case .avoid: return "Flag as dangerous — will trigger a red warning"
        case .caution: return "Flag with a caution — amber warning shown"
        case .note: return "Just note the presence — blue info badge"
        }
    }
}
