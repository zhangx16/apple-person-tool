import SwiftUI
import UIKit

/// A compact, draggable music navigation bar inspired by Kumone's iOS glass bar.
/// The indicator follows the finger and settles on the closest destination.
struct MusicGlassTabBar: View {
    let tabs: [MeloXTab]
    @Binding var selection: MeloXTab
    var onReselect: (MeloXTab) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var dragLocation: CGFloat?
    @State private var isDragging = false

    private let height: CGFloat = 52

    var body: some View {
        GeometryReader { proxy in
            let cellWidth = proxy.size.width / CGFloat(max(tabs.count, 1))
            let selectedIndex = tabs.firstIndex(of: selection) ?? 0
            let restingX = cellWidth * (CGFloat(selectedIndex) + 0.5)
            let indicatorX = isDragging
                ? min(max(dragLocation ?? restingX, cellWidth / 2), proxy.size.width - cellWidth / 2)
                : restingX

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.07))
                    .frame(width: max(cellWidth - 8, 36), height: height)
                    .position(x: indicatorX, y: proxy.size.height / 2)

                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        label(for: tab)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(selectionGesture(cellWidth: cellWidth))
        }
        .frame(height: height)
        .padding(4)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.10), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
    }

    private func label(for tab: MeloXTab) -> some View {
        let selected = selection == tab
        return VStack(spacing: 2) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .symbolVariant(selected ? .fill : .none)
            Text(tab.title)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(selected ? Color.red : Color.primary.opacity(0.72))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if selected {
                onReselect(tab)
            } else {
                withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)) {
                    selection = tab
                }
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }

    private func selectionGesture(cellWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging, abs(value.translation.width) < 8 { return }
                isDragging = true
                dragLocation = value.location.x
                let tab = tab(at: value.location.x, cellWidth: cellWidth)
                if tab != selection {
                    selection = tab
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .onEnded { value in
                let tab = tab(at: value.location.x, cellWidth: cellWidth)
                if !isDragging, tab == selection {
                    onReselect(tab)
                } else {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)) {
                        selection = tab
                        dragLocation = nil
                    }
                }
                isDragging = false
            }
    }

    private func tab(at x: CGFloat, cellWidth: CGFloat) -> MeloXTab {
        let index = min(max(Int(x / cellWidth), 0), tabs.count - 1)
        return tabs[index]
    }
}
