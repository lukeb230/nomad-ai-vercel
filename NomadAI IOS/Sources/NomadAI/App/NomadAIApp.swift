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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(schemePref == "light" ? .light : .dark)
        }
        .modelContainer(container)
    }
}
