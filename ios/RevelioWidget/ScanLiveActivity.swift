import ActivityKit
import SwiftUI
import WidgetKit

// Grade color helper duplicated from the main app — the widget bundle
// doesn't link against the app target's sources, and the palette is
// small enough that a separate copy beats a shared module dependency.
private func gradeColor(_ grade: String) -> Color {
    switch grade {
    case "A": return Color(red: 0.13, green: 0.77, blue: 0.37)
    case "B": return Color(red: 0.52, green: 0.80, blue: 0.09)
    case "C": return Color(red: 0.96, green: 0.62, blue: 0.04)
    case "D": return Color(red: 0.98, green: 0.45, blue: 0.09)
    case "-": return Color.secondary
    default:  return Color(red: 0.94, green: 0.27, blue: 0.27)
    }
}

/// Live Activity + Dynamic Island configuration for in-progress scans.
/// One `Widget` drives three presentations:
///   • Lock Screen banner       — `content:` closure
///   • Compact Dynamic Island   — `compactLeading` / `compactTrailing` / `minimal`
///   • Expanded Dynamic Island  — `DynamicIslandExpandedRegion`s
///
/// The main app's `ScanActivityService` starts / updates / ends the
/// Activity; this file is purely presentation. State → visual mapping:
/// scanning/fetching → spinner + barcode; scored → grade pill; failed
/// → muted warning.
struct ScanLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScanActivityAttributes.self) { context in
            lockScreenView(state: context.state)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    leadingExpanded(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    trailingExpanded(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    bottomExpanded(state: context.state)
                }
            } compactLeading: {
                compactLeading(state: context.state)
            } compactTrailing: {
                compactTrailing(state: context.state)
            } minimal: {
                minimalView(state: context.state)
            }
            .widgetURL(URL(string: "revelio://scan"))
            .keylineTint(gradeColor(context.state.grade ?? "-"))
        }
    }

    // MARK: - Lock Screen

    @ViewBuilder
    private func lockScreenView(state: ScanActivityAttributes.ContentState) -> some View {
        HStack(spacing: 12) {
            phaseIcon(state: state)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(phaseTitle(state.phase))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Text(state.productName ?? state.barcode)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if state.phase == .scored, let grade = state.grade {
                Text(grade)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(gradeColor(grade)))
            }
        }
    }

    // MARK: - Dynamic Island — compact

    @ViewBuilder
    private func compactLeading(state: ScanActivityAttributes.ContentState) -> some View {
        Image(systemName: "barcode.viewfinder")
            .foregroundColor(.white)
    }

    @ViewBuilder
    private func compactTrailing(state: ScanActivityAttributes.ContentState) -> some View {
        switch state.phase {
        case .scored:
            Text(state.grade ?? "-")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundColor(gradeColor(state.grade ?? "-"))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        default:
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
        }
    }

    @ViewBuilder
    private func minimalView(state: ScanActivityAttributes.ContentState) -> some View {
        switch state.phase {
        case .scored:
            Text(state.grade ?? "-")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(gradeColor(state.grade ?? "-"))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        default:
            ProgressView().progressViewStyle(.circular).tint(.white)
        }
    }

    // MARK: - Dynamic Island — expanded

    @ViewBuilder
    private func leadingExpanded(state: ScanActivityAttributes.ContentState) -> some View {
        HStack(spacing: 8) {
            phaseIcon(state: state)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Revelio")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                Text(phaseTitle(state.phase))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }

    @ViewBuilder
    private func trailingExpanded(state: ScanActivityAttributes.ContentState) -> some View {
        if state.phase == .scored, let grade = state.grade {
            Text(grade)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(gradeColor(grade)))
        } else if state.phase == .failed {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundColor(.orange)
        } else {
            ProgressView().progressViewStyle(.circular).tint(.white)
        }
    }

    @ViewBuilder
    private func bottomExpanded(state: ScanActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let name = state.productName {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            Text(state.barcode)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Shared helpers

    @ViewBuilder
    private func phaseIcon(state: ScanActivityAttributes.ContentState) -> some View {
        switch state.phase {
        case .scanning:
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
        case .fetching:
            ProgressView().progressViewStyle(.circular).tint(.white)
        case .scored:
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.orange)
        }
    }

    private func phaseTitle(_ phase: ScanActivityAttributes.ContentState.Phase) -> String {
        switch phase {
        case .scanning: return "Scanning…"
        case .fetching: return "Analyzing…"
        case .scored:   return "Score ready"
        case .failed:   return "Couldn't score"
        }
    }
}
