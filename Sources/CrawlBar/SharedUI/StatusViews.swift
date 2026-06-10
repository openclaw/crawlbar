import AppKit
import CrawlBarCore
import SwiftUI

private enum CrawlBarStatusMetrics {
    static let dotSize: CGFloat = 8
    static let pillSpacing: CGFloat = 5
    static let pillHorizontalPadding: CGFloat = 8
    static let pillVerticalPadding: CGFloat = 4
    static let pillBackgroundOpacity = 0.12
}

struct CrawlBarStatusDot: View {
    let state: CrawlAppState

    var body: some View {
        Circle()
            .fill(self.color)
            .frame(width: CrawlBarStatusMetrics.dotSize, height: CrawlBarStatusMetrics.dotSize)
            .accessibilityLabel(CrawlBarStatusLabel.text(for: self.state))
    }

    private var color: Color {
        switch self.state {
        case .current:
            .green
        case .stale, .unknown:
            .yellow
        case .syncing:
            .blue
        case .needsConfig, .needsAuth, .error:
            .red
        case .disabled:
            .gray
        }
    }
}

struct CrawlBarStatusPill: View {
    let state: CrawlAppState
    var label: String? = nil

    var body: some View {
        HStack(spacing: CrawlBarStatusMetrics.pillSpacing) {
            CrawlBarStatusDot(state: self.state)
            Text(self.label ?? CrawlBarStatusLabel.text(for: self.state))
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, CrawlBarStatusMetrics.pillHorizontalPadding)
        .padding(.vertical, CrawlBarStatusMetrics.pillVerticalPadding)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(CrawlBarStatusMetrics.pillBackgroundOpacity))
        .clipShape(Capsule())
    }
}

enum CrawlBarStatusLabel {
    static func text(for state: CrawlAppState) -> String {
        switch state {
        case .current:
            "Current"
        case .stale:
            "Stale"
        case .syncing:
            "Syncing"
        case .needsConfig:
            "Needs Config"
        case .needsAuth:
            "Needs Auth"
        case .error:
            "Error"
        case .disabled:
            "Disabled"
        case .unknown:
            "Unknown"
        }
    }
}
