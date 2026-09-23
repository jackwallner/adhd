import SwiftUI
@preconcurrency import RevenueCat

struct NextCuePaywallView: View {
    @EnvironmentObject private var purchases: StoreService
    @Environment(\.dismiss) private var dismiss

    @State private var selection: NextCuePlan = .yearly

    init() {
        _selection = State(initialValue: NextCueDebugLaunch.paywallPlan)
    }

    private var selectedPackage: Package? {
        switch selection {
        case .yearly: purchases.yearly
        case .monthly: purchases.monthly
        case .lifetime: purchases.lifetime
        }
    }

    private var selectedTrial: String? {
        guard let package = selectedPackage, selection != .lifetime,
              purchases.isEligibleForTrial(package) else { return nil }
        return package.trialLabel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Make room for more routines")
                            .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                            .foregroundStyle(NextCueStyle.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Your first routine is free. Pro lets you make one for every part of your day.")
                            .font(.body)
                            .foregroundStyle(NextCueStyle.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 12) {
                        NextCueBenefit(symbol: "list.bullet.rectangle", title: "Unlimited routines", detail: "Create a separate routine for mornings, work, evenings, and more.")
                        NextCueBenefit(symbol: "calendar.badge.clock", title: "A schedule for every routine", detail: "Set different days and reminder times as your week changes.")
                    }

                    VStack(spacing: 10) {
                        if let yearly = purchases.yearly {
                            NextCuePlanCard(package: yearly, title: "Yearly", note: trialNote(for: yearly), badge: savingsBadge, selected: selection == .yearly) {
                                selection = .yearly
                            }
                        }
                        if let monthly = purchases.monthly {
                            NextCuePlanCard(package: monthly, title: "Monthly", note: trialNote(for: monthly), badge: nil, selected: selection == .monthly) {
                                selection = .monthly
                            }
                        }
                        if let lifetime = purchases.lifetime {
                            NextCuePlanCard(package: lifetime, title: "Lifetime", note: "One-time purchase · no renewal", badge: nil, selected: selection == .lifetime) {
                                selection = .lifetime
                            }
                        }
                        if purchases.packages.isEmpty {
                            ProgressView("Loading plans")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 22)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }
            .background(NextCueStyle.background.ignoresSafeArea())
            .navigationTitle("Next Cue Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .accessibilityLabel("Close subscription options")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { purchaseFooter }
            .onAppear { purchases.trackPaywallImpression(id: "nextcue_main") }
            .onChange(of: purchases.isPro) { _, isPro in
                if isPro { dismiss() }
            }
        }
        .tint(NextCueStyle.accent)
    }

    private var purchaseFooter: some View {
        VStack(spacing: 9) {
            if let error = purchases.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(NextCueStyle.danger)
                    .multilineTextAlignment(.center)
            }

            if let selectedPackage {
                Text(renewalDisclosure(for: selectedPackage))
                    .font(.caption)
                    .foregroundStyle(NextCueStyle.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Plans and prices are provided by the App Store.")
                    .font(.caption)
                    .foregroundStyle(NextCueStyle.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: purchaseSelected) {
                ZStack {
                    Text(purchaseButtonTitle).opacity(purchases.isPurchasing ? 0 : 1)
                    if purchases.isPurchasing { ProgressView().tint(.white) }
                }
            }
            .buttonStyle(NextCuePrimaryButtonStyle())
            .disabled(purchases.isPurchasing || selectedPackage == nil)

            Button("Restore purchases") {
                Task { await purchases.restore() }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(NextCueStyle.secondary)
            .disabled(purchases.isPurchasing)

            HStack(spacing: 16) {
                Link("Privacy Policy", destination: NextCueLinks.privacy)
                Link("Terms", destination: NextCueLinks.terms)
                Link("Apple Standard EULA", destination: NextCueLinks.eula)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(NextCueStyle.secondary)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(NextCueStyle.background)
    }

    private var purchaseButtonTitle: String {
        if selection == .lifetime { return "Get lifetime access" }
        if let selectedTrial { return "Start \(selectedTrial)" }
        return selection == .yearly ? "Continue with yearly" : "Continue monthly"
    }

    private func trialNote(for package: Package) -> String? {
        guard purchases.isEligibleForTrial(package), let trial = package.trialLabel else { return nil }
        return "\(trial) included"
    }

    private var savingsBadge: String? {
        guard let yearly = purchases.yearly, let monthly = purchases.monthly else { return nil }
        let annualPrice = NSDecimalNumber(decimal: yearly.storeProduct.price).doubleValue
        let monthlyPrice = NSDecimalNumber(decimal: monthly.storeProduct.price).doubleValue
        guard monthlyPrice > 0 else { return nil }
        let percentage = Int(((1 - annualPrice / (monthlyPrice * 12)) * 100).rounded())
        return percentage >= 10 ? "Save \(percentage)%" : nil
    }

    private func renewalDisclosure(for package: Package) -> String {
        if selection == .lifetime {
            return "\(package.storeProduct.localizedPriceString) one time. No subscription or automatic renewal."
        }
        if let selectedTrial {
            let duration = selectedTrial.replacingOccurrences(of: " free trial", with: "")
            return "\(duration) free, then \(package.billedLabel). Automatically renews at that price unless cancelled at least 24 hours before the current period ends. Manage or cancel in your Apple Account subscription settings."
        }
        return "\(package.billedLabel), billed now and automatically renewed unless cancelled at least 24 hours before the current period ends. Manage or cancel in your Apple Account subscription settings."
    }

    private func purchaseSelected() {
        guard let selectedPackage else { return }
        Task { _ = await purchases.purchase(selectedPackage) }
    }
}

enum NextCuePlan: String {
    case yearly
    case monthly
    case lifetime
}

private struct NextCuePlanCard: View {
    let package: Package
    let title: String
    let note: String?
    let badge: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? NextCueStyle.accent : NextCueStyle.line)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(NextCueStyle.ink)
                        if let badge {
                            Text(badge.uppercased())
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .tracking(0.4)
                                .foregroundStyle(NextCueStyle.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(NextCueStyle.accentWash, in: Capsule())
                        }
                    }
                    if let note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(NextCueStyle.secondary)
                    }
                }
                Spacer(minLength: 4)
                Text(package.billedLabel)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(NextCueStyle.ink)
                    .multilineTextAlignment(.trailing)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NextCueStyle.surface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .strokeBorder(selected ? NextCueStyle.accent : NextCueStyle.line, lineWidth: selected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct NextCueBenefit: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            NextCueIcon(symbol: symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(NextCueStyle.ink)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(NextCueStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
    }
}
