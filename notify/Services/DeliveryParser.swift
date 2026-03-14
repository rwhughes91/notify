//
//  DeliveryParser.swift
//  notify
//
//  Created by Robert Hughes on 3/13/26.
//

import Foundation

enum DeliveryParser {

    static func parse(message: GmailMessage) -> Delivery? {
        let subject  = message.subject?.lowercased() ?? ""
        let from     = message.from?.lowercased() ?? ""
        // Prefer full body over snippet for richer parsing
        let bodyText = message.bodyText?.lowercased()
            ?? stripHTML(message.bodyHTML ?? "").lowercased()
        let combined = subject + " " + from + " " + bodyText

        let kind     = detectKind(subject: subject, body: bodyText)
        let carrier  = detectCarrier(sender: from, subject: subject, body: bodyText)

        // Extract tracking URL from HTML body (href values), then fall back to text
        let trackingURLString = extractTrackingURL(
            bodyHTML: message.bodyHTML ?? "",
            bodyText: bodyText,
            carrier: carrier
        )

        // Try to pull tracking number out of the URL first, then regex the body
        let trackingNumber = trackingNumberFromURL(trackingURLString)
            ?? extractTrackingNumber(from: combined, carrier: carrier)

        let expectedDate = extractExpectedDate(from: combined)
        let status       = extractStatus(from: combined, kind: kind)

        // Drop pure receipts / order confirmations that have no shipping signals
        let shippingSignals = [
            "shipped", "on its way", "on the way", "out for delivery",
            "in transit", "has shipped", "tracking", "arriving",
            "estimated delivery", "expected delivery", "delivery by",
            "has been delivered", "was delivered", "return label",
        ]
        let hasShippingSignal = shippingSignals.contains { combined.contains($0) }
        let hasTrackingData   = trackingURLString != nil || trackingNumber != "N/A"
        guard hasShippingSignal || hasTrackingData else {
            print("[DeliveryParser] skipping receipt/non-shipping email: \(message.subject ?? "nil")")
            return nil
        }

        return Delivery(
            carrier: carrier,
            trackingNumber: trackingNumber,
            expectedDate: expectedDate,
            status: status,
            kind: kind,
            emailMessageId: message.id,
            subject: message.subject ?? "",
            receivedDate: message.receivedDate ?? .now,
            fromEmail: message.from ?? "",
            trackingURLString: trackingURLString
        )
    }

    // MARK: - Kind

    private static func detectKind(subject: String, body: String) -> DeliveryKind {
        let keywords = ["return label", "return shipping", "your return",
                        "drop off", "return confirmation", "returning your",
                        "refund initiated"]
        for kw in keywords where subject.contains(kw) || body.contains(kw) {
            return .return
        }
        return .incoming
    }

    // MARK: - Carrier

    private static func detectCarrier(sender: String, subject: String, body: String) -> Carrier {
        let all = sender + " " + subject + " " + body
        if all.contains("amazon")           { return .amazon }
        if all.contains("ups.com") || subject.contains(" ups ") || body.contains(" ups ") { return .ups }
        if all.contains("fedex")            { return .fedex  }
        if all.contains("usps")             { return .usps   }
        if all.contains(" dhl ") || sender.contains("dhl") { return .dhl }
        return .unknown
    }

    // MARK: - Tracking URL extraction

    private static let knownTrackingPatterns = [
        "ups.com/track",
        "fedex.com/apps/fedextrack",
        "fedex.com/tracking",
        "tools.usps.com",
        "m.usps.com",
        "dhl.com",
        "amazon.com/progress-tracker",
        "amazon.com/gp/css/order-tracking",
        "amazon.com/dp/",
    ]

    /// Searches HTML href attributes first, then plain text, for a known carrier tracking URL.
    private static func extractTrackingURL(bodyHTML: String, bodyText: String, carrier: Carrier) -> String? {
        // 1. Pull all href="…" values from the HTML email
        let hrefRegex = try? NSRegularExpression(pattern: #"href="([^"]+)""#, options: .caseInsensitive)
        let nsHTML    = bodyHTML as NSString
        let matches   = hrefRegex?.matches(in: bodyHTML,
                                           range: NSRange(location: 0, length: nsHTML.length)) ?? []
        for match in matches {
            guard let r = Range(match.range(at: 1), in: bodyHTML) else { continue }
            let href      = String(bodyHTML[r])
            let hrefLower = href.lowercased()
            for pattern in knownTrackingPatterns where hrefLower.contains(pattern) {
                // Decode &amp; entities before returning
                return href.replacingOccurrences(of: "&amp;", with: "&")
            }
        }

        // 2. NSDataDetector on plain text (catches plain-text emails)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let nsText  = bodyText as NSString
            let textMatches = detector.matches(in: bodyText,
                                               range: NSRange(location: 0, length: nsText.length))
            for match in textMatches {
                guard let url = match.url else { continue }
                let lower = url.absoluteString.lowercased()
                for pattern in knownTrackingPatterns where lower.contains(pattern) {
                    return url.absoluteString
                }
            }
        }

        return nil
    }

    /// Attempts to pull a tracking number out of a known tracking URL.
    private static func trackingNumberFromURL(_ urlString: String?) -> String? {
        guard let str = urlString else { return nil }
        // UPS: tracknum=1Z…
        if let r = str.range(of: #"(?:tracknum|tracknumbers?|trackingnumber)=([^&\s]+)"#,
                              options: [.regularExpression, .caseInsensitive]) {
            let full = String(str[r])
            if let eq = full.firstIndex(of: "=") {
                let tn = String(full[full.index(after: eq)...])
                if !tn.isEmpty { return tn }
            }
        }
        return nil
    }

    // MARK: - Tracking number (regex on body)

    private static func extractTrackingNumber(from text: String, carrier: Carrier) -> String {
        if carrier == .ups || carrier == .unknown {
            if let m = text.range(of: #"1Z[A-Z0-9]{16}"#,
                                  options: [.regularExpression, .caseInsensitive]) {
                return String(text[m]).uppercased()
            }
        }
        if carrier == .usps || carrier == .unknown {
            if let m = text.range(of: #"\b9\d{19,21}\b"#, options: .regularExpression) {
                return String(text[m])
            }
        }
        if carrier == .fedex || carrier == .unknown {
            if let m = text.range(of: #"\b\d{12,20}\b"#, options: .regularExpression) {
                return String(text[m])
            }
        }
        if carrier == .amazon || carrier == .unknown {
            if let m = text.range(of: #"\d{3}-\d{7}-\d{7}"#, options: .regularExpression) {
                return String(text[m])
            }
        }
        return "N/A"
    }

    // MARK: - Expected date

    private static func extractExpectedDate(from text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let calendar    = Calendar.current
        let currentYear = calendar.component(.year, from: .now)

        let candidates: [(format: String, pattern: String)] = [
            ("MMMM d, yyyy",
             #"(january|february|march|april|may|june|july|august|september|october|november|december) \d{1,2}, \d{4}"#),
            ("MMMM d",
             #"(january|february|march|april|may|june|july|august|september|october|november|december) \d{1,2}"#),
            ("MMM d, yyyy",
             #"(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\.? \d{1,2}, \d{4}"#),
            ("MMM d",
             #"(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\.? \d{1,2}"#),
            ("M/d/yyyy",
             #"\d{1,2}/\d{1,2}/\d{4}"#),
        ]

        for (format, pattern) in candidates {
            guard let range = text.range(of: pattern,
                                         options: [.regularExpression, .caseInsensitive])
            else { continue }
            formatter.dateFormat = format
            guard var date = formatter.date(from: String(text[range])) else { continue }

            if !format.contains("y") {
                var comps = calendar.dateComponents([.month, .day], from: date)
                comps.year = currentYear
                if let d = calendar.date(from: comps) {
                    date = d
                    if date < Date.now.addingTimeInterval(-86_400) {
                        comps.year = currentYear + 1
                        date = calendar.date(from: comps) ?? date
                    }
                }
            }
            return date
        }
        return nil
    }

    // MARK: - Status

    private static func extractStatus(from text: String, kind: DeliveryKind) -> DeliveryStatus {
        if kind == .return {
            let returnDeliveredPhrases = ["has been delivered", "was delivered", "received your return"]
            if returnDeliveredPhrases.contains(where: { text.contains($0) }) { return .returnDelivered }
            if text.contains("shipped") || text.contains("in transit")       { return .returnShipped   }
            return .returnInitiated
        }

        if text.contains("out for delivery") { return .outForDelivery }

        // Require explicit past-tense delivery language — avoids matching
        // "will be delivered", "estimated delivery date", "expected to be delivered", etc.
        let deliveredPhrases = [
            "has been delivered",
            "was delivered",
            "successfully delivered",
            "package has been delivered",
            "your delivery is complete",
            "delivered to your",
            "delivered at your",
            "item delivered",
        ]
        if deliveredPhrases.contains(where: { text.contains($0) }) { return .delivered }

        if text.contains("shipped") || text.contains("on its way")
            || text.contains("on the way") || text.contains("in transit")
            || text.contains("has shipped") || text.contains("order shipped") { return .shipped }

        return .ordered
    }

    // MARK: - HTML strip

    static func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
    }
}
