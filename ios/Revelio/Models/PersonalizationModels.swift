import Foundation
import SwiftUI

// MARK: - Health Goals

struct HealthGoal: Identifiable, Hashable, Codable {
    let id: String
    let emoji: String
    let title: String
    let description: String
    /// Maps to the priorities/flags array keys in the backend
    let flagKey: String

    static let all: [HealthGoal] = [
        HealthGoal(id: "seed_oils",            emoji: "🫒", title: "Avoid Seed Oils",           description: "Flag canola, soybean, corn, sunflower oils",    flagKey: "seed_oils"),
        HealthGoal(id: "artificial_dyes",      emoji: "🌈", title: "No Artificial Dyes",        description: "Flag Red 40, Yellow 5/6, Blue 1/2, caramel color", flagKey: "artificial_additives"),
        HealthGoal(id: "endocrine_disruptors", emoji: "🧬", title: "No Endocrine Disruptors",   description: "Flag parabens, triclosan, oxybenzone, phthalates", flagKey: "endocrine_disruptors"),
        HealthGoal(id: "keto",                 emoji: "🥩", title: "Keto Friendly",             description: "Flag high-carb sweeteners and grains",             flagKey: "keto"),
        HealthGoal(id: "gluten_free",          emoji: "🌾", title: "Gluten Free",               description: "Flag wheat, barley, rye derivatives",             flagKey: "gluten_free"),
        HealthGoal(id: "vegan",                emoji: "🌱", title: "Vegan",                     description: "Flag animal-derived ingredients",                  flagKey: "vegan"),
        HealthGoal(id: "paraben_free",         emoji: "🧴", title: "Paraben Free",              description: "Flag methylparaben, propylparaben, butylparaben",  flagKey: "paraben_free"),
        HealthGoal(id: "sulfate_free",         emoji: "🫧", title: "Sulfate Free",              description: "Flag SLS, SLES, and other sulfates",              flagKey: "sulfate_free"),
        HealthGoal(id: "fragrance_free",       emoji: "🧪", title: "No Artificial Fragrances", description: "Flag fragrance / parfum",                          flagKey: "fragrance_free"),
        HealthGoal(id: "heavy_metals",         emoji: "⚗️", title: "Heavy Metal Aware",         description: "Flag lead, mercury, arsenic",                      flagKey: "heavy_metals"),
    ]
}

// MARK: - Family Member

struct FamilyMember: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var isChild: Bool
    var goals: [String]
    var allergies: [String]
    var avatarColor: String

    enum CodingKeys: String, CodingKey {
        case id, name, goals, allergies
        case isChild = "is_child"
        case avatarColor = "avatar_color"
    }

    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var color: Color {
        Color(hex: avatarColor.replacingOccurrences(of: "#", with: ""))
    }

    static let memberColors: [String] = [
        "#00B87C", "#6366F1", "#F59E0B", "#EF4444",
        "#8B5CF6", "#EC4899", "#14B8A6", "#F97316",
    ]
}

// MARK: - Personalization Storage (UserDefaults offline cache)

struct PersonalizationState: Codable {
    var goals: [String]
    var allergies: [String]
    var familyMembers: [FamilyMember]

    static let empty = PersonalizationState(goals: [], allergies: [], familyMembers: [])
}

@MainActor
class PersonalizationStore: ObservableObject {
    static let shared = PersonalizationStore()

    private let defaultsKey = "revelio_personalization_v1"
    private let apiBase: String

    @Published var state: PersonalizationState = .empty
    @Published var isLoading = false

    init() {
        apiBase = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app"
        loadLocal()
    }

    // MARK: - Local persistence

    func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(PersonalizationState.self, from: data)
        else { return }
        state = decoded
    }

    func saveLocal() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    // MARK: - Remote sync

    func syncToServer(profileId: String) {
        guard let url = URL(string: "\(apiBase)/profiles/\(profileId)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "goals": state.goals,
            "allergies": state.allergies,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req).resume()
    }

    func fetchMembers(profileId: String) {
        guard let url = URL(string: "\(apiBase)/profiles/\(profileId)/members") else { return }
        isLoading = true
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data else {
                DispatchQueue.main.async { self?.isLoading = false }
                return
            }
            struct Resp: Decodable { let members: [FamilyMember] }
            if let resp = try? JSONDecoder().decode(Resp.self, from: data) {
                DispatchQueue.main.async {
                    self.state.familyMembers = resp.members
                    self.saveLocal()
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async { self.isLoading = false }
            }
        }.resume()
    }

    func addMember(_ member: FamilyMember, profileId: String) {
        guard let url = URL(string: "\(apiBase)/profiles/\(profileId)/members") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "name": member.name,
            "is_child": member.isChild,
            "goals": member.goals,
            "allergies": member.allergies,
            "avatar_color": member.avatarColor,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data else { return }
            struct Resp: Decodable { let member: FamilyMember }
            if let resp = try? JSONDecoder().decode(Resp.self, from: data) {
                DispatchQueue.main.async {
                    self.state.familyMembers.append(resp.member)
                    self.saveLocal()
                }
            }
        }.resume()
    }

    func deleteMember(memberId: String, profileId: String) {
        guard let url = URL(string: "\(apiBase)/profiles/\(profileId)/members/\(memberId)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        URLSession.shared.dataTask(with: req).resume()
        DispatchQueue.main.async {
            self.state.familyMembers.removeAll { $0.id == memberId }
            self.saveLocal()
        }
    }

    // MARK: - Goal helpers

    func toggleGoal(_ goalId: String, profileId: String) {
        if state.goals.contains(goalId) {
            state.goals.removeAll { $0 == goalId }
        } else {
            state.goals.append(goalId)
        }
        saveLocal()
        syncToServer(profileId: profileId)
    }

    func updateAllergies(_ allergies: [String], profileId: String) {
        state.allergies = allergies
        saveLocal()
        syncToServer(profileId: profileId)
    }
}
