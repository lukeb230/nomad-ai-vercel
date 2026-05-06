//
//  OnboardingFlow.swift
//  Multi-step "tell us about your trip" flow that pre-fills context for
//  Claude before the user types anything. Renders below the WelcomeCard
//  while the chat is empty; collapses once the user types their own query
//  or completes the flow.
//
//  Step graph:
//      tripType
//          → route          (only if Overlanding / Multi-day)
//          → sites
//              → location   (only if NOT a multi-stop trip)
//              → complete
//
//  On completion, the synthesized natural-language query is handed back to
//  SearchView's sendQuery via the `onComplete` closure.
//

import SwiftUI

// MARK: - Trip-type taxonomy

enum TripType: String, CaseIterable, Identifiable {
    case overland = "Overlanding"
    case multiDay = "Multi-day road trip"
    case weekend = "Weekend trip"
    case dayTrip = "Day trip"
    case browsing = "Just exploring"

    var id: String { rawValue }
    var isMultiStop: Bool { self == .overland || self == .multiDay }
    var systemImage: String {
        switch self {
        case .overland: return "mountain.2.fill"
        case .multiDay: return "road.lanes"
        case .weekend: return "sun.max.fill"
        case .dayTrip: return "cloud.sun.fill"
        case .browsing: return "binoculars.fill"
        }
    }
}

// MARK: - Process-wide flow state

@Observable
@MainActor
final class OnboardingFlowState {
    static let shared = OnboardingFlowState()

    enum Step {
        case tripType, route, sites, location, complete, dismissed
    }

    var step: Step = .tripType
    var tripType: TripType? = nil
    var route: String = ""
    var sites: Set<String> = []
    var location: String = ""

    static let siteOptions = [
        "Dispersed / BLM",
        "Established / paid",
        "Free",
        "Walk-up",
        "Reservable",
        "RV friendly",
        "Tent only",
        "Overlanding"
    ]

    private init() {}

    /// User typed a real query — kill the flow so we don't double-prompt.
    func dismiss() { step = .dismissed }

    /// Move to the next applicable step. The graph branches on
    /// `tripType.isMultiStop` so single-stop trips skip the route input
    /// and multi-stop trips skip the location input.
    func advance() {
        switch step {
        case .tripType:
            step = (tripType?.isMultiStop == true) ? .route : .sites
        case .route:
            step = .sites
        case .sites:
            step = (tripType?.isMultiStop == true) ? .complete : .location
        case .location:
            step = .complete
        case .complete, .dismissed:
            break
        }
    }

    /// Walk one step back through the graph so the user can change a previous
    /// answer. No-op from the first step.
    func goBack() {
        switch step {
        case .tripType, .complete, .dismissed:
            break
        case .route:
            step = .tripType
        case .sites:
            step = (tripType?.isMultiStop == true) ? .route : .tripType
        case .location:
            step = .sites
        }
    }

    /// Build a natural-language query from the collected fields. Sent to Claude
    /// as if the user had typed it — same .location/.route classification path.
    func synthesizedQuery() -> String {
        var parts: [String] = []
        if let trip = tripType {
            parts.append(trip.rawValue.lowercased())
        }
        if !sites.isEmpty {
            parts.append("looking for \(sites.map { $0.lowercased() }.joined(separator: ", "))")
        }
        if !route.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append("along \(route.trimmingCharacters(in: .whitespaces))")
        }
        if !location.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append("near \(location.trimmingCharacters(in: .whitespaces))")
        }
        if parts.isEmpty { return "Recommend some good camps near me" }
        return parts.joined(separator: " — ")
    }
}

// MARK: - Flow view

struct OnboardingFlow: View {
    @Bindable var state: OnboardingFlowState
    let onComplete: (String) -> Void

    var body: some View {
        Group {
            switch state.step {
            case .tripType:    tripTypeStep
            case .route:       routeStep
            case .sites:       sitesStep
            case .location:    locationStep
            case .complete, .dismissed: EmptyView()
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: Step 1 — trip type

    private var tripTypeStep: some View {
        StepCard(prompt: "What kind of trip?") {
            FlowLayout(spacing: 6) {
                ForEach(TripType.allCases) { type in
                    OnboardingChip(label: type.rawValue, systemImage: type.systemImage, isOn: state.tripType == type) {
                        state.tripType = type
                        withAnimation(.easeOut(duration: 0.2)) { state.advance() }
                    }
                }
            }
        }
    }

    // MARK: Step 2 — route (multi-stop only)

    private var routeStep: some View {
        StepCard(prompt: "Where to? Try a route like \"Denver to Moab\" or a region like \"southern Utah loop\".",
                 onBack: { withAnimation(.easeOut(duration: 0.2)) { state.goBack() } }) {
            HStack(spacing: 8) {
                TextField("Route", text: $state.route)
                    .font(.body(14))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line, lineWidth: 1))
                Button("Next") {
                    withAnimation(.easeOut(duration: 0.2)) { state.advance() }
                }
                .buttonStyle(.plain)
                .font(.body(13, weight: .bold))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .foregroundStyle(Color.clayInk)
                .background(Capsule().fill(Color.clay))
                .opacity(state.route.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                .disabled(state.route.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: Step 3 — site preferences

    private var sitesStep: some View {
        StepCard(prompt: "What kind of sites are you after? Pick a few.",
                 onBack: { withAnimation(.easeOut(duration: 0.2)) { state.goBack() } }) {
            VStack(alignment: .leading, spacing: 10) {
                FlowLayout(spacing: 6) {
                    ForEach(OnboardingFlowState.siteOptions, id: \.self) { opt in
                        OnboardingChip(label: opt, isOn: state.sites.contains(opt)) {
                            if state.sites.contains(opt) { state.sites.remove(opt) }
                            else { state.sites.insert(opt) }
                        }
                    }
                }
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        state.advance()
                        if state.step == .complete {
                            onComplete(state.synthesizedQuery())
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(state.tripType?.isMultiStop == true ? "Build trip" : "Continue")
                        Image(systemName: "arrow.right")
                    }
                    .font(.body(13, weight: .bold))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .foregroundStyle(Color.clayInk)
                    .background(Capsule().fill(Color.clay))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Step 4 — location (single-stop only)

    private var locationStep: some View {
        StepCard(prompt: "Where? A city, park, or 'near me'.",
                 onBack: { withAnimation(.easeOut(duration: 0.2)) { state.goBack() } }) {
            HStack(spacing: 8) {
                TextField("Where", text: $state.location)
                    .font(.body(14))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line, lineWidth: 1))
                Button {
                    if state.location.trimmingCharacters(in: .whitespaces).isEmpty {
                        state.location = "near me"
                    }
                    withAnimation(.easeOut(duration: 0.2)) {
                        state.advance()
                        onComplete(state.synthesizedQuery())
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                        Text("Find")
                    }
                    .font(.body(13, weight: .bold))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .foregroundStyle(Color.clayInk)
                    .background(Capsule().fill(Color.clay))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Step card chrome

private struct StepCard<Content: View>: View {
    let prompt: String
    var onBack: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(Color.moss).frame(width: 5, height: 5)
                Text("NOMADAI").monoLabel()
                Spacer(minLength: 0)
                if let onBack {
                    Button(action: onBack) {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 9, weight: .semibold))
                            Text("BACK")
                                .font(.mono(9, weight: .semibold))
                                .tracking(1.2)
                        }
                        .foregroundStyle(Color.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Go back to the previous step")
                }
            }
            Text(prompt)
                .font(.body(14))
                .foregroundStyle(.fg)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.line, lineWidth: 1))
    }
}

// MARK: - Chip

private struct OnboardingChip: View {
    let label: String
    var systemImage: String? = nil
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 10))
                }
                Text(label).font(.body(12, weight: .semibold))
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .foregroundStyle(isOn ? Color.clayInk : Color.fgDim)
            .background(Capsule().fill(isOn ? Color.clay : Color.bark))
            .overlay(Capsule().strokeBorder(isOn ? Color.clay : Color.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
