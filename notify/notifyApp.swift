//
//  notifyApp.swift
//  notify
//
//  Created by Robert Hughes on 3/13/26.
//

import SwiftUI
import GoogleSignIn

@main
struct notifyApp: App {
    @State private var store        = DeliveryStore()
    @State private var gmailService = GmailService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(gmailService)
                .task {
                    // Restore previous Google sign-in on launch
                    await gmailService.restoreSignIn()
                }
                .onOpenURL { url in
                    // Handle OAuth redirect from Google
                    gmailService.handle(url: url)
                }
        }
    }
}
