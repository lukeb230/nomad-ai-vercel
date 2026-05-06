//
//  SitePhotoView.swift
//  Photo carousel for Campsite-bound views (CampsiteCard, CampsiteDetailSheet,
//  MapPopupCard). Pages: any Google Places photos first (1–5), then a hybrid
//  satellite snapshot as the always-available last frame.
//
//  Two display modes:
//    - paged: true (default) — TabView with .page style. Swipe to scroll.
//    - paged: false — single image, prefers Places' first photo, falls back to
//      satellite. Used by the 52×52 popup thumb where paging is overkill.
//
//  Resolution flow:
//    1. campsite.photoReferences == nil → kick off PlacesService text-search.
//       Migrate the legacy singular `photoReference` into the array if present.
//    2. Each rendered AsyncImage hits /api/places?type=photo&ref=… → URLCache
//       (32MB / 200MB, configured in NomadAIApp).
//    3. Satellite pane uses MKMapSnapshotter via SatelliteSnapshotStore (in-memory
//       per-session cache). No API key, no Google quota cost.
//

import SwiftUI
import SwiftData
import UIKit

struct SitePhotoView<Placeholder: View>: View {
    let campsite: Campsite
    var paged: Bool = true
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.modelContext) private var ctx

    var body: some View {
        Group {
            if paged {
                pagedCarousel
            } else {
                singleImage
            }
        }
        .task(id: campsite.id) { await resolveIfNeeded() }
    }

    // MARK: - Paged carousel

    private var pagedCarousel: some View {
        TabView {
            ForEach(placesRefs, id: \.self) { ref in
                placesImage(ref: ref)
            }
            if hasCoords {
                SatellitePane(campsite: campsite, placeholder: placeholder)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: pageCount > 1 ? .always : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
    }

    // MARK: - Single (popup thumb)

    private var singleImage: some View {
        Group {
            if let first = placesRefs.first {
                placesImage(ref: first)
            } else if hasCoords {
                SatellitePane(campsite: campsite, placeholder: placeholder)
            } else {
                placeholder()
            }
        }
    }

    // MARK: - Pieces

    private func placesImage(ref: String) -> some View {
        AsyncImage(url: PlacesService.shared.photoURL(reference: ref)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                placeholder()
            }
        }
    }

    // MARK: - Derived

    private var placesRefs: [String] {
        if let arr = campsite.photoReferences { return arr }
        // Lazy migration: legacy singular field → first array element.
        if let old = campsite.photoReference, !old.isEmpty { return [old] }
        return []
    }

    private var hasCoords: Bool {
        campsite.lat != nil && campsite.lng != nil
    }

    private var pageCount: Int {
        placesRefs.count + (hasCoords ? 1 : 0)
    }

    // MARK: - Resolve

    private func resolveIfNeeded() async {
        // Migrate legacy singular reference into the array (idempotent).
        if campsite.photoReferences == nil, let old = campsite.photoReference {
            campsite.photoReferences = old.isEmpty ? [] : [old]
            try? ctx.save()
        }
        guard campsite.photoReferences == nil else { return }
        let query = [campsite.name, campsite.city, campsite.state]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty else { return }
        do {
            let refs = try await PlacesService.shared.searchPhotoReferences(for: query)
            campsite.photoReferences = refs
            try? ctx.save()
        } catch {
            // Network fail — leave nil so a future appearance can retry.
        }
    }
}

// MARK: - Satellite pane (one TabView page)

private struct SatellitePane<Placeholder: View>: View {
    let campsite: Campsite
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: campsite.id) { await load() }
    }

    private func load() async {
        guard let lat = campsite.lat, let lng = campsite.lng else { return }
        // 600×400 is a reasonable card-ish render size; SwiftUI scales to fit the parent frame.
        let size = CGSize(width: 600, height: 400)
        image = await SatelliteSnapshotStore.shared.snapshot(lat: lat, lng: lng, size: size)
    }
}
