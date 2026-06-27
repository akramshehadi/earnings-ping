import SwiftUI

/// The dedicated Settings window (opened with ⌘, or the popover's gear button).
///
/// Doubles as first-run onboarding: with no key stored it leads with a welcome
/// + key-entry section; once a key exists that collapses to a compact
/// "stored / Change / Remove" row and the rest of the preferences take over.
struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var loginItem: LoginItemController

    /// Mirrors `environment.hasStoredAPIKey()`; seeded in `.task` (an off-main-
    /// thread Keychain read) and flipped locally when the user saves or removes a
    /// key (the store isn't `@Published`). Defaults to `true` so the onboarding
    /// form never flashes before the read resolves for the common (key-present) case.
    @State private var hasKey = true
    @State private var isEditingKey = false

    private static let signupURL = URL(string: "https://finnhub.io/register")!

    var body: some View {
        VStack(spacing: 0) {
            Form {
                apiKeySection
                remindersSection
                refreshSection
                watchlistSection
                generalSection
            }
            .formStyle(.grouped)

            Divider()

            // Explicit dismiss: a menu-bar-only app has no Close menu item, so the
            // red button is the only other way out. Labeled "Done" (not "Save")
            // because every setting persists the moment it changes.
            HStack {
                Spacer()
                Button("Done") { SettingsWindowOpener.shared.close() }
                    .keyboardShortcut("w", modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 460)
        .frame(minHeight: 540)
        .task {
            // Off-main-thread Keychain read (see AppEnvironment.hasStoredAPIKey)
            // so an ACL prompt can't freeze the Settings window on open.
            hasKey = await environment.hasStoredAPIKey()
            loginItem.refresh()
        }
    }

    // MARK: - API key / onboarding

    @ViewBuilder
    private var apiKeySection: some View {
        if hasKey && !isEditingKey {
            Section("API Key") {
                LabeledContent("Finnhub key") {
                    HStack(spacing: 8) {
                        Label("Stored in Keychain", systemImage: "key.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Spacer()
                        Button("Change…") { isEditingKey = true }
                        Button("Remove", role: .destructive, action: removeKey)
                    }
                }
            }
        } else {
            Section(hasKey ? "Change API Key" : "Set up Earnings Ping") {
                if !hasKey {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Earnings Ping needs a free Finnhub API key to fetch earnings dates. It's stored only in your macOS Keychain — there's no account and no server.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Link("Get a free key at finnhub.io →", destination: Self.signupURL)
                            .font(.callout)
                    }
                    .padding(.vertical, 2)
                }

                APIKeyEntry(onSaved: {
                    hasKey = true
                    isEditingKey = false
                })

                if isEditingKey {
                    Button("Cancel") { isEditingKey = false }
                        .buttonStyle(.link)
                }
            }
        }
    }

    private func removeKey() {
        try? environment.apiKeyStore.deleteKey()
        hasKey = false
        isEditingKey = false
    }

    // MARK: - Preferences

    private var remindersSection: some View {
        Section("Reminders & Alerts") {
            Stepper(value: $settings.leadTimeTradingDays, in: 0...AppSettings.maxLeadTimeTradingDays) {
                LabeledContent("Reminder lead time", value: leadTimeLabel)
            }
            Stepper(value: $settings.imminentWindowDays, in: 1...AppSettings.maxImminentWindowDays) {
                LabeledContent("Imminent window", value: dayCount(settings.imminentWindowDays))
            }
            Text("The lead time picks the morning a reminder fires (trading days). The imminent window is when the menu-bar icon starts badging (calendar days).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var refreshSection: some View {
        Section("Refresh") {
            Stepper(value: $settings.refreshIntervalHours,
                    in: AppSettings.minRefreshIntervalHours...AppSettings.maxRefreshIntervalHours) {
                LabeledContent("Check for date changes every", value: hourCount(settings.refreshIntervalHours))
            }
        }
    }

    private var watchlistSection: some View {
        Section("Watchlist") {
            Stepper(value: $settings.maxWatchlistSize, in: 1...AppSettings.maxWatchlistCeiling) {
                LabeledContent("Maximum tickers", value: "\(settings.maxWatchlistSize)")
            }
            Picker("Sort order", selection: $settings.watchlistSortOrder) {
                ForEach(WatchlistSortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
        }
    }

    private var generalSection: some View {
        Section("General") {
            Toggle(isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at Login")
                    Text("Reminders and date-change alerts only fire while Earnings Ping is running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let error = loginItem.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            LabeledContent("Provider", value: "Finnhub")
        }
    }

    // MARK: - Formatting

    private var leadTimeLabel: String {
        let n = settings.leadTimeTradingDays
        return n == 0 ? "Same morning" : "\(n) trading day\(n == 1 ? "" : "s") before"
    }

    private func dayCount(_ n: Int) -> String { "\(n) day\(n == 1 ? "" : "s")" }
    private func hourCount(_ n: Int) -> String { "\(n) hour\(n == 1 ? "" : "s")" }
}

// MARK: - Key entry

/// Paste → validate → store-in-Keychain control, shared by onboarding and the
/// "Change key" flow. Only a key that authenticates against the provider is
/// saved (acceptance: invalid key rejected at onboarding).
private struct APIKeyEntry: View {
    @EnvironmentObject private var environment: AppEnvironment

    /// Called after a key is validated and written, so the parent can leave the
    /// editing/onboarding state.
    let onSaved: () -> Void

    @State private var keyInput = ""
    @State private var status: Status = .idle

    private enum Status: Equatable {
        case idle, validating, rejected(String), saved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SecureField("Paste your Finnhub API key", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("Validate & Save", action: save)
                    .disabled(trimmed.isEmpty || status == .validating)
            }
            statusLine
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .idle:
            EmptyView()
        case .validating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking key…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .rejected(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        case .saved:
            Label("Key saved.", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    private var trimmed: String {
        keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let candidate = trimmed
        guard !candidate.isEmpty else { return }
        status = .validating
        Task {
            switch await environment.apiKeyValidator.validate(candidate) {
            case .valid:
                do {
                    try environment.apiKeyStore.setKey(candidate)
                    status = .saved
                    keyInput = ""
                    // Fetch immediately so the watchlist fills without waiting
                    // for the next timer tick.
                    environment.refreshCoordinator.refreshNow()
                    onSaved()
                } catch {
                    status = .rejected("Couldn't save to Keychain: \(error.localizedDescription)")
                }
            case .invalid:
                status = .rejected("That key was rejected. Double-check it and try again.")
            case .networkError(let message):
                status = .rejected("Couldn't reach Finnhub: \(message)")
            }
        }
    }
}
