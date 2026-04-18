import SwiftUI

/// Settings row with a "Sync with Apple Health" toggle. Shown in the
/// Preferences section of SettingsView.
///
/// The toggle binds to HealthKitService.isEnabled but we mediate mutations
/// through `setEnabled(_:)` so we can trigger the system permission prompt
/// and roll the switch back if the user declines.
struct HealthKitRow: View {
    @StateObject private var health = HealthKitService.shared
    @State private var pendingToggle: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.pink)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Sync with Apple Health")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                if !health.isHealthDataAvailable {
                    Text("Not available on this device")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textDim)
                } else {
                    Text("Log dietary energy from scans")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { health.isEnabled },
                set: { newValue in
                    pendingToggle = newValue
                    Task { await health.setEnabled(newValue) }
                }
            ))
            .labelsHidden()
            .disabled(!health.isHealthDataAvailable)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    List {
        HealthKitRow()
    }
}
