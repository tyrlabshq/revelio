import SwiftUI

struct ScanView: View {
    @StateObject private var viewModel = ScanViewModel()
    @State private var showManualEntry = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 0) {
                    HStack {
                        Text("REVELIO")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
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
                    
                    Divider()
                        .background(Color.gray.opacity(0.1))
                }

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
                                        .font(.subheadline)
                                        .foregroundColor(Theme.textSecondary)
                                }
                                .padding(24)
                                .background(Theme.surface.opacity(0.95))
                                .cornerRadius(16)
                                .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
                                .padding(.bottom, 60)
                            }
                        }
                        
                        if case .error(let msg) = viewModel.state {
                            VStack {
                                Spacer()
                                Text(msg)
                                    .font(.subheadline)
                                    .foregroundColor(Theme.danger)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                    .background(Theme.surface.opacity(0.95))
                                    .cornerRadius(12)
                                    .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
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
    @State private var pulseOpacity: Double = 0.3
    let cornerLength: CGFloat = 30
    let frameSize: CGFloat = 260
    let lineWidth: CGFloat = 4
    
    private var screenWidth: CGFloat { UIScreen.main.bounds.width }
    private var screenHeight: CGFloat { UIScreen.main.bounds.height }
    private var frameX: CGFloat { (screenWidth - frameSize) / 2 }
    private var frameY: CGFloat { (screenHeight - frameSize) / 2 + 40 }

    var body: some View {
        ZStack {
            // Dark overlay with cutout
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .mask(
                    Rectangle()
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .frame(width: frameSize, height: frameSize)
                                .blendMode(.destinationOut)
                        )
                )
                .ignoresSafeArea()
            
            // L-shaped corner brackets
            ZStack {
                // Calculate positions
                let leftX = frameX + cornerLength / 2 - 8
                let rightX = frameX + frameSize - cornerLength / 2 + 8
                let topY = frameY + cornerLength / 2
                let bottomY = frameY + frameSize - cornerLength / 2
                
                // Top-left corner
                CornerBracketView(rotation: 0, lineWidth: lineWidth, color: Theme.accent)
                    .frame(width: cornerLength, height: cornerLength)
                    .position(x: leftX, y: topY)
                
                // Top-right corner
                CornerBracketView(rotation: 90, lineWidth: lineWidth, color: Theme.accent)
                    .frame(width: cornerLength, height: cornerLength)
                    .position(x: rightX, y: topY)
                
                // Bottom-right corner
                CornerBracketView(rotation: 180, lineWidth: lineWidth, color: Theme.accent)
                    .frame(width: cornerLength, height: cornerLength)
                    .position(x: rightX, y: bottomY)
                
                // Bottom-left corner
                CornerBracketView(rotation: 270, lineWidth: lineWidth, color: Theme.accent)
                    .frame(width: cornerLength, height: cornerLength)
                    .position(x: leftX, y: bottomY)
            }
            .shadow(color: Theme.accent.opacity(pulseOpacity), radius: 12, x: 0, y: 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulseOpacity = 0.8
                }
            }
            
            // Hint text
            VStack {
                Spacer()
                Text("Tap to scan a barcode")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textDim)
                    .padding(.bottom, 100)
            }
        }
    }
}

// L-shaped corner bracket view
struct CornerBracketView: View {
    let rotation: Double
    let lineWidth: CGFloat
    let color: Color
    
    var body: some View {
        CornerBracketShape()
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .rotationEffect(.degrees(rotation))
    }
}

struct CornerBracketShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cornerRadius: CGFloat = 4
        
        // Start from top-left, go right
        path.move(to: CGPoint(x: 0, y: cornerRadius))
        path.addQuadCurve(to: CGPoint(x: cornerRadius, y: 0),
                          control: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        
        // Go down
        path.addLine(to: CGPoint(x: rect.width, y: cornerRadius))
        path.addQuadCurve(to: CGPoint(x: rect.width - cornerRadius, y: cornerRadius * 2),
                          control: CGPoint(x: rect.width, y: cornerRadius * 2))
        path.addLine(to: CGPoint(x: rect.width - cornerRadius, y: rect.height))
        
        return path
    }
}

#Preview {
    ScanView()
}
