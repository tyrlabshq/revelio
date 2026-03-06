import SwiftUI

struct ManualBarcodeView: View {
    let onBarcode: (String) -> Void
    @State private var code = ""
    @Environment(\\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Enter Barcode Manually").font(.headline).foregroundColor(Theme.textPrimary)
                TextField("Barcode", text: $code)
                    .keyboardType(.numberPad)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Theme.surfaceElevated)
                    .cornerRadius(12)
                    .foregroundColor(Theme.textPrimary)

                Button("Look Up") {
                    guard !code.isEmpty else { return }
                    dismiss(); onBarcode(code)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(code.isEmpty)

                Spacer()
            }
            .padding(24)
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(Theme.textSecondary)
                }
            }
        }
    }
}
