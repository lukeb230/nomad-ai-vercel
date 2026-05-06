//
//  HomeView.swift
//  Tab 1 — Editorial dashboard.
//
//  Spec: docs/screen-inventory.md §1, redesign HTML lines 1393–1592.
//

import SwiftUI

struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Topbar()
                EditorialHero()
                SectionLabel("Current trip")
                TripHeroCardEmpty()      // TODO: replace with real Trip when available
                SectionLabel("Your stats")
                StatsStrip(visited: 0, trips: 0, states: 0)
                SectionLabel("Camp journal · Field notes")
                JournalEmpty()
                Spacer(minLength: 100)   // bottom-nav safe area
            }
            .padding(.horizontal, Spacing.pageHorizontal)
            .padding(.top, 8)
        }
        .background(Color.bg)
    }
}

// MARK: - Topbar

private struct Topbar: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                FrauncesEmphasis(prefix: "Nomad", italic: "AI", suffix: "", size: 22)
                Text("Field journal").monoLabel()
            }
            Spacer()
            HStack(spacing: 8) {
                IconButton(systemName: "gearshape") { /* openSettings */ }
                Button {
                    /* openProfile or auth */
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(LinearGradient(colors: [.clay, .rust], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 22, height: 22)
                            .overlay(Image(systemName: "person.fill").font(.system(size: 11)).foregroundStyle(Color.clayInk))
                        Text("Sign in").font(.body(11, weight: .semibold)).foregroundStyle(.fgDim)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 4).padding(.leading, 6)
                    .background(Capsule().fill(Color.bark))
                    .overlay(Capsule().strokeBorder(Color.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct EditorialHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Color.clay).frame(width: 6, height: 6)
                    .overlay(Circle().strokeBorder(Color.clay.opacity(0.2), lineWidth: 3))
                Text("Welcome back").monoLabel()
            }
            FrauncesEmphasis(prefix: "Where to, ", italic: "this weekend", suffix: "?", size: 36)
                .foregroundStyle(.fg)
            Text("Plain English. Route queries, vibe queries, beginner questions — all ok.")
                .font(.body(14))
                .foregroundStyle(.muted)
                .lineLimit(nil)
        }
    }
}

// MARK: - Trip Hero (empty state)

private struct TripHeroCardEmpty: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.clay)
            Text("No trip on the road").font(.frauncesCard(18)).foregroundStyle(.fg)
            Text("Add stops to your route planner and they'll show up here.")
                .font(.body(13)).foregroundStyle(.muted)
                .multilineTextAlignment(.center)
            Button {
                /* TODO switch to Saved, open route planner */
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "location.north")
                    Text("Start a trip")
                }
                .font(.body(13, weight: .bold))
                .padding(.horizontal, 22).padding(.vertical, 12)
                .foregroundStyle(Color.clayInk)
                .background(Capsule().fill(Color.clay))
                .shadow(color: Color.clay.opacity(0.25), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.bark))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.line, lineWidth: 1))
        .shadowMd()
    }
}

// MARK: - Stats Strip

private struct StatsStrip: View {
    let visited: Int
    let trips: Int
    let states: Int

    var body: some View {
        HStack(spacing: 10) {
            StatCard(value: visited, label: "Visited")
            StatCard(value: trips, label: "Trips")
            StatCard(value: states, label: "States")
        }
    }
}

private struct StatCard: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(value)").font(.frauncesNumeral(28)).foregroundStyle(.fg)
            Text(label).monoLabel()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.bark))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.line, lineWidth: 1))
    }
}

private struct JournalEmpty: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("✓ Mark campsites as visited to start your journal.")
                .font(.body(13)).foregroundStyle(.muted)
            Text("Tap the ✓ button on any card.")
                .font(.body(12, weight: .semibold)).foregroundStyle(.clay)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.vertical, 24)
    }
}

// MARK: - Helpers

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).monoLabel() }
}

struct IconButton: View {
    let systemName: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .light))
                .frame(width: 38, height: 38)
                .foregroundStyle(.fgDim)
                .background(Circle().fill(Color.bark))
                .overlay(Circle().strokeBorder(Color.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HomeView().preferredColorScheme(.dark)
}
