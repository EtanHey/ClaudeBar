import SwiftUI
import Domain

/// Embedded Claude account management section used inside the main configuration card.
struct AccountManagementCard: View {
    let provider: ClaudeProvider

    @Environment(\.appTheme) private var theme
    @State private var aliasDrafts: [String: String] = [:]
    @State private var refreshingAccountId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("AUTH STATUS")

            VStack(spacing: 10) {
                accountSummaryTile(
                    title: "Viewing",
                    account: provider.activeAccount,
                    accent: theme.accentPrimary,
                    detail: activeAccountDetail
                )

                if let primaryAccount = provider.primaryAccount {
                    accountSummaryTile(
                        title: "Bare `claude`",
                        account: primaryAccount,
                        accent: theme.textSecondary,
                        detail: "New shell sessions default here"
                    )
                }
            }

            AccountPickerView(provider: provider) { accountId in
                switchToAccount(accountId)
            }

            VStack(spacing: 8) {
                ForEach(provider.accounts, id: \.id) { account in
                    accountRow(account)
                }
            }

            footerNote
        }
        .onAppear(perform: syncAliasDrafts)
        .onChange(of: provider.accounts.map(\.id)) { _, _ in
            syncAliasDrafts()
        }
    }

    private var activeAccountDetail: String {
        if let snapshot = provider.accountSnapshots[provider.activeAccount.accountId] ?? provider.snapshot {
            return "Loaded \(snapshot.ageDescription)"
        }
        return "Switching here will load usage"
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
            .foregroundStyle(theme.textSecondary)
            .tracking(0.5)
    }

    private func accountSummaryTile(
        title: String,
        account: ProviderAccount,
        accent: Color,
        detail: String
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.14))
                    .frame(width: 28, height: 28)

                Text(account.initialLetter)
                    .font(.system(size: 10, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)

                Text(account.displayName)
                    .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)

                if let email = account.email {
                    Text(email)
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }

                Text(detail)
                    .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.glassBackground.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(theme.glassBorder.opacity(0.6), lineWidth: 1)
                )
        )
    }

    private func accountRow(_ account: ProviderAccount) -> some View {
        let isActive = account.accountId == provider.activeAccount.accountId
        let isPrimary = account.accountId == provider.primaryAccount?.accountId
        let snapshot = provider.accountSnapshots[account.accountId]
        let statusColor = theme.statusColor(for: snapshot?.overallStatus ?? .healthy)
        let isRefreshing = refreshingAccountId == account.accountId

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isActive ? theme.accentPrimary.opacity(0.18) : theme.glassBackground)
                        .frame(width: 24, height: 24)

                    Text(account.initialLetter)
                        .font(.system(size: 10, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(isActive ? theme.accentPrimary : theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(account.displayName)
                            .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)

                        if isActive {
                            subtleBadge("Viewing", color: theme.accentPrimary)
                        }

                        if isPrimary {
                            subtleBadge("Default", color: theme.textSecondary)
                        }
                    }

                    if let email = account.email {
                        Text(email)
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }

                    if let organization = account.organization, organization != account.displayName {
                        Text(organization)
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary.opacity(0.9))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 6) {
                    if let snapshot {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)
                            Text(snapshot.overallStatus.badgeText)
                                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                                .foregroundStyle(theme.textSecondary)
                        }
                    } else if isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Text("Not loaded")
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    }

                    HStack(spacing: 6) {
                        if !isActive {
                            Button {
                                switchToAccount(account.accountId)
                            } label: {
                                subtleAction("View")
                            }
                            .buttonStyle(.plain)
                        }

                        if !isPrimary {
                            Button {
                                _ = provider.setPrimaryAccount(to: account.accountId)
                            } label: {
                                subtleAction("Make Default")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Alias", text: aliasBinding(for: account))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.glassBackground.opacity(0.55))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(theme.glassBorder.opacity(0.55), lineWidth: 1)
                            )
                    )

                if isActive {
                    Button {
                        refreshAccount(account.accountId)
                    } label: {
                        Image(systemName: isRefreshing ? "hourglass" : "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(theme.glassBackground.opacity(0.55))
                                    .overlay(
                                        Circle()
                                            .stroke(theme.glassBorder.opacity(0.55), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? theme.glassBackground.opacity(0.72) : theme.glassBackground.opacity(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isActive
                                ? theme.accentPrimary.opacity(0.22)
                                : theme.glassBorder.opacity(0.45),
                            lineWidth: 1
                        )
                )
        )
    }

    private func subtleBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold, design: theme.fontDesign))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color.opacity(0.10))
                    .overlay(
                        Capsule()
                            .stroke(color.opacity(0.22), lineWidth: 1)
                    )
            )
    }

    private func subtleAction(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(theme.glassBackground.opacity(0.55))
                    .overlay(
                        Capsule()
                            .stroke(theme.glassBorder.opacity(0.5), lineWidth: 1)
                    )
            )
    }

    private var footerNote: some View {
        Text("Uses the same standard Claude auth roots that `claude auth status` resolves: `~/.claude` and `~/.claude-*`.")
            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
            .foregroundStyle(theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func aliasBinding(for account: ProviderAccount) -> Binding<String> {
        Binding(
            get: { aliasDrafts[account.accountId] ?? account.label },
            set: { newValue in
                aliasDrafts[account.accountId] = newValue
                _ = provider.setAlias(newValue, for: account.accountId)
            }
        )
    }

    private func syncAliasDrafts() {
        aliasDrafts = Dictionary(uniqueKeysWithValues: provider.accounts.map { ($0.accountId, $0.label) })
    }

    private func switchToAccount(_ accountId: String) {
        guard provider.switchAccount(to: accountId) else { return }
        guard provider.accountSnapshots[accountId] == nil else { return }
        refreshAccount(accountId)
    }

    private func refreshAccount(_ accountId: String) {
        refreshingAccountId = accountId
        Task {
            try? await provider.refreshAccount(accountId)
            await MainActor.run {
                refreshingAccountId = nil
            }
        }
    }
}
