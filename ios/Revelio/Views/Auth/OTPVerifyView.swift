import SwiftUI
import Combine

struct OTPVerifyView: View {
    let phone: String

    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var digits: [String] = Array(repeating: "", count: 6)
    @FocusState private var focusedIndex: Int?
    @State private var errorMessage: String?
    @State private var isVerifying = false

    // Resend countdown
    @State private var resendCooldown: Int = 30
    @State private var resendTimer: AnyCancellable?
    @State private var canResend = false
    @State private var resendLoading = false

    private var code: String { digits.joined() }
    private var isComplete: Bool { code.count == 6 && code.allSatisfy({ $0.isNumber }) }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.accent)
                        .padding(.top, 60)

                    Text("Check your texts")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.textPrimary)

                    Text("We sent a 6-digit code to\n\(formattedPhone)")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Spacer().frame(height: 48)

                // OTP boxes
                HStack(spacing: 12) {
                    ForEach(0..<6, id: \.self) { index in
                        OTPDigitBox(
                            digit: digits[index],
                            isFocused: focusedIndex == index,
                            hasError: errorMessage != nil
                        )
                        .onTapGesture { focusedIndex = index }
                    }
                }
                .padding(.horizontal, 24)

                // Hidden text field that captures actual input
                TextField("", text: Binding(
                    get: { code },
                    set: { handleInput($0) }
                ))
                .keyboardType(.numberPad)
                .focused($focusedIndex, equals: 0)
                .frame(width: 0, height: 0)
                .opacity(0)
                .onAppear { focusedIndex = 0 }

                // Error
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Theme.danger)
                        .padding(.top, 16)
                        .transition(.opacity.combined(with: .scale))
                }

                Spacer().frame(height: 32)

                // Loading / auto-submit indicator
                if isVerifying {
                    ProgressView()
                        .tint(Theme.accent)
                        .scaleEffect(1.2)
                        .padding(.bottom, 16)
                }

                // Resend button
                VStack(spacing: 4) {
                    Text("Didn't get it?")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)

                    if canResend {
                        Button {
                            Task { await resendCode() }
                        } label: {
                            if resendLoading {
                                ProgressView().tint(Theme.accent)
                            } else {
                                Text("Resend Code")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Theme.accent)
                            }
                        }
                        .disabled(resendLoading)
                    } else {
                        Text("Resend in \(resendCooldown)s")
                            .font(.subheadline)
                            .foregroundColor(Theme.textDim)
                    }
                }
                .padding(.top, 8)

                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Verify")
        .onAppear { startResendTimer() }
        .onDisappear { resendTimer?.cancel() }
    }

    // ─── Input handling ───────────────────────────────────────────────────────

    private func handleInput(_ value: String) {
        let filtered = value.filter { $0.isNumber }
        errorMessage = nil
        for i in 0..<6 {
            digits[i] = i < filtered.count ? String(filtered[filtered.index(filtered.startIndex, offsetBy: i)]) : ""
        }
        // Auto-advance focus
        let count = min(filtered.count, 6)
        if count < 6 { focusedIndex = count }
        // Auto-submit when complete
        if filtered.count >= 6 && !isVerifying {
            Task { await verify() }
        }
    }

    private func verify() async {
        guard isComplete, !isVerifying else { return }
        isVerifying = true
        errorMessage = nil
        defer { isVerifying = false }

        do {
            try await authViewModel.verifyOTP(phone: phone, code: code)
            // AuthViewModel will set isAuthenticated = true, triggering nav
        } catch {
            withAnimation {
                errorMessage = error.localizedDescription
                digits = Array(repeating: "", count: 6)
                focusedIndex = 0
            }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func resendCode() async {
        resendLoading = true
        defer { resendLoading = false }
        do {
            try await authViewModel.requestOTP(phone: phone)
            canResend = false
            resendCooldown = 30
            startResendTimer()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private var formattedPhone: String {
        let d = phone.filter { $0.isNumber }
        guard d.count >= 10 else { return phone }
        let last10 = String(d.suffix(10))
        return "+1 (\(last10.prefix(3))) \(last10.dropFirst(3).prefix(3))-\(last10.dropFirst(6))"
    }

    private func startResendTimer() {
        resendTimer?.cancel()
        resendTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                if resendCooldown > 0 {
                    resendCooldown -= 1
                } else {
                    canResend = true
                    resendTimer?.cancel()
                }
            }
    }
}

// ─── OTP Digit Box ────────────────────────────────────────────────────────────

private struct OTPDigitBox: View {
    let digit: String
    let isFocused: Bool
    let hasError: Bool

    private var borderColor: Color {
        if hasError { return Theme.danger }
        if isFocused { return Theme.accent }
        if !digit.isEmpty { return Theme.accent.opacity(0.5) }
        return Theme.textDim
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(borderColor, lineWidth: isFocused ? 2 : 1)
                )
                .frame(width: 44, height: 56)

            if digit.isEmpty && isFocused {
                // Cursor blink
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: 2, height: 24)
                    .opacity(isFocused ? 1 : 0)
            } else {
                Text(digit)
                    .font(.title2.bold())
                    .foregroundColor(Theme.textPrimary)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .animation(.easeInOut(duration: 0.15), value: digit)
    }
}
