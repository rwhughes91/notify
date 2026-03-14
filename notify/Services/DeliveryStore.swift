//
//  DeliveryStore.swift
//  notify
//
//  Created by Robert Hughes on 3/13/26.
//

import Foundation
import WidgetKit

@Observable
class DeliveryStore {
    // Shared UserDefaults — written so the widget can read it, never read by the app itself.
    private let suite        = UserDefaults(suiteName: "group.org.roberthughesdev.notify")
    private let deliveriesKey = "deliveries_v1"

    var deliveries: [Delivery] = []

    // MARK: - Mutating

    /// Replaces all deliveries with the freshly-scraped set and pushes to the widget store.
    func replace(_ incoming: [Delivery]) {
        deliveries = incoming
        if let data = try? JSONEncoder().encode(deliveries) {
            suite?.set(data, forKey: deliveriesKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func signOut() {
        deliveries = []
        suite?.removeObject(forKey: deliveriesKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Computed sections

    var todayDeliveries: [Delivery] {
        let cal = Calendar.current
        return deliveries.filter {
            $0.kind == .incoming &&
            $0.status != .delivered &&
            ($0.expectedDate.map { cal.isDateInToday($0) } ?? false)
        }
    }

    var upcomingDeliveries: [Delivery] {
        let cal = Calendar.current
        let tomorrow = cal.startOfDay(for: Date.now.addingTimeInterval(86_400))
        return deliveries
            .filter {
                $0.kind == .incoming &&
                $0.status != .delivered &&
                ($0.expectedDate.map { $0 >= tomorrow } ?? false)
            }
            .sorted { ($0.expectedDate ?? .distantFuture) < ($1.expectedDate ?? .distantFuture) }
    }

    var deliveredDeliveries: [Delivery] {
        deliveries
            .filter { $0.kind == .incoming && $0.status == .delivered }
            .sorted { $0.receivedDate > $1.receivedDate }
    }

    var returnDeliveries: [Delivery] {
        deliveries.filter { $0.kind == .return }
    }
}
