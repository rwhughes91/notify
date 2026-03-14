//
//  SignInView.swift
//  notify
//
//  Created by Robert Hughes on 3/13/26.
//

import SwiftUI
import GoogleSignInSwift

struct SignInView: View {
    @Environment(GmailService.self) private var gmailService

    @State private var isSigningIn  = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "shippingbox.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 8) {
                Text("Notify")
                    .font(.largeTitle.bold())

                Text("Track your deliveries and returns\nfrom your Gmail inbox.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            GoogleSignInButton(action: signIn)
                .frame(maxWidth: 280)
                .disabled(isSigningIn)

            Spacer()
        }
        .padding(40)
        .frame(minWidth: 420, minHeight: 440)
    }

    private func signIn() {
        isSigningIn  = true
        errorMessage = nil
        Task {
            do {
                try await gmailService.signIn()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSigningIn = false
        }
    }
}
