//
//  GmailService.swift
//  notify
//
//  Created by Robert Hughes on 3/13/26.
//

import Foundation
import GoogleSignIn

/// Full email data passed from GmailService to DeliveryParser.
struct GmailMessage {
    let id: String
    let subject: String?
    let from: String?
    let snippet: String?
    let receivedDate: Date?
    let bodyText: String?   // decoded text/plain part
    let bodyHTML: String?   // decoded text/html part
}

@Observable
class GmailService {

    var isSignedIn: Bool = false

    // MARK: - Auth

    func restoreSignIn() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, _ in
                self?.isSignedIn = (user != nil)
                cont.resume()
            }
        }
    }

    func signIn(presenting window: NSWindow? = nil) async throws {
        let presentingWindow = window
            ?? NSApp.keyWindow
            ?? NSApp.windows.first(where: { $0.isVisible })
            ?? NSApp.windows.first
        guard let win = presentingWindow else { throw GmailError.noWindow }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: win,
                hint: nil,
                additionalScopes: ["https://www.googleapis.com/auth/gmail.readonly"]
            ) { [weak self] result, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    self?.isSignedIn = true
                    cont.resume()
                }
            }
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
    }

    func handle(url: URL) {
        GIDSignIn.sharedInstance.handle(url)
    }

    // MARK: - Fetch deliveries

    func fetchDeliveries(weeks: Int) async throws -> [Delivery] {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            throw GmailError.notSignedIn
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            currentUser.refreshTokensIfNeeded { _, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            }
        }

        let accessToken = currentUser.accessToken.tokenString
        let dateClause  = " after:\(gmailDateString(Date.now.addingTimeInterval(-Double(weeks) * 7 * 86_400)))"

        // Broad query: any email containing "order" (catches most shipping notifications)
        let orderQ  = "order\(dateClause)"
        // Separate return query for emails that may not mention "order"
        let returnQ = "(\"return label\" OR \"return shipping\" OR \"your return\" OR \"drop off\")\(dateClause)"

        print("[GmailService] orderQ:  \(orderQ)")
        print("[GmailService] returnQ: \(returnQ)")

        async let orderMessages  = fetchMessages(query: orderQ,  accessToken: accessToken)
        async let returnMessages = fetchMessages(query: returnQ, accessToken: accessToken)

        // Deduplicate by message ID in case an email matches both queries
        var seen = Set<String>()
        let allMessages = try await (orderMessages + returnMessages).filter {
            seen.insert($0.id).inserted
        }

        print("[GmailService] unique messages: \(allMessages.count)")
        for msg in allMessages {
            print("[GmailService] [\(msg.id)] subject: \(msg.subject ?? "nil")  from: \(msg.from ?? "nil")")
        }

        let deliveries = allMessages.compactMap { DeliveryParser.parse(message: $0) }
        print("[GmailService] deliveries parsed: \(deliveries.count)")
        return deliveries
    }

    // MARK: - Private helpers

    private func fetchMessages(query: String, accessToken: String) async throws -> [GmailMessage] {
        var comps = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        comps.queryItems = [
            URLQueryItem(name: "q",          value: query),
            URLQueryItem(name: "maxResults",  value: "50"),
        ]

        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: req)
        let list = try JSONDecoder().decode(MessageListResponse.self, from: data)

        guard let refs = list.messages, !refs.isEmpty else {
            print("[GmailService] no messages for query: \(query)")
            // Surface API-level errors for debugging
            if let errorJSON = String(data: data, encoding: .utf8), errorJSON.contains("error") {
                print("[GmailService] API error: \(errorJSON)")
            }
            return []
        }

        print("[GmailService] fetching \(refs.count) message details…")
        return try await withThrowingTaskGroup(of: GmailMessage?.self) { group in
            for ref in refs {
                group.addTask {
                    try? await self.fetchMessageDetail(id: ref.id, accessToken: accessToken)
                }
            }
            var results: [GmailMessage] = []
            for try await msg in group {
                if let m = msg { results.append(m) }
            }
            return results
        }
    }

    private func fetchMessageDetail(id: String, accessToken: String) async throws -> GmailMessage {
        // format=full gives us headers + decoded body parts
        let url = URL(string:
            "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=full"
        )!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: req)
        let detail    = try JSONDecoder().decode(MessageDetailResponse.self, from: data)

        let headers   = detail.payload?.headers ?? []
        let subject   = headers.first(where: { $0.name.lowercased() == "subject" })?.value
        let from      = headers.first(where: { $0.name.lowercased() == "from"    })?.value
        let dateStr   = headers.first(where: { $0.name.lowercased() == "date"    })?.value

        var receivedDate: Date?
        if let ds = dateStr {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z"] {
                fmt.dateFormat = format
                if let d = fmt.date(from: ds) { receivedDate = d; break }
            }
        }

        let bodyText = detail.payload.flatMap { extractBody(from: $0, mimeType: "text/plain") }
        let bodyHTML = detail.payload.flatMap { extractBody(from: $0, mimeType: "text/html")  }

        return GmailMessage(
            id: id, subject: subject, from: from,
            snippet: detail.snippet, receivedDate: receivedDate,
            bodyText: bodyText, bodyHTML: bodyHTML
        )
    }

    // MARK: - Body extraction

    /// Recursively walks a MIME payload tree to find the first part matching `mimeType`.
    private func extractBody(from payload: MessagePayload, mimeType: String) -> String? {
        if payload.mimeType?.lowercased() == mimeType,
           let encoded = payload.body?.data {
            return decodeBase64URL(encoded)
        }
        for part in payload.parts ?? [] {
            if let text = extractBody(from: part, mimeType: mimeType) { return text }
        }
        return nil
    }

    private func decodeBase64URL(_ encoded: String) -> String? {
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = base64.count % 4
        if rem > 0 { base64 += String(repeating: "=", count: 4 - rem) }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func gmailDateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy/MM/dd"
        return fmt.string(from: date)
    }
}

// MARK: - Error

enum GmailError: LocalizedError {
    case notSignedIn
    case noWindow

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in to Google."
        case .noWindow:    return "No window available for sign-in presentation."
        }
    }
}

// MARK: - API response models (private)

private struct MessageListResponse: Codable {
    let messages: [MessageRef]?
}

private struct MessageRef: Codable {
    let id: String
    let threadId: String
}

private struct MessageDetailResponse: Codable {
    let id: String
    let snippet: String?
    let payload: MessagePayload?
}

private struct MessagePayload: Codable {
    let mimeType: String?
    let headers: [MessageHeader]?
    let body: MessageBody?
    let parts: [MessagePayload]?
}

private struct MessageBody: Codable {
    let data: String?
    let size: Int?
}

private struct MessageHeader: Codable {
    let name: String
    let value: String
}
