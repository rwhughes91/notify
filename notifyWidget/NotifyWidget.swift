//
//  notifyWidget.swift
//  notifyWidget
//
//  Created by Robert Hughes on 3/13/26.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct DeliveryEntry: TimelineEntry {
    let date: Date
    let deliveries: [WidgetDelivery]
}

struct WidgetDelivery: Identifiable {
    let id: String
    let vendorName: String
}

// MARK: - Timeline provider

struct Provider: TimelineProvider {

    func placeholder(in context: Context) -> DeliveryEntry {
        DeliveryEntry(date: .now, deliveries: [
            WidgetDelivery(id: "placeholder", vendorName: "Amazon")
        ])
    }

    func getSnapshot(in context: Context,
                     completion: @escaping (DeliveryEntry) -> Void) {
        completion(DeliveryEntry(date: .now, deliveries: loadTodayDeliveries()))
    }

    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<DeliveryEntry>) -> Void) {
        let now = Date.now
        let deliveries = loadTodayDeliveries()

        // 6 entries × 10 min = 1-hour lookahead; WidgetKit re-fetches at .atEnd
        let entries: [DeliveryEntry] = (0..<6).map { i in
            DeliveryEntry(date: now.addingTimeInterval(Double(i) * 600),
                          deliveries: deliveries)
        }

        completion(Timeline(entries: entries, policy: .atEnd))
    }

    // MARK: - Load from shared App Group store

    private func loadTodayDeliveries() -> [WidgetDelivery] {
        guard
            let suite = UserDefaults(suiteName: "group.org.roberthughesdev.notify"),
            let data  = suite.data(forKey: "deliveries_v1"),
            let all   = try? JSONDecoder().decode([WidgetDeliveryData].self, from: data)
        else { return [] }

        let calendar = Calendar.current
        print("[Widget] total decoded: \(all.count)")
        for d in all { print("[Widget] \(d.kind) | \(d.status) | expected: \(String(describing: d.expectedDate)) | from: \(d.fromEmail ?? "nil")") }

        return all
            .filter { d in
                d.kind == "Incoming" &&
                (d.expectedDate.map { calendar.isDateInToday($0) } ?? false)
            }
            .map { d in
                WidgetDelivery(id: d.trackingNumber + d.kind,
                               vendorName: vendorName(from: d.fromEmail ?? ""))
            }
    }

    private func vendorName(from fromEmail: String) -> String {
        // "Display Name <email@domain.com>" → "Display Name"
        if let ltIdx = fromEmail.firstIndex(of: "<") {
            let name = String(fromEmail[fromEmail.startIndex..<ltIdx])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !name.isEmpty { return name }
        }
        // No display name — use the raw email address
        return fromEmail.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
    }
}

// MARK: - Minimal Codable mirror of Delivery (no main-app dependency)

private struct WidgetDeliveryData: Codable {
    let carrier: String
    let trackingNumber: String
    let expectedDate: Date?
    let status: String
    let kind: String
    let fromEmail: String?  // optional for backwards compatibility
}

// MARK: - Widget view

struct notifyWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Today's Deliveries", systemImage: "shippingbox.fill")
                .font(.caption.bold())
                .foregroundStyle(Color.accentColor)

            Divider()

            if entry.deliveries.isEmpty {
                Text("No deliveries today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ForEach(entry.deliveries.prefix(5)) { d in
                    Text(d.vendorName)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
                if entry.deliveries.count > 5 {
                    Text("+\(entry.deliveries.count - 5) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget configuration

struct notifyWidget: Widget {
    let kind: String = "notifyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            notifyWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Notify")
        .description("Today's incoming deliveries.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
