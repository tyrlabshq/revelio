import SwiftUI

// MARK: - Models

struct PantryMember: Identifiable {
    let id: String
    let name: String
    var items: [PantryItem]
}

extension PantryItem {
    var category: ProductCategory {
        // Infer from grade/name for mock; real data comes from backend
        return .food
    }
}

// MARK: - Sort & Filter

enum PantrySort: String, CaseIterable {
    case grade = "Worst First"
    case category = "Category"
    case date = "Date Added"
}

enum PantryFilter: String, CaseIterable {
    case all = "All"
    case fdOnly = "F & D"
    case food = "Food"
    case cosmetics = "Cosmetics"
}

// MARK: - ViewModel

@MainActor
class PantryViewModel: ObservableObject {
    @Published var members: [PantryMember] = PantryViewModel.mockMembers()
    @Published var selectedMemberIndex: Int = 0
    @Published var sort: PantrySort = .grade
    @Published var filter: PantryFilter = .all
    @Published var showScanner = false
    @Published var isLoading = false

    var currentMember: PantryMember { members[selectedMemberIndex] }

    var filteredItems: [PantryItem] {
        var items = currentMember.items
        switch filter {
        case .all: break
        case .fdOnly: items = items.filter { $0.grade == "F" || $0.grade == "D" }
        case .food: items = items.filter { $0.category == .food }
        case .cosmetics: items = items.filter { $0.category == .cosmetics }
        }
        switch sort {
        case .grade:
            let order = ["F","D","C","B","A"]
            items = items.sorted { (order.firstIndex(of: $0.grade) ?? 5) < (order.firstIndex(of: $1.grade) ?? 5) }
        case .category:
            items = items.sorted { $0.category.rawValue < $1.category.rawValue }
        case .date:
            items = items.sorted { $0.addedAt > $1.addedAt }
        }
        return items
    }

    var householdScore: Int {
        let items = currentMember.items
        guard !items.isEmpty else { return 0 }
        var totalWeight = 0.0
        var weightedSum = 0.0
        for item in items {
            let w: Double = item.grade == "F" ? 3 : item.grade == "D" ? 2 : 1
            weightedSum += Double(item.score) * w
            totalWeight += w
        }
        return Int(weightedSum / totalWeight)
    }

    var householdGrade: String {
        let s = householdScore
        switch s {
        case 85...: return "A"
        case 70..<85: return "B"
        case 55..<70: return "C"
        case 40..<55: return "D"
        default: return "F"
        }
    }

    var cleanPercent: Double {
        let items = currentMember.items
        guard !items.isEmpty else { return 0 }
        return Double(items.filter { $0.grade == "A" || $0.grade == "B" }.count) / Double(items.count)
    }

    var concerningPercent: Double {
        let items = currentMember.items
        guard !items.isEmpty else { return 0 }
        return Double(items.filter { $0.grade == "C" }.count) / Double(items.count)
    }

    var avoidPercent: Double {
        let items = currentMember.items
        guard !items.isEmpty else { return 0 }
        return Double(items.filter { $0.grade == "D" || $0.grade == "F" }.count) / Double(items.count)
    }

    var worstOffenders: [PantryItem] {
        let order = ["F","D","C","B","A"]
        return Array(currentMember.items
            .sorted { (order.firstIndex(of: $0.grade) ?? 5) < (order.firstIndex(of: $1.grade) ?? 5) }
            .prefix(3))
    }

    var quickWins: [PantryItem] {
        currentMember.items.filter { $0.score < 50 }.prefix(3).map { $0 }
    }

    func removeItem(at offsets: IndexSet) {
        let ids = offsets.map { filteredItems[$0].id }
        members[selectedMemberIndex].items.removeAll { ids.contains($0.id) }
    }

    func addItem(_ item: PantryItem) {
        members[selectedMemberIndex].items.append(item)
    }

    static func mockMembers() -> [PantryMember] {
        // Return empty for production - no fake data
        return []
    }
}

// MARK: - Main View

struct PantryView: View {
    @StateObject private var vm = PantryViewModel()

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        // Family member tabs
                        FamilyTabBar(members: vm.members, selected: $vm.selectedMemberIndex)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        // Household score header
                        HouseholdScoreCard(vm: vm)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        // Sort/Filter bar
                        SortFilterBar(sort: $vm.sort, filter: $vm.filter)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        // Grid of pantry items
                        if vm.filteredItems.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "house")
                                    .font(.system(size: 56, weight: .light))
                                    .foregroundColor(Theme.textDim)
                                Text("Your pantry is empty")
                                    .font(.headline.weight(.semibold))
                                    .foregroundColor(Theme.textPrimary)
                                Text("Add products by scanning them")
                                    .font(.subheadline)
                                    .foregroundColor(Theme.textSecondary)
                            }
                            .padding(.top, 80)
                        } else {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(Array(vm.filteredItems.enumerated()), id: \.element.id) { index, item in
                                    PantryItemCard(item: item)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                vm.members[vm.selectedMemberIndex].items.removeAll { $0.id == item.id }
                                            } label: {
                                                Label("Remove", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                        }

                        Spacer().frame(height: 100)
                    }
                }

                // FAB camera button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            vm.showScanner = true
                        } label: {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Theme.accent)
                                .clipShape(Circle())
                                .shadow(color: Theme.accent.opacity(0.4), radius: 12, x: 0, y: 4)
                        }
                        .padding(.trailing, 24)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Pantry")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $vm.showScanner) {
            PantryScannerSheet(onAdd: { item in
                vm.addItem(item)
                vm.showScanner = false
            })
        }
    }
}

// MARK: - Family Tab Bar

struct FamilyTabBar: View {
    let members: [PantryMember]
    @Binding var selected: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(members.indices, id: \.self) { i in
                    Button {
                        selected = i
                    } label: {
                        Text(members[i].name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(selected == i ? .white : Theme.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selected == i ? Theme.accent : Theme.surfaceElevated)
                            .cornerRadius(20)
                    }
                }
            }
        }
    }
}

// MARK: - Household Score Card

struct HouseholdScoreCard: View {
    @ObservedObject var vm: PantryViewModel

    var body: some View {
        VStack(spacing: 16) {
            // Score + ring
            HStack(alignment: .center, spacing: 24) {
                ZStack {
                    CircularScoreRing(
                        score: vm.householdScore,
                        cleanPct: vm.cleanPercent,
                        concerningPct: vm.concerningPercent,
                        avoidPct: vm.avoidPercent
                    )
                    VStack(spacing: 2) {
                        Text("\(vm.householdScore)")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(Theme.textPrimary)
                        Text(vm.householdGrade)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Theme.gradeColor(vm.householdGrade))
                    }
                }
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Household Score")
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                    RingLegendRow(color: Theme.success, label: "Clean", pct: vm.cleanPercent)
                    RingLegendRow(color: Theme.warning, label: "Concerning", pct: vm.concerningPercent)
                    RingLegendRow(color: Theme.danger, label: "Avoid", pct: vm.avoidPercent)
                }
            }

            Divider()
                .background(Color.gray.opacity(0.12))

            // Worst offenders
            if !vm.worstOffenders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Worst Offenders", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.danger)
                    ForEach(vm.worstOffenders) { item in
                        HStack {
                            Text(item.grade)
                                .font(.caption.weight(.black))
                                .foregroundColor(Theme.gradeColor(item.grade))
                                .frame(width: 20)
                            Text(item.productName)
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(item.score)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Theme.textDim)
                        }
                    }
                }
            }

            // Quick wins
            if !vm.quickWins.isEmpty {
                Divider()
                    .background(Color.gray.opacity(0.12))
                VStack(alignment: .leading, spacing: 8) {
                    Label("Quick Wins", systemImage: "bolt.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.warning)
                    ForEach(vm.quickWins) { item in
                        HStack {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundColor(Theme.success)
                                .font(.caption)
                            Text(item.productName)
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text("Swap it →")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(Theme.accent)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.surface)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
    }
}

struct RingLegendRow: View {
    let color: Color
    let label: String
    let pct: Double

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Text("\(Int(pct * 100))%")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.textDim)
        }
    }
}

struct CircularScoreRing: View {
    let score: Int
    let cleanPct: Double
    let concerningPct: Double
    let avoidPct: Double

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Theme.surfaceElevated, lineWidth: 10)

            // Clean arc
            Circle()
                .trim(from: 0, to: cleanPct)
                .stroke(Theme.success, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Concerning arc
            Circle()
                .trim(from: cleanPct, to: cleanPct + concerningPct)
                .stroke(Theme.warning, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Avoid arc
            Circle()
                .trim(from: cleanPct + concerningPct, to: cleanPct + concerningPct + avoidPct)
                .stroke(Theme.danger, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Sort / Filter Bar

struct SortFilterBar: View {
    @Binding var sort: PantrySort
    @Binding var filter: PantryFilter

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(PantrySort.allCases, id: \.self) { s in
                    Button(s.rawValue) { sort = s }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption)
                    Text(sort.rawValue)
                        .font(.caption.weight(.semibold))
                }
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.surfaceElevated)
                .cornerRadius(8)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PantryFilter.allCases, id: \.self) { f in
                        Button(f.rawValue) { filter = f }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(filter == f ? .white : Theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(filter == f ? Theme.accent : Theme.surfaceElevated)
                            .cornerRadius(8)
                    }
                }
            }
        }
    }
}

// MARK: - Pantry Item Card

struct PantryItemCard: View {
    let item: PantryItem

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.surfaceElevated)
                    .frame(height: 80)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(Theme.textDim)
                    )

                Text(item.grade)
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.gradeColor(item.grade))
                    .cornerRadius(4)
                    .padding(4)
            }

            Text(item.productName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text("\(item.score)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Theme.gradeColor(item.grade))
        }
        .padding(8)
        .background(Theme.surface)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Scanner Sheet (Pantry Mode)

struct PantryScannerSheet: View {
    let onAdd: (PantryItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 64))
                        .foregroundColor(Theme.accent)
                    Text("Pantry Mode")
                        .font(.title2.weight(.bold))
                        .foregroundColor(Theme.textPrimary)
                    Text("Scanned items will be added to your pantry")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    // In a real build, embed BarcodeScannerRepresentable here
                    // For now, show a placeholder
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Theme.surfaceElevated)
                        .frame(height: 200)
                        .overlay(
                            VStack(spacing: 12) {
                                Image(systemName: "barcode.viewfinder")
                                    .font(.system(size: 48))
                                    .foregroundColor(Theme.textDim)
                                Text("Scanner placeholder")
                                    .font(.subheadline)
                                    .foregroundColor(Theme.textSecondary)
                            }
                        )
                        .padding(.horizontal, 32)
                }
                .padding()
            }
            .navigationTitle("Scan for Pantry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
    }
}

#Preview {
    PantryView()
}
