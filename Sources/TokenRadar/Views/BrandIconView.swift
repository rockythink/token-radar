import AppKit
import SwiftUI
import TokenRadarCore

enum AppIconKind {
    case codex
    case claudeCode

    var resourceName: String {
        switch self {
        case .codex:
            "app-codex"
        case .claudeCode:
            "app-claude-code"
        }
    }
}

struct AppIconView: View {
    var kind: AppIconKind
    var size: CGFloat = 24

    var body: some View {
        BundledIconImageView(
            resourceName: kind.resourceName,
            size: size,
            contentSize: size,
            fallbackSystemImage: "app.dashed",
            fallbackTint: .secondary
        )
            .clipShape(RoundedRectangle(cornerRadius: min(8, max(5, size * 0.22))))
            .overlay {
                RoundedRectangle(cornerRadius: min(8, max(5, size * 0.22)))
                    .stroke(.separator.opacity(0.25), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

struct SourceIconView: View {
    var appIcon: AppIconKind?
    var provider: ProviderKind?
    var size: CGFloat = 24
    var fallbackSystemImage: String = "circle.grid.2x2"
    var fallbackTint: Color = .secondary

    var body: some View {
        if let appIcon {
            AppIconView(kind: appIcon, size: size)
        } else {
            ProviderIconView(
                provider: provider,
                size: size,
                fallbackSystemImage: fallbackSystemImage,
                fallbackTint: fallbackTint
            )
        }
    }
}

struct ProviderIconView: View {
    var provider: ProviderKind?
    var size: CGFloat = 24
    var fallbackSystemImage: String = "circle.grid.2x2"
    var fallbackTint: Color = .secondary

    var body: some View {
        BundledIconImageView(
            resourceName: provider?.brandIconResourceName,
            size: size,
            contentSize: contentSize,
            fallbackSystemImage: fallbackSystemImage,
            fallbackTint: fallbackTint
        )
        .frame(width: size, height: size)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(.separator.opacity(0.35), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private var contentSize: CGFloat {
        max(12, size * 0.72)
    }

    private var cornerRadius: CGFloat {
        min(7, max(4, size * 0.22))
    }

    private var backgroundColor: Color {
        provider == nil ? fallbackTint.opacity(0.10) : Color.white.opacity(0.96)
    }
}

private struct BundledIconImageView: View {
    var resourceName: String?
    var size: CGFloat
    var contentSize: CGFloat
    var fallbackSystemImage: String
    var fallbackTint: Color

    var body: some View {
        Group {
            if let image = bundledImage {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: contentSize, height: contentSize)
            } else {
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: max(11, contentSize * 0.72), weight: .semibold))
                    .foregroundStyle(fallbackTint)
                    .frame(width: contentSize, height: contentSize)
            }
        }
        .frame(width: size, height: size)
    }

    private var bundledImage: NSImage? {
        guard let resourceName else { return nil }
        return Bundle.module.image(forResource: resourceName)
    }
}

struct ModelIconView: View {
    var modelName: String
    var provider: ProviderKind?
    var size: CGFloat = 24

    var body: some View {
        ProviderIconView(
            provider: provider ?? ModelCatalog.trackedModel(for: modelName)?.provider,
            size: size,
            fallbackSystemImage: "cpu"
        )
    }
}

struct ProviderPickerItem: View {
    var provider: ProviderKind

    var body: some View {
        HStack(spacing: 7) {
            ProviderIconView(provider: provider, size: 18)
            Text(provider.displayName)
        }
    }
}

extension ProviderKind {
    var brandIconResourceName: String {
        switch self {
        case .openAI:
            "openai"
        case .anthropic:
            "anthropic"
        case .openRouter:
            "openrouter"
        case .siliconFlow:
            "siliconflow"
        case .vercelAIGateway:
            "vercel"
        case .cloudflareAIGateway, .cloudflareWorkersAI:
            "cloudflare"
        case .gemini:
            "gemini"
        case .deepSeek:
            "deepseek"
        case .moonshotKimi:
            "moonshot-kimi"
        case .zhipuGLM:
            "zhipu-glm"
        case .volcengineDoubao:
            "volcengine-doubao"
        case .alibabaQwen:
            "alibaba-qwen"
        case .minimax:
            "minimax"
        case .tencentHunyuan:
            "tencent-hunyuan"
        case .xAI:
            "xai"
        case .xiaomiMimo:
            "xiaomi-mimo"
        }
    }
}

extension DashboardBreakdownRow {
    var inferredProvider: ProviderKind? {
        if let provider = ProviderKind(rawValue: id) {
            return provider
        }

        guard let providerRaw = id.split(separator: "|", maxSplits: 1).first else {
            return nil
        }

        return ProviderKind(rawValue: String(providerRaw))
    }
}
