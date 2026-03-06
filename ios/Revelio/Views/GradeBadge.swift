import SwiftUI

struct GradeBadge: View {
    let grade: String
    let score: Int
    enum BadgeSize { case small, large }
    var size: BadgeSize = .small

    var diameter: CGFloat { size == .large ? 80 : 48 }
    var gradeFontSize: CGFloat { size == .large ? 32 : 20 }

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.gradeColor(grade).opacity(0.15))
                .overlay(Circle().stroke(Theme.gradeColor(grade), lineWidth: 2.5))
                .frame(width: diameter, height: diameter)
            VStack(spacing: 0) {
                Text(grade)
                    .font(.system(size: gradeFontSize, weight: .black, design: .rounded))
                    .foregroundColor(Theme.gradeColor(grade))
                if size == .large {
                    Text("\(score)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.gradeColor(grade).opacity(0.8))
                }
            }
        }
    }
}
