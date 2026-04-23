import SwiftUI
import Domain

/// Displays cached local Codex analytics derived from `@ccusage/codex`.
struct CodexLocalAnalyticsBlockView: View {
    let report: CodexLocalAnalyticsReport
    let delay: Double

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Local Analytics")
                    .font(.system(size: 11, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .tracking(0.3)

                Spacer()

                Text("Powered by @ccusage/codex")
                    .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            section(title: "Today", slice: report.today, delay: delay)
            section(title: "This Month", slice: report.thisMonth, delay: delay + 0.18)
            section(title: "Latest Session", slice: report.latestSession, delay: delay + 0.36)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func section(title: String, slice: CodexLocalAnalyticsSlice, delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.3)

                if let referenceLabel = slice.referenceLabel, !referenceLabel.isEmpty {
                    Text(referenceLabel)
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ],
                spacing: 10
            ) {
                ForEach(Array(metrics(for: slice).enumerated()), id: \.element.label) { index, metric in
                    ExtensionMetricCardView(metric: metric, delay: delay + Double(index) * 0.05)
                }
            }
        }
    }

    private func metrics(for slice: CodexLocalAnalyticsSlice) -> [ExtensionMetric] {
        [
            ExtensionMetric(
                label: "Cost",
                value: slice.formattedCost,
                unit: "Spent",
                icon: "dollarsign.circle.fill",
                color: "FFD60A"
            ),
            ExtensionMetric(
                label: "Total Tokens",
                value: slice.formattedTotalTokens,
                unit: "Tokens",
                icon: "number.circle.fill",
                color: "30D158"
            ),
            ExtensionMetric(
                label: "Cached Tokens",
                value: slice.formattedCachedInputTokens,
                unit: "Cached",
                icon: "bolt.circle.fill",
                color: "64D2FF"
            ),
            ExtensionMetric(
                label: "Reasoning Tokens",
                value: slice.formattedReasoningOutputTokens,
                unit: "Reasoning",
                icon: "brain.head.profile",
                color: "BF5AF2"
            ),
        ]
    }
}
