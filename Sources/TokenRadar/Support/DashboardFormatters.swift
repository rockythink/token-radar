import Foundation
import TokenRadarCore

func formatTokens(_ tokens: Int) -> String {
    let value = Double(tokens)
    if tokens >= 1_000_000_000 {
        return String(format: "%.1fB tok", value / 1_000_000_000)
    }
    if tokens >= 1_000_000 {
        return String(format: "%.1fM tok", value / 1_000_000)
    }
    if tokens >= 1_000 {
        return String(format: "%.1fk tok", value / 1_000)
    }
    return "\(tokens) tok"
}

extension UsageSource {
    static var allCasesForDashboard: [UsageSource] {
        [.providerAPI, .localProxy, .cliSessionLog, .estimate, .fixture]
    }
}
