//
//  ContentView.swift
//  NomadAI — Root view with the custom pill-style tab bar.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .home

    enum Tab: String, CaseIterable {
        case home, search, map, saved

        var label: String {
            switch self {
            case .home: return "Home"
            case .search: return "Search"
            case .map: return "Map"
            case .saved: return "Saved"
            }
        }

        var systemImage: String {
            switch self {
            case .home: return "house"
            case .search: return "magnifyingglass"
            case .map: return "map"
            case .saved: return "bookmark"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Selected tab content
            Group {
                switch selectedTab {
                case .home:   HomeView()
                case .search: SearchView()
                case .map:    CampsiteMapView()
                case .saved:  SavedView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.bg)

            // Floating pill tab bar
            TabBar(selected: $selectedTab)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

// MARK: - Tab Bar (the floating pill)

struct TabBar: View {
    @Binding var selected: ContentView.Tab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ContentView.Tab.allCases, id: \.self) { tab in
                TabButton(
                    tab: tab,
                    isActive: selected == tab,
                    action: { selected = tab }
                )
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.bark)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(Color.line, lineWidth: 1)
                )
        )
        .shadowMd()
    }
}

struct TabButton: View {
    let tab: ContentView.Tab
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 22, weight: .light))
                Text(tab.label)
                    .font(.body(10.5, weight: .semibold))
                    .tracking(0.2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, isActive ? 11 : 9)
            .foregroundStyle(isActive ? Color.clayInk : Color.muted)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isActive ? Color.clay : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isActive)
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
