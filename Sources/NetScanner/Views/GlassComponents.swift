//
//  GlassComponents.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import SwiftUI

/// Soft mesh gradient behind the detail pane so Liquid Glass surfaces have something to refract.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.55, 0.45], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: colorScheme == .dark ? Self.dark : Self.light
        )
        .ignoresSafeArea()
    }

    private static let dark: [Color] = [
        Color(red: 0.04, green: 0.06, blue: 0.12), Color(red: 0.05, green: 0.09, blue: 0.20), Color(red: 0.07, green: 0.06, blue: 0.16),
        Color(red: 0.03, green: 0.10, blue: 0.16), Color(red: 0.06, green: 0.12, blue: 0.26), Color(red: 0.10, green: 0.07, blue: 0.20),
        Color(red: 0.03, green: 0.05, blue: 0.10), Color(red: 0.04, green: 0.08, blue: 0.15), Color(red: 0.06, green: 0.05, blue: 0.12),
    ]

    private static let light: [Color] = [
        Color(red: 0.90, green: 0.94, blue: 1.00), Color(red: 0.86, green: 0.91, blue: 0.99), Color(red: 0.93, green: 0.90, blue: 0.99),
        Color(red: 0.88, green: 0.95, blue: 0.98), Color(red: 0.82, green: 0.89, blue: 1.00), Color(red: 0.92, green: 0.88, blue: 0.98),
        Color(red: 0.94, green: 0.96, blue: 1.00), Color(red: 0.90, green: 0.93, blue: 0.99), Color(red: 0.95, green: 0.93, blue: 0.99),
    ]
}

/// A rounded Liquid Glass panel with an optional header.
struct GlassCard<Content: View>: View {
    var title: Text?
    var systemImage: String?
    var trailing: AnyView?
    /// Stretch to the height offered, so cards side by side end up the same height.
    var fillsHeight = false
    @ViewBuilder var content: Content

    init(_ title: LocalizedStringKey? = nil, systemImage: String? = nil, trailing: AnyView? = nil, fillsHeight: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.title = title.map { Text($0) }
        self.systemImage = systemImage
        self.trailing = trailing
        self.fillsHeight = fillsHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 8) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .foregroundStyle(.tint)
                            .frame(width: 18)
                    }
                    title
                        .font(.headline)
                    Spacer(minLength: 0)
                    trailing
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

/// Segmented tab bar floating in a glass capsule, modelled after the reference layout.
struct GlassTabBar: View {
    @Binding var selection: DetailTab
    var isEnabled: (DetailTab) -> Bool = { _ in true }
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DetailTab.allCases) { tab in
                let selected = selection == tab
                Button {
                    withAnimation(.smooth(duration: 0.28)) { selection = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 14, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    // Grows for longer translations; English titles all fit the 104 pt minimum.
                    .padding(.horizontal, 14)
                    .frame(minWidth: 104)
                    .frame(height: 42)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .background {
                        if selected {
                            Capsule()
                                .fill(Color.accentColor.opacity(0.16))
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled(tab))
                .opacity(isEnabled(tab) ? 1 : 0.45)
            }
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// Label / value row used inside cards. Values are selectable.
struct InfoRow: View {
    let label: LocalizedStringKey
    let value: String?
    var monospaced = false

    var body: some View {
        if monospaced, value != nil {
            // Addresses never wrap mid-token: side by side when they fit, otherwise the value drops below the label.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    labelText
                    Spacer(minLength: 8)
                    valueText.lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    labelText
                    valueText
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .font(.callout)
            .padding(.vertical, 2)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                labelText
                Spacer(minLength: 8)
                valueText
                    .multilineTextAlignment(.trailing)
                    .lineLimit(3)
            }
            .font(.callout)
            .padding(.vertical, 2)
        }
    }

    private var labelText: some View {
        Text(label).foregroundStyle(.secondary)
    }

    private var valueText: some View {
        Text(value ?? "—")
            .font(monospaced ? .callout.monospaced() : .callout)
            .foregroundStyle(value == nil ? .tertiary : .primary)
            .textSelection(.enabled)
    }
}

/// Small tinted capsule label.
struct Pill: View {
    let text: Text
    var systemImage: String?
    var tint: Color = .accentColor

    init(text: LocalizedStringKey, systemImage: String? = nil, tint: Color = .accentColor) {
        self.init(Text(text), systemImage: systemImage, tint: tint)
    }

    /// For values that are never translated: addresses, MACs, already-localized titles.
    init(verbatim: String, systemImage: String? = nil, tint: Color = .accentColor) {
        self.init(Text(verbatim: verbatim), systemImage: systemImage, tint: tint)
    }

    private init(_ text: Text, systemImage: String?, tint: Color) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            text
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(tint)
        .background(tint.opacity(0.16), in: .capsule)
    }
}

/// Big number tile for the scanner summary.
struct StatTile: View {
    let value: String
    let label: LocalizedStringKey
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

/// Wrapping horizontal layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        var y: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                y += row.height + spacing
                rows.append(Row(indices: [index], y: y, width: size.width, height: size.height))
                continue
            }
            row.indices.append(index)
            row.width = needed
            row.height = max(row.height, size.height)
            row.y = y
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

extension View {
    /// Constrains scrolling content to a readable column centered in the pane.
    func readableColumn(_ maxWidth: CGFloat = 860) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

/// Scan progress as a tinted ring, optionally around a stop square (the toolbar's stop button).
struct ScanProgressRing: View {
    let progress: Double
    var showsStop = true
    var diameter: CGFloat = 17

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.35), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.03, min(progress, 1)))
                .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.3), value: progress)
            if showsStop {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.primary)
                    .frame(width: diameter * 0.35, height: diameter * 0.35)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}
