// ─── ios/Revelio/Services/ScorecardVideoExporter.swift ───────────────────────
// Track 3.8 — viral video scorecards.
//
// Renders a vertical 1080×1920 MP4 of a scan reveal:
//   0.0–3.0s  intro      — barcode slides in from the right
//   3.0–4.0s  scanning   — scanning line sweeps across
//   4.0–7.0s  reveal     — grade + product name + score animate in
//   7.0–9.0s  CTA        — watermark + deep-link URL "revelio://scan/<barcode>"
//
// Output: H.264 Main profile, 30fps, no audio, ~9s, written to
// FileManager.default.temporaryDirectory and returned as a URL.
//
// Implementation: a CALayer tree driven by CABasicAnimation/CAKeyframeAnimation,
// captured via AVAssetWriter + AVAssetWriterInputPixelBufferAdaptor. We sample
// the layer tree at each frame by forwarding the frame's time into the layer's
// animations (beginTime fixed to AVCoreAnimationBeginTimeAtZero pattern, but
// applied via a per-frame render pass since we write pixels, not a composition).
//
// Why not the composition/CALayer-synchronized approach? AVVideoCompositionCoreAnimationTool
// requires a source video track; we have none. Rendering the layer tree per
// frame into a CGContext is the cleanest dependency-free path.

import AVFoundation
import UIKit
import CoreGraphics

final class ScorecardVideoExporter: @unchecked Sendable {

    static let shared = ScorecardVideoExporter()
    private init() {}

    // ── Config ────────────────────────────────────────────────────────────────

    private let width: Int = 1080
    private let height: Int = 1920
    private let fps: Int32 = 30
    private let totalSeconds: Double = 9.0

    private var totalFrames: Int { Int(Double(fps) * totalSeconds) }

    // ── Public API ────────────────────────────────────────────────────────────

    /// Export a vertical MP4 for the given scan. Returns the temp URL on success.
    /// - Parameter scan: the ScanResult to animate.
    func export(scan: ScanResult) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("revelio-scorecard-\(UUID().uuidString).mp4")
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let compressionProps: [String: Any] = [
            AVVideoAverageBitRateKey: 6_000_000,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel,
            AVVideoMaxKeyFrameIntervalKey: fps,
        ]
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compressionProps,
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let adaptorAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: adaptorAttrs
        )

        guard writer.canAdd(input) else {
            throw NSError(domain: "ScorecardVideoExporter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot add writer input"])
        }
        writer.add(input)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Pre-compose static resources on a background task to avoid blocking
        // the caller's thread with a synchronous network fetch.
        let context = makeContext()
        let productImage: UIImage? = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let urlStr = scan.imageUrl,
                  let u = URL(string: urlStr),
                  let data = try? Data(contentsOf: u, options: .mappedIfSafe) else { return nil }
            return UIImage(data: data)
        }.value

        // Drive the writer on a serial queue. The input's requestMediaDataWhenReady
        // block is asynchronous; we bridge it back with a continuation.
        let queue = DispatchQueue(label: "revelio.scorecard.writer")
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var frameIndex = 0
            let totalFrames = self.totalFrames
            let totalFramesLocal = totalFrames

            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if frameIndex >= totalFramesLocal {
                        input.markAsFinished()
                        writer.finishWriting {
                            if writer.status == .completed {
                                cont.resume(returning: ())
                            } else {
                                cont.resume(throwing: writer.error ?? NSError(
                                    domain: "ScorecardVideoExporter", code: 2,
                                    userInfo: [NSLocalizedDescriptionKey: "Writer failed"]
                                ))
                            }
                        }
                        return
                    }

                    let t = Double(frameIndex) / Double(self.fps)
                    guard let buffer = self.renderFrame(
                        scan: scan,
                        productImage: productImage,
                        time: t,
                        context: context,
                        adaptor: adaptor
                    ) else {
                        input.markAsFinished()
                        writer.cancelWriting()
                        cont.resume(throwing: NSError(
                            domain: "ScorecardVideoExporter", code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "Frame render failed"]
                        ))
                        return
                    }

                    let presentTime = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(self.fps))
                    if !adaptor.append(buffer, withPresentationTime: presentTime) {
                        input.markAsFinished()
                        writer.cancelWriting()
                        cont.resume(throwing: writer.error ?? NSError(
                            domain: "ScorecardVideoExporter", code: 4,
                            userInfo: [NSLocalizedDescriptionKey: "Append failed"]
                        ))
                        return
                    }
                    frameIndex += 1
                }
            }
        }

        return url
    }

    // ── CG context ───────────────────────────────────────────────────────────

    private func makeContext() -> CGContext {
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: bitmapInfo
        ) else {
            fatalError("Failed to create CGContext for scorecard video")
        }
        return ctx
    }

    // ── Per-frame render ─────────────────────────────────────────────────────

    private func renderFrame(
        scan: ScanResult,
        productImage: UIImage?,
        time t: Double,
        context ctx: CGContext,
        adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) -> CVPixelBuffer? {
        // 1. Clear to dark background.
        ctx.saveGState()
        ctx.setFillColor(UIColor(red: 0.04, green: 0.05, blue: 0.10, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.restoreGState()

        // 2. Draw accent gradient top band.
        drawGradientBand(ctx: ctx)

        // 3. Timeline phases.
        if t < 3.0 {
            drawIntroPhase(ctx: ctx, t: t, scan: scan, productImage: productImage)
        } else if t < 4.0 {
            drawScanningPhase(ctx: ctx, t: t - 3.0, scan: scan, productImage: productImage)
        } else if t < 7.0 {
            drawRevealPhase(ctx: ctx, t: t - 4.0, scan: scan, productImage: productImage)
        } else {
            drawCTAPhase(ctx: ctx, t: t - 7.0, scan: scan, productImage: productImage)
        }

        // 4. Persistent watermark (bottom-right).
        drawWatermark(ctx: ctx)

        // 5. Extract into pixel buffer.
        return pixelBufferFromContext(ctx, adaptor: adaptor)
    }

    // ── Phase renderers ──────────────────────────────────────────────────────

    private func drawGradientBand(ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let cs = CGColorSpaceCreateDeviceRGB()
        let colors = [
            UIColor(red: 0.00, green: 0.72, blue: 0.49, alpha: 0.55).cgColor,
            UIColor(red: 0.00, green: 0.72, blue: 0.49, alpha: 0.00).cgColor,
        ] as CFArray
        guard let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0.0, 1.0]) else { return }
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: height),
                               end: CGPoint(x: 0, y: height - 420), options: [])
    }

    private func drawIntroPhase(
        ctx: CGContext, t: Double, scan: ScanResult, productImage: UIImage?
    ) {
        // Barcode slides in from the right, settling at center.
        let progress = easeOut(min(1, t / 1.2))
        let slideX = Double(width) + 100 - progress * (Double(width) / 2 + Double(width) / 2 + 100)

        let barcodeBoxSize = CGSize(width: 720, height: 220)
        let barcodeBoxOrigin = CGPoint(
            x: slideX - Double(barcodeBoxSize.width) / 2,
            y: Double(height) / 2 - Double(barcodeBoxSize.height) / 2
        )
        drawBarcodeBadge(ctx: ctx, origin: barcodeBoxOrigin, size: barcodeBoxSize, barcode: scan.barcode)

        // Tagline above.
        let tagAlpha = CGFloat(max(0, min(1, (t - 0.4) / 0.8)))
        drawText(
            ctx: ctx,
            text: "SCANNING…",
            origin: CGPoint(x: width / 2, y: height / 2 + 200),
            fontSize: 36, weight: .semibold,
            color: UIColor(white: 1, alpha: tagAlpha), centered: true
        )

        if let img = productImage {
            let thumbAlpha = CGFloat(max(0, min(1, (t - 1.6) / 1.0)))
            drawProductThumb(ctx: ctx, image: img, alpha: thumbAlpha,
                             center: CGPoint(x: width / 2, y: height / 2 - 360))
        }
    }

    private func drawScanningPhase(
        ctx: CGContext, t: Double, scan: ScanResult, productImage: UIImage?
    ) {
        // Keep barcode box centered; draw scanning line sweeping down.
        drawBarcodeBadge(ctx: ctx,
                         origin: CGPoint(x: width / 2 - 360, y: height / 2 - 110),
                         size: CGSize(width: 720, height: 220),
                         barcode: scan.barcode)

        let lineY = Double(height / 2 - 110) + t * 220.0
        ctx.saveGState()
        ctx.setStrokeColor(UIColor(red: 0.00, green: 0.90, blue: 0.55, alpha: 0.95).cgColor)
        ctx.setLineWidth(6)
        ctx.setShadow(offset: .zero, blur: 18, color: UIColor(red: 0, green: 1, blue: 0.5, alpha: 0.7).cgColor)
        ctx.move(to: CGPoint(x: width / 2 - 360, y: lineY))
        ctx.addLine(to: CGPoint(x: width / 2 + 360, y: lineY))
        ctx.strokePath()
        ctx.restoreGState()

        drawText(ctx: ctx, text: "ANALYZING INGREDIENTS",
                 origin: CGPoint(x: width / 2, y: height / 2 + 200),
                 fontSize: 36, weight: .semibold,
                 color: UIColor(white: 1, alpha: 0.9), centered: true)

        if let img = productImage {
            drawProductThumb(ctx: ctx, image: img, alpha: 1.0,
                             center: CGPoint(x: width / 2, y: height / 2 - 360))
        }
    }

    private func drawRevealPhase(
        ctx: CGContext, t: Double, scan: ScanResult, productImage: UIImage?
    ) {
        // Big grade letter scales in with haptic-style pulse.
        let scale: CGFloat = {
            if t < 0.3 {
                return CGFloat(0.1 + 3.0 * t)     // ramp up
            } else if t < 0.55 {
                return CGFloat(1.0 + 0.12 * sin((t - 0.3) * .pi / 0.25))
            }
            return 1.0
        }()

        let gradeColor = gradeColor(grade: scan.grade)

        ctx.saveGState()
        // Pulsing halo ring
        if t < 1.2 {
            let haloAlpha = CGFloat(max(0, 0.6 - t * 0.5))
            let haloRadius = 320 + t * 160
            ctx.setStrokeColor(gradeColor.withAlphaComponent(haloAlpha).cgColor)
            ctx.setLineWidth(10)
            ctx.addEllipse(in: CGRect(
                x: Double(width / 2) - haloRadius,
                y: Double(height / 2) - haloRadius,
                width: haloRadius * 2,
                height: haloRadius * 2
            ))
            ctx.strokePath()
        }
        ctx.restoreGState()

        // Big grade letter
        drawText(
            ctx: ctx,
            text: scan.grade,
            origin: CGPoint(x: width / 2, y: height / 2 - 40),
            fontSize: 480 * scale,
            weight: .heavy,
            color: gradeColor,
            centered: true
        )

        // Score number
        let scoreAlpha = CGFloat(max(0, min(1, (t - 0.35) / 0.5)))
        drawText(
            ctx: ctx,
            text: "SCORE \(scan.displayScore)",
            origin: CGPoint(x: width / 2, y: height / 2 + 260),
            fontSize: 58,
            weight: .bold,
            color: UIColor(white: 1, alpha: scoreAlpha),
            centered: true
        )

        // Product name + brand
        let prodAlpha = CGFloat(max(0, min(1, (t - 0.7) / 0.6)))
        drawText(
            ctx: ctx,
            text: scan.productName,
            origin: CGPoint(x: width / 2, y: height / 2 + 360),
            fontSize: 48, weight: .semibold,
            color: UIColor(white: 1, alpha: prodAlpha),
            centered: true, maxWidth: CGFloat(width - 120)
        )
        drawText(
            ctx: ctx,
            text: scan.brand.uppercased(),
            origin: CGPoint(x: width / 2, y: height / 2 + 430),
            fontSize: 28, weight: .medium,
            color: UIColor(white: 1, alpha: prodAlpha * 0.7),
            centered: true
        )

        if let img = productImage {
            drawProductThumb(ctx: ctx, image: img, alpha: prodAlpha * 0.85,
                             center: CGPoint(x: width / 2, y: 280))
        }
    }

    private func drawCTAPhase(
        ctx: CGContext, t: Double, scan: ScanResult, productImage: UIImage?
    ) {
        // Hold the score quietly in the background
        let gradeColor = gradeColor(grade: scan.grade)
        drawText(
            ctx: ctx,
            text: scan.grade,
            origin: CGPoint(x: width / 2, y: 620),
            fontSize: 280, weight: .heavy,
            color: gradeColor.withAlphaComponent(0.35),
            centered: true
        )
        drawText(
            ctx: ctx,
            text: scan.productName,
            origin: CGPoint(x: width / 2, y: 900),
            fontSize: 46, weight: .semibold,
            color: UIColor(white: 1, alpha: 0.8),
            centered: true, maxWidth: CGFloat(width - 120)
        )

        // CTA block
        let ctaAlpha = CGFloat(max(0, min(1, t / 0.5)))
        let boxRect = CGRect(x: 120, y: 1180, width: width - 240, height: 320)
        ctx.saveGState()
        ctx.setFillColor(UIColor(red: 0.00, green: 0.72, blue: 0.49, alpha: 0.18 * ctaAlpha).cgColor)
        ctx.setStrokeColor(UIColor(red: 0.00, green: 0.72, blue: 0.49, alpha: 0.85 * ctaAlpha).cgColor)
        ctx.setLineWidth(4)
        let path = UIBezierPath(roundedRect: boxRect, cornerRadius: 36)
        ctx.addPath(path.cgPath)
        ctx.drawPath(using: .fillStroke)
        ctx.restoreGState()

        drawText(
            ctx: ctx,
            text: "SEE THE FULL BREAKDOWN",
            origin: CGPoint(x: width / 2, y: 1250),
            fontSize: 40, weight: .bold,
            color: UIColor(white: 1, alpha: ctaAlpha),
            centered: true
        )
        drawText(
            ctx: ctx,
            text: "revelio://scan/\(scan.barcode)",
            origin: CGPoint(x: width / 2, y: 1330),
            fontSize: 32, weight: .regular,
            color: UIColor(red: 0.36, green: 1.0, blue: 0.74, alpha: ctaAlpha),
            centered: true, monospaced: true
        )
        drawText(
            ctx: ctx,
            text: "Scan it yourself on Revelio",
            origin: CGPoint(x: width / 2, y: 1410),
            fontSize: 28, weight: .regular,
            color: UIColor(white: 1, alpha: ctaAlpha * 0.75),
            centered: true
        )

        if let img = productImage {
            drawProductThumb(ctx: ctx, image: img, alpha: 0.5,
                             center: CGPoint(x: width / 2, y: 300))
        }
    }

    // ── Primitive drawers ────────────────────────────────────────────────────

    private func drawBarcodeBadge(ctx: CGContext, origin: CGPoint, size: CGSize, barcode: String) {
        let rect = CGRect(origin: origin, size: size)
        ctx.saveGState()
        ctx.setFillColor(UIColor(white: 1.0, alpha: 0.96).cgColor)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 28)
        ctx.addPath(path.cgPath)
        ctx.fillPath()
        ctx.restoreGState()

        // Barcode stripes (visual only)
        ctx.saveGState()
        ctx.setFillColor(UIColor.black.cgColor)
        var x = origin.x + 32
        var i = 0
        while x < origin.x + size.width - 32 {
            let w: CGFloat = [2, 3, 4, 6, 2][i % 5]
            ctx.fill(CGRect(x: x, y: origin.y + 28, width: w, height: size.height - 86))
            x += w + 4
            i += 1
        }
        ctx.restoreGState()

        drawText(
            ctx: ctx,
            text: barcode,
            origin: CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height - 30),
            fontSize: 32, weight: .medium,
            color: .black, centered: true, monospaced: true
        )
    }

    private func drawWatermark(ctx: CGContext) {
        let text = "revelio.app"
        drawText(
            ctx: ctx,
            text: text,
            origin: CGPoint(x: width - 40, y: height - 60),
            fontSize: 28, weight: .semibold,
            color: UIColor(white: 1, alpha: 0.7),
            rightAligned: true
        )
    }

    private func drawProductThumb(ctx: CGContext, image: UIImage, alpha: CGFloat, center: CGPoint) {
        guard let cg = image.cgImage else { return }
        let size: CGFloat = 320
        let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        ctx.saveGState()
        ctx.setAlpha(alpha)
        let clip = UIBezierPath(roundedRect: rect, cornerRadius: 32)
        ctx.addPath(clip.cgPath)
        ctx.clip()
        // UIKit draws top-left origin; CGContext here is bottom-left origin. Flip.
        ctx.translateBy(x: 0, y: rect.origin.y * 2 + rect.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cg, in: rect)
        ctx.restoreGState()
    }

    private func drawText(
        ctx: CGContext,
        text: String,
        origin: CGPoint,
        fontSize: CGFloat,
        weight: UIFont.Weight,
        color: UIColor,
        centered: Bool = false,
        rightAligned: Bool = false,
        monospaced: Bool = false,
        maxWidth: CGFloat? = nil
    ) {
        let font: UIFont = monospaced
            ? UIFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
            : UIFont.systemFont(ofSize: fontSize, weight: weight)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let bounds = attr.boundingRect(
            with: CGSize(width: maxWidth ?? CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        var drawOrigin = origin
        if centered {
            drawOrigin.x = origin.x - bounds.width / 2
        } else if rightAligned {
            drawOrigin.x = origin.x - bounds.width
        }
        // CG is bottom-left origin; shift so "origin.y" means a top-ish baseline-ish y.
        drawOrigin.y = CGFloat(height) - origin.y - bounds.height

        UIGraphicsPushContext(ctx)
        if let maxW = maxWidth {
            let rect = CGRect(x: drawOrigin.x, y: drawOrigin.y, width: maxW, height: bounds.height + 10)
            attr.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        } else {
            attr.draw(at: drawOrigin)
        }
        UIGraphicsPopContext()
    }

    private func easeOut(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }

    private func gradeColor(grade: String) -> UIColor {
        switch grade.uppercased() {
        case "A": return UIColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1.0)
        case "B": return UIColor(red: 0.52, green: 0.80, blue: 0.09, alpha: 1.0)
        case "C": return UIColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1.0)
        case "D": return UIColor(red: 0.98, green: 0.45, blue: 0.09, alpha: 1.0)
        default:  return UIColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1.0)
        }
    }

    // ── Pixel buffer extraction ──────────────────────────────────────────────

    private func pixelBufferFromContext(
        _ ctx: CGContext,
        adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) -> CVPixelBuffer? {
        guard let pool = adaptor.pixelBufferPool else { return nil }
        var pb: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        guard status == kCVReturnSuccess, let buffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let dest = CVPixelBufferGetBaseAddress(buffer),
              let src = ctx.data else { return nil }

        let destRow = CVPixelBufferGetBytesPerRow(buffer)
        let srcRow = ctx.bytesPerRow
        let rowBytes = min(destRow, srcRow)
        for y in 0..<height {
            memcpy(
                dest.advanced(by: y * destRow),
                src.advanced(by: y * srcRow),
                rowBytes
            )
        }
        return buffer
    }
}
