import SwiftUI
import Photos

// ─── Share Card Generator ─────────────────────────────────────────────────────
/// Renders ShareCardView offscreen using ImageRenderer (iOS 16+).
/// All rendering must happen on the main actor.

@MainActor
final class ShareCardGenerator {

    static let shared = ShareCardGenerator()
    private init() {}

    // ── Public API ─────────────────────────────────────────────────────────────

    /// Render a share card for the given scan.
    /// - Parameters:
    ///   - scan: The scanned product result.
    ///   - variant: Portrait (stories) or square (feed).
    ///   - activePriority: If set, shows personalization label on card.
    /// - Returns: Rendered UIImage at 3× scale (1080px output).
    func renderCard(scan: ScanResult, variant: ShareCardVariant, activePriority: String? = nil) -> UIImage? {
        let view = ShareCardView(scan: scan, variant: variant, activePriority: activePriority)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3.0   // 360pt × 3 = 1080px
        renderer.proposedSize = ProposedViewSize(variant.size)

        guard let baseImage = renderer.uiImage else { return nil }
        return addFilmGrain(to: baseImage)
    }

    /// Render both portrait and square variants.
    func renderBothVariants(scan: ScanResult, activePriority: String? = nil) -> (portrait: UIImage?, square: UIImage?) {
        let portrait = renderCard(scan: scan, variant: .portrait, activePriority: activePriority)
        let square   = renderCard(scan: scan, variant: .square,   activePriority: activePriority)
        return (portrait, square)
    }

    // ── Film Grain ────────────────────────────────────────────────────────────
    /// Overlays a subtle procedural film grain texture onto the rendered image.
    /// Grain is generated via Core Graphics using random noise seeded per render.

    private func addFilmGrain(to image: UIImage, intensity: CGFloat = 0.035) -> UIImage {
        let size = image.size
        let scale = image.scale

        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }

        guard let ctx = UIGraphicsGetCurrentContext() else { return image }

        // Draw base image
        image.draw(at: .zero)

        // Generate grain as semi-transparent noise
        let pixelW = Int(size.width * scale)
        let pixelH = Int(size.height * scale)
        let bytesPerRow = pixelW * 4
        var pixels = [UInt8](repeating: 0, count: pixelH * bytesPerRow)

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let noise = UInt8.random(in: 0...255)
            pixels[i]     = noise   // R
            pixels[i + 1] = noise   // G
            pixels[i + 2] = noise   // B
            pixels[i + 3] = UInt8(intensity * 255)  // A — controls grain strength
        }

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let grainCtx = CGContext(
                data: &pixels,
                width: pixelW,
                height: pixelH,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let grainCGImage = grainCtx.makeImage()
        else {
            return image
        }

        // Blend grain overlay (screen-ish mix via normal alpha blend)
        ctx.setBlendMode(.normal)
        ctx.draw(grainCGImage, in: CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))

        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }

    // ── Save to Camera Roll ───────────────────────────────────────────────────

    func saveToPhotoLibrary(_ image: UIImage) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    // ── Caption Builder ───────────────────────────────────────────────────────

    static func defaultCaption(for scan: ScanResult) -> String {
        "I scanned \(scan.productName) and got a \(scan.grade) 💀 #revelio #cleaningupmy pantry #seedoils"
    }
}

// ─── Share Card Sheet ─────────────────────────────────────────────────────────
/// Bottom sheet shown from ProductDetailView — previews the card and offers share options.

struct ShareCardSheet: View {
    let scan: ScanResult
    var activePriority: String? = nil

    @State private var selectedVariant: ShareCardVariant = .portrait
    @State private var renderedImage: UIImage? = nil
    @State private var caption: String = ""
    @State private var showActivitySheet = false
    @State private var isRendering = false
    @State private var saveSuccess: Bool? = nil
    @State private var showSaveConfirmation = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ── Variant picker ─────────────────────────────────────────
                    Picker("Format", selection: $selectedVariant) {
                        Text("Stories (9:16)").tag(ShareCardVariant.portrait)
                        Text("Feed (1:1)").tag(ShareCardVariant.square)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .onChange(of: selectedVariant) {
                        renderCard()
                    }

                    // ── Card preview ───────────────────────────────────────────
                    ZStack {
                        if let img = renderedImage {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .cornerRadius(16)
                                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(hex: "0a0e1a"))
                                .aspectRatio(selectedVariant == .portrait ? 9/16 : 1, contentMode: .fit)
                                .overlay(
                                    Group {
                                        if isRendering {
                                            ProgressView()
                                                .tint(.white)
                                        } else {
                                            Image(systemName: "photo.fill")
                                                .font(.system(size: 32))
                                                .foregroundColor(.white.opacity(0.3))
                                        }
                                    }
                                )
                        }
                    }
                    .frame(maxWidth: selectedVariant == .portrait ? 220 : 300)
                    .padding(.horizontal, 20)

                    // ── Caption editor ─────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CAPTION")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(Theme.textDim)

                        TextEditor(text: $caption)
                            .frame(height: 80)
                            .font(.system(size: 14))
                            .padding(10)
                            .background(Theme.surfaceElevated)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 20)

                    // ── Action buttons ─────────────────────────────────────────
                    VStack(spacing: 12) {

                        // Share (UIActivityViewController)
                        Button {
                            guard renderedImage != nil else { return }
                            showActivitySheet = true
                        } label: {
                            Label("Share to TikTok / Instagram", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.accent)
                                .cornerRadius(12)
                        }
                        .disabled(renderedImage == nil)

                        HStack(spacing: 12) {
                            // Copy image
                            Button {
                                if let img = renderedImage {
                                    UIPasteboard.general.image = img
                                }
                            } label: {
                                Label("Copy Image", systemImage: "doc.on.doc")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Theme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Theme.surfaceElevated)
                                    .cornerRadius(10)
                            }
                            .disabled(renderedImage == nil)

                            // Save to camera roll
                            Button {
                                guard let img = renderedImage else { return }
                                Task {
                                    let ok = await ShareCardGenerator.shared.saveToPhotoLibrary(img)
                                    saveSuccess = ok
                                    showSaveConfirmation = true
                                }
                            } label: {
                                Label("Save", systemImage: "square.and.arrow.down")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Theme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Theme.surfaceElevated)
                                    .cornerRadius(10)
                            }
                            .disabled(renderedImage == nil)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .padding(.top, 4)
            }
            .background(Theme.background)
            .navigationTitle("Share Your Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
            .sheet(isPresented: $showActivitySheet) {
                if let img = renderedImage {
                    ActivityShareSheet(items: [img, caption])
                }
            }
            .alert(saveSuccess == true ? "Saved!" : "Save Failed", isPresented: $showSaveConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveSuccess == true
                    ? "Card saved to your Camera Roll."
                    : "Could not save. Check Photos permissions in Settings.")
            }
        }
        .onAppear {
            caption = ShareCardGenerator.defaultCaption(for: scan)
            renderCard()
        }
    }

    // ── Render ────────────────────────────────────────────────────────────────

    private func renderCard() {
        isRendering = true
        renderedImage = nil

        // Slight delay lets SwiftUI settle before offscreen render
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            renderedImage = ShareCardGenerator.shared.renderCard(
                scan: scan,
                variant: selectedVariant,
                activePriority: activePriority
            )
            isRendering = false
        }
    }
}

// ─── Activity Share Sheet ─────────────────────────────────────────────────────

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
