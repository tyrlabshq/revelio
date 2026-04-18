import SwiftUI
import PhotosUI
import UIKit

// ─── Response models ──────────────────────────────────────────────────────────

struct ReceiptProductSummary: Decodable, Hashable {
    let barcode: String
    let name: String
    let brand: String
    let category: String
    let imageUrl: String?
}

struct ReceiptLineItem: Decodable, Identifiable, Hashable {
    var id: String { line + (match?.barcode ?? "-") }
    let line: String
    let match: ReceiptProductSummary?
    let score: Int?
    let grade: String?
}

struct ReceiptAggregate: Decodable {
    let avgScore: Int
    let grade: String
    let clean: Int
    let concerning: Int
    let avoid: Int
    let worstOffender: ReceiptProductSummary?
    let swapSuggestion: ReceiptProductSummary?
}

struct ReceiptScoreResponse: Decodable {
    let items: [ReceiptLineItem]
    let aggregate: ReceiptAggregate
}

// ─── ViewModel ────────────────────────────────────────────────────────────────

@MainActor
final class ReceiptScanViewModel: ObservableObject {
    enum State {
        case idle
        case scanning
        case uploading
        case done(ReceiptScoreResponse)
        case error(String)
    }

    @Published var state: State = .idle
    @Published var ocrLines: [ReceiptLine] = []

    private var apiBase: String {
        ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app"
    }

    func scan(image: UIImage) async {
        state = .scanning
        do {
            let lines = try await ReceiptScannerService.extractLines(from: image)
            ocrLines = lines
            if lines.isEmpty {
                state = .error("No readable product lines found. Try a clearer photo.")
                return
            }
            await submitForScoring(lines: lines.map { $0.lineText })
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func submitForScoring(lines: [String]) async {
        state = .uploading
        guard let url = URL(string: "\(apiBase)/receipts/score") else {
            state = .error("Invalid API URL")
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = UserDefaults.standard.string(forKey: "auth_token") {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONEncoder().encode(["lines": lines])

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                state = .error("Server error (\(status))")
                return
            }
            let decoded = try JSONDecoder().decode(ReceiptScoreResponse.self, from: data)
            state = .done(decoded)
        } catch {
            state = .error("Upload failed: \(error.localizedDescription)")
        }
    }

    func reset() {
        state = .idle
        ocrLines = []
    }
}

// ─── PhotoPicker wrapper ─────────────────────────────────────────────────────

struct ReceiptImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    var onPicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPicked: (UIImage) -> Void
        init(onPicked: @escaping (UIImage) -> Void) { self.onPicked = onPicked }

        func imagePickerController(_ picker: UIImagePickerController,
                                    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                onPicked(img)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// ─── Main view ────────────────────────────────────────────────────────────────

struct ReceiptScanView: View {
    @StateObject private var vm = ReceiptScanViewModel()
    @State private var showCamera = false
    @State private var showLibrary = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 20) {
                        switch vm.state {
                        case .idle:
                            idleView
                        case .scanning:
                            progressView("Reading receipt…")
                        case .uploading:
                            progressView("Scoring your trip…")
                        case .done(let response):
                            ReceiptReportView(response: response) { vm.reset() }
                        case .error(let msg):
                            errorView(msg)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            ReceiptImagePicker(sourceType: .camera) { img in
                Task { await vm.scan(image: img) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showLibrary) {
            ReceiptImagePicker(sourceType: .photoLibrary) { img in
                Task { await vm.scan(image: img) }
            }
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack {
            Text("RECEIPT SCAN")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.accent)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Theme.surface)
    }

    private var idleView: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 64, weight: .regular))
                .foregroundColor(Theme.accent)
                .padding(.top, 40)

            Text("Score every item in one trip")
                .font(Theme.fontTitle)
                .foregroundColor(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text("Snap a grocery receipt — we'll read the line items and give you a clean score for the whole haul.")
                .font(Theme.fontBody)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            VStack(spacing: 10) {
                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showCamera = true
                    } else {
                        showLibrary = true
                    }
                } label: {
                    Label("Take a photo", systemImage: "camera.fill")
                        .font(Theme.fontHeadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Button {
                    showLibrary = true
                } label: {
                    Label("Choose from library", systemImage: "photo.on.rectangle")
                        .font(Theme.fontHeadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.surface)
                        .foregroundColor(Theme.textPrimary)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.textDim.opacity(0.3), lineWidth: 1))
                        .cornerRadius(12)
                }
            }
            .padding(.top, 20)
        }
    }

    private func progressView(_ msg: String) -> some View {
        VStack(spacing: 14) {
            ProgressView().tint(Theme.accent).scaleEffect(1.5)
            Text(msg).font(Theme.fontBody).foregroundColor(Theme.textSecondary)
        }
        .padding(40)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(Theme.danger)
            Text(msg)
                .font(Theme.fontBody)
                .foregroundColor(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Button("Try again") { vm.reset() }
                .font(Theme.fontHeadline)
                .foregroundColor(Theme.accent)
        }
        .padding(32)
    }
}

// ─── Report view ──────────────────────────────────────────────────────────────

struct ReceiptReportView: View {
    let response: ReceiptScoreResponse
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summaryCard

            Text("Line items")
                .font(Theme.fontHeadline)
                .foregroundColor(Theme.textPrimary)
                .padding(.top, 8)

            ForEach(response.items) { item in
                lineRow(item)
            }

            Button("Scan another receipt") { onDismiss() }
                .font(Theme.fontHeadline)
                .foregroundColor(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
    }

    private var summaryCard: some View {
        let matched = response.items.filter { $0.match != nil }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You bought \(matched) product\(matched == 1 ? "" : "s") this trip.")
                        .font(Theme.fontHeadline)
                        .foregroundColor(Theme.textPrimary)
                    Text("Clean score: \(response.aggregate.grade)")
                        .font(Theme.fontTitle)
                        .foregroundColor(Theme.gradeColor(response.aggregate.grade))
                }
                Spacer()
                GradeBadge(grade: response.aggregate.grade, score: response.aggregate.avgScore)
            }

            HStack(spacing: 12) {
                statPill("Clean", value: response.aggregate.clean, color: Theme.success)
                statPill("Concerning", value: response.aggregate.concerning, color: Theme.warning)
                statPill("Avoid", value: response.aggregate.avoid, color: Theme.danger)
            }

            if let worst = response.aggregate.worstOffender {
                Divider().padding(.vertical, 4)
                Text("Worst offender: \(worst.name)")
                    .font(Theme.fontBody)
                    .foregroundColor(Theme.textPrimary)
                if let swap = response.aggregate.swapSuggestion {
                    Text("Try swapping to \(swap.name).")
                        .font(Theme.fontBody)
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
        .padding(16)
        .background(Theme.surface)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private func statPill(_ label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)%")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(Theme.fontCaption)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .cornerRadius(10)
    }

    private func lineRow(_ item: ReceiptLineItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.match?.name ?? item.line)
                    .font(Theme.fontBody)
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                if let brand = item.match?.brand {
                    Text(brand)
                        .font(Theme.fontCaption)
                        .foregroundColor(Theme.textSecondary)
                } else {
                    Text("No match — tap to search")
                        .font(Theme.fontCaption)
                        .foregroundColor(Theme.textDim)
                }
            }
            Spacer()
            if let grade = item.grade, let score = item.score {
                GradeBadge(grade: grade, score: score)
            } else {
                Text("—")
                    .font(Theme.fontCaption)
                    .foregroundColor(Theme.textDim)
            }
        }
        .padding(12)
        .background(Theme.surface)
        .cornerRadius(10)
    }
}
