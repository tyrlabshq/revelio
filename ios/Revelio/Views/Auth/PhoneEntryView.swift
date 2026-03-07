import SwiftUI

struct PhoneEntryView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var phoneDigits = ""
    @State private var navigateToOTP = false
    @State private var errorMessage: String?
    @State private var isLoading = false

    // Formatted display: (555) 867-5309
    private var formattedPhone: String {
        let d = phoneDigits
        if d.count <= 3 { return d }
        if d.count <= 6 { return "(\(d.prefix(3))) \(d.dropFirst(3))" }
        return "(\(d.prefix(3))) \(d.dropFirst(3).prefix(3))-\(d.dropFirst(6))"
    }

    private var canSubmit: Bool {
        phoneDigits.count == 10 && !isLoading
    }

    private let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "⌫"],
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.accent)
                        .padding(.top, 60)

                    Text("Enter your number")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.textPrimary)

                    Text("We'll text you a code. No password needed.")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Spacer().frame(height: 40)

                // Phone display
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Text("+1")
                            .font(.title)
                            .fontWeight(.medium)
                            .foregroundColor(Theme.textSecondary)

                        Text(formattedPhone.isEmpty ? "   " : formattedPhone)
                            .font(.system(size: 32, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.textPrimary)
                            .frame(minWidth: 200, alignment: .leading)
                            .animation(.none, value: formattedPhone)
                    }
                    .padding(.horizontal, 32)

                    // Underline
                    Rectangle()
                        .fill(phoneDigits.isEmpty ? Theme.textDim : Theme.accent)
                        .frame(height: 2)
                        .padding(.horizontal, 32)
                        .animation(.easeInOut(duration: 0.2), value: phoneDigits.isEmpty)
                }

                // Error
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Theme.danger)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                        .transition(.opacity)
                }

                Spacer().frame(height: 32)

                // Number pad
                VStack(spacing: 0) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(row, id: \.self) { key in
                                NumberPadKey(key: key, action: { handleKey(key) })
                            }
                        }
                    }
                }

                Spacer().frame(height: 24)

                // Send Code button
                Button {
                    Task { await sendCode() }
                } label: {
                    ZStack {
                        Text("Send Code")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .opacity(isLoading ? 0 : 1)

                        if isLoading {
                            ProgressView().tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(canSubmit ? Theme.accent : Theme.textDim)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(!canSubmit)
                .padding(.horizontal, 32)
                .animation(.easeInOut(duration: 0.2), value: canSubmit)

                Spacer().frame(height: 40)
            }
        }
        .navigationDestination(isPresented: $navigateToOTP) {
            OTPVerifyView(phone: "+1\(phoneDigits)")
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func handleKey(_ key: String) {
        withAnimation(.none) {
            errorMessage = nil
            switch key {
            case "⌫":
                if !phoneDigits.isEmpty { phoneDigits.removeLast() }
            case "":
                break
            default:
                if phoneDigits.count < 10 { phoneDigits += key }
            }
        }
    }

    private func sendCode() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await authViewModel.requestOTP(phone: "+1\(phoneDigits)")
            navigateToOTP = true
        } catch {
            withAnimation { errorMessage = error.localizedDescription }
        }
    }
}

// ─── Number Pad Key ───────────────────────────────────────────────────────────

private struct NumberPadKey: View {
    let key: String
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            guard !key.isEmpty else { return }
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            action()
        } label: {
            ZStack {
                if key.isEmpty {
                    Color.clear
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isPressed ? Theme.surfaceElevated : Theme.surface)
                        .padding(4)

                    if key == "⌫" {
                        Image(systemName: "delete.left")
                            .font(.title2)
                            .foregroundColor(Theme.textPrimary)
                    } else {
                        Text(key)
                            .font(.title)
                            .fontWeight(.regular)
                            .foregroundColor(Theme.textPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
        }
        .buttonStyle(PressedButtonStyle(isPressed: $isPressed))
        .disabled(key.isEmpty)
    }
}

// ─── Pressed Button Style ─────────────────────────────────────────────────────

private struct PressedButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}
