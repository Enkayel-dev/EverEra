//
//  TimelineView.swift
//  EverEra
//
//  The Temporal Surface — a vertical timeline where every event occupies a
//  moment in calendar time. Events live in colour-coded lanes; a Liquid Glass
//  date bubble hovers over the date gutter tracking the nearest date as you
//  scroll. Scroll snaps to event dates; the snapped event auto-promotes to
//  summary state. Only a tap expands to the full detail view.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Card presentation state

enum CardState: Equatable {
    case collapsed
    case summary
    case expanded
}

// MARK: - Custom snap-to-date scroll behavior

/// Snaps the scroll view so that the nearest timeline date row (from the stable
/// base layout) lands at `anchorY` from the top of the visible area.
/// Using the *base* (all-collapsed) Y positions keeps snap targets stable
/// even when card-state changes resize cards in the render layout.
struct DateSnapBehavior: ScrollTargetBehavior {
    /// Stable snap offsets in scroll-view content coordinates (already offset by topPad).
    let snapContentOffsets: [CGFloat]

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard !snapContentOffsets.isEmpty else { return }
        let proposed = target.rect.minY
        // Pick the closest stable snap point
        let best = snapContentOffsets.min(by: { abs($0 - proposed) < abs($1 - proposed) }) ?? proposed
        target.rect.origin.y = max(0, best)
    }
}

// MARK: - TimelineMainView

struct TimelineMainView: View {

    // MARK: Constants

    /// Left-gutter width for date labels.
    private let labelArea: CGFloat = 160
    /// Horizontal width per lane column.
    private let laneWidth: CGFloat = 20
    /// Gap between lane zone and the first card.
    private let cardGap: CGFloat = 16
    /// Top padding so the newest content scrolls up to be visible.
    private let topPad: CGFloat = 60
    /// Extra bottom padding.
    private let bottomPad: CGFloat = 300

    // MARK: State

    @Query(sort: \LSEntity.createdAt, order: .forward) private var entities: [LSEntity]
    @Environment(\.modelContext) private var modelContext

    @State private var cardStates: [UUID: CardState] = [:]
    @State private var showingAddEntity = false

    /// Stable layout computed with ALL cards collapsed — drives snap targets and date bubble.
    @State private var baseLayout: TimelineLayout?
    /// Render layout computed with actual card states — drives drawing and card positions.
    @State private var renderLayout: TimelineLayout?

    /// The content-space scroll offset (minY of visible rect).
    @State private var scrollOffsetY: CGFloat = 0
    /// The date row currently nearest to the top of the viewport (for the sticky bubble).
    @State private var visibleDateRow: TimelineDateRow? = nil
    /// Event IDs whose start date matches the currently snapped date.
    @State private var snappedEventIDs: Set<UUID> = []

    // Derived flat list of all events from all entities
    private var allEvents: [LSEvent] {
        entities.flatMap { $0.events }
    }

    private var expandedID: UUID? {
        cardStates.first(where: { $0.value == .expanded })?.key
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if allEvents.isEmpty {
                emptyState
            } else {
                timelineCanvas
            }
            addButton
        }
        .navigationTitle("Timeline")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddEntity = true } label: {
                    Label("Add Entity", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddEntity) {
            AddEntitySheet()
        }
        // Only rebuild both layouts when events are added/removed/changed
        .onChange(of: allEvents.map { $0.id }) { rebuildLayouts() }
        // Render layout also reacts to expanded state (summary never changes Y in render layout)
        .onChange(of: expandedID) { rebuildRenderLayout() }
        .onAppear { rebuildLayouts() }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "timeline.selection")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.secondary)
            Text("Your life story starts here.")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Add an entity — an employer, residence, or vehicle — and attach events to it.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Add First Entity") { showingAddEntity = true }
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Timeline canvas

    private var timelineCanvas: some View {
        GeometryReader { geo in
            // We need baseLayout for snap offsets and renderLayout for drawing.
            // Both are optional; only show content when baseLayout is ready.
            if let base = baseLayout {
                let render = renderLayout ?? base
                let cardLeft = labelArea + CGFloat(render.numLanes) * laneWidth + cardGap
                let cardWidth = max(geo.size.width - cardLeft - 16, 200)
                // Total height comes from the render layout (expands with card state)
                let totalH = render.totalHeight + topPad + bottomPad

                // Snap offsets are always from the stable base layout
                let snapOffsets: [CGFloat] = base.dateRows.map { $0.y + topPad - topPad }
                // ↑ dateRow.y is in content space (0-based), scroll offset to land at top = dateRow.y
                // But we add topPad in drawing, so the actual content-space position of the date line
                // is (dateRow.y + topPad). The scroll offset to bring that to the top of the viewport
                // is (dateRow.y + topPad) - 0 = dateRow.y + topPad. Since the viewport shows from
                // scrollOffsetY, we want scrollOffsetY = dateRow.y + topPad - topPad = dateRow.y.
                // Actually: content drawn at y=(dateRow.y + topPad). Viewport top = scrollOffsetY.
                // For date line to sit at top: scrollOffsetY = dateRow.y + topPad - 0 = dateRow.y + topPad? 
                // No — we want the line *just below the bubble* (~topPad from top).
                // scrollOffsetY + topPad = dateRow.y + topPad → scrollOffsetY = dateRow.y. ✓

                ZStack(alignment: .topLeading) {
                    ScrollView(.vertical, showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            // Background canvas: grid lines, lane bars, dots
                            Canvas { ctx, size in
                                drawGrid(ctx: ctx, layout: render, size: size)
                                drawLanes(ctx: ctx, layout: render)
                            }
                            .frame(width: geo.size.width, height: totalH)

                            // Event cards overlaid at computed positions
                            ForEach(render.segments) { seg in
                                eventCardGroup(
                                    seg: seg,
                                    cardLeft: cardLeft,
                                    cardWidth: cardWidth,
                                    viewportHeight: geo.size.height
                                )
                            }
                        }
                        .frame(width: geo.size.width, height: totalH)
                    }
                    .scrollTargetBehavior(
                        DateSnapBehavior(snapContentOffsets: base.dateRows.map { $0.y })
                    )
                    .onScrollGeometryChange(for: CGFloat.self) { g in
                        g.contentOffset.y
                    } action: { _, newY in
                        scrollOffsetY = newY
                        updateVisibleDate(base: base, render: render, offsetY: newY)
                    }

                    // ── Liquid Glass sticky date bubble ──
                    // Positioned inside the left gutter, floating above date labels
                    if let row = visibleDateRow {
                        stickyDateBubble(for: row)
                            .frame(width: labelArea, alignment: .center)
                            .padding(.top, 6)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    // MARK: - Sticky date bubble

    @ViewBuilder
    private func stickyDateBubble(for row: TimelineDateRow) -> some View {
        VStack(spacing: 2) {
            // Month/year — smaller, secondary
            Text(formatMonthYear(row.date))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Day — large, magnified relative to the tiny static gutter labels
            Text(formatDay(row.date))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(row.isToday ? Color.accentColor : .primary)

            if row.isToday {
                Text("TODAY")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: row.dateStr)
        .id(row.dateStr)
    }

    // MARK: - Canvas drawing

    private func drawGrid(ctx: GraphicsContext, layout: TimelineLayout, size: CGSize) {
        for month in layout.months {
            let y = month.y + topPad
            let lineH: CGFloat = month.isJanuary ? 3 : 1
            ctx.fill(
                Path(CGRect(x: 0, y: y, width: size.width, height: lineH)),
                with: .color(Color.primary.opacity(month.isJanuary ? 0.25 : 0.10))
            )

            let labelY = y + month.height / 2
            let monthName = monthAbbrev(month.month)
            let labelStr = month.height > 14
                ? "\(monthName.uppercased()) \(month.year)"
                : "\(monthName.uppercased())"
            ctx.draw(
                Text(labelStr).font(.system(size: 9, weight: .bold)).foregroundStyle(Color.primary.opacity(0.3)),
                at: CGPoint(x: labelArea / 2, y: labelY), anchor: .center
            )
        }

        for row in layout.dateRows {
            let y = row.y + topPad
            let isSnapped = visibleDateRow?.dateStr == row.dateStr
            let opacity: CGFloat = isSnapped ? 0.65 : (row.isToday ? 0.45 : 0.15)

            ctx.fill(
                Path(CGRect(x: labelArea, y: y, width: size.width - labelArea, height: isSnapped ? 1.5 : 1)),
                with: .color(Color.accentColor.opacity(opacity))
            )
            // Small date label in gutter (the bubble is the main indicator — this is secondary)
            let label = Text(formatDateShort(row.date))
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.accentColor.opacity(isSnapped ? 0.0 : (row.isToday ? 0.7 : 0.45)))
            ctx.draw(label, at: CGPoint(x: labelArea / 2, y: y + 8), anchor: .center)
        }
    }

    private func drawLanes(ctx: GraphicsContext, layout: TimelineLayout) {
        let snappedIDs = snappedEventIDs
        let snappedDateStr = visibleDateRow?.dateStr

        for seg in layout.segments {
            let x = labelArea + CGFloat(seg.lane) * laneWidth + laneWidth / 2
            let sy = seg.startY + topPad
            let ey = seg.endY + topPad
            let color = seg.event.category.color
            let isSnapped = snappedIDs.contains(seg.event.id)

            // Vertical lane bar
            ctx.fill(
                Path(CGRect(x: x - 1, y: sy, width: 2, height: ey - sy)),
                with: .color(color.opacity(isSnapped ? 0.78 : 0.55))
            )

            let startDateStr = seg.event.startDate.map { TimelineLayout.dateString(from: $0) } ?? ""
            let endDateStr = TimelineLayout.dateString(from: seg.event.endDate ?? Calendar.current.startOfDay(for: Date()))
            let startGlows = isSnapped && snappedDateStr == startDateStr
            let endGlows = isSnapped && snappedDateStr == endDateStr

            // Start dot
            let startDot = CGRect(x: x - 5, y: sy - 5, width: 10, height: 10)
            if startGlows {
                ctx.stroke(Path(ellipseIn: startDot.insetBy(dx: -5, dy: -5)), with: .color(color.opacity(0.2)), lineWidth: 4)
                ctx.stroke(Path(ellipseIn: startDot.insetBy(dx: -2, dy: -2)), with: .color(color.opacity(0.45)), lineWidth: 2)
            }
            ctx.stroke(Path(ellipseIn: startDot), with: .color(color), lineWidth: startGlows ? 3 : 2.5)

            // End dot
            let endDot = CGRect(x: x - 5, y: ey - 5, width: 10, height: 10)
            if endGlows {
                ctx.stroke(Path(ellipseIn: endDot.insetBy(dx: -5, dy: -5)), with: .color(color.opacity(0.2)), lineWidth: 4)
                ctx.stroke(Path(ellipseIn: endDot.insetBy(dx: -2, dy: -2)), with: .color(color.opacity(0.45)), lineWidth: 2)
            }
            if seg.ongoing {
                ctx.fill(Path(ellipseIn: endDot.insetBy(dx: 2, dy: 2)), with: .color(color))
                ctx.stroke(Path(ellipseIn: endDot), with: .color(color.opacity(endGlows ? 0.7 : 0.4)), lineWidth: endGlows ? 2 : 1.5)
            } else {
                ctx.fill(Path(ellipseIn: endDot), with: .color(color))
            }
        }
    }

    // MARK: - Event card overlay

    @ViewBuilder
    private func eventCardGroup(
        seg: TimelineLaneSegment,
        cardLeft: CGFloat,
        cardWidth: CGFloat,
        viewportHeight: CGFloat
    ) -> some View {
        let state = cardStates[seg.id] ?? .collapsed
        let color = seg.event.category.color
        let startH = cardHeightForState(state, viewportHeight: viewportHeight)
        let endH = cardHeightForState(state, viewportHeight: viewportHeight)

        // Start card — sits ABOVE the start date line
        EventCard(
            event: seg.event,
            cardType: .start,
            state: state,
            color: color,
            onTap: { cycleState(for: seg.id) },
            onDismiss: { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { cardStates[seg.id] = .collapsed } },
            modelContext: modelContext
        )
        .frame(width: cardWidth, height: startH)
        .offset(x: cardLeft, y: seg.startY + topPad - startH)

        if !seg.ongoing {
            EventCard(
                event: seg.event,
                cardType: .end,
                state: state,
                color: color,
                onTap: { cycleState(for: seg.id) },
                onDismiss: { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { cardStates[seg.id] = .collapsed } },
                modelContext: modelContext
            )
            .frame(width: cardWidth, height: endH)
            .offset(x: cardLeft, y: seg.endY + topPad + 4)
        }
    }

    // MARK: - FAB

    private var addButton: some View {
        Button { showingAddEntity = true } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.glass)
        .padding(24)
    }

    // MARK: - Scroll tracking

    private func updateVisibleDate(base: TimelineLayout, render: TimelineLayout, offsetY: CGFloat) {
        // The date line drawn at (dateRow.y + topPad) in content space.
        // Viewport top is at scrollOffsetY. We track the date nearest to scrollOffsetY.
        let targetY = offsetY + topPad   // content Y that maps to the top of the viewport

        guard !base.dateRows.isEmpty else {
            visibleDateRow = nil
            snappedEventIDs = []
            return
        }

        let nearest = base.dateRows.min(by: {
            abs($0.y - targetY) < abs($1.y - targetY)
        })
        guard let nearest, nearest.dateStr != visibleDateRow?.dateStr else { return }

        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
            visibleDateRow = nearest

            // Auto-promote events whose START date matches the snapped date
            var newSnapped: Set<UUID> = []
            for seg in render.segments {
                let startStr = seg.event.startDate.map { TimelineLayout.dateString(from: $0) } ?? ""
                if startStr == nearest.dateStr {
                    newSnapped.insert(seg.event.id)
                    // Only promote if currently collapsed (don't downgrade expanded)
                    if cardStates[seg.event.id] == nil || cardStates[seg.event.id] == .collapsed {
                        cardStates[seg.event.id] = .summary
                    }
                }
            }
            // Revert auto-promoted events when we scroll away
            for id in snappedEventIDs where !newSnapped.contains(id) {
                if cardStates[id] == .summary {
                    cardStates[id] = .collapsed
                }
            }
            snappedEventIDs = newSnapped
        }
        // Note: we deliberately do NOT call rebuildRenderLayout() here.
        // Summary cards expand/contract purely via SwiftUI frame animation;
        // the stable snap positions in baseLayout are never invalidated by card state.
    }

    // MARK: - Layout management

    /// Full rebuild: recomputes both base (collapsed-only) and render layouts.
    /// Called only when events are added/removed/modified — not on card state changes.
    private func rebuildLayouts() {
        baseLayout = TimelineLayout.compute(events: allEvents)
        rebuildRenderLayout()
    }

    /// Rebuilds only the render layout with current card states.
    /// Called when the expanded card changes (which actually shifts content).
    private func rebuildRenderLayout() {
        renderLayout = TimelineLayout.compute(
            events: allEvents,
            expandedEventID: expandedID
        )
    }

    // MARK: - Helpers

    private func cycleState(for id: UUID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            let current = cardStates[id] ?? .collapsed
            switch current {
            case .collapsed: cardStates[id] = .summary
            case .summary:   cardStates[id] = .expanded
            case .expanded:  cardStates[id] = .collapsed
            }
        }
    }

    private func cardHeightForState(_ state: CardState, viewportHeight: CGFloat) -> CGFloat {
        switch state {
        case .collapsed: return TimelineLayout.collapsedCardHeight
        case .summary:   return TimelineLayout.summaryCardHeight
        case .expanded:  return min(TimelineLayout.expandedCardHeight, viewportHeight * 0.9)
        }
    }

    private func monthAbbrev(_ month: Int) -> String {
        let names = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        return month >= 0 && month < 12 ? names[month] : "?"
    }

    private func formatDateShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private func formatMonthYear(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f.string(from: date)
    }

    private func formatDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }
}

// MARK: - EventCard

enum EventCardType { case start; case end }

struct EventCard: View {

    @Bindable var event: LSEvent
    let cardType: EventCardType
    let state: CardState
    let color: Color
    let onTap: () -> Void
    let onDismiss: () -> Void
    let modelContext: ModelContext

    @State private var showingFileImporter = false
    @State private var importError: String?

    var body: some View {
        cardContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(color.opacity(0.35), lineWidth: 1)
                    )
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(state == .expanded ? 0.28 : 0.07), radius: state == .expanded ? 12 : 3)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture { if state != .expanded { onTap() } }
            .alert("Import Error", isPresented: .constant(importError != nil)) {
                Button("OK") { importError = nil }
            } message: { Text(importError ?? "") }
    }

    @ViewBuilder
    private var cardContent: some View {
        switch state {
        case .collapsed: collapsedBody
        case .summary:   summaryBody
        case .expanded:  expandedBody
        }
    }

    // MARK: Collapsed

    private var collapsedBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(event.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                Spacer()
                Text(event.category.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.18), in: Capsule())
                    .foregroundStyle(color)
            }
            HStack {
                Text(cardType == .start ? "Started" : (event.isOngoing ? "Ongoing" : "Ended"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(dateLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(cardType == .start ? color : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .padding(.leading, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Summary

    private var summaryBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            collapsedBody

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.durationLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                let topProps = event.properties
                    .filter { !$0.displayValue.isEmpty }
                    .sorted { $0.displayOrder < $1.displayOrder }
                    .prefix(3)

                ForEach(Array(topProps)) { prop in
                    HStack(spacing: 4) {
                        Text(prop.key + ":")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(prop.displayValue)
                            .font(.system(size: 10))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .padding(.leading, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Expanded

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fixed header
            HStack {
                Image(systemName: event.category.systemImage)
                    .foregroundStyle(color)
                Text(event.title)
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Scrollable content — fills remaining card height
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    formField("Title") {
                        TextField("Event title", text: $event.title)
                            .textFieldStyle(.roundedBorder)
                    }

                    formField("Category") {
                        Picker("", selection: $event.category) {
                            ForEach(EventCategory.allCases, id: \.self) { cat in
                                Label(cat.rawValue, systemImage: cat.systemImage).tag(cat)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    HStack(spacing: 12) {
                        formField("Start Date") {
                            DatePicker("", selection: Binding(
                                get: { event.startDate ?? Date() },
                                set: { event.startDate = $0 }
                            ), displayedComponents: .date)
                            .labelsHidden()
                        }
                        formField("End Date") {
                            HStack {
                                if event.endDate != nil {
                                    DatePicker("", selection: Binding(
                                        get: { event.endDate ?? Date() },
                                        set: { event.endDate = $0 }
                                    ), displayedComponents: .date)
                                    .labelsHidden()
                                } else {
                                    Text("Ongoing")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { event.endDate != nil },
                                    set: { event.endDate = $0 ? Date() : nil }
                                ))
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .controlSize(.small)
                            }
                        }
                    }

                    formField("Notes") {
                        TextField("Notes…", text: $event.notes, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                    }

                    if !event.properties.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Details")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            ForEach(event.properties.sorted { $0.displayOrder < $1.displayOrder }) { prop in
                                PropertyInlineRow(property: prop)
                            }
                        }
                    }

                    if !event.documents.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Documents (\(event.documents.count))")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            ForEach(event.documents.sorted { $0.importedAt < $1.importedAt }) { doc in
                                HStack {
                                    Image(systemName: doc.kind.systemImage)
                                        .foregroundStyle(.secondary)
                                    Text(doc.displayName)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }

                    Divider()
                    HStack {
                        Button(role: .destructive) {
                            modelContext.delete(event)
                            onDismiss()
                        } label: {
                            Label("Delete Event", systemImage: "trash")
                                .font(.callout)
                        }
                        .buttonStyle(.borderless)

                        Spacer()

                        Button("Done", action: onDismiss)
                            .buttonStyle(.glass)
                            .controlSize(.small)
                    }
                }
                .padding(14)
            }
        }
    }

    @ViewBuilder
    private func formField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private var dateLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return cardType == .start
            ? (event.startDate.map { fmt.string(from: $0) } ?? "?")
            : (event.endDate.map { fmt.string(from: $0) } ?? "Present")
    }
}

// MARK: - PropertyInlineRow

private struct PropertyInlineRow: View {
    @Bindable var property: LSProperty

    var body: some View {
        HStack(spacing: 8) {
            Text(property.key + ":")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)

            switch property.valueType {
            case .string:
                TextField("", text: Binding(
                    get: { property.stringValue ?? "" },
                    set: { property.stringValue = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            case .url:
                TextField("", text: Binding(
                    get: { property.urlString ?? "" },
                    set: { property.urlString = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            case .number:
                TextField("", value: $property.numberValue, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            case .date:
                DatePicker("", selection: Binding(
                    get: { property.dateValue ?? Date() },
                    set: { property.dateValue = $0 }
                ), displayedComponents: .date)
                .labelsHidden()
                .font(.caption)
            }
        }
    }
}
