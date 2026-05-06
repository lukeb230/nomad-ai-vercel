//
//  MapView.swift
//  Tab 3 — MapKit-backed map with custom pins and floating mode bar.
//
//  Spec: docs/screen-inventory.md §3, redesign HTML lines 1739–1808.
//

import SwiftUI
import MapKit

struct CampsiteMapView: View {
    enum MapMode: String, CaseIterable {
        case results, saved, route
        var label: String {
            switch self {
            case .results: return "Results"
            case .saved: return "Saved"
            case .route: return "Route"
            }
        }
        var systemImage: String {
            switch self {
            case .results: return "magnifyingglass"
            case .saved: return "bookmark"
            case .route: return "location.north"
            }
        }
    }

    @State private var mode: MapMode = .results
    @State private var position: MapCameraPosition = .userLocation(fallback: .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.5, longitude: -111.5),
            span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
        )
    ))

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Topbar
            VStack(alignment: .leading, spacing: 4) {
                Text("Map").monoLabel()
                FrauncesEmphasis(prefix: "The ", italic: "field", suffix: "", size: 22)
            }
            .padding(.horizontal, Spacing.pageHorizontal)
            .padding(.top, 18)

            // Map
            Map(position: $position)
                .mapStyle(.standard(elevation: .realistic))
                .overlay(alignment: .top) { ModeBar(selected: $mode) }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.line, lineWidth: 1))
                .padding(.horizontal, Spacing.pageHorizontal)

            // TODO: floating "Search this area" button on pan; route info card below

            Spacer(minLength: 100)
        }
        .background(Color.bg)
    }
}

private struct ModeBar: View {
    @Binding var selected: CampsiteMapView.MapMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CampsiteMapView.MapMode.allCases, id: \.self) { m in
                Button { selected = m } label: {
                    HStack(spacing: 5) {
                        Image(systemName: m.systemImage).font(.system(size: 11, weight: .regular))
                        Text(m.label).font(.body(11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .foregroundStyle(selected == m ? Color.clayInk : Color.fgDim)
                    .background(RoundedRectangle(cornerRadius: 10).fill(selected == m ? Color.clay : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial.opacity(0.8))
        .background(Color.bark.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.line, lineWidth: 1))
        .padding(12)
    }
}

#Preview {
    CampsiteMapView().preferredColorScheme(.dark)
}
