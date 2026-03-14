//
//  Delivery.swift
//  notify
//
//  Created by Robert Hughes on 3/13/26.
//

import Foundation

enum Carrier: String, Codable, CaseIterable, Hashable {
    case amazon  = "Amazon"
    case ups     = "UPS"
    case fedex   = "FedEx"
    case usps    = "USPS"
    case dhl     = "DHL"
    case unknown = "Unknown"
}

enum DeliveryStatus: String, Codable, Hashable {
    case ordered         = "Ordered"
    case shipped         = "Shipped"
    case outForDelivery  = "Out for Delivery"
    case delivered       = "Delivered"
    case returnInitiated = "Return Initiated"
    case returnShipped   = "Return Shipped"
    case returnDelivered = "Return Delivered"
    case unknown         = "Unknown"
}

enum DeliveryKind: String, Codable, Hashable {
    case incoming = "Incoming"
    case `return` = "Return"
}

struct Delivery: Codable, Identifiable, Hashable {
    var id: String { emailMessageId }

    var carrier: Carrier
    var trackingNumber: String
    var expectedDate: Date?
    var status: DeliveryStatus
    var kind: DeliveryKind
    var emailMessageId: String
    var subject: String
    var receivedDate: Date
    var fromEmail: String           // raw From header, e.g. "Amazon <ship@amazon.com>"
    var trackingURLString: String?  // best tracking URL found in email body

    // MARK: - Computed

    /// Direct link to open this email in Gmail.
    var gmailURL: URL {
        URL(string: "https://mail.google.com/mail/u/0/#inbox/\(emailMessageId)")!
    }

    /// Resolved tracking URL (from body, or nil).
    var trackingURL: URL? {
        trackingURLString.flatMap { URL(string: $0) }
    }

    /// Human-readable vendor name parsed from the From header.
    var vendorName: String {
        // "Display Name <email@domain.com>" → "Display Name"
        if let ltIdx = fromEmail.firstIndex(of: "<") {
            let name = String(fromEmail[fromEmail.startIndex..<ltIdx])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !name.isEmpty { return name }
        }
        // "email@domain.com" → domain capitalized
        if let atIdx = fromEmail.firstIndex(of: "@") {
            let domain = String(fromEmail[fromEmail.index(after: atIdx)...])
            if let firstPart = domain.split(separator: ".").first {
                return String(firstPart).capitalized
            }
        }
        return fromEmail.isEmpty ? carrier.rawValue : fromEmail
    }
}
