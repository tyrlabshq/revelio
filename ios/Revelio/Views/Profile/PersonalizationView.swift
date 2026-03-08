import SwiftUI

// MARK: - PersonalizationView

struct PersonalizationView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var store = PersonalizationStore.shared
    @State private var showAddMember = false
    @State private var allergyInput = ""
    @FocusState private var allergyFieldFocused: Bool

    private var profileId: String {
        authViewModel.currentUser?.id ?? "guest"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                goalSection
                allergySection
                rescorePreview
                familySection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Personalization")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            store.fetchMembers(profileId: profileId)
        }
        .sheet(isPresented: $showAddMember) {
            AddFamilyMemberSheet(profileId: profileId, store: store)
        }
    }

    // MARK: - Goal Section

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                icon: "target",
                title: "Your Health Goals",
                subtitle: "Your score re-weights to match what you care about"
            )

            // Chip grid
            GoalChipGrid(selectedGoals: store.state.goals) { goalId in
                store.toggleGoal(goalId, profileId: profileId)
            }
        }
    }

    // MARK: - Allergy Section

    private var allergySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                icon: "allergens",
                title: "Allergens & Avoidances",
                subtitle: "We'll flag these in every scan"
            )

            VStack(spacing: 8) {
                // Existing allergy chips
                if !store.state.allergies.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(store.state.allergies, id: \.self) { allergen in
                            AllergenChip(text: allergen) {
                                var updated = store.state.allergies
                                updated.removeAll { $0 == allergen }
                                store.updateAllergies(updated, profileId: profileId)
                            }
                        }
                    }
                }

                // Add allergen input
                HStack(spacing: 8) {
                    TextField("Add allergen (e.g. peanuts)", text: $allergyInput)
                        .focused($allergyFieldFocused)
                        .font(Theme.fontBody)
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Theme.surface)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(allergyFieldFocused ? Theme.accent : Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .onSubmit { addAllergen() }

                    Button(action: addAllergen) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(allergyInput.isEmpty ? Theme.textDim : Theme.accent)
                            .font(.title2)
                    }
                    .disabled(allergyInput.isEmpty)
                }
            }
            .padding(14)
            .background(Theme.surface)
            .cornerRadius(14)
        }
    }

    private func addAllergen() {
        let trimmed = allergyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !store.state.allergies.contains(trimmed.lowercased()) else { return }
        var updated = store.state.allergies
        updated.append(trimmed.lowercased())
        store.updateAllergies(updated, profileId: profileId)
        allergyInput = ""
    }

    // MARK: - Rescore Preview

    @ViewBuilder
    private var rescorePreview: some View {
        if !store.state.goals.isEmpty {
            RescorePreviewCard(selectedGoals: store.state.goals)
        }
    }

    // MARK: - Family Section

    private var familySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(
                    icon: "person.2.fill",
                    title: "Family Profiles",
                    subtitle: "Each member gets their own personalized score"
                )
                Spacer()
                Button {
                    showAddMember = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Theme.accent)
                        .font(.title2)
                }
            }

            VStack(spacing: 10) {
                // Owner row
                FamilyMemberRow(
                    initials: ownerInitials,
                    name: "You (Owner)",
                    goalCount: store.state.goals.count,
                    allergyCount: store.state.allergies.count,
                    isChild: false,
                    color: Theme.accent
                )

                ForEach(store.state.familyMembers) { member in
                    FamilyMemberRow(
                        initials: member.initials,
                        name: member.name + (member.isChild ? " 👶" : ""),
                        goalCount: member.goals.count,
                        allergyCount: member.allergies.count,
                        isChild: member.isChild,
                        color: member.color
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.deleteMember(memberId: member.id, profileId: profileId)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var ownerInitials: String {
        // AuthUser has no name field — fall back to phone last 2 digits or default
        if let phone = authViewModel.currentUser?.phone, phone.count >= 2 {
            return String(phone.suffix(2))
        }
        return "ME"
    }
}

// MARK: - Goal Chip Grid

struct GoalChipGrid: View {
    let selectedGoals: [String]
    let onToggle: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(HealthGoal.all) { goal in
                GoalChip(goal: goal, isSelected: selectedGoals.contains(goal.id)) {
                    onToggle(goal.id)
                }
            }
        }
    }
}

struct GoalChip: View {
    let goal: HealthGoal
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(goal.emoji)
                    .font(.system(size: 16))
                Text(goal.title)
                    .font(Theme.fontCaption)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.accent)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Theme.accent.opacity(0.12) : Theme.surface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Theme.accent : Color.gray.opacity(0.2), lineWidth: 1.5)
            )
        }
        .foregroundColor(isSelected ? Theme.accent : Theme.textPrimary)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Allergen Chip

struct AllergenChip: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text.capitalized)
                .font(Theme.fontCaption)
                .foregroundColor(Theme.textPrimary)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(Theme.textSecondary)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surfaceElevated)
        .cornerRadius(20)
        .overlay(
            Capsule().stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Rescore Preview Card

struct RescorePreviewCard: View {
    let selectedGoals: [String]

    // Hard-coded Hellmann's Mayo demo values
    private let baseGrade = "C"
    private let baseScore = 55

    private var personalizedScore: Int {
        // Each relevant goal lowers the mayo score further
        let relevantGoals = ["seed_oils", "keto"]
        let penaltyPerGoal = 10
        let matches = selectedGoals.filter { relevantGoals.contains($0) }.count
        return max(0, baseScore - (matches * penaltyPerGoal) - (selectedGoals.count > 3 ? 10 : 0))
    }

    private var personalizedGrade: String {
        switch personalizedScore {
        case 80...: return "A"
        case 60..<80: return "B"
        case 40..<60: return "C"
        case 20..<40: return "D"
        default: return "F"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(Theme.accent)
                    .font(.subheadline)
                Text("Personalized Score Preview")
                    .font(Theme.fontCaption)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.accent)
            }

            HStack(spacing: 0) {
                // Product name
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hellmann's Mayo")
                        .font(Theme.fontBody)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.textPrimary)
                    Text("With your goals applied")
                        .font(Theme.fontCaption)
                        .foregroundColor(Theme.textSecondary)
                }

                Spacer()

                // Before
                VStack(spacing: 2) {
                    Text(baseGrade)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.gradeColor(baseGrade))
                    Text("\(baseScore)")
                        .font(Theme.fontCaption)
                        .foregroundColor(Theme.textSecondary)
                }
                .frame(width: 44)

                // Arrow
                Image(systemName: "arrow.right")
                    .foregroundColor(Theme.textDim)
                    .font(.subheadline)
                    .padding(.horizontal, 8)

                // After
                VStack(spacing: 2) {
                    Text(personalizedGrade)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.gradeColor(personalizedGrade))
                    Text("\(personalizedScore)")
                        .font(Theme.fontCaption)
                        .foregroundColor(Theme.textSecondary)
                }
                .frame(width: 44)
            }

            Text("Seed oils and other flagged ingredients carry more weight because of your goals.")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .italic()
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Theme.accent.opacity(0.08), Theme.accent.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.accent.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Family Member Row

struct FamilyMemberRow: View {
    let initials: String
    let name: String
    let goalCount: Int
    let allergyCount: Int
    let isChild: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 44, height: 44)
                Text(initials)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(Theme.fontBody)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.textPrimary)
                HStack(spacing: 10) {
                    Label("\(goalCount) goal\(goalCount == 1 ? "" : "s")", systemImage: "target")
                        .font(Theme.fontCaption)
                        .foregroundColor(Theme.textSecondary)
                    if allergyCount > 0 {
                        Label("\(allergyCount) allergen\(allergyCount == 1 ? "" : "s")", systemImage: "allergens")
                            .font(Theme.fontCaption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }

            Spacer()

            if isChild {
                Text("Child")
                    .font(Theme.fontCaption)
                    .foregroundColor(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.12))
                    .cornerRadius(8)
            }
        }
        .padding(12)
        .background(Theme.surface)
        .cornerRadius(14)
    }
}

// MARK: - Add Family Member Sheet

struct AddFamilyMemberSheet: View {
    let profileId: String
    let store: PersonalizationStore

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isChild = false
    @State private var selectedGoals: Set<String> = []
    @State private var allergyInput = ""
    @State private var allergies: [String] = []
    @State private var selectedColorIndex = 0
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Avatar preview
                    ZStack {
                        Circle()
                            .fill(selectedColor.opacity(0.18))
                            .frame(width: 72, height: 72)
                        Text(initials)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(selectedColor)
                    }

                    // Color picker
                    HStack(spacing: 10) {
                        ForEach(Array(FamilyMember.memberColors.enumerated()), id: \.offset) { idx, colorHex in
                            Circle()
                                .fill(Color(hex: colorHex.replacingOccurrences(of: "#", with: "")))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle().stroke(Color.white, lineWidth: selectedColorIndex == idx ? 3 : 0)
                                )
                                .scaleEffect(selectedColorIndex == idx ? 1.2 : 1.0)
                                .onTapGesture { withAnimation { selectedColorIndex = idx } }
                        }
                    }

                    Divider()

                    // Name field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(Theme.fontCaption)
                            .foregroundColor(Theme.textSecondary)
                        TextField("Family member name", text: $name)
                            .focused($nameFieldFocused)
                            .font(Theme.fontBody)
                            .foregroundColor(Theme.textPrimary)
                            .padding(12)
                            .background(Theme.surface)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    }

                    // Child toggle
                    Toggle(isOn: $isChild) {
                        Label("Is a child", systemImage: "figure.child")
                            .foregroundColor(Theme.textPrimary)
                    }
                    .tint(Theme.accent)
                    .padding(12)
                    .background(Theme.surface)
                    .cornerRadius(10)

                    // Goals
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Health Goals")
                            .font(Theme.fontCaption)
                            .foregroundColor(Theme.textSecondary)
                        GoalChipGrid(selectedGoals: Array(selectedGoals)) { goalId in
                            if selectedGoals.contains(goalId) {
                                selectedGoals.remove(goalId)
                            } else {
                                selectedGoals.insert(goalId)
                            }
                        }
                    }

                    // Allergies
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Allergens")
                            .font(Theme.fontCaption)
                            .foregroundColor(Theme.textSecondary)
                        if !allergies.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(allergies, id: \.self) { a in
                                    AllergenChip(text: a) {
                                        allergies.removeAll { $0 == a }
                                    }
                                }
                            }
                        }
                        HStack(spacing: 8) {
                            TextField("Add allergen", text: $allergyInput)
                                .font(Theme.fontBody)
                                .padding(10)
                                .background(Theme.surface)
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                                .onSubmit { addAllergen() }
                            Button(action: addAllergen) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(allergyInput.isEmpty ? Theme.textDim : Theme.accent)
                                    .font(.title2)
                            }
                            .disabled(allergyInput.isEmpty)
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Add Family Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addMember() }
                        .fontWeight(.semibold)
                        .foregroundColor(name.isEmpty ? Theme.textDim : Theme.accent)
                        .disabled(name.isEmpty)
                }
            }
        }
        .onAppear { nameFieldFocused = true }
    }

    private var selectedColor: Color {
        Color(hex: FamilyMember.memberColors[selectedColorIndex].replacingOccurrences(of: "#", with: ""))
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return name.isEmpty ? "?" : String(name.prefix(2)).uppercased()
    }

    private func addAllergen() {
        let t = allergyInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty, !allergies.contains(t) else { return }
        allergies.append(t)
        allergyInput = ""
    }

    private func addMember() {
        let member = FamilyMember(
            id: UUID().uuidString,
            name: name,
            isChild: isChild,
            goals: Array(selectedGoals),
            allergies: allergies,
            avatarColor: FamilyMember.memberColors[selectedColorIndex]
        )
        store.addMember(member, profileId: profileId)
        dismiss()
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(Theme.accent)
                .font(.subheadline)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.fontHeadline)
                    .foregroundColor(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.fontCaption)
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }
}


