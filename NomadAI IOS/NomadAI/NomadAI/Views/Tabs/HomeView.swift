//
//  HomeView.swift
//  Tab 1 — Editorial dashboard.
//
//  Spec: docs/screen-inventory.md §1, redesign HTML lines 1393–1592.
//
//  Currently rendered with mock data from Models/MockData.swift so we can
//  validate the design system. Wire to real SwiftData / network when ready.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @State private var showingSettings = false
    @State private var showingSignIn = false

    @Query(filter: #Predicate<Trip> { $0.completedAt == nil },
           sort: \Trip.startedAt, order: .reverse)
    private var activeTrips: [Trip]

    /// Trip rendered in the hero card. ONLY the user-pinned active trip — no
    /// implicit fallback. If the user has trips but hasn't pinned one, Home
    /// shows the empty card prompting them to pin one in Saved.
    private var displayedTrip: Trip? {
        activeTrips.first(where: { $0.isActive })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Topbar(showingSettings: $showingSettings, showingSignIn: $showingSignIn)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                EditorialHero()
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 14)

                if let trip = displayedTrip, !trip.sortedStops.isEmpty {
                    TripHeroCard(trip: trip)
                        .padding(.horizontal, 16)
                } else if !activeTrips.isEmpty {
                    EmptyTripCard(
                        title: "No active trip set",
                        message: "You have \(activeTrips.count) trip\(activeTrips.count == 1 ? "" : "s") in Saved. Tap the star on one to pin it as your active trip — it'll show up here.",
                        buttonLabel: "Open Saved"
                    )
                    .padding(.horizontal, 16)
                } else {
                    EmptyTripCard()
                        .padding(.horizontal, 16)
                }

                StatStrip(stats: .sample)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)

                SectionHeader(eyebrow: "Field notes", title: "Camp journal", more: "All entries")
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 4)

                JournalList(entries: MockJournalEntry.samples)
                    .padding(.horizontal, 16)

                SectionHeader(eyebrow: "Shortcuts", title: "Before you air down")
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 12)

                QuickActionGrid()
                    .padding(.horizontal, 16)

                Spacer(minLength: 100)  // bottom-nav clearance
            }
        }
        .background(Color.bg)
        .sheet(isPresented: $showingSettings) {
            SettingsSheet().presentationDetents([.large])
        }
        .sheet(isPresented: $showingSignIn) {
            SignInSheet()
        }
    }
}

// MARK: - Empty trip card

private struct EmptyTripCard: View {
    var title: String = "No active trip"
    var message: String = "Plan one in Saved → Route, or tap Trip on a campsite to start."
    var buttonLabel: String = "Open Saved"

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "map")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.muted)
            Text(title)
                .font(.frauncesTitle(20))
                .foregroundStyle(.fg)
            Text(message)
                .font(.body(12))
                .foregroundStyle(.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                AppNavigationState.shared.selectedTab = .saved
            } label: {
                Text(buttonLabel)
                    .font(.body(12, weight: .bold))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .foregroundStyle(Color.clayInk)
                    .background(Capsule().fill(Color.clay))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(Color.bark)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.line, lineWidth: 1)
        )
        .shadowSm()
    }
}

// MARK: - Topbar

private struct Topbar: View {
    @Binding var showingSettings: Bool
    @Binding var showingSignIn: Bool
    @State private var auth = AuthState.shared

    var body: some View {
        HStack(alignment: .center) {
            BrandMark(caption: "Field journal")
            Spacer()
            HStack(spacing: 8) {
                IconButton(systemName: "gearshape") { showingSettings = true }
                    .accessibilityLabel("Settings")

                Button {
                    if auth.isSignedIn {
                        showingSettings = true
                    } else {
                        showingSignIn = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(colors: [.clay, .rust],
                                                   startPoint: .topLeading,
                                                   endPoint: .bottomTrailing)
                                )
                                .frame(width: 22, height: 22)
                            if auth.isSignedIn {
                                Text(initial(from: auth.email))
                                    .font(.mono(10, weight: .bold))
                                    .foregroundStyle(Color.clayInk)
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.clayInk)
                            }
                        }
                        Text(auth.isSignedIn ? "Account" : "Sign in")
                            .font(.body(11, weight: .semibold))
                            .foregroundStyle(.fgDim)
                    }
                    .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Color.bark))
                    .overlay(Capsule().strokeBorder(Color.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func initial(from email: String?) -> String {
        guard let e = email, let first = e.first else { return "·" }
        return String(first).uppercased()
    }
}

// MARK: - Editorial hero

private struct EditorialHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PulsingDot()
                Text("DAY 3 · ROLLING")
                    .font(.mono(10, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(.muted)
            }

            // "Still chasing *the long way* west."
            (
                Text("Still chasing ")
                    .font(.frauncesHero(36))
                +
                Text("the long way")
                    .font(.frauncesHero(36, italic: true))
                    .foregroundColor(.clay)
                +
                Text(" west.")
                    .font(.frauncesHero(36))
            )
            .kerning(-1.0)
            .lineSpacing(2)
            .foregroundStyle(.fg)

            Text("Three stops checked. Eight to go. The wind out of Moab is calmer tonight.")
                .font(.body(14))
                .foregroundStyle(.muted)
                .frame(maxWidth: 340, alignment: .leading)
                .lineSpacing(3)
        }
    }
}

private struct PulsingDot: View {
    @State private var pulse = false
    var body: some View {
        Circle()
            .fill(Color.clay)
            .frame(width: 6, height: 6)
            .background(
                Circle()
                    .fill(Color.clay.opacity(0.2))
                    .frame(width: 12, height: 12)
            )
            .opacity(pulse ? 0.55 : 1)
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true),
                       value: pulse)
            .onAppear { pulse = true }
    }
}

// MARK: - Section header (eyebrow + title + optional "more" CTA)

struct SectionHeader: View {
    let eyebrow: String
    let title: String
    var more: String? = nil
    var moreAction: () -> Void = {}

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow.uppercased())
                    .font(.mono(10, weight: .medium))
                    .tracking(1.8)
                    .foregroundStyle(.muted)
                Text(title)
                    .font(.frauncesTitle(24))
                    .foregroundStyle(.fg)
                    .kerning(-0.4)
            }
            Spacer()
            if let more {
                Button(action: moreAction) {
                    HStack(spacing: 4) {
                        Text(more)
                            .font(.body(12, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.clay)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Icon button (used by topbar)

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
