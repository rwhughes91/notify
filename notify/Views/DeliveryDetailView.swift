//
//  DeliveryDetailView.swift
//  notify
//
//  Created by Robert Hughes on 3/13/26.
//

import SwiftUI

struct DeliveryDetailView: View {
    let delivery: Delivery

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(delivery.vendorName)
                            .font(.title2.bold())
                        if delivery.kind == .return {
                            Label("Return Shipment",
                                  systemImage: "arrow.uturn.left.circle.fill")
                                .foregroundStyle(.orange)
                                .font(.subheadline)
                        }
                    }
                    Spacer()
                    Text(delivery.status.rawValue)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.15))
                        .foregroundStyle(statusColor)
                        .clipShape(Capsule())
                }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {

                    // Subject
                    GridRow {
                        label("Subject")
                        Text(delivery.subject)
                            .textSelection(.enabled)
                    }

                    // From
                    GridRow {
                        label("From")
                        Text(delivery.fromEmail)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }

                    // Tracking
                    GridRow {
                        label("Tracking")
                        if delivery.trackingNumber != "N/A" {
                            if let url = delivery.trackingURL {
                                Link(delivery.trackingNumber, destination: url)
                                    .textSelection(.enabled)
                            } else {
                                Text(delivery.trackingNumber)
                                    .textSelection(.enabled)
                            }
                        } else if let url = delivery.trackingURL {
                            Link("View tracking", destination: url)
                        } else {
                            Text("Not found").foregroundStyle(.secondary)
                        }
                    }

                    // Expected / sent date
                    if let date = delivery.expectedDate {
                        GridRow {
                            label(delivery.kind == .return ? "Sent" : "Expected")
                            Text(date, style: .date)
                        }
                    }

                    // Email received date
                    GridRow {
                        label("Email Date")
                        Text(delivery.receivedDate, style: .date)
                    }

                    // Open in Gmail
                    GridRow {
                        label("Gmail")
                        Link("Open email", destination: delivery.gmailURL)
                    }
                }

                Spacer()
            }
            .padding(24)
        }
        .navigationTitle(delivery.vendorName)
    }

    // MARK: - Helpers

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }

    private var statusColor: Color {
        switch delivery.status {
        case .delivered, .returnDelivered:  return .green
        case .outForDelivery:               return .blue
        case .shipped, .returnShipped:      return .indigo
        case .ordered, .returnInitiated,
             .unknown:                      return .gray
        }
    }
}
