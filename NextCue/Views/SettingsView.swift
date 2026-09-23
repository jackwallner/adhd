import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var routines: RoutineStore
    @EnvironmentObject private var purchases: StoreService
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Form {
                remindersSection
                subscriptionSection
                privacySection
                feedbackSection
                aboutSection

                #if DEBUG
                Section("Debug") {
                    Toggle("Pro access", isOn: Binding(
                        get: { purchases.isPro },
                        set: { purchases.setLocalOverride(isPro: $0) }
                    ))
                }
                #endif
            }
            .scrollContentBackground(.hidden)
            .background(NextCueStyle.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPaywall) { NextCuePaywallView() }
            .task { await refreshNotificationStatus() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task {
                    routines.refreshReminders()
                    await refreshNotificationStatus()
                }
            }
        }
        .tint(NextCueStyle.accent)
    }

    private var remindersSection: some View {
        Section {
            LabeledContent("Permission", value: notificationStatusTitle)
            if notificationStatus == .notDetermined {
                Button {
                    Task { await askForReminderPermission() }
                } label: {
                    Label("Allow reminder alerts", systemImage: "bell.badge")
                }
            } else if notificationStatus == .denied {
                Button("Open notification settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Set a time and days inside each routine. Reminders follow the schedule you choose.")
        }
    }

    private var subscriptionSection: some View {
        Section {
            if purchases.isPro {
                Label("Next Cue Pro is active", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(NextCueStyle.success)
                Link("Manage subscription", destination: NextCueLinks.appleSubscriptions)
            } else {
                Button("See Next Cue Pro") { showPaywall = true }
                    .fontWeight(.semibold)
            }
            Button("Restore purchases") {
                Task { await purchases.restore() }
            }
            .disabled(purchases.isPurchasing)
            if let errorMessage = purchases.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(NextCueStyle.danger)
            }
        } header: {
            Text("Subscription")
        } footer: {
            if !purchases.isPro {
                Text("One routine is free. Pro adds unlimited routines, with monthly, yearly, and lifetime options.")
            }
        }
    }

    private var privacySection: some View {
        Section {
            Link("Privacy Policy", destination: NextCueLinks.privacy)
            Link("Terms of Use", destination: NextCueLinks.terms)
            Link("Apple Standard EULA", destination: NextCueLinks.eula)
        } header: {
            Text("Privacy and terms")
        } footer: {
            Text("Next Cue uses the details you add to show your routines and schedule reminders. The Privacy Policy explains data handling.")
        }
    }

    private var feedbackSection: some View {
        Section("Feedback") {
            Button("Rate Next Cue") { requestReview() }
            Link("Send feedback", destination: NextCueLinks.feedback)
            Link("Help and support", destination: NextCueLinks.support)
        }
    }

    private var aboutSection: some View {
        Section {
            Text("Next Cue is a routine and planning tool. It does not provide medical advice, diagnose, or treat ADHD or any health condition.")
                .font(.footnote)
                .foregroundStyle(NextCueStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
        } header: {
            Text("About Next Cue")
        }
    }

    private var notificationStatusTitle: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Off"
        case .notDetermined: "Not set up"
        @unknown default: "Unknown"
        }
    }

    @MainActor
    private func refreshNotificationStatus() async {
        notificationStatus = await ReminderService.authorizationStatus()
    }

    @MainActor
    private func askForReminderPermission() async {
        let granted = await ReminderService.requestAuthorization()
        if granted { routines.refreshReminders() }
        await refreshNotificationStatus()
    }
}

enum NextCueLinks {
    static let privacy = URL(string: "https://jackwallner.github.io/adhd/privacy-policy.html")!
    static let support = URL(string: "https://jackwallner.github.io/adhd/support.html")!
    static let terms = URL(string: "https://jackwallner.github.io/adhd/terms.html")!
    static let eula = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let appleSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
    static let feedback = URL(string: "mailto:jackwallner@gmail.com?subject=Next%20Cue%20feedback")!
}
