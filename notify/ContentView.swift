//
//  ContentView.swift
//  notify
//
//  Created by Robert Hughes on 3/13/26.
//

import SwiftUI

/// Routes to SignInView or DeliveryListView based on authentication state.
struct ContentView: View {
    @Environment(GmailService.self) private var gmailService

    var body: some View {
        if gmailService.isSignedIn {
            DeliveryListView()
        } else {
            SignInView()
        }
    }
}
