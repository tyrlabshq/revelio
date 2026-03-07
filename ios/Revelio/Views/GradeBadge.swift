import SwiftUI

struct GradeBadge: View {
    let grade: String
    let score: Int
    enum Size { case small, large, xlarge }
    var size: Size = .small
    
    @State private var animatedScore: Double = 0
    @State private var ringProgress: CGFloat = 0

    private var diameter: CGFloat {
        switch size {
        case .small: return 52
        case .large: return 80
        case .xlarge: return 100
        }
    }
    
    private var ringThickness: CGFloat {
        switch size {
        case .small: return 5
        case .large: return 7
        case .xlarge: return 8
        }
    }
    
    private var scoreFontSize: CGFloat {
        switch size {
        case .small: return 14
        case .large: return 22
        case .xlarge: return 28
        }
    }
    
    private var gradeFontSize: CGFloat {
        switch size {
        case .small: return 10
        case .large: return 12
        case .xlarge: return 14
        }
    }
    
    private var ringColor: Color {
        Theme.gradeColor(grade)
    }

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Theme.surfaceElevated, lineWidth: ringThickness)
            
            // Animated progress ring
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: ringThickness, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8), value: ringProgress)
            
            // Center content
            VStack(spacing: 1) {
                Text("\(Int(animatedScore))")
                    .font(.system(size: scoreFontSize, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                    .animation(.easeOut(duration: 0.6), value: animatedScore)
                
                Text(grade)
                    .font(.system(size: gradeFontSize, weight: .black, design: .rounded))
                    .foregroundColor(ringColor)
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            // Animate the ring and score
            ringProgress = CGFloat(score) / 100.0
            withAnimation(.easeOut(duration: 0.8)) {
                animatedScore = Double(score)
            }
        }
        .onChange(of: score) { _, newScore in
            ringProgress = CGFloat(newScore) / 100.0
            withAnimation(.easeOut(duration: 0.6)) {
                animatedScore = Double(newScore)
            }
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        GradeBadge(grade: "A", score: 92, size: .small)
        GradeBadge(grade: "B", score: 75, size: .large)
        GradeBadge(grade: "C", score: 58, size: .xlarge)
    }
    .padding()
    .background(Theme.background)
}
