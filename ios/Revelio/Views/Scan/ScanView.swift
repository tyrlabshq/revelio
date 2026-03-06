import SwiftUI

struct ScanView: View {
    @StateObject private var viewModel = ScanViewModel()
    @State private var showManualEntry = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("REVELIO")
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .foregroundColor(Theme.accent)
                    Spacer()
                    Button { viewModel.toggleTorch() } label: {
                        Image(systemName: viewModel.torchOn ? "bolt.fill" : "bolt.slash")
                            .foregroundColor(viewModel.torchOn ? Theme.warning : Theme.textSecondary)
                            .font(.system(size: 18))
                    }
                    Button { showManualEntry = true } label: {
                        Image(systemName: "keyboard")
                            .foregroundColor(Theme.textSecondary)
                            .font(.system(size: 18))
                    }
                    .padding(.leading, 12)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                // Main area
                if case .result(let scan) = viewModel.state {
                    ScanResultCard(scan: scan) { viewModel.resetScan() }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    ZStack {
                        BarcodeScannerRepresentable(onBarcode: viewModel.handleBarcode)
                            .ignoresSafeArea()
                        ScanFrameOverlay()
                        if case .loading = viewModel.state {
                            VStack {
                                Spacer()
                                VStack(spacing: 12) {
                                    ProgressView().tint(Theme.accent).scaleEffect(1.5)
                                    Text("Analyzing ingredients...")
                                        .font(.subheadline).foregroundColor(Theme.textSecondary)
                                }
                                .padding(24)
                                .background(Theme.surface.opacity(0.95))
                                .cornerRadius(16)
                                .padding(.bottom, 60)
                            }
                        }
                        if case .error(let msg) = viewModel.state {
                            VStack {
                                Spacer()
                                Text(msg)
                                    .foregroundColor(Theme.danger)
                                    .padding()
                                    .background(Theme.surface.opacity(0.95))
                                    .cornerRadius(12)
                                    .padding(.bottom, 60)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showManualEntry) {
            ManualBarcodeView(onBarcode: viewModel.handleBarcode)
        }
        .animation(.spring(response: 0.4), value: viewModel.stateTag)
    }
}

struct ScanFrameOverlay: View {
    @State private var scanLineY: CGFloat = -110

    var body: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.55)).ignoresSafeArea()
            RoundedRectangle(cornerRadius: 20).frame(width: 270, height: 270)
                .blendMode(.destinationOut)
            RoundedRectangle(cornerRadius: 20)
                .stroke(Theme.accent, lineWidth: 3)
                .frame(width: 270, height: 270)
            Rectangle()
                .fill(Theme.accent.opacity(0.75))
                .frame(width: 250, height: 2)
                .offset(y: scanLineY)
                .onAppear {
                    withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: true)) {
                        scanLineY = 110
                    }
                }
            VStack {
                Spacer()
                Text("Point at a barcode to scan")
                    .font(.caption)
                    .foregroundColor(Theme.textDim)
                    .padding(.bottom, 24)
            }
        }
        .compositingGroup()
    }
}
