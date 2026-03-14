//
//  DeliveryListView.swift
//  notify
//
//  Created by Robert Hughes on 3/13/26.
//

import SwiftUI

struct DeliveryListView: View {
    @Environment(DeliveryStore.self)  private var store
    @Environment(GmailService.self)   private var gmailService

    @State private var selectedDelivery: Delivery?
    @State private var isSyncing    = false
    @State private var syncError: String?
    @State private var lookbackWeeks = 1

    var body: some View {
        NavigationSplitView {
            listContent
                .navigationTitle("Notify")
                .toolbar { toolbar }
                .overlay(alignment: .bottom) { errorBanner }
        } detail: {
            if let delivery = selectedDelivery {
                DeliveryDetailView(delivery: delivery)
            } else {
                ContentUnavailableView("Select a Delivery",
                                       systemImage: "shippingbox.fill")
            }
        }
        .task { await syncDeliveries() }
        .onChange(of: lookbackWeeks) { _, _ in
            Task { await syncDeliveries() }
        }
    }

    // MARK: - List content

    @ViewBuilder
    private var listContent: some View {
        List(selection: $selectedDelivery) {
            Section {
                HStack {
                    Text("Scan last")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $lookbackWeeks) {
                        Text("1 week").tag(1)
                        Text("2 weeks").tag(2)
                        Text("4 weeks").tag(4)
                        Text("8 weeks").tag(8)
                        Text("12 weeks").tag(12)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(isSyncing)
                }
            }
            if !store.todayDeliveries.isEmpty {
                Section("Today") {
                    ForEach(store.todayDeliveries) { delivery in
                        DeliveryRowView(delivery: delivery).tag(delivery)
                    }
                }
            }

            if !store.upcomingDeliveries.isEmpty {
                Section("Upcoming") {
                    ForEach(store.upcomingDeliveries) { delivery in
                        DeliveryRowView(delivery: delivery).tag(delivery)
                    }
                }
            }

            if !store.deliveredDeliveries.isEmpty {
                Section("Delivered") {
                    ForEach(store.deliveredDeliveries) { delivery in
                        DeliveryRowView(delivery: delivery).tag(delivery)
                    }
                }
            }

            if !store.returnDeliveries.isEmpty {
                Section("Returns") {
                    ForEach(store.returnDeliveries) { delivery in
                        DeliveryRowView(delivery: delivery).tag(delivery)
                    }
                }
            }

            if store.deliveries.isEmpty && !isSyncing {
                ContentUnavailableView(
                    "No Deliveries",
                    systemImage: "shippingbox",
                    description: Text("No shipping emails found in the last \(lookbackWeeks) week\(lookbackWeeks == 1 ? "" : "s").")
                )
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await syncDeliveries() }
            } label: {
                if isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(isSyncing)
            .keyboardShortcut("r", modifiers: .command)
            .help("Sync deliveries from Gmail")
        }

        ToolbarItem(placement: .destructiveAction) {
            Button("Sign Out", role: .destructive) {
                store.signOut()
                gmailService.signOut()
            }
        }
    }

    // MARK: - Error banner

    @ViewBuilder
    private var errorBanner: some View {
        if let error = syncError {
            Text(error)
                .font(.caption)
                .padding(8)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Sync

    private func syncDeliveries() async {
        isSyncing = true
        syncError = nil
        do {
            let deliveries = try await gmailService.fetchDeliveries(weeks: lookbackWeeks)
            store.replace(deliveries)
        } catch {
            syncError = "Sync failed: \(error.localizedDescription)"
        }
        isSyncing = false
    }
}
