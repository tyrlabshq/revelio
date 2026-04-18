// ─── ios/Revelio/Views/Share/ScoreVideoShareSheet.swift ──────────────────────
// Track 3.8 — share-as-video sibling of ShareCardSheet.
//
// Renders a 9s vertical MP4 of the scan reveal using ScorecardVideoExporter,
// previews the first frame, and presents UIActivityViewController so the user
// can share to Instagram / TikTok / iMessage / Files.

import SwiftUI
import AVFoundation
import AVKit
import UIKit

// ─── Launcher button used on the scan-result screen ──────────────────────────

struct ShareAsVideoButton: View {
    let scan: ScanResult
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            Label("Share as video", systemImage: "play.rectangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Theme.accent, Theme.accent.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(12)
        }
        .sheet(isPresented: $showSheet) {
            ScoreVideoShareSheet(scan: scan)
        }
    }
}

// ─── Sheet: render → preview → share ─────────────────────────────────────────

struct ScoreVideoShareSheet: View {
    let scan: ScanResult

    @State private var videoURL: URL? = nil
    @State private var isRendering = true
    @State private var renderError: String? = nil
    @State private var showActivity = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // Preview
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.black)
                            .aspectRatio(9.0 / 16.0, contentMode: .fit)
                            .overlay {
                                if let url = videoURL {
                                    VideoPlayerView(url: url)
                                        .clipShape(RoundedRectangle(cornerRadius: 18))
                                } else if let err = renderError {
                                    VStack(spacing: 10) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(Theme.warning)
                                        Text(err)
                                            .font(Theme.fontCaption)
                                            .foregroundColor(.white)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 16)
                                    }
                                } else if isRendering {
                                    VStack(spacing: 12) {
                                        ProgressView().tint(.white)
                                        Text("Rendering 9-second scorecard…")
                                            .font(Theme.fontCaption)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                            }
                            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                    }
                    .frame(maxWidth: 260)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // Meta
                    VStack(spacing: 6) {
                        Text(scan.productName)
                            .font(Theme.fontHeadline)
                            .foregroundColor(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        Text("1080 × 1920 · 30fps · ~9s · MP4")
                            .font(Theme.fontCaption)
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding(.horizontal, 20)

                    // Actions
                    VStack(spacing: 12) {
                        Button {
                            showActivity = true
                        } label: {
                            Label("Share to Instagram / TikTok / iMessage",
                                  systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.accent)
                                .cornerRadius(12)
                        }
                        .disabled(videoURL == nil)
                        .opacity(videoURL == nil ? 0.5 : 1.0)

                        Button {
                            Task { await render() }
                        } label: {
                            Label("Re-render", systemImage: "arrow.clockwise")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Theme.surfaceElevated)
                                .cornerRadius(10)
                        }
                        .disabled(isRendering)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .background(Theme.background)
            .navigationTitle("Share as Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
            .sheet(isPresented: $showActivity) {
                if let url = videoURL {
                    ActivityShareSheet(items: [
                        url,
                        "I scanned \(scan.productName) on Revelio and got a \(scan.grade). revelio://scan/\(scan.barcode)"
                    ])
                }
            }
        }
        .onAppear {
            if videoURL == nil { Task { await render() } }
        }
    }

    // ── Render ───────────────────────────────────────────────────────────────

    @MainActor
    private func render() async {
        isRendering = true
        renderError = nil
        videoURL = nil
        do {
            let url = try await ScorecardVideoExporter.shared.export(scan: scan)
            videoURL = url
        } catch {
            renderError = "Could not render: \(error.localizedDescription)"
        }
        isRendering = false
    }
}

// ─── Looping video preview ───────────────────────────────────────────────────

struct VideoPlayerView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = false
        vc.videoGravity = .resizeAspect
        vc.view.backgroundColor = .black
        player.isMuted = true
        player.play()
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
