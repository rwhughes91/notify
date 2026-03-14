//
//  DeliveryRowView.swift
//  notify
//
//  Created by Robert Hughes on 3/13/26.
//

import SwiftUI

struct DeliveryRowView: View {
    let delivery: Delivery

    var body: some View {
        HStack(spacing: 12) {
            carrierIcon

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(delivery.vendorName)
                        .fontWeight(.medium)

                    if delivery.kind == .return {
                        Text("RETURN")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18))
                            .foregroundStyle(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Spacer()

                    statusBadge
                }

                Text(delivery.subject)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let date = delivery.expectedDate {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Sub-views

    private var carrierIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(carrierColor.opacity(0.15))
                .frame(width: 36, height: 36)
            Image(systemName: carrierSystemImage)
                .foregroundStyle(carrierColor)
        }
    }

    private var statusBadge: some View {
        Text(delivery.status.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }

    // MARK: - Helpers

    private var carrierColor: Color {
        switch delivery.carrier {
        case .amazon:  return .orange
        case .ups:     return Color(red: 0.6, green: 0.35, blue: 0.1)
        case .fedex:   return .purple
        case .usps:    return .blue
        case .dhl:     return Color(red: 0.9, green: 0.7, blue: 0.0)
        case .unknown: return .gray
        }
    }

    private var carrierSystemImage: String {
        switch delivery.carrier {
        case .amazon:           return "cart.fill"
        case .ups, .fedex, .dhl: return "shippingbox.fill"
        case .usps:             return "envelope.fill"
        case .unknown:          return "questionmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch delivery.status {
        case .delivered, .returnDelivered:  return .green
        case .outForDelivery:               return .blue
        case .shipped, .returnShipped:      return .indigo
        case .ordered, .returnInitiated:    return .gray
        case .unknown:                      return .gray
        }
    }
}
