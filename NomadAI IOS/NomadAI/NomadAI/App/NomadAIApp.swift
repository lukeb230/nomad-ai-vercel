//
//  NomadAIApp.swift
//  NomadAI
//
//  Entry point. Sets up the SwiftData container and root view.
//

import SwiftUI
import SwiftData

@main
struct NomadAIApp: App {
    init() {
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )
    }

    // Schema registration for SwiftData. Add new @Model types here.
    let container: ModelContainer = {
        do {
            return try ModelContainer(for:
                Campsite.self,
                Trip.self,
                TripStop.self,
                CompletedTrip.self,
                Profile.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    // Theme preference. Default is dark per the brand.
    @AppStorage("color_scheme") private var schemePref: String = "dark"

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(schemePref == "light" ? .light : .dark)
                .task {
                    AuthState.shared.modelContext = container.mainContext
                    _ = AuthState.shared    // initializes auth listener; SDK fires resumed session if any
                    SyncService.shared.start(context: container.mainContext)
                    Seed.seedIfNeeded(context: container.mainContext)
                    await NotificationService.shared.refreshStatus()
                    let trips = (try? container.mainContext.fetch(FetchDescriptor<Trip>())) ?? []
                    await NotificationService.shared.rebuildSchedule(from: trips)
                }
                .onChange(of: scenePhase) { _, new in
                    if new == .active {
                        Task {
                            await SyncService.shared.onForeground()
                            await NotificationService.shared.refreshStatus()
                            let trips = (try? container.mainContext.fetch(FetchDescriptor<Trip>())) ?? []
                            await NotificationService.shared.rebuildSchedule(from: trips)
                        }
                    }
                }
        }
        .modelContainer(container)
    }
}
