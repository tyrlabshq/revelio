import SwiftUI
import Combine

struct ManualBarcodeView: View {
    let onBarcode: (String) -> Void
    let onSearch: (String) -> Void
    var autoFocused: Bool = false

    @State private var code = ""
    @State private var productName = ""
    @State private var selectedTab = 0 // 0 = barcode, 1 = product name
    @State private var debounceTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Tab picker
                Picker("Search type", selection: $selectedTab) {
                    Text("Barcode").tag(0)
                    Text("Product Name").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if selectedTab == 0 {
                    // Barcode entry
                    VStack(spacing: 16) {
                        Text("Enter the barcode number")
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)

                        TextField("e.g. 012345678901", text: $code)
                            .keyboardType(.numberPad)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(Theme.surfaceElevated)
                            .cornerRadius(12)
                            .foregroundColor(Theme.textPrimary)

                        Button("Look Up") {
                            guard !code.isEmpty else { return }
                            dismiss()
                            onBarcode(code)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .disabled(code.isEmpty)
                    }
                } else {
                    // Product name search
                    VStack(spacing: 16) {
                        Text("Search by product name")
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)

                        TextField("e.g. Oreo Cookies", text: $productName)
                            .keyboardType(.default)
                            .font(.system(size: 20, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(Theme.surfaceElevated)
                            .cornerRadius(12)
                            .foregroundColor(Theme.textPrimary)
                            .onChange(of: productName) { _, newValue in
                                // Debounce at 300ms
                                debounceTask?.cancel()
                                debounceTask = Task {
                                    try? await Task.sleep(nanoseconds: 300_000_000)
                                    guard !Task.isCancelled, !newValue.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                                    await MainActor.run {
                                        dismiss()
                                        onSearch(newValue)
                                    }
                                }
                            }

                        Button("Search") {
                            let query = productName.trimmingCharacters(in: .whitespaces)
                            guard !query.isEmpty else { return }
                            debounceTask?.cancel()
                            dismiss()
                            onSearch(query)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .disabled(productName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Spacer()
            }
            .padding(24)
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Manual Entry")
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        debounceTask?.cancel()
                        dismiss()
                    }
                    .foregroundColor(Theme.textSecondary)
                }
            }
            .onAppear {
                if autoFocused {
                    // Slight delay to let sheet animate in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        // Focus is handled by system for first TextField
                    }
                }
            }
        }
    }
}
