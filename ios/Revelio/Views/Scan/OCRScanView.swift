import SwiftUI
import PhotosUI

/// Fallback view shown when a barcode scan didn't resolve to a known product.
///
/// Flow:
///   1. User selects or captures a photo of the ingredient panel.
///   2. `IngredientOCRService` extracts the ingredient list on-device.
///   3. The text is POSTed to `/scan/ocr` to get a Revelio score using the
///      same pipeline as the barcode path.
///   4. Result is handed back to the caller via `onResult`.
struct OCRScanView: View {
    /// Optional barcode captured earlier that failed lookup. Passed back to
    /// contributions flow so users can submit the product.
    let unresolvedBarcode: String?

    /// Invoked with a scored `ScanResult` once OCR + backend scoring succeeds.
    let onResult: (ScanResult) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var chosenImage: UIImage?
    @State private var extractedIngredients: [String] = []
    @State private var statusMessage: String?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showCameraSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        header
                        imageCard
                        if !extractedIngredients.isEmpty {
                            ingredientsPreview
                        }
                        if let msg = statusMessage {
                            Text(msg)
                                .font(Theme.fontCaption)
                                .foregroundColor(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        if let err = errorMessage {
                            Text(err)
                                .font(Theme.fontCaption)
                                .foregroundColor(Theme.danger)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        actionButtons
                        Spacer(minLength: 40)
                    }
                    .padding()
                }
            }
            .navigationTitle("Scan Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showCameraSheet) {
                CameraCaptureView(image: $chosenImage)
                    .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, newItem in
                Task { await loadPickerImage(newItem) }
            }
            .onChange(of: chosenImage) { _, newImage in
                guard newImage != nil else { return }
                Task { await runOCR() }
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(Theme.accent)
            Text("Couldn't find this product")
                .font(Theme.fontHeadline)
                .foregroundColor(Theme.textPrimary)
            Text("Snap the ingredients panel and we'll score it on-device.")
                .font(Theme.fontBody)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var imageCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            if let img = chosenImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(16)
                    .frame(maxHeight: 280)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 32, weight: .thin))
                        .foregroundColor(Theme.textDim)
                    Text("No image yet")
                        .font(Theme.fontCaption)
                        .foregroundColor(Theme.textDim)
                }
                .frame(height: 200)
            }
        }
    }

    private var ingredientsPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Detected ingredients")
                .font(Theme.fontLabel)
                .foregroundColor(Theme.textSecondary)
            Text(extractedIngredients.prefix(12).joined(separator: ", "))
                .font(Theme.fontBody)
                .foregroundColor(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if extractedIngredients.count > 12 {
                Text("+ \(extractedIngredients.count - 12) more")
                    .font(Theme.fontCaption)
                    .foregroundColor(Theme.textDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.surfaceElevated)
        .cornerRadius(12)
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                showCameraSheet = true
            } label: {
                Label("Take Photo", systemImage: "camera.fill")
                    .font(Theme.fontHeadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(isProcessing)

            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label("Pick from Library", systemImage: "photo.on.rectangle")
                    .font(Theme.fontHeadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.surface)
                    .foregroundColor(Theme.accent)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent, lineWidth: 1))
                    .cornerRadius(12)
            }
            .disabled(isProcessing)

            if !extractedIngredients.isEmpty {
                Button {
                    Task { await submitForScoring() }
                } label: {
                    HStack {
                        if isProcessing {
                            ProgressView().tint(.white)
                        }
                        Text(isProcessing ? "Scoring…" : "Score this label")
                            .font(Theme.fontHeadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.textPrimary)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isProcessing)
            }
        }
    }

    // MARK: - Actions

    private func loadPickerImage(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                chosenImage = img
            }
        } catch {
            errorMessage = "Couldn't load that photo."
        }
    }

    private func runOCR() async {
        guard let img = chosenImage else { return }
        errorMessage = nil
        statusMessage = "Reading label…"
        isProcessing = true
        defer { isProcessing = false }
        do {
            let tokens = try await IngredientOCRService.shared.extractIngredients(from: img)
            extractedIngredients = tokens
            if tokens.isEmpty {
                statusMessage = nil
                errorMessage = "No ingredients found. Try a closer, brighter shot."
            } else {
                statusMessage = "Detected \(tokens.count) ingredients. Tap Score to continue."
            }
        } catch {
            statusMessage = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "OCR failed."
        }
    }

    private func submitForScoring() async {
        guard !extractedIngredients.isEmpty else { return }
        isProcessing = true
        errorMessage = nil
        statusMessage = "Scoring…"
        defer { isProcessing = false }

        do {
            let scan = try await postOCRForScoring(
                ingredients: extractedIngredients,
                barcode: unresolvedBarcode
            )
            onResult(scan)
            dismiss()
        } catch {
            statusMessage = nil
            errorMessage = "Couldn't score label: \(error.localizedDescription)"
        }
    }

    private func postOCRForScoring(ingredients: [String], barcode: String?) async throws -> ScanResult {
        let base = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app"
        guard let url = URL(string: "\(base)/scan/ocr") else {
            throw URLError(.badURL)
        }

        struct Payload: Encodable {
            let ingredientText: String
            let category: String?
            let priorities: [String]?
            let barcode: String?
        }
        let payload = Payload(
            ingredientText: ingredients.joined(separator: ", "),
            category: "food",
            priorities: nil,
            barcode: barcode
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = UserDefaults.standard.string(forKey: "auth_token") {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ScanResult.self, from: data)
    }
}

// MARK: - Camera

/// Minimal UIImagePickerController wrapper for camera capture.
private struct CameraCaptureView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCaptureView
        init(_ parent: CameraCaptureView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.image = img
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    OCRScanView(unresolvedBarcode: "0123456789", onResult: { _ in })
}
