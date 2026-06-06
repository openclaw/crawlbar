import AppKit
import CrawlBarCore
import SwiftUI

struct CrawlBarStatusDot: View {
    let state: CrawlAppState

    var body: some View {
        Circle()
            .fill(self.color)
            .frame(width: 8, height: 8)
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

    var body: some View {
        HStack(spacing: 5) {
            CrawlBarStatusDot(state: self.state)
            Text(CrawlBarStatusLabel.text(for: self.state))
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.12))
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
