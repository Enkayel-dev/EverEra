//
//  TimelineView.swift
//  EverEra
//
//  The Temporal Surface — a vertical timeline where every event occupies a
//  moment in calendar time. Events live in colour-coded lanes; a sticky date
//  lens tracks the currently visible date range.
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
    @State private var layout: TimelineLayout?

    // Derived flat list of all events from all entities
    private var allEvents: [LSEvent] {
        entities.flatMap { $0.events }
    }

    private var focusedID: UUID? {
        cardStates.first(where: { $0.value == .summary })?.key
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
                Button {
                    showingAddEntity = true
                } label: {
                    Label("Add Entity", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddEntity) {
            AddEntitySheet()
        }
        .onChange(of: allEvents.map { $0.id }) { recalcLayout() }
        .onChange(of: focusedID) { recalcLayout() }
        .onChange(of: expandedID) { recalcLayout() }
        .onAppear { recalcLayout() }
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
            ScrollView(.vertical, showsIndicators: true) {
                if let layout {
                    let cardLeft = labelArea + CGFloat(layout.numLanes) * laneWidth + cardGap
                    let cardWidth = max(geo.size.width - cardLeft - 16, 200)
                    let totalH = layout.totalHeight + topPad + bottomPad

                    ZStack(alignment: .topLeading) {
                        // Background canvas: lines, labels, lane bars
                        Canvas { ctx, size in
                            drawGrid(ctx: ctx, layout: layout, size: size)
                            drawLanes(ctx: ctx, layout: layout)
                        }
                        .frame(width: geo.size.width, height: totalH)

                        // Event cards overlaid at computed positions
                        ForEach(layout.segments) { seg in
                            eventCardGroup(
                                seg: seg,
                                cardLeft: cardLeft,
                                cardWidth: cardWidth
                            )
                        }
                    }
                    .frame(width: geo.size.width, height: totalH)
                }
            }
        }
    }

    // MARK: - Canvas drawing

    private func drawGrid(ctx: GraphicsContext, layout: TimelineLayout, size: CGSize) {
        // Month rows
        for month in layout.months {
            let y = month.y + topPad
            // January gets a thicker line
            let lineH: CGFloat = month.isJanuary ? 3 : 1
            let lineColor = month.isJanuary
                ? Color.primary.opacity(0.25)
                : Color.primary.opacity(0.10)

            ctx.fill(
                Path(CGRect(x: 0, y: y, width: size.width, height: lineH)),
                with: .color(lineColor)
            )

            // Month label centered in the month's height
            let labelY = y + month.height / 2
            let monthName = monthAbbrev(month.month)
            let labelStr = month.height > 14
                ? "\(monthName.uppercased()) \(month.year)"
                : "\(monthName.uppercased())"

            let text = Text(labelStr)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.3))
            ctx.draw(text, at: CGPoint(x: labelArea / 2, y: labelY), anchor: .center)
        }

        // Date rows
        for row in layout.dateRows {
            let y = row.y + topPad
            let lineColor = row.isToday
                ? Color.accentColor.opacity(0.5)
                : Color.accentColor.opacity(0.15)

            // Horizontal date line (from end of label area to right edge)
            ctx.fill(
                Path(CGRect(x: labelArea, y: y, width: size.width - labelArea, height: 1)),
                with: .color(lineColor)
            )

            // Date label pill
            let dateText = row.isToday
                ? "Today · \(formatDateShort(row.date))"
                : formatDateShort(row.date)

            let label = Text(dateText)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.accentColor.opacity(row.isToday ? 0.9 : 0.6))
            ctx.draw(label, at: CGPoint(x: labelArea / 2, y: y), anchor: .center)
        }
    }

    private func drawLanes(ctx: GraphicsContext, layout: TimelineLayout) {
        for seg in layout.segments {
            let x = labelArea + CGFloat(seg.lane) * laneWidth + laneWidth / 2
            let sy = seg.startY + topPad
            let ey = seg.endY + topPad
            let color = seg.event.category.color

            // Vertical lane bar
            ctx.fill(
                Path(CGRect(x: x - 1, y: sy, width: 2, height: ey - sy)),
                with: .color(color.opacity(0.55))
            )

            // Start dot (hollow ring)
            let startDot = CGRect(x: x - 5, y: sy - 5, width: 10, height: 10)
            ctx.stroke(
                Path(ellipseIn: startDot),
                with: .color(color),
                lineWidth: 2.5
            )

            // End dot (filled)
            let endDot = CGRect(x: x - 5, y: ey - 5, width: 10, height: 10)
            if seg.ongoing {
                // Pulsing "ongoing" marker — draw as a smaller filled dot + ring
                ctx.fill(Path(ellipseIn: endDot.insetBy(dx: 2, dy: 2)), with: .color(color))
                ctx.stroke(Path(ellipseIn: endDot), with: .color(color.opacity(0.4)), lineWidth: 1.5)
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
        cardWidth: CGFloat
    ) -> some View {
        let state = cardStates[seg.id] ?? .collapsed
        let color = seg.event.category.color

        // Start card — sits ABOVE the start date line
        EventCard(
            event: seg.event,
            cardType: .start,
            state: state,
            color: color,
            onTap: { cycleState(for: seg.id) },
            onDismiss: { cardStates[seg.id] = .collapsed },
            modelContext: modelContext
        )
        .frame(width: cardWidth)
        .offset(
            x: cardLeft,
            y: seg.startY + topPad - cardHeight(for: seg.event, state: state)
        )

        // End card — sits BELOW the end date line (only if not ongoing)
        if !seg.ongoing {
            EventCard(
                event: seg.event,
                cardType: .end,
                state: state,
                color: color,
                onTap: { cycleState(for: seg.id) },
                onDismiss: { cardStates[seg.id] = .collapsed },
                modelContext: modelContext
            )
            .frame(width: cardWidth)
            .offset(x: cardLeft, y: seg.endY + topPad + 4)
        }
    }

    // MARK: - FAB

    private var addButton: some View {
        Button {
            showingAddEntity = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.glass)
        .padding(24)
    }

    // MARK: - Helpers

    private func recalcLayout() {
        layout = TimelineLayout.compute(
            events: allEvents,
            focusedEventID: focusedID,
            expandedEventID: expandedID
        )
    }

    private func cycleState(for id: UUID) {
        let current = cardStates[id] ?? .collapsed
        switch current {
        case .collapsed: cardStates[id] = .summary
        case .summary:   cardStates[id] = .expanded
        case .expanded:  cardStates[id] = .collapsed
        }
    }

    private func cardHeight(for event: LSEvent, state: CardState) -> CGFloat {
        switch state {
        case .collapsed: return TimelineLayout.collapsedCardHeight
        case .summary:   return TimelineLayout.summaryCardHeight
        case .expanded:  return TimelineLayout.expandedCardHeight
        }
    }

    private func monthAbbrev(_ month: Int) -> String {
        let names = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        return month >= 0 && month < 12 ? names[month] : "?"
    }

    private func formatDateShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }
}

// MARK: - EventCard

/// The card view rendered at each event's start and end positions.
/// Three states: collapsed, summary (key fields), expanded (full edit form).
enum EventCardType { case start; case end }

struct EventCard: View {

    @Bindable var event: LSEvent
    let cardType: EventCardType
    let state: CardState
    let color: Color
    let onTap: () -> Void
    let onDismiss: () -> Void
    let modelContext: ModelContext

    @State private var showingAddEvent = false
    @State private var showingFileImporter = false
    @State private var importError: String?

    var body: some View {
        cardContent
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
                    .padding(.leading, 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(state == .expanded ? 0.3 : 0.08), radius: state == .expanded ? 12 : 3)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture { if state != .expanded { onTap() } }
            .sheet(isPresented: $showingFileImporter) { }
            .alert("Import Error", isPresented: .constant(importError != nil)) {
                Button("OK") { importError = nil }
            } message: { Text(importError ?? "") }
    }

    @ViewBuilder
    private var cardContent: some View {
        switch state {
        case .collapsed:
            collapsedBody
        case .summary:
            summaryBody
        case .expanded:
            expandedBody
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
        .padding(.leading, 6)   // left-border offset
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

                // Show top 3 non-empty properties as key–value pairs
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
    }

    // MARK: Expanded (full edit form)

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
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

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Title
                    formField("Title") {
                        TextField("Event title", text: $event.title)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Category
                    formField("Category") {
                        Picker("", selection: $event.category) {
                            ForEach(EventCategory.allCases, id: \.self) { cat in
                                Label(cat.rawValue, systemImage: cat.systemImage).tag(cat)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    // Dates
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

                    // Notes
                    formField("Notes") {
                        TextField("Notes…", text: $event.notes, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                    }

                    // Properties
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

                    // Documents
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

                    // Footer actions
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

    // MARK: Computed helpers

    private var dateLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        if cardType == .start {
            return event.startDate.map { fmt.string(from: $0) } ?? "?"
        } else {
            return event.endDate.map { fmt.string(from: $0) } ?? "Present"
        }
    }
}

// MARK: - PropertyInlineRow

/// Compact editable row for a single LSProperty inside the expanded card.
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


