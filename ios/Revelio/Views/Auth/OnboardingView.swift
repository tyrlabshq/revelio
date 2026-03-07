import SwiftUI

struct OnboardingView: View {
    @State private var currentSlide = 0

    private let slides: [OnboardingSlide] = [
        OnboardingSlide(
            icon: "barcode.viewfinder",
            iconColor: Theme.accent,
            title: "Know what's in your food",
            subtitle: "Scan any barcode and get an instant ingredient analysis with science-backed safety grades.",
            glowColor: Theme.accent.opacity(0.12)
        ),
        OnboardingSlide(
            icon: "atom",
            iconColor: Theme.warning,
            title: "Understand every ingredient",
            subtitle: "We flag hidden nasties — preservatives, additives, allergens — explained in plain English.",
            glowColor: Theme.warning.opacity(0.12)
        ),
        OnboardingSlide(
            icon: "checkmark.seal.fill",
            iconColor: Theme.success,
            title: "Make healthier choices",
            subtitle: "Every product gets a letter grade. See the A-rated alternatives side by side.",
            glowColor: Theme.success.opacity(0.12)
        ),
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Slides
                TabView(selection: $currentSlide) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                        SlideView(slide: slide)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentSlide)

                // Page dots
                HStack(spacing: 8) {
                    ForEach(0..<slides.count, id: \.self) { index in
                        Capsule()
                            .fill(index == currentSlide ? Theme.accent : Theme.textDim)
                            .frame(width: index == currentSlide ? 20 : 8, height: 8)
                            .animation(.spring(response: 0.3), value: currentSlide)
                    }
                }
                .padding(.top, 8)

                Spacer().frame(height: 48)

                // CTA Button
                Button {
                    if currentSlide < slides.count - 1 {
                        withAnimation { currentSlide += 1 }
                    }
                    // On last slide, button does nothing - user proceeds to ContentView
                } label: {
                    HStack {
                        Text(currentSlide < slides.count - 1 ? "Next" : "Get Started")
                            .font(.headline)
                            .fontWeight(.semibold)
                        if currentSlide == slides.count - 1 {
                            Image(systemName: "arrow.right")
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 32)

                // Skip
                if currentSlide < slides.count - 1 {
                    Button("Skip") {
                        // No-op: user is already authenticated
                    }
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.top, 16)
                }

                Spacer().frame(height: 48)
            }
        }
    }
}

// ─── Slide Data ───────────────────────────────────────────────────────────────

struct OnboardingSlide {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let glowColor: Color
}

// ─── Slide View ───────────────────────────────────────────────────────────────

private struct SlideView: View {
    let slide: OnboardingSlide

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon with glow using solid color circle
            ZStack {
                Circle()
                    .fill(slide.glowColor)
                    .frame(width: 200, height: 200)

                Image(systemName: slide.icon)
                    .font(.system(size: 72, weight: .light))
                    .foregroundColor(slide.iconColor)
            }

            // Mock UI card (slide-specific)
            SlideIllustration(slide: slide)
                .frame(height: 140)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                Text(slide.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(slide.subtitle)
                    .font(.body)
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}

// ─── Slide Illustration ───────────────────────────────────────────────────────

private struct SlideIllustration: View {
    let slide: OnboardingSlide

    var body: some View {
        switch slide.icon {
        case "barcode.viewfinder":
            // Scanner mockup
            ScannerMockup()
        case "atom":
            // Science card mockup
            ScienceCardMockup()
        default:
            // Grade badge examples
            GradeBadgeMockup()
        }
    }
}

private struct ScannerMockup: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Theme.surface)
            .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
            .overlay {
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        ForEach(["🥛", "🍫", "🥗", "🧴"], id: \.self) { emoji in
                            Text(emoji)
                                .font(.title)
                                .padding(8)
                                .background(Theme.surfaceElevated)
                                .cornerRadius(8)
                        }
                    }
                    Text("Tap to scan any product")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
            }
    }
}

private struct ScienceCardMockup: View {
    private let ingredients = [("High Fructose Corn Syrup", "AVOID", Color(hex: "ef4444")),
                                ("Natural Flavors", "WATCH", Color(hex: "f59e0b")),
                                ("Vitamin C", "FINE", Color(hex: "22c55e"))]
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Theme.surface)
            .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
            .overlay {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(ingredients, id: \.0) { name, label, color in
                        HStack {
                            Circle().fill(color).frame(width: 8, height: 8)
                            Text(name).font(.caption).foregroundColor(Theme.textPrimary)
                            Spacer()
                            Text(label)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(color.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(16)
            }
    }
}

private struct GradeBadgeMockup: View {
    private let grades = [("Organic Valley", "A", "22c55e"),
                           ("Chobani", "B", "84cc16"),
                           ("Yoplait", "C", "f59e0b")]
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Theme.surface)
            .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
            .overlay {
                HStack(spacing: 12) {
                    ForEach(grades, id: \.0) { name, grade, hex in
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: hex).opacity(0.2))
                                    .frame(width: 44, height: 44)
                                Text(grade)
                                    .font(.title2.bold())
                                    .foregroundColor(Color(hex: hex))
                            }
                            Text(name)
                                .font(.caption2)
                                .foregroundColor(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
            }
    }
}
