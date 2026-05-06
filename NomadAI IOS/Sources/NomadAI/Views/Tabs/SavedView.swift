//
//  SavedView.swift
//  Tab 4 — Timeline route planner + Passport.
//
//  Spec: docs/screen-inventory.md §4, redesign HTML lines 1811–1931.
//

import SwiftUI
import SwiftData

struct SavedView: View {
    enum Mode: String, CaseIterable { case route, all, passport
        var label: String {
            switch self {
            case .route: return "Route"
            case .all: return "All saved"
            case .passport: return "Passport"
            }
        }
    }

    @State private var mode: Mode = .route
    @Query private var trips: [Trip]
    @Query private var saved: [Campsite]      // SwiftData filtering: where isSaved == true happens at usage site

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Topbar
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved").monoLabel()
                    FrauncesEmphasis(prefix: "Your ", italic: "pins", suffix: "", size: 22)
                }
                .padding(.horizontal, Spacing.pageHorizontal)
                .padding(.top, 18)

                FrauncesEmphasis(prefix: "The ", italic: "long way", suffix: " — your draft", size: 28)
                    .foregroundStyle(.fg)
                    .padding(.horizontal, Spacing.pageHorizontal)

                // Mode tabs
                ModeTabs(mode: $mode)
                    .padding(.horizontal, Spacing.pageHorizontal)

                Group {
                    switch mode {
                    case .route:    RouteTimelineStub()
                    case .all:      AllSavedStub(saved: saved.filter(\.isSaved))
                    case .passport: PassportStub()
                    }
                }
                .padding(.horizontal, Spacing.pageHorizontal)

                Spacer(minLength: 100)
            }
        }
        .background(Color.bg)
    }
}

private struct ModeTabs: View {
    @Binding var mode: SavedView.Mode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SavedView.Mode.allCases, id: \.self) { m in
                Button { mode = m } label: {
                    Text(m.label)
                        .font(.body(12, weight: .semibold))
                        .foregroundStyle(mode == m ? Color.fg : Color.muted)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(mode == m ? Color.clay : Color.clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

// MARK: - Stubs (TODO: build out per docs/screen-inventory.md)

private struct RouteTimelineStub: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "list.bullet.indent").font(.system(size: 32, weight: .light))
                .foregroundStyle(.clay)
            Text("Build the timeline planner here").font(.frauncesCard(16))
            Text("See docs/screen-inventory.md §4 for the spec.")
                .font(.body(12)).foregroundStyle(.muted)
        }
        .frame(maxWidth: .infinity).padding(40)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.bark))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.line, lineWidth: 1))
    }
}

private struct AllSavedStub: View {
    let saved: [Campsite]
    var body: some View {
        if saved.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "bookmark").font(.system(size: 32, weight: .light)).foregroundStyle(.muted)
                Text("No saved campsites yet").font(.body(14)).foregroundStyle(.muted)
                Text("Search and tap save to start collecting.").font(.body(12)).foregroundStyle(.faint)
            }
            .frame(maxWidth: .infinity).padding(40)
        } else {
            VStack(spacing: 14) {
                ForEach(saved) { c in
                    CampsiteCard(campsite: c)
                }
            }
        }
    }
}

private struct PassportStub: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cover
            VStack(alignment: .leading, spacing: 6) {
                Text("NomadAI · Field Passport")
                    .font(.mono(10, weight: .semibold))
                    .tracking(2.0)
                    .textCase(.uppercase)
                    .foregroundStyle(Color(red: 0.91, green: 0.86, blue: 0.75).opacity(0.6))
                Text("Book No. 01")
                    .font(.frauncesNumeral(30))
                    .foregroundStyle(Color(red: 0.91, green: 0.86, blue: 0.75))
                Text("0 stamps · 0 states · 0 trips")
                    .font(.body(12))
                    .foregroundStyle(Color(red: 0.91, green: 0.86, blue: 0.75).opacity(0.8))
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.35, green: 0.24, blue: 0.16),
                             Color(red: 0.43, green: 0.29, blue: 0.18)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .inset(by: 6)
                    .strokeBorder(Color(red: 0.91, green: 0.86, blue: 0.75).opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadowMd()

            Text("Stamp grid goes here — see docs/screen-inventory.md").font(.body(12)).foregroundStyle(.muted)
        }
    }
}

#Preview {
    SavedView().preferredColorScheme(.dark).modelContainer(for: [Trip.self, TripStop.self, Campsite.self, CompletedTrip.self, Profile.self], inMemory: true)
}
