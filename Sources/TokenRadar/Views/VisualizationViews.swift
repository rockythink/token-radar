import SwiftUI
import TokenRadarCore

struct StatusRingView: View {
    var progress: Decimal
    var centerText: String
    var centerCaption: String
    var tint: Color
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, progress.doubleValue))))
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(centerText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Text(centerCaption)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 7)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct BudgetRingView: View {
    var progress: Decimal
    var lineWidth: CGFloat = 8

    var body: some View {
        StatusRingView(
            progress: progress,
            centerText: MoneyFormatter.percent(progress),
            centerCaption: "",
            tint: ringColor,
            lineWidth: lineWidth
        )
    }

    private var ringColor: Color {
        if progress >= Decimal(string: "0.95")! { return .red }
        if progress >= Decimal(string: "0.8")! { return .orange }
        if progress >= Decimal(string: "0.5")! { return .teal }
        return .green
    }
}

struct SparklineView: View {
    var values: [Decimal]
    var tint: Color = .cyan
    var fill: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let doubles = values.map(\.doubleValue)
            let maxValue = max(doubles.max() ?? 0, 0.001)
            let points = doubles.enumerated().map { index, value in
                let x = doubles.count <= 1 ? 0 : proxy.size.width * CGFloat(index) / CGFloat(doubles.count - 1)
                let y = proxy.size.height - proxy.size.height * CGFloat(value / maxValue)
                return CGPoint(x: x, y: y)
            }

            ZStack {
                if fill, points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: proxy.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.28), tint.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(minHeight: 48)
    }
}

struct MicroBarView: View {
    var values: [Decimal]

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(values.map(\.doubleValue).max() ?? 0, 0.001)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    let ratio = CGFloat(value.doubleValue / maxValue)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(barColor(index: index))
                        .frame(width: max(2, proxy.size.width / CGFloat(max(values.count, 1)) - 2), height: max(3, proxy.size.height * ratio))
                }
            }
        }
        .frame(height: 16)
    }

    private func barColor(index: Int) -> Color {
        let palette: [Color] = [.green, .teal, .cyan, .blue, .indigo, .orange, .red]
        return palette[index % palette.count]
    }
}

struct ProviderDistributionBar: View {
    var rows: [(provider: ProviderKind, spend: Decimal, ratio: Decimal)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(providerColor(index))
                        .frame(maxWidth: max(8, CGFloat(row.ratio.doubleValue) * 260))
                }
            }
            .frame(height: 9)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 8) {
                    ProviderIconView(provider: row.provider, size: 18)
                    Text(row.provider.displayName)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(MoneyFormatter.compactUSD(row.spend))
                        .font(.caption.monospacedDigit())
                }
            }
        }
    }

    private func providerColor(_ index: Int) -> Color {
        let palette: [Color] = [.cyan, .green, .orange, .purple, .pink, .blue]
        return palette[index % palette.count]
    }
}

struct SpendProgressBar: View {
    var value: Decimal
    var maxValue: Decimal
    var tint: Color = .cyan

    var body: some View {
        GeometryReader { proxy in
            let ratio = maxValue > 0 ? min(1, value.doubleValue / maxValue.doubleValue) : 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary)
                RoundedRectangle(cornerRadius: 3)
                    .fill(tint)
                    .frame(width: proxy.size.width * CGFloat(ratio))
            }
        }
        .frame(height: 6)
    }
}

struct QuotaRunwayView: View {
    var summary: QuotaWindowSummary
    var quotaLabel: String
    var timeLabel: String
    var paceLabel: String
    var refreshLabel: String
    var elapsedLabel: String
    var remainingText: String
    var refreshText: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.window.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(refreshText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                Text(remainingText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            VStack(alignment: .leading, spacing: 7) {
                QuotaRunwayLane(
                    label: quotaLabel,
                    valueText: MoneyFormatter.percent(summary.remainingRatio),
                    ratio: summary.remainingRatio,
                    tint: tint
                )
                QuotaRunwayLane(
                    label: timeLabel,
                    valueText: MoneyFormatter.percent(summary.timeRemainingRatio),
                    ratio: summary.timeRemainingRatio,
                    tint: .secondary,
                    isSubdued: true
                )
            }

            HStack(spacing: 12) {
                compactMetric(title: paceLabel, value: paceText)
                compactMetric(title: refreshLabel, value: refreshText)
                compactMetric(title: elapsedLabel, value: MoneyFormatter.percent(summary.timeElapsedRatio))
            }
        }
        .padding(.vertical, 4)
        .help("\(quotaLabel) \(MoneyFormatter.percent(summary.remainingRatio)) · \(timeLabel) \(MoneyFormatter.percent(summary.timeRemainingRatio))")
        .accessibilityElement(children: .combine)
    }

    private var paceText: String {
        let value = min(99, max(0, summary.quotaTimeRatio.doubleValue))
        if value >= 10 {
            return String(format: "%.0fx", value)
        }
        return String(format: "%.2fx", value)
    }

    private func compactMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuotaRunwayLane: View {
    var label: String
    var valueText: String
    var ratio: Decimal
    var tint: Color
    var isSubdued = false

    private var clampedRatio: CGFloat {
        CGFloat(min(1, max(0, ratio.doubleValue)))
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 68, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tint.opacity(isSubdued ? 0.42 : 0.86))
                        .frame(width: max(3, proxy.size.width * clampedRatio))
                }
            }
            .frame(height: 9)

            Text(valueText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 46, alignment: .trailing)
        }
    }
}
