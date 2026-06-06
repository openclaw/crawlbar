import AppKit
import SwiftUI

private struct CrawlBarMenuItemHighlightedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var crawlBarMenuItemHighlighted: Bool {
        get { self[CrawlBarMenuItemHighlightedKey.self] }
        set { self[CrawlBarMenuItemHighlightedKey.self] = newValue }
    }
}

enum CrawlBarMenuHighlightStyle {
    static let selectionText = Color(nsColor: .selectedMenuItemTextColor)
    static let normalPrimaryText = Color(nsColor: .controlTextColor)
    static let normalSecondaryText = Color(nsColor: .secondaryLabelColor)

    static func primary(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : self.normalPrimaryText
    }

    static func secondary(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText.opacity(0.86) : self.normalSecondaryText
    }

    static func selectionBackground(_ highlighted: Bool) -> Color {
        highlighted ? Color(nsColor: .selectedContentBackgroundColor) : .clear
    }
}

@MainActor
final class CrawlBarMenuItemHighlightState: ObservableObject {
    @Published var isHighlighted = false
}

private struct CrawlBarMenuItemSelectionBackground: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(
            dx: CrawlBarMenuMetrics.selectionHorizontalInset,
            dy: CrawlBarMenuMetrics.selectionVerticalInset)
        return RoundedRectangle(
            cornerRadius: CrawlBarMenuMetrics.selectionCornerRadius,
            style: .continuous).path(in: inset)
    }
}

struct CrawlBarMenuItemContainerView<Content: View>: View {
    @ObservedObject var highlightState: CrawlBarMenuItemHighlightState
    let showsSubmenuIndicator: Bool
    @ViewBuilder var content: Content

    var body: some View {
        self.content
            .fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, self.showsSubmenuIndicator ? CrawlBarMenuMetrics.submenuIndicatorTrailingPadding : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.crawlBarMenuItemHighlighted, self.highlightState.isHighlighted)
            .foregroundStyle(CrawlBarMenuHighlightStyle.primary(self.highlightState.isHighlighted))
            .background(alignment: .topLeading) {
                if self.highlightState.isHighlighted {
                    CrawlBarMenuItemSelectionBackground()
                        .fill(CrawlBarMenuHighlightStyle.selectionBackground(true))
                }
            }
            .overlay(alignment: .topTrailing) {
                if self.showsSubmenuIndicator {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(CrawlBarMenuHighlightStyle.secondary(self.highlightState.isHighlighted))
                        .padding(.top, 8)
                        .padding(.trailing, CrawlBarMenuMetrics.submenuIndicatorTrailingPadding)
                }
            }
    }
}
