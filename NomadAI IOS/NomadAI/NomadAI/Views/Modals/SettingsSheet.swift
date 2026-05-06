//
//  SettingsSheet.swift
//  Bottom sheet (large detent) opened from the Home topbar gear icon.
//
//  Spec: docs/screen-inventory.md §Settings (line 129–130) +
//  web canonical: app.html lines 1708–1850.
//

import SwiftUI
import SwiftData
import UIKit

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @AppStorage("color_scheme") private var schemePref: String = "dark"
    @AppStorage("default_radius") private var defaultRadius: Int = 50
    @AppStorage("discovery_enabled") private var discoveryEnabled: Bool = true

    @Query(filter: #Predicate<Campsite> { $0.isSaved == true })
    private var saved: [Campsite]

    @Query(filter: #Predicate<Campsite> { $0.isVisited == true })
    private var visited: [Campsite]

    @State private var alert: ConfirmAlert? = nil
    @State private var notice: NoticeAlert? = nil

    @State private var auth = AuthState.shared
    @State private var showSignIn: Bool = false
    @State private var showStats: Bool = false
    @State private var notif = NotificationService.shared
    @State private var sync = SyncService.shared

    @Query(filter: #Predicate<Trip> { $0.completedAt == nil })
    private var activeTripsForNotif: [Trip]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    appearanceSection
                    searchDefaultsSection
                    notificationsSection
                    dataSection
                    accountSection
                    aboutSection
                    versionFooter
                }
                .padding(Spacing.pageHorizontal)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Color.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Color.clay)
                }
            }
        }
        .alert(item: $alert) { a in
            Alert(
                title: Text(a.title),
                message: Text(a.message),
                primaryButton: .destructive(Text(a.confirmLabel), action: a.action),
                secondaryButton: .cancel()
            )
        }
        .alert(item: $notice) { n in
            Alert(title: Text(n.title), message: Text(n.message), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $showSignIn) {
            SignInSheet()
        }
        .sheet(isPresented: $showStats) {
            StatsSheet()
        }
        // Sheets present in their own context — re-apply the color scheme here
        // so toggling Light mode updates the sheet immediately, not on reopen.
        .preferredColorScheme(schemePref == "light" ? .light : .dark)
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        SettingsSection(eyebrow: "Appearance") {
            SettingsRow(icon: "moon.stars", title: "Light mode", subtitle: "Switch between dark and light theme") {
                Toggle("", isOn: Binding(
                    get: { schemePref == "light" },
                    set: { schemePref = $0 ? "light" : "dark" }
                ))
                .labelsHidden()
                .tint(Color.clay)
            }
        }
    }

    private var searchDefaultsSection: some View {
        SettingsSection(eyebrow: "Search defaults") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Default radius")
                        .font(.body(13, weight: .semibold))
                        .foregroundStyle(.fg)
                    HStack(spacing: 6) {
                        ForEach([25, 50, 100, 200], id: \.self) { r in
                            Button { defaultRadius = r } label: {
                                Text("\(r) mi")
                                    .font(.body(12, weight: .semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                                    .foregroundStyle(defaultRadius == r ? Color.clayInk : Color.fgDim)
                                    .background(Capsule().fill(defaultRadius == r ? Color.clay : Color.surface))
                                    .overlay(Capsule().strokeBorder(defaultRadius == r ? Color.clay : Color.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Used as the starting radius in Location search.")
                        .font(.body(11))
                        .foregroundStyle(.muted)
                }

                Divider().background(Color.line)

                SettingsRow(
                    icon: "person.2.wave.2",
                    title: "Community picks",
                    subtitle: "Adds a second pass that pulls Dyrt, iOverlander, and overland blogs into results."
                ) {
                    Toggle("", isOn: $discoveryEnabled)
                        .labelsHidden()
                        .tint(Color.clay)
                }
            }
            .padding(14)
        }
    }

    private var notificationsSection: some View {
        SettingsSection(eyebrow: "Notifications") {
            SettingsRow(
                icon: notif.status == .authorized ? "bell.fill" : "bell",
                title: notifTitle,
                subtitle: notifSubtitle,
                action: handleNotificationsTap
            ) {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.faint)
            }
        }
    }

    private var notifTitle: String {
        switch notif.status {
        case .authorized, .provisional: return "Trip reminders are on"
        case .denied:      return "Trip reminders blocked"
        default:                        return "Enable trip reminders"
        }
    }

    private var notifSubtitle: String {
        switch notif.status {
        case .authorized, .provisional:
            return "\(notif.scheduledCount) scheduled · tap a stop in Saved → Route to add dates"
        case .denied:
            return "Allow notifications in iOS Settings to schedule per-stop reminders"
        default:
            return "Get a heads-up before each trip stop"
        }
    }

    private func handleNotificationsTap() {
        Task {
            switch notif.status {
            case .notDetermined:
                let granted = await notif.requestPermission()
                if granted {
                    await notif.rebuildSchedule(from: activeTripsForNotif)
                }
            case .denied:
                openSystemSettings()
            default:
                break
            }
        }
    }

    private var dataSection: some View {
        SettingsSection(eyebrow: "Data") {
            VStack(spacing: 0) {
                SettingsRow(
                    icon: "bookmark.slash",
                    title: "Clear saved spots",
                    subtitle: "Removes all bookmarks (\(saved.count))",
                    isDestructive: true,
                    action: confirmClearSaved
                ) { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.faint) }

                rowDivider

                SettingsRow(
                    icon: "seal",
                    title: "Clear passport stamps",
                    subtitle: "Marks visited campsites as unvisited (\(visited.count))",
                    isDestructive: true,
                    action: confirmClearPassport
                ) { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.faint) }

                rowDivider

                SettingsRow(
                    icon: "magnifyingglass",
                    title: "Clear search history",
                    subtitle: "Coming soon — search history isn't tracked yet",
                    isDestructive: true,
                    action: nil
                ) { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.faint.opacity(0.5)) }
                .opacity(0.55)

                rowDivider

                SettingsRow(
                    icon: "arrow.counterclockwise",
                    title: "Reset all data",
                    subtitle: "Wipes everything and re-seeds on next launch",
                    isDestructive: true,
                    action: confirmResetAll
                ) { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.faint) }
            }
        }
    }

    private var accountSection: some View {
        SettingsSection(eyebrow: "Account") {
            if let email = auth.email {
                SettingsRow(
                    icon: "person.crop.circle.fill",
                    title: email,
                    subtitle: "Signed in",
                    action: nil
                ) {
                    Button("Sign out") {
                        Task { await auth.signOut() }
                    }
                    .font(.body(11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.berry)
                    .buttonStyle(.plain)
                }
            } else {
                SettingsRow(
                    icon: "person",
                    title: "Sign in",
                    subtitle: "Sync trips and saved spots across devices",
                    action: { showSignIn = true }
                ) {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.faint)
                }
            }
        }
    }

    private var aboutSection: some View {
        SettingsSection(eyebrow: "About") {
            VStack(spacing: 0) {
                SettingsRow(
                    icon: "chart.bar",
                    title: "Your stats",
                    subtitle: "Visited / Trips / States overview",
                    action: { showStats = true }
                ) { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.faint) }

                rowDivider

                LinkRow(
                    icon: "globe",
                    title: "NomadAI",
                    subtitle: "nomadai.us",
                    url: URL(string: "https://nomadai.us")!
                )

                rowDivider

                LinkRow(
                    icon: "lock.shield",
                    title: "Privacy Policy",
                    subtitle: "How your data is handled",
                    url: URL(string: "https://nomadai.us/privacy")!
                )

                rowDivider

                LinkRow(
                    icon: "doc.text",
                    title: "Terms of Service",
                    subtitle: "Usage agreement",
                    url: URL(string: "https://nomadai.us/terms")!
                )

                rowDivider

                VStack(alignment: .leading, spacing: 4) {
                    Text("Disclaimer")
                        .font(.mono(10, weight: .semibold)).tracking(1.2).textCase(.uppercase)
                        .foregroundStyle(.muted)
                    Text("Not affiliated with The Dyrt, iOverlander, Recreation.gov, BLM, or Campendium.")
                        .font(.body(11))
                        .foregroundStyle(.muted)
                        .lineSpacing(2)
                }
                .padding(14)
            }
        }
    }

    private var versionFooter: some View {
        VStack(spacing: 4) {
            if let err = sync.lastSyncError {
                Text("Last sync: \(err)")
                    .font(.body(10))
                    .foregroundStyle(.berry)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 4)
            }
            Text("NomadAI v\(appVersion) (\(appBuild))")
                .font(.mono(10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.faint)
            Text("Made for the long way.")
                .font(.body(11))
                .foregroundStyle(.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    // MARK: - Helpers

    private var rowDivider: some View {
        Rectangle().fill(Color.line).frame(height: 1).padding(.leading, 56)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    // MARK: - Actions

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func confirmClearSaved() {
        alert = ConfirmAlert(
            title: "Clear saved spots?",
            message: "All \(saved.count) bookmarks will be removed. This can't be undone.",
            confirmLabel: "Clear",
            action: clearSaved
        )
    }

    private func clearSaved() {
        for c in saved { c.isSaved = false; c.savedAt = nil }
        try? ctx.save()
    }

    private func confirmClearPassport() {
        alert = ConfirmAlert(
            title: "Clear passport stamps?",
            message: "Visited campsites will be marked unvisited and completed-trip records will be deleted.",
            confirmLabel: "Clear",
            action: clearPassport
        )
    }

    private func clearPassport() {
        for c in visited { c.isVisited = false; c.visitedAt = nil; c.rating = nil }
        try? ctx.delete(model: CompletedTrip.self)
        try? ctx.save()
    }

    private func confirmResetAll() {
        alert = ConfirmAlert(
            title: "Reset all data?",
            message: "Wipes every saved spot, visited stamp, and trip. The app will re-seed sample data on next launch.",
            confirmLabel: "Reset",
            action: resetAll
        )
    }

    private func resetAll() {
        try? ctx.delete(model: TripStop.self)
        try? ctx.delete(model: Trip.self)
        try? ctx.delete(model: CompletedTrip.self)
        try? ctx.delete(model: Campsite.self)
        try? ctx.delete(model: Profile.self)
        try? ctx.save()
        UserDefaults.standard.removeObject(forKey: Seed.didSeedKey)
        dismiss()
    }

    // MARK: - Alert payloads

    struct ConfirmAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let confirmLabel: String
        let action: () -> Void
    }

    struct NoticeAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }
}

// MARK: - SettingsSection (eyebrow + card container)

struct SettingsSection<Content: View>: View {
    let eyebrow: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased())
                .font(.mono(10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(.muted)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Color.bark))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Color.line, lineWidth: 1))
        }
    }
}

// MARK: - SettingsRow (icon + title + subtitle + trailing slot)

struct SettingsRow<Trailing: View>: View {
    let icon: String
    let title: String
    let subtitle: String?
    var isDestructive: Bool = false
    var action: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        // Use a tap gesture instead of wrapping in a Button so trailing
        // controls (Toggle, Picker, etc.) remain interactive.
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(isDestructive ? Color.berry : Color.clay)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.surface2))
                .overlay(Circle().strokeBorder(Color.line, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body(14, weight: .semibold))
                    .foregroundStyle(isDestructive ? Color.berry : Color.fg)
                if let subtitle {
                    Text(subtitle)
                        .font(.body(11))
                        .foregroundStyle(.muted)
                        .lineLimit(2)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { action?() }
    }
}

// MARK: - LinkRow (opens an external URL)

private struct LinkRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(Color.clay)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.surface2))
                    .overlay(Circle().strokeBorder(Color.line, lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body(14, weight: .semibold)).foregroundStyle(.fg)
                    Text(subtitle).font(.body(11)).foregroundStyle(.muted)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.faint)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
    }
}

#Preview {
    SettingsSheet()
        .preferredColorScheme(.dark)
        .modelContainer(for: [Trip.self, TripStop.self, Campsite.self, CompletedTrip.self, Profile.self], inMemory: true)
}
