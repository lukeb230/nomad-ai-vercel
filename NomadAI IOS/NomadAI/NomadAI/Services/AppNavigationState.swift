//
//  AppNavigationState.swift
//  Process-wide cross-tab navigation state.
//
//  Lets one tab (e.g. SavedView) trigger a switch to another tab (Map) and
//  set its mode (Route) atomically — without prop-drilling bindings through
//  ContentView. Mirrors SearchResultsStore's @Observable singleton pattern.
//

import Foundation

@Observable
final class AppNavigationState {
    static let shared = AppNavigationState()

    var selectedTab: ContentView.Tab = .home
    var mapMode: CampsiteMapView.MapMode = .results

    private init() {}

    /// Switch to the Map tab and set its mode in one call.
    func openMap(mode: CampsiteMapView.MapMode) {
        self.mapMode = mode
        self.selectedTab = .map
    }
}
