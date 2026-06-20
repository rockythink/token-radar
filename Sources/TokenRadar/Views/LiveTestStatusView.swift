import SwiftUI

struct LiveTestStatusView: View {
    var result: LiveTestResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(result.message, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
            if !result.detail.isEmpty {
                Text(result.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var symbol: String {
        switch result.status {
        case .running:
            "arrow.triangle.2.circlepath"
        case .success:
            "checkmark.circle.fill"
        case .failure:
            "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch result.status {
        case .running:
            .blue
        case .success:
            .green
        case .failure:
            .orange
        }
    }
}
