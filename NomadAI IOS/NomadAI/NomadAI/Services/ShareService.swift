//
//  ShareService.swift
//  Persists a Trip snapshot to public.shared_trips and returns a share URL
//  of the form https://gcvyzunlihlnjmhkwkbz.supabase.co/r/<uuid>. The
//  receiving-side handler (deep-link or static landing) is future work —
//  this phase only generates the link.
//
//  RLS on the table: anyone (including anon) can SELECT by id; only the
//  authenticated creator can INSERT/DELETE their own row.
//

import Foundation
import OSLog
import Supabase
import PostgREST

private let shareLog = Logger(subsystem: "LukeBrowne.NomadAI", category: "share")

actor ShareService {
    static let shared = ShareService()

    private struct InsertRow: Codable {
        let tripData: SharedTripPayload
        let createdBy: String
    }

    private struct InsertedRow: Codable {
        let id: UUID
    }

    private struct SharedTripPayload: Codable {
        let id: UUID
        let startedAt: Date
        let completedAt: Date?
        let currentStopIndex: Int
        let roundTrip: Bool
        let startFromUserLocation: Bool
        let stops: [Stop]

        struct Stop: Codable {
            let order: Int
            let campsiteId: String
            let campsiteName: String
            let lat: Double?
            let lng: Double?
            let scheduledDate: Date?
        }
    }

    /// Persists a Trip snapshot and returns the share URL.
    func createShareLink(for trip: Trip) async throws -> URL {
        guard let userId = await MainActor.run(body: { AuthState.shared.userId }) else {
            throw NSError(domain: "ShareService", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Sign in to share trips."])
        }
        let payload = await MainActor.run {
            SharedTripPayload(
                id: trip.id,
                startedAt: trip.startedAt,
                completedAt: trip.completedAt,
                currentStopIndex: trip.currentStopIndex,
                roundTrip: trip.roundTrip,
                startFromUserLocation: trip.startFromUserLocation,
                stops: trip.sortedStops.map {
                    .init(order: $0.order,
                          campsiteId: $0.campsiteId,
                          campsiteName: $0.campsiteName,
                          lat: $0.lat,
                          lng: $0.lng,
                          scheduledDate: $0.scheduledDate)
                }
            )
        }
        let row = InsertRow(tripData: payload, createdBy: userId)
        let client = await SupabaseService.shared.client

        let inserted: [InsertedRow] = try await client
            .from("shared_trips")
            .insert(row)
            .select("id")
            .execute()
            .value

        guard let id = inserted.first?.id else {
            throw NSError(domain: "ShareService", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "No id returned"])
        }
        let url = URL(string: "https://gcvyzunlihlnjmhkwkbz.supabase.co/r/\(id.uuidString.lowercased())")!
        shareLog.notice("created share link \(url.absoluteString)")
        return url
    }
}
