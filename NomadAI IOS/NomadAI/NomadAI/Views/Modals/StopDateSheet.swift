//
//  StopDateSheet.swift
//  Modal date+time picker for setting a TripStop's scheduledDate.
//
//  Save → writes scheduledDate to the model, bumps Trip.updatedAt (so sync
//  picks it up), saves the context, asks NotificationService to rebuild the
//  reminder schedule, dismisses.
//

import SwiftUI
import SwiftData

struct StopDateSheet: View {
    let stop: TripStop
    let trip: Trip

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @State private var pickedDate: Date

    init(stop: TripStop, trip: Trip) {
        self.stop = stop
        self.trip = trip
        // Default to existing date if set; otherwise today at 5:00 PM local.
        let initial = stop.scheduledDate ?? Self.defaultArrivalDate()
        self._pickedDate = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                header

                DatePicker(
                    "Arrival",
                    selection: $pickedDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .tint(.clay)

                Spacer()

                actions
            }
            .padding(.horizontal, Spacing.pageHorizontal)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .background(Color.bg)
            .navigationTitle(stop.campsiteName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Stop \(stop.order + 1)").monoLabel()
            Text("When are you arriving?")
                .font(.frauncesTitle(20))
                .foregroundStyle(.fg)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button(action: save) {
                Text("Save reminder")
                    .font(.body(14, weight: .bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .foregroundStyle(Color.clayInk)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.clay))
            }
            .buttonStyle(.plain)

            if stop.scheduledDate != nil {
                Button(action: removeDate) {
                    Text("Remove date")
                        .font(.body(13, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(.berry)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.surface))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.berry.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func save() {
        stop.scheduledDate = pickedDate
        trip.updatedAt = Date()
        try? ctx.save()
        Task {
            await NotificationService.shared.rebuildSchedule(from: [trip])
        }
        dismiss()
    }

    private func removeDate() {
        stop.scheduledDate = nil
        trip.updatedAt = Date()
        try? ctx.save()
        Task {
            await NotificationService.shared.rebuildSchedule(from: [trip])
        }
        dismiss()
    }

    private static func defaultArrivalDate() -> Date {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = 17
        comps.minute = 0
        let candidate = cal.date(from: comps) ?? now
        // If 5pm has already passed today, bump to 5pm tomorrow.
        return candidate <= now ? cal.date(byAdding: .day, value: 1, to: candidate) ?? candidate : candidate
    }
}
