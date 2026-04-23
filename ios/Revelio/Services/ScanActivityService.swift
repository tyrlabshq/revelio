import ActivityKit
import Foundation

/// Owns the single in-progress scan `Activity` lifecycle on behalf of
/// `ScanViewModel`. Call `.start(barcode:)` when the user triggers a
/// scan, `.updateFetching()` when the network request fires,
/// `.finish(grade:productName:)` on success, and `.fail()` on any
/// error. Live Activities are best-effort: if the user has disabled
/// them in Settings, every method no-ops silently.
///
/// We keep a single `Activity` reference in `current` — ActivityKit
/// supports multiple concurrent activities but the UX we want is
/// "one scan at a time", so starting a new one automatically ends the
/// previous.
@MainActor
final class ScanActivityService {
    static let shared = ScanActivityService()
    private init() {}

    private var current: Activity<ScanActivityAttributes>?

    /// `true` if Live Activities are enabled system-wide and permitted
    /// for this app. Checked before every mutation so a later "disable"
    /// in Settings can't strand us mid-activity.
    private var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - Lifecycle

    /// Begin a new Live Activity for `barcode`. Silently no-ops if
    /// activities are disabled or if ActivityKit refuses (e.g. quota
    /// exhausted) — the scan itself must never be blocked by an
    /// ornamental surface.
    func start(barcode: String) {
        guard areActivitiesEnabled else { return }

        // End any stale activity so we only ever have one on screen.
        Task { await endCurrent(finalPhase: nil) }

        let attributes = ScanActivityAttributes()
        let state = ScanActivityAttributes.ContentState(
            phase: .scanning,
            barcode: barcode,
            productName: nil,
            grade: nil
        )
        do {
            let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(90))
            current = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            // Quota, entitlement, or other ActivityKit failure. Drop it —
            // the scan continues uninterrupted.
            current = nil
        }
    }

    /// Advance the activity to the "analyzing" phase once the network
    /// request is in flight. Safe to call even if `start` didn't
    /// succeed.
    func updateFetching() {
        guard areActivitiesEnabled, let current else { return }
        let oldState = current.content.state
        let newState = ScanActivityAttributes.ContentState(
            phase: .fetching,
            barcode: oldState.barcode,
            productName: oldState.productName,
            grade: nil
        )
        Task {
            await current.update(
                ActivityContent(state: newState, staleDate: Date().addingTimeInterval(60))
            )
        }
    }

    /// Terminal success state: we have a grade, show it briefly, then
    /// dismiss. The system keeps the Lock Screen card visible for a
    /// few seconds after `end`, which is what we want.
    func finish(grade: String, productName: String?) {
        guard areActivitiesEnabled, let current else { return }
        let oldState = current.content.state
        let newState = ScanActivityAttributes.ContentState(
            phase: .scored,
            barcode: oldState.barcode,
            productName: productName ?? oldState.productName,
            grade: grade
        )
        Task {
            await current.end(
                ActivityContent(state: newState, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(6))
            )
            self.current = nil
        }
    }

    /// Terminal failure state (404, network error, etc.). Same
    /// dismissal behavior as `finish` but with a muted warning glyph
    /// in the Dynamic Island.
    func fail() {
        guard areActivitiesEnabled, let current else { return }
        let oldState = current.content.state
        let newState = ScanActivityAttributes.ContentState(
            phase: .failed,
            barcode: oldState.barcode,
            productName: oldState.productName,
            grade: nil
        )
        Task {
            await current.end(
                ActivityContent(state: newState, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(3))
            )
            self.current = nil
        }
    }

    // MARK: - Internal

    private func endCurrent(finalPhase: ScanActivityAttributes.ContentState.Phase?) async {
        guard let activity = current else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        current = nil
    }
}
