import Foundation
import Combine

// ─── Data Models ──────────────────────────────────────────────────────────────

enum AllergenSeverity: String, Codable, CaseIterable {
    case avoid, caution, note

    var label: String {
        switch self {
        case .avoid: return "AVOID"
        case .caution: return "CAUTION"
        case .note: return "NOTE"
        }
    }

    var emoji: String {
        switch self {
        case .avoid: return "🚫"
        case .caution: return "⚠️"
        case .note: return "📝"
        }
    }

    var colorHex: String {
        switch self {
        case .avoid: return "ef4444"
        case .caution: return "f97316"
        case .note: return "3b82f6"
        }
    }
}

struct PersonalAllergen: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var severity: AllergenSeverity
}

struct AllergenProfile: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var allergens: [PersonalAllergen]

    init(id: String = UUID().uuidString, name: String, allergens: [PersonalAllergen] = []) {
        self.id = id
        self.name = name
        self.allergens = allergens
    }
}

// ─── Match Result ─────────────────────────────────────────────────────────────

struct AllergenMatch: Identifiable {
    let id: String
    let ingredient: String      // ingredient from product
    let allergen: PersonalAllergen
    let profileName: String
}

// ─── Manager ─────────────────────────────────────────────────────────────────

@MainActor
class AllergenProfileManager: ObservableObject {
    static let shared = AllergenProfileManager()

    private let profilesKey = "allergen_profiles"
    private let activeProfileIdKey = "allergen_active_profile_id"

    @Published var profiles: [AllergenProfile] = []
    @Published var activeProfileId: String?

    var activeProfile: AllergenProfile? {
        guard let id = activeProfileId else { return profiles.first }
        return profiles.first { $0.id == id }
    }

    private init() {
        load()
        // Seed a default "Me" profile on first launch
        if profiles.isEmpty {
            let defaultProfile = AllergenProfile(name: "Me", allergens: [])
            profiles = [defaultProfile]
            activeProfileId = defaultProfile.id
            save()
        }
    }

    // ── CRUD ──────────────────────────────────────────────────────────────────

    func addProfile(name: String) {
        let profile = AllergenProfile(name: name)
        profiles.append(profile)
        if profiles.count == 1 { activeProfileId = profile.id }
        save()
    }

    func deleteProfile(_ profile: AllergenProfile) {
        profiles.removeAll { $0.id == profile.id }
        if activeProfileId == profile.id {
            activeProfileId = profiles.first?.id
        }
        save()
    }

    func updateProfile(_ profile: AllergenProfile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
            save()
        }
    }

    func setActiveProfile(_ id: String) {
        activeProfileId = id
        UserDefaults.standard.set(id, forKey: activeProfileIdKey)
    }

    func addAllergen(to profileId: String, name: String, severity: AllergenSeverity) {
        guard let idx = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        let allergen = PersonalAllergen(name: name.trimmingCharacters(in: .whitespaces), severity: severity)
        profiles[idx].allergens.append(allergen)
        save()
    }

    func removeAllergen(_ allergen: PersonalAllergen, from profileId: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        profiles[idx].allergens.removeAll { $0.id == allergen.id }
        save()
    }

    func updateAllergen(_ allergen: PersonalAllergen, in profileId: String) {
        guard let pIdx = profiles.firstIndex(where: { $0.id == profileId }),
              let aIdx = profiles[pIdx].allergens.firstIndex(where: { $0.id == allergen.id }) else { return }
        profiles[pIdx].allergens[aIdx] = allergen
        save()
    }

    // ── Matching ──────────────────────────────────────────────────────────────

    /// Check product ingredients against the active profile's allergens.
    /// Returns matches sorted by severity (avoid first).
    func matches(for ingredients: [String]) -> [AllergenMatch] {
        guard let profile = activeProfile else { return [] }
        var results: [AllergenMatch] = []

        let normalizedIngredients = ingredients.map { $0.lowercased() }

        for allergen in profile.allergens {
            let needle = allergen.name.lowercased()
            for ingredient in normalizedIngredients {
                if ingredient.contains(needle) || needle.contains(ingredient) {
                    let match = AllergenMatch(
                        id: UUID().uuidString,
                        ingredient: ingredient,
                        allergen: allergen,
                        profileName: profile.name
                    )
                    results.append(match)
                    break  // one match per allergen is enough
                }
            }
        }

        // Sort: avoid → caution → note
        return results.sorted {
            let order: [AllergenSeverity: Int] = [.avoid: 0, .caution: 1, .note: 2]
            return (order[$0.allergen.severity] ?? 3) < (order[$1.allergen.severity] ?? 3)
        }
    }

    // ── Persistence ───────────────────────────────────────────────────────────

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
        if let id = activeProfileId {
            UserDefaults.standard.set(id, forKey: activeProfileIdKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([AllergenProfile].self, from: data) {
            profiles = decoded
        }
        activeProfileId = UserDefaults.standard.string(forKey: activeProfileIdKey)
    }
}
