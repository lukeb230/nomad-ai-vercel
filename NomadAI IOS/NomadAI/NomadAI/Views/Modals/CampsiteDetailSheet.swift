//
//  CampsiteDetailSheet.swift
//  Bottom-sheet wrapper around an always-expanded CampsiteCard.
//
//  Presented from MapView's pin popup "Open" button. Reuses the existing
//  card design rather than duplicating layout — Phase 9 polish can add a
//  bespoke detail layout (bigger photo, full amenities, related actions)
//  if one is needed.
//

import SwiftUI
import SwiftData

struct CampsiteDetailSheet: View {
    let campsite: Campsite
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                CampsiteCard(campsite: campsite, initiallyExpanded: true)
                    .padding(.horizontal, Spacing.pageHorizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
            }
            .background(Color.bg)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationTitle(campsite.name)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }
}
