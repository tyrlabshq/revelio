import SwiftUI
import Combine

// ─── Kid-Safe preferences store ──────────────────────────────────────────────
//
// Track 3.6: kid-safe mode is per family member. In this codebase the closest
// concept to "family member" is AllergenProfile (name + allergens). We store a
// boolean flag per profile id in UserDefaults; the scan pipeline reads it
// alongside the active profile to decide whether to request/display the
// kidSafeGrade from the server.

@MainActor
final class KidSafePreferences: ObservableObject {
    static let shared = KidSafePreferences()
    private let storageKey = "kid_safe_enabled_profiles"

    @Published private(set) var enabledProfileIds: Set<String> = []

    private init() { load() }

    func isEnabled(for profileId: String) -> Bool {
        enabledProfileIds.contains(profileId)
    }

    func setEnabled(_ enabled: Bool, for profileId: String) {
        if enabled {
            enabledProfileIds.insert(profileId)
        } else {
            enabledProfileIds.remove(profileId)
        }
        save()
    }

    /// Convenience: is kid-safe on for whatever profile is currently active?
    func isEnabledForActive() -> Bool {
        guard let id = AllergenProfileManager.shared.activeProfile?.id else { return false }
        return isEnabled(for: id)
    }

    private func save() {
        let arr = Array(enabledProfileIds)
        UserDefaults.standard.set(arr, forKey: storageKey)
    }

    private func load() {
        if let arr = UserDefaults.standard.array(forKey: storageKey) as? [String] {
            enabledProfileIds = Set(arr)
        }
    }
}

// ─── Kid-Safe toggle view ────────────────────────────────────────────────────

struct KidSafeToggleView: View {
    @ObservedObject private var prefs = KidSafePreferences.shared
    @ObservedObject private var allergens = AllergenProfileManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Optional: bind to a specific profile id. Defaults to the active one.
    var profileId: String? = nil

    private var activeId: String? {
        profileId ?? allergens.activeProfile?.id
    }

    private var profileName: String {
        let id = activeId
        return allergens.profiles.first(where: { $0.id == id })?.name
            ?? allergens.activeProfile?.name
            ?? "this profile"
    }

    private var isOn: Binding<Bool> {
        Binding(
            get: {
                guard let id = activeId else { return false }
                return prefs.isEnabled(for: id)
            },
            set: { newValue in
                guard let id = activeId else { return }
                prefs.setEnabled(newValue, for: id)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "fde68a").opacity(0.6))
                        .frame(width: 40, height: 40)
                    Image(systemName: "figure.and.child.holdinghands")
                        .foregroundColor(Color(hex: "b45309"))
                        .font(.title3)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kid-safe mode")
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                    Text("For \(profileName)")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                Toggle("Kid-safe mode for \(profileName)", isOn: isOn)
                    .labelsHidden()
                    .tint(Theme.accent)
                    .disabled(activeId == nil)
                    .accessibilityHint("Downgrades products with concerning additives to grade F")
            }

            if isOn.wrappedValue {
                VStack(alignment: .leading, spacing: 8) {
                    kidSafeBullet(
                        icon: "exclamationmark.octagon.fill",
                        color: Theme.danger,
                        text: "Any product with a concerning (severity 2+) additive, heavy metal, or endocrine disruptor is automatically downgraded to F."
                    )
                    kidSafeBullet(
                        icon: "checkmark.shield.fill",
                        color: Theme.success,
                        text: "Surfaces additives banned in the EU but allowed in the US."
                    )
                    kidSafeBullet(
                        icon: "eye.fill",
                        color: Theme.accent,
                        text: "Scan results display the kid-safe grade prominently with the reason."
                    )
                }
                .padding(12)
                .background(Theme.surfaceElevated)
                .cornerRadius(10)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isOn.wrappedValue)
        .padding(16)
        .background(Theme.surface)
        .cornerRadius(14)
    }

    @ViewBuilder
    private func kidSafeBullet(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// ─── Scan-result kid-safe banner ─────────────────────────────────────────────
//
// Shown on a scan result when the current active profile has kid-safe on AND
// the server returned a kidSafeGrade downgrade. Read by ScanResultCard /
// ProductDetailView (wiring optional — the toggle is the primary deliverable).

struct KidSafeGradeBanner: View {
    let kidSafeGrade: String
    let reason: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.danger.opacity(0.15))
                    .frame(width: 40, height: 40)
                Text(kidSafeGrade)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.danger)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Kid-safe grade: \(kidSafeGrade)")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
                if let reason = reason, !reason.isEmpty {
                    Text(reason)
                        .font(.footnote)
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.danger.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.danger.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kid-safe grade \(kidSafeGrade), avoid. \(reason ?? "")")
    }
}

#Preview {
    VStack(spacing: 16) {
        KidSafeToggleView()
        KidSafeGradeBanner(
            kidSafeGrade: "F",
            reason: "Contains titanium dioxide — banned in EU for children"
        )
    }
    .padding()
    .background(Theme.background)
}
