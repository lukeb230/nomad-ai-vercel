//
//  SearchView.swift
//  Tab 2 — AI-as-hero search.
//
//  Spec: docs/screen-inventory.md §2, redesign HTML lines 1595–1736.
//

import SwiftUI

struct SearchView: View {
    enum Mode { case askAI, location }
    @State private var mode: Mode = .askAI
    @State private var query: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Topbar
                VStack(alignment: .leading, spacing: 4) {
                    Text("Search").monoLabel()
                    FrauncesEmphasis(prefix: "Find your ", italic: "spot", suffix: "", size: 22)
                }
                .padding(.top, 18)

                // Hero
                VStack(alignment: .leading, spacing: 6) {
                    Text("★ Ask freely").monoLabel()
                    Text("Plain English. Route queries, vibe queries, beginner questions — all ok.")
                        .font(.body(13)).foregroundStyle(.muted)
                }

                // Mode toggle pill
                HStack(spacing: 2) {
                    ModeButton(label: "Ask AI", system: "sparkle", active: mode == .askAI) { mode = .askAI }
                    ModeButton(label: "Location", system: "location", active: mode == .location) { mode = .location }
                }
                .padding(4)
                .background(Capsule().fill(Color.bark))
                .overlay(Capsule().strokeBorder(Color.line, lineWidth: 1))

                // Mode-specific panel
                Group {
                    switch mode {
                    case .askAI:    AIChatPanel(query: $query)
                    case .location: LocationPanel()
                    }
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, Spacing.pageHorizontal)
        }
        .background(Color.bg)
    }
}

private struct ModeButton: View {
    let label: String
    let system: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: system).font(.system(size: 12, weight: .regular))
                Text(label).font(.body(12, weight: .semibold))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(active ? Color.clayInk : Color.muted)
            .background(Capsule().fill(active ? Color.clay : Color.clear))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AI Chat panel (stub)

struct AIChatPanel: View {
    @Binding var query: String

    var body: some View {
        VStack(spacing: 0) {
            // Chat scroll area placeholder
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ChatBubble(role: .ai, text: "Tell me what you're looking for. I'll search every source and build a list.")
                }
                .padding(16)
            }
            .frame(minHeight: 360)

            Divider().background(Color.line)

            // Input bar
            HStack(spacing: 8) {
                TextField("Ask about campsites…", text: $query, axis: .vertical)
                    .font(.body(14))
                    .lineLimit(1...4)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.surface))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.line, lineWidth: 1))

                Button {
                    /* mic */
                } label: {
                    Image(systemName: "mic")
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.fgDim)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.surface))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.line, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    sendQuery()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Color.clayInk)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.clay))
                        .shadow(color: Color.clay.opacity(0.25), radius: 12, y: 4)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.bark)
        }
        .background(Color.bark)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.line, lineWidth: 1))
        .shadowSm()
    }

    private func sendQuery() {
        // TODO: classify, build prompt, call ClaudeService.
        // See docs/business-logic.md sections 1-4.
    }
}

struct ChatBubble: View {
    enum Role { case user, ai }
    let role: Role
    let text: String

    var body: some View {
        HStack {
            if role == .user { Spacer(minLength: 60) }
            Text(text)
                .font(.body(14))
                .foregroundStyle(role == .user ? Color.clayInk : Color.fg)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(role == .user ? Color.clay : Color.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(role == .ai ? Color.line : Color.clear, lineWidth: 1)
                )
            if role == .ai { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Location panel (stub)

struct LocationPanel: View {
    @State private var input: String = ""
    @State private var radius: Int = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.muted)
                TextField("City, park, or highway…", text: $input)
                    .font(.body(14))
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.bark))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.line, lineWidth: 1))

            // TODO: filter chip rows (Type / Sources / Radius)

            Button {
                /* search */
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Search the field").font(.body(14, weight: .bold))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .foregroundStyle(Color.clayInk)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.clay))
                .shadow(color: Color.clay.opacity(0.3), radius: 16, y: 6)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    SearchView().preferredColorScheme(.dark)
}
