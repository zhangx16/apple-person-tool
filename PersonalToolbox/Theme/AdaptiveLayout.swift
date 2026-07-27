import SwiftUI
import UIKit

/// Shared size-class helpers for iPhone / iPad layouts.
enum AdaptiveLayout {
    /// Readable column for forms, settings, overview sections.
    static let contentMaxWidth: CGFloat = 760
    /// Slightly narrower for dense settings forms.
    static let formMaxWidth: CGFloat = 680
    /// Novel / long-text reading measure.
    static let readerMaxWidth: CGFloat = 720
    /// Minimum tile width for adaptive service grids.
    static let gridMinTile: CGFloat = 160
    /// Overview metric / quick-tile minimum.
    static let metricMinTile: CGFloat = 150
    static let quickTileMin: CGFloat = 100

    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Adaptive flexible columns based on available width.
    static func columns(
        minimum: CGFloat,
        spacing: CGFloat = 12,
        maxColumns: Int = 6
    ) -> [GridItem] {
        [GridItem(.adaptive(minimum: minimum, maximum: 480), spacing: spacing)]
    }

    /// Fixed flexible columns (phone 2-up style that grows on pad).
    static func flexibleColumns(
        count: Int,
        spacing: CGFloat = 12
    ) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: max(1, count))
    }

    /// Column count from container width.
    static func columnCount(width: CGFloat, minimum: CGFloat, spacing: CGFloat = 12, max: Int = 6) -> Int {
        guard width > 0, minimum > 0 else { return 1 }
        let n = Int((width + spacing) / (minimum + spacing))
        return min(max, max(1, n))
    }
}

// MARK: - View modifiers

extension View {
    /// Center content and cap width on regular-size (iPad) layouts.
    func adaptiveReadableWidth(_ maxWidth: CGFloat = AdaptiveLayout.contentMaxWidth) -> some View {
        modifier(AdaptiveReadableWidthModifier(maxWidth: maxWidth))
    }

    /// Same as `adaptiveReadableWidth` but only when horizontal size class is regular.
    func adaptiveReadableWidth(
        _ maxWidth: CGFloat = AdaptiveLayout.contentMaxWidth,
        horizontalSizeClass: UserInterfaceSizeClass?
    ) -> some View {
        modifier(AdaptiveReadableWidthModifier(
            maxWidth: maxWidth,
            forceApply: horizontalSizeClass == .regular || AdaptiveLayout.isPad
        ))
    }
}

private struct AdaptiveReadableWidthModifier: ViewModifier {
    var maxWidth: CGFloat
    var forceApply: Bool = AdaptiveLayout.isPad

    func body(content: Content) -> some View {
        if forceApply {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}
