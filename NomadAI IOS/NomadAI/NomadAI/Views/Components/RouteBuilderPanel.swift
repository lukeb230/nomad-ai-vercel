//
//  RouteBuilderPanel.swift
//  Inline panel that appears in the AI chat above the chat scroll while a
//  route is being built. Shows the user's route description, a count of
//  selected stops, instructional copy, and a "Build route" CTA that creates
//  the Trip and navigates to Saved → Route mode.
//

import SwiftUI
import SwiftData

struct RouteBuilderPanel: View {
    /// Caller fires this when the user taps "More options" — typically wired
    /// to SearchView's sendQuery with a refresh-prompt synthesized in place.
    /// Optional so previews / standalone usage still work.
    var onMoreOptions: (() -> Void)? = nil

    @State private var state = RouteBuilderState.shared
    @Environment(\.modelContext) private var ctx

    var body: some View {
        if state.isActive {
            VStack(alignment: .leading, spacing: 10) {
                header
                summary
                actions
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.clay.opacity(0.5), lineWidth: 1))
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "location.north")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.clay)
            Text("ROUTE BUILDER").monoLabel()
                .foregroundStyle(Color.clay)
            Spacer(minLength: 0)
            Button { state.cancel() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.muted)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel route")
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.routeDescription)
                .font(.frauncesCard(15))
                .foregroundStyle(.fg)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(instructionalCopy)
                .font(.body(12))
                .foregroundStyle(.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(stopBadgeText)
                    .font(.mono(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.muted)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.bark))
                    .overlay(Capsule().strokeBorder(Color.line, lineWidth: 1))

                Spacer(minLength: 0)

                Button { build() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                        Text("Build route")
                    }
                    .font(.body(13, weight: .bold))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .foregroundStyle(state.stopCount > 0 ? Color.clayInk : Color.muted)
                    .background(Capsule().fill(state.stopCount > 0 ? Color.clay : Color.bark))
                    .overlay(Capsule().strokeBorder(Color.line.opacity(state.stopCount > 0 ? 0 : 1), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(state.stopCount == 0)
            }

            if let onMoreOptions {
                Button(action: onMoreOptions) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Show more options")
                            .font(.body(12, weight: .semibold))
                    }
                    .foregroundStyle(.fgDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.bark))
                    .overlay(Capsule().strokeBorder(Color.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show more candidate stops")
            }
        }
    }

    private var instructionalCopy: String {
        if state.stopCount == 0 {
            return "Tap \u{201C}Add to route\u{201D} on the cards below to pick stops, then come back here and tap Build route."
        }
        return "Add more stops below if you want, then tap Build route to drop them into the Saved tab."
    }

    private var stopBadgeText: String {
        let n = state.stopCount
        if n == 0 { return "0 STOPS — PICK FROM CARDS" }
        return "\(n) STOP\(n == 1 ? "" : "S") SELECTED"
    }

    private func build() {
        guard state.stopCount > 0 else { return }
        if state.build(in: ctx) != nil {
            // Navigate to Saved → Route. Saved view defaults to Route mode for
            // first-time users; if the user changed it earlier in this session
            // they'll be on whatever they last picked, but the new trip will be
            // visible there regardless.
            AppNavigationState.shared.selectedTab = .saved
        }
    }
}
