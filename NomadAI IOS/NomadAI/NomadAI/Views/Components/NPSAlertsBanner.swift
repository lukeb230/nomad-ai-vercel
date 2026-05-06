//
//  NPSAlertsBanner.swift
//  Small tappable banner shown above tab content when there are active major
//  NPS alerts in the user's current state. Pulls from the @Observable
//  `NPSAlertsService.shared` so all tabs that include the banner stay in
//  sync without prop-drilling.
//
//  Visible on Search / Map / Saved. Tap → bottom sheet listing each alert.
//

import SwiftUI

struct NPSAlertsBanner: View {
    @State private var service = NPSAlertsService.shared
    @State private var showingSheet = false

    var body: some View {
        if !service.alerts.isEmpty {
            Button { showingSheet = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.berry)
                    Text(headline)
                        .font(.body(12, weight: .semibold))
                        .foregroundStyle(Color.fg)
                    Spacer(minLength: 4)
                    Text("View")
                        .font(.mono(10, weight: .semibold))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.berry)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.muted)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.berry.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.berry.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingSheet) {
                NPSAlertsSheet(alerts: service.alerts, stateCode: service.stateCode)
            }
        }
    }

    private var headline: String {
        let n = service.alerts.count
        let suffix = n == 1 ? "alert" : "alerts"
        if let state = service.stateCode {
            return "\(n) park \(suffix) in \(state)"
        }
        return "\(n) park \(suffix) nearby"
    }
}

// MARK: - Detail sheet

struct NPSAlertsSheet: View {
    let alerts: [NPSAlert]
    let stateCode: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(alerts) { alert in
                        AlertCard(alert: alert)
                    }
                }
                .padding(.horizontal, Spacing.pageHorizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.bg)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationTitle(stateCode.map { "Alerts in \($0)" } ?? "Park alerts")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }
}

private struct AlertCard: View {
    let alert: NPSAlert

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(alert.category.uppercased())
                    .font(.mono(9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(categoryColor)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(categoryColor.opacity(0.15)))
                    .overlay(Capsule().strokeBorder(categoryColor.opacity(0.35), lineWidth: 1))
                Spacer(minLength: 4)
                Text(alert.parkName)
                    .font(.mono(10))
                    .tracking(0.8)
                    .foregroundStyle(.muted)
                    .lineLimit(1)
            }

            Text(alert.title)
                .font(.body(14, weight: .bold))
                .foregroundStyle(.fg)
                .fixedSize(horizontal: false, vertical: true)

            if !alert.description.isEmpty {
                Text(alert.description)
                    .font(.body(12))
                    .foregroundStyle(.fgDim)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let url = URL(string: alert.url), !alert.url.isEmpty {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text("Open NPS page")
                            .font(.mono(10, weight: .semibold))
                            .tracking(1.2)
                            .textCase(.uppercase)
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(Color.clay)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.bark))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.line, lineWidth: 1))
    }

    private var categoryColor: Color {
        switch alert.category {
        case "Danger":       return .berry
        case "Park Closure": return .berry
        case "Caution":      return .sand
        default:             return .muted
        }
    }
}
