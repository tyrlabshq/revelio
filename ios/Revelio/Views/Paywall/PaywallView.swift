import SwiftUI
import StoreKit

// ─── Product IDs ──────────────────────────────────────────────────────────────

private enum ProductID {
    static let monthly = "com.revelio.pro.monthly"
    static let yearly  = "com.revelio.pro.yearly"
}

// ─── Paywall View ─────────────────────────────────────────────────────────────

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var selectedPlan: Plan = .annual
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var purchaseSuccess = false

    enum Plan { case monthly, annual }

    private let features: [(String, Bool, Bool)] = [
        // (label, free, pro)
        ("Scans per day", false, false),   // handled separately
        ("Ingredient flags", true, true),
        ("Basic health grades", true, true),
        ("Full flag explanations", false, true),
        ("Science citations", false, true),
        ("Personalized scoring", false, true),
        ("Pantry tracking", false, true),
        ("Pro alternatives", false, true),
        ("Priority support", false, true),
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    paywallHeader
                        .padding(.top, 32)

                    // Plan toggle
                    planToggle
                        .padding(.top, 32)

                    // Price display
                    priceDisplay
                        .padding(.top, 20)

                    // Feature comparison
                    featureTable
                        .padding(.top, 28)
                        .padding(.horizontal, 24)

                    // Trial note
                    if selectedPlan == .annual {
                        HStack(spacing: 6) {
                            Image(systemName: "gift.fill")
                                .foregroundColor(Theme.success)
                                .font(.subheadline)
                            Text("7-day free trial — cancel anytime")
                                .font(.subheadline)
                                .foregroundColor(Theme.textSecondary)
                        }
                        .padding(.top, 20)
                    }

                    // Error
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(Theme.danger)
                            .padding(.horizontal, 32)
                            .padding(.top, 12)
                            .multilineTextAlignment(.center)
                    }

                    // CTA
                    ctaButton
                        .padding(.top, 24)
                        .padding(.horizontal, 32)

                    // Legal
                    Text("Payment charged to Apple ID at confirmation. Subscription auto-renews unless cancelled at least 24h before the period ends.")
                        .font(.caption2)
                        .foregroundColor(Theme.textDim)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 16)

                    // Restore purchases
                    Button("Restore Purchases") {
                        Task { await restorePurchases() }
                    }
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
        .alert("You're Pro! 🎉", isPresented: $purchaseSuccess) {
            Button("Let's go!") { dismiss() }
        } message: {
            Text("Unlimited scans and full ingredient analysis — enjoy.")
        }
    }

    // ─── Sub-views ────────────────────────────────────────────────────────────

    private var paywallHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "star.fill")
                    .font(.system(size: 36))
                    .foregroundColor(Theme.accent)
            }

            Text("Upgrade to Revelio Pro")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(Theme.textPrimary)

            Text("Full ingredient transparency. No limits.")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private var planToggle: some View {
        ZStack {
            Capsule()
                .fill(Theme.surfaceElevated)
                .frame(height: 48)

            HStack(spacing: 0) {
                planButton("Monthly", plan: .monthly)
                planButton("Annual", plan: .annual, badge: "Save 42%")
            }
            .padding(4)
        }
        .padding(.horizontal, 32)
    }

    private func planButton(_ title: String, plan: Plan, badge: String? = nil) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) { selectedPlan = plan }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(selectedPlan == plan ? .semibold : .regular)
                    .foregroundColor(selectedPlan == plan ? .white : Theme.textSecondary)

                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(selectedPlan == plan ? Theme.success : Theme.textDim)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background((selectedPlan == plan ? Theme.success : Theme.textDim).opacity(0.15))
                        .cornerRadius(3)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(selectedPlan == plan ? Theme.accent : Color.clear)
            .clipShape(Capsule())
        }
    }

    private var priceDisplay: some View {
        VStack(spacing: 4) {
            if selectedPlan == .annual {
                HStack(alignment: .top, spacing: 2) {
                    Text("$")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.textPrimary)
                        .padding(.top, 6)
                    Text("34")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                    Text(".99")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.textSecondary)
                        .padding(.top, 10)
                }
                Text("per year • ~$2.92/month")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)

                Text("Most Popular")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.12))
                    .cornerRadius(8)
                    .padding(.top, 4)
            } else {
                HStack(alignment: .top, spacing: 2) {
                    Text("$")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.textPrimary)
                        .padding(.top, 6)
                    Text("4")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                    Text(".99")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.textSecondary)
                        .padding(.top, 10)
                }
                Text("per month")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }

    private var featureTable: some View {
        VStack(spacing: 0) {
            // Header row
            HStack {
                Spacer()
                Text("Free")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 60, alignment: .center)
                Text("Pro")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.accent)
                    .frame(width: 60, alignment: .center)
            }
            .padding(.bottom, 8)

            Divider()
                .background(Color.gray.opacity(0.12))

            // Scan limit row (special)
            featureRow(
                label: "Scans per day",
                freeValue: "10",
                proValue: "∞",
                isHighlighted: true
            )

            // Feature rows
            ForEach(features.dropFirst(), id: \.0) { label, free, pro in
                featureRow(label: label, freeCheck: free, proCheck: pro)
            }
        }
    }

    private func featureRow(label: String, freeCheck: Bool, proCheck: Bool) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(Theme.textPrimary)
            Spacer()
            checkmark(freeCheck)
                .frame(width: 60, alignment: .center)
            checkmark(proCheck)
                .frame(width: 60, alignment: .center)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider()
                .background(Color.gray.opacity(0.12))
        }
    }

    private func featureRow(label: String, freeValue: String, proValue: String, isHighlighted: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Text(freeValue)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(Theme.textSecondary)
                .frame(width: 60, alignment: .center)
            Text(proValue)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(Theme.success)
                .frame(width: 60, alignment: .center)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider()
                .background(Color.gray.opacity(0.12))
        }
    }

    @ViewBuilder
    private func checkmark(_ enabled: Bool) -> some View {
        if enabled {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Theme.success)
                .font(.subheadline)
        } else {
            Image(systemName: "minus")
                .foregroundColor(Theme.textDim)
                .font(.subheadline)
        }
    }

    private var ctaButton: some View {
        Button {
            Task { await purchase() }
        } label: {
            ZStack {
                VStack(spacing: 2) {
                    Text(selectedPlan == .annual ? "Start Free Trial" : "Subscribe")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    if selectedPlan == .annual {
                        Text("7 days free, then $34.99/yr")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .opacity(isPurchasing ? 0 : 1)

                if isPurchasing {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Theme.accent.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .disabled(isPurchasing)
    }

    // ─── Purchase logic ───────────────────────────────────────────────────────

    private func purchase() async {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        let productId = selectedPlan == .annual ? ProductID.yearly : ProductID.monthly

        #if DEBUG
        // Use STOREKIT_MOCK=1 to bypass real StoreKit in simulator testing
        if ProcessInfo.processInfo.environment["STOREKIT_MOCK"] == "1" {
            print("[PaywallView/mock] Mock purchase for \(productId)")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            purchaseSuccess = true
            return
        }
        #endif

        do {
            // StoreKit 2 purchase flow
            guard let product = try await Product.products(for: [productId]).first else {
                errorMessage = "Product not available. Try again later."
                return
            }
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                // Verify the transaction — never trust unverified purchases
                guard case .verified(let transaction) = verification else {
                    errorMessage = "Purchase could not be verified. Contact support if you were charged."
                    return
                }
                // Finish the transaction to remove it from the payment queue
                await transaction.finish()
                purchaseSuccess = true
                await authViewModel.refreshUser()
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Purchase pending. Check back soon."
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    private func restorePurchases() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await authViewModel.refreshUser()
            if authViewModel.currentUser?.isPro == true {
                purchaseSuccess = true
            } else {
                errorMessage = "No active subscription found."
            }
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }
}
