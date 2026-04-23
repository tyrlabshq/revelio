import Foundation
import UIKit

/// Centralized haptic feedback for Revelio.
///
/// The most important trigger is the grade reveal on a scan result — we map
/// each grade to a distinct haptic so repeat users build an association
/// between the *feel* and the *outcome* before they've even looked at the
/// screen. A/B feels good (success), C feels neutral (impact), D feels
/// cautionary (warning), F feels wrong (error).
///
/// All methods respect `UIAccessibility.isReduceMotionEnabled` and no-op when
/// the user has asked the OS to cut down on motion/haptics. The grade-reveal
/// helper in particular is designed to be called at most once per scan — the
/// caller should gate it with a `@State var didHaptic = false` check against
/// `.onAppear`.
final class HapticsService {
    static let shared = HapticsService()

    private init() {}

    /// True when the system has Reduce Motion enabled. We treat it as a global
    /// "no haptics" switch because vestibular-sensitive users often disable
    /// both motion and haptics together, and Apple ties haptic preferences to
    /// accessibility settings for system feedback generators.
    private var shouldSuppress: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    /// Fire the haptic that matches the grade reveal on a scan result.
    ///
    /// - Parameter grade: A single letter — "A", "B", "C", "D", or "F". Unknown
    ///   grades are treated as F so we still communicate "something is off".
    func gradeReveal(_ grade: String) {
        guard !shouldSuppress else { return }

        let normalized = grade.uppercased()
        switch normalized {
        case "A", "B":
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        case "C":
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
        case "D":
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.warning)
        default:
            // F or unknown — strongest negative feedback.
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.error)
        }
    }
}
