//
//  TimelineView.swift
//  EverEra
//
//  The Temporal Surface — a vertical timeline where every event occupies a
//  moment in calendar time. Events live in colour-coded lanes; date labels
//  magnify dock-style as they approach the snap focal point near the viewport
//  top. Scroll snaps to every event date and every empty month.
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

    // MARK: State

    @Query(sort: \LSEntity.createdAt, order: .forward) private var entities: [LSEntity]
    @Environment(\.modelContext) private var modelContext

    @State private var cardStates: [UUID: CardState] = [:]
    @State private var showingAddEntity = false

    /// The ID of the currently snapped row (drives scroll position + card promotion).
    @State private var snappedRowID: String?
    /// Event IDs whose start date matches the currently snapped date.
    @State private var snappedEventIDs: Set<UUID> = []
    /// The event the user explicitly tapped/selected — drives auto-scroll + expand.
    @State private var selectedEventID: UUID?
    /// Debounce task that delays card-state promotion until scroll fully settles.
    @State private var snapDebounceTask: Task<Void, Never>?
    /// ScrollViewReader proxy stored so selectEvent can trigger programmatic scroll.
    @State private var scrollProxy: ScrollViewProxy?

    // Derived flat list of all events from all entities
    private var allEvents: [LSEvent] {
        entities.flatMap { $0.events }
    }

    // MARK: Computed timeline data

    private var timelineRows: [TimelineRow] {
        buildTimelineRows(from: allEvents)
    }

    private var eventsByDate: [String: [LSEvent]] {
        let today = Calendar.current.startOfDay(for: Date())
        var result: [String: [LSEvent]] = [:]
        for event in allEvents {
            if let start = event.startDate {
                let ds = TimelineHelpers.dateString(from: start)
                result[ds, default: []].append(event)
            }
            let endDS = TimelineHelpers.dateString(from: event.endDate ?? today)
            if result[endDS]?.contains(where: { $0.id == event.id }) != true {
                result[endDS, default: []].append(event)
            }
        }
        return result
    }

    private var laneData: (assignments: [UUID: Int], numLanes: Int) {
        assignLanes(events: allEvents)
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if allEvents.isEmpty {
                emptyState
            } else {
                timelineContent
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
        // Prune stale card states when events change.
        .onChange(of: allEvents.map { $0.id }) { _, newIDs in
            let live = Set(newIDs)
            cardStates = cardStates.filter { live.contains($0.key) }
        }
        // Card-state promotion now happens in onScrollPhaseChange (idle) inside
        // timelineContent, so the state update never races the scroll physics.
        // Auto-expand card when an event is selected.
        // The scroll is handled by selectEvent(_:proxy:) directly.
        .onChange(of: selectedEventID) { _, newID in
            guard let newID else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                cardStates[newID] = .expanded
            }
        }
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

    // MARK: Timeline content

    private var timelineContent: some View {
        GeometryReader { geo in
            let lanes = laneData
            let cardLeft = labelArea + CGFloat(lanes.numLanes) * laneWidth + cardGap
            let cardWidth = max(geo.size.width - cardLeft - 16, 200)

            ZStack(alignment: .topLeading) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            ForEach(timelineRows) { row in
                                switch row {
                                case .emptyMonth(let year, let month):
                                    EmptyMonthRow(year: year, month: month)
                                        .id(row.id)

                                case .eventDate(let dateStr, let date):
                                    EventDateRow(
                                        dateStr: dateStr,
                                        date: date,
                                        events: eventsByDate[dateStr] ?? [],
                                        laneAssignments: lanes.assignments,
                                        numLanes: lanes.numLanes,
                                        cardStates: $cardStates,
                                        labelArea: labelArea,
                                        laneWidth: laneWidth,
                                        cardWidth: cardWidth,
                                        cardLeft: cardLeft,
                                        snappedEventIDs: snappedEventIDs,
                                        onSelect: { selectEvent($0, proxy: proxy) },
                                        onCycleState: { cycleState(for: $0) },
                                        onDismiss: { id in
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                                cardStates[id] = .collapsed
                                                if selectedEventID == id { selectedEventID = nil }
                                            }
                                        },
                                        modelContext: modelContext
                                    )
                                    .id(row.id)
                                }
                            }
                        }
                        // scrollTargetLayout tells scrollPosition(id:) which views
                        // are candidates for position tracking (read-only use here).
                        .scrollTargetLayout()
                    }
                    // No scrollTargetBehavior — viewAligned(.always) was the root
                    // cause of bounce/hesitation: it fought card-height changes that
                    // occurred while the scroll physics were still running.
                    // Manual snap-to-nearest is applied on .idle phase instead.
                    .scrollPosition(id: $snappedRowID, anchor: .top)
                    // contentMargins(.top) must equal lensY so that when a row is
                    // snapped to the top anchor its date label lands at the lens.
                    // lensY = topInset + rowPadding(4) + labelTopPad(8) + labelHalf(9) ≈ topInset + 21
                    // With topInset = 59 → lensY ≈ 80. See DateLabel.visualEffect below.
                    .contentMargins(.top, 59, for: .scrollContent)
                    .contentMargins(.bottom, 300, for: .scrollContent)
                    .scrollBounceBehavior(.basedOnSize)
                    .onAppear { scrollProxy = proxy }
                    // Snap-on-idle: after the user's scroll physics fully settle,
                    // lock the nearest row cleanly to the top anchor, then
                    // promote/demote cards with a safe delay so the height change
                    // never overlaps active scroll physics.
                    .onScrollPhaseChange { _, newPhase in
                        guard newPhase == .idle else { return }
                        snapDebounceTask?.cancel()
                        // 1. Snap-lock the resting position.
                        if let proxy = scrollProxy {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                proxy.scrollTo(snappedRowID, anchor: .top)
                            }
                        }
                        // 2. Promote/demote cards after snap animation completes.
                        snapDebounceTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(280))
                            guard !Task.isCancelled else { return }
                            handleSnapChange(to: snappedRowID)
                        }
                    }
                }

                // Sticky date pill — floats over the left label gutter, vertically
                // centered at lensY (80pt) so it aligns with the magnified DateLabel.
                // frame(width: labelArea) constrains it to the same 160pt column that
                // EventDateRow uses for its DateLabel, centering the pill within it.
                // pill height ≈ 28pt → top = lensY - halfPill = 80 - 14 = 66.
                StickyDateHeader(label: stickyDateLabel)
                    .frame(width: labelArea)
                    .padding(.top, 66)
            }
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

    // MARK: - Snap change handling

    /// Called once after scroll physics idle. `oldID` was removed — the
    /// `snappedEventIDs` set already tracks what was previously promoted.
    private func handleSnapChange(to newID: String?) {
        // Determine which events are at the new snapped date
        var newSnapped: Set<UUID> = []
        var statesToUpdate: [UUID: CardState] = [:]

        if let newID, case .eventDate(let dateStr, _) = timelineRows.first(where: { $0.id == newID }) {
            for event in (eventsByDate[dateStr] ?? []) {
                let startStr = event.startDate.map { TimelineHelpers.dateString(from: $0) } ?? ""
                if startStr == dateStr {
                    newSnapped.insert(event.id)
                    // Selected event stays expanded; others get summary
                    if event.id == selectedEventID {
                        statesToUpdate[event.id] = .expanded
                    } else if cardStates[event.id] == nil || cardStates[event.id] == .collapsed {
                        statesToUpdate[event.id] = .summary
                    }
                }
            }
        }

        // Revert previously snapped events that are no longer snapped
        for id in snappedEventIDs where !newSnapped.contains(id) {
            if cardStates[id] == .summary {
                statesToUpdate[id] = .collapsed
            }
            // Note: Don't clear selection here - let explicit user actions control it
        }
        
        // Apply all state changes in a single animation transaction
        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
            for (id, state) in statesToUpdate {
                cardStates[id] = state
            }
            snappedEventIDs = newSnapped
        }
    }

    // MARK: - Helpers

    /// Select an event: programmatically scroll its date row to the top and expand.
    private func selectEvent(_ id: UUID, proxy: ScrollViewProxy) {
        // Find the row ID for this event's start date
        guard let event = allEvents.first(where: { $0.id == id }),
              let start = event.startDate else { return }

        let ds = TimelineHelpers.dateString(from: start)
        let rowID = "date-\(ds)"

        // Expand the card first so the row has its final height
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            selectedEventID = id
            cardStates[id] = .expanded
        }

        // Use ScrollViewReader to scroll directly — avoids the viewAligned hesitancy
        // that occurs when the snap engine resists landing on tall rows.
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            proxy.scrollTo(rowID, anchor: .top)
        }
    }

    private func cycleState(for id: UUID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            let current = cardStates[id] ?? .collapsed
            switch current {
            case .collapsed: cardStates[id] = .summary
            case .summary:   cardStates[id] = .expanded
            case .expanded:
                cardStates[id] = .collapsed
                if selectedEventID == id { selectedEventID = nil }
            }
        }
    }

    // MARK: - Sticky date label

    /// Derives the sticky pill label directly from `snappedRowID` — no height
    /// estimation needed. `scrollPosition(id:anchor:.top)` reliably reports the
    /// row whose top edge is at the scroll anchor once scroll physics settle.
    private var stickyDateLabel: String {
        guard let rowID = snappedRowID,
              let row = timelineRows.first(where: { $0.id == rowID })
        else { return "" }
        switch row {
        case .emptyMonth(let year, let month):
            return MonthKey(year: year, month: month).label
        case .eventDate(_, let date):
            return Self.stickyDateFormatter.string(from: date)
        }
    }

    // MARK: - Cached formatters

    static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let stickyDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}

// MARK: - DateLabel

/// A date/month label in the left gutter that magnifies as it approaches the
/// sticky lens position near the top of the scroll view.
private struct DateLabel: View {
    let text: String
    let isMonth: Bool

    var body: some View {
        Text(text)
            .font(.system(size: isMonth ? 10 : 11, weight: isMonth ? .medium : .semibold, design: .rounded))
            .foregroundStyle(isMonth ? .tertiary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .visualEffect { content, geometry in
                // Lens center in scroll-view coordinate space.
                // Derivation: contentMargins.top(59) + rowPad(4) + labelPad(8) + labelHalf(9) = 80.
                // Must stay in sync with StickyDateHeader's .padding(.top, 66) (lensY - halfPill).
                let lensY: CGFloat = 80
                let frame = geometry.frame(in: .scrollView)
                let dist = abs(frame.midY - lensY)
                let radius: CGFloat = 80
                let t = max(0.0, 1.0 - dist / radius)
                let scale = 1.0 + t * 0.45
                let brighten = Double(t) * 0.5
                return content
                    .scaleEffect(scale, anchor: .leading)
                    .brightness(brighten)
            }
    }
}

// MARK: - PulsingHalo

/// GPU-driven pulsing glow behind a snapped lane dot.
/// Uses a single @State bool toggled on appear — the animation runs entirely on
/// the render server, no per-frame CPU callback unlike TimelineView(.animation).
private struct PulsingHalo: View {
    let color: Color
    @State private var expanded = false

    var body: some View {
        Circle()
            .fill(color.opacity(expanded ? 0.5 : 0.15))
            .frame(width: 18, height: 18)
            .blur(radius: 4)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                ) { expanded = true }
            }
            .onDisappear { expanded = false }
    }
}

// MARK: - StickyDateHeader

/// A pill pinned near the top of the timeline whose label is derived from
/// `snappedRowID` — no height estimation or per-frame offset math needed.
/// The parent `TimelineMainView.stickyDateLabel` does the lookup.
private struct StickyDateHeader: View {
    let label: String

    var body: some View {
        Text(label.isEmpty ? " " : label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(label.isEmpty ? .clear : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(.primary.opacity(0.15), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            }
            // Animate text cross-fades, not position — keeps the pill stationary.
            .animation(.easeOut(duration: 0.15), value: label)
    }
}

// MARK: - EmptyMonthRow

/// A minimal snap-target row for months that have no events.
private struct EmptyMonthRow: View {
    let year: Int
    let month: Int  // 1-based

    private var monthLabel: String {
        MonthKey(year: year, month: month).label
    }

    var body: some View {
        HStack {
            DateLabel(text: monthLabel, isMonth: true)
                .frame(width: 160, alignment: .center)
            Spacer()
        }
        .frame(height: 40)
    }
}

// MARK: - EventDateRow

/// A row for a specific date, showing the magnifying date label, lane dots,
/// and event cards.
private struct EventDateRow: View {
    let dateStr: String
    let date: Date
    let events: [LSEvent]
    let laneAssignments: [UUID: Int]
    let numLanes: Int
    @Binding var cardStates: [UUID: CardState]
    let labelArea: CGFloat
    let laneWidth: CGFloat
    let cardWidth: CGFloat
    let cardLeft: CGFloat
    let snappedEventIDs: Set<UUID>
    let onSelect: (UUID) -> Void
    let onCycleState: (UUID) -> Void
    let onDismiss: (UUID) -> Void
    let modelContext: ModelContext

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left gutter: static date label
            DateLabel(text: Self.dateFormatter.string(from: date), isMonth: false)
                .frame(width: labelArea, alignment: .center)
                .padding(.top, 8)

            // Lane zone: colored dots
            LaneDotColumn(
                events: events,
                laneAssignments: laneAssignments,
                numLanes: numLanes,
                laneWidth: laneWidth,
                snappedEventIDs: snappedEventIDs
            )
            .padding(.top, 8)

            // Cards column
            VStack(spacing: 8) {
                ForEach(events) { event in
                    let state = cardStates[event.id] ?? .collapsed
                    let color = event.category.color
                    EventCard(
                        event: event,
                        cardType: .start,
                        state: state,
                        color: color,
                        onTap: {
                            if state == .collapsed {
                                onSelect(event.id)
                            } else {
                                onCycleState(event.id)
                            }
                        },
                        onDismiss: { onDismiss(event.id) },
                        modelContext: modelContext
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: cardHeight(for: state))
                }
            }
            .frame(width: cardWidth)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
        }
        .padding(.vertical, 4)
        // Per-row lane connector background
        .background(alignment: .topLeading) {
            LaneConnectorBackground(
                events: events,
                laneAssignments: laneAssignments,
                laneWidth: laneWidth,
                labelArea: labelArea,
                snappedEventIDs: snappedEventIDs
            )
        }
    }

    private func cardHeight(for state: CardState) -> CGFloat {
        switch state {
        case .collapsed: return 68
        case .summary:   return 120
        case .expanded:  return 480
        }
    }
}

// MARK: - LaneDotColumn

/// Draws colored dots in each lane for events at this date.
private struct LaneDotColumn: View {
    let events: [LSEvent]
    let laneAssignments: [UUID: Int]
    let numLanes: Int
    let laneWidth: CGFloat
    let snappedEventIDs: Set<UUID>

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<numLanes, id: \.self) { lane in
                ZStack {
                    if let event = events.first(where: { laneAssignments[$0.id] == lane }) {
                        let isSnapped = snappedEventIDs.contains(event.id)
                        let color = event.category.color

                        // Pulsing glow halo — GPU-driven repeatForever avoids
                        // the per-frame CPU cost of TimelineView(.animation).
                        if isSnapped {
                            PulsingHalo(color: color)
                        }

                        Circle()
                            .fill(color)
                            .frame(width: isSnapped ? 10 : 7, height: isSnapped ? 10 : 7)
                            .shadow(color: color.opacity(isSnapped ? 0.7 : 0), radius: isSnapped ? 6 : 0)
                    }
                }
                .frame(width: laneWidth, height: 20)
            }
        }
    }
}

// MARK: - LaneConnectorBackground

/// Draws vertical lane bar segments behind each EventDateRow.
private struct LaneConnectorBackground: View {
    let events: [LSEvent]
    let laneAssignments: [UUID: Int]
    let laneWidth: CGFloat
    let labelArea: CGFloat
    let snappedEventIDs: Set<UUID>

    var body: some View {
        GeometryReader { geo in
            ForEach(events) { event in
                if let lane = laneAssignments[event.id] {
                    let x = labelArea + CGFloat(lane) * laneWidth + laneWidth / 2
                    let isSnapped = snappedEventIDs.contains(event.id)
                    let color = event.category.color

                    // Glow halo behind the line when snapped
                    if isSnapped {
                        Path { path in
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: geo.size.height))
                        }
                        .stroke(color.opacity(0.25), lineWidth: 6)
                        .blur(radius: 3)
                    }

                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                    .stroke(color.opacity(isSnapped ? 0.75 : 0.3), lineWidth: isSnapped ? 2.5 : 2)
                }
            }
        }
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

                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Documents" + (event.documents.isEmpty ? "" : " (\(event.documents.count))"))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Spacer()
                            Button {
                                showingFileImporter = true
                            } label: {
                                Label("Attach", systemImage: "paperclip")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                        if event.documents.isEmpty {
                            Text("No documents attached.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(event.documents.sorted { $0.importedAt < $1.importedAt }) { doc in
                                HStack {
                                    Image(systemName: doc.kind.systemImage)
                                        .foregroundStyle(.secondary)
                                    Text(doc.displayName)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                    Button {
                                        modelContext.delete(doc)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.tertiary)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    .fileImporter(
                        isPresented: $showingFileImporter,
                        allowedContentTypes: [.pdf, .image, .png, .jpeg, .heic],
                        allowsMultipleSelection: true
                    ) { result in
                        switch result {
                        case .failure(let error):
                            importError = error.localizedDescription
                        case .success(let urls):
                            for url in urls {
                                let accessing = url.startAccessingSecurityScopedResource()
                                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                                do {
                                    let storedName = try LSDocument.importFile(from: url)
                                    let doc = LSDocument(
                                        displayName: url.deletingPathExtension().lastPathComponent,
                                        kind: DocumentKind.infer(from: url),
                                        storedFileName: storedName
                                    )
                                    modelContext.insert(doc)
                                    doc.event = event
                                    doc.runOCRIfNeeded()
                                } catch {
                                    importError = "Could not import \(url.lastPathComponent): \(error.localizedDescription)"
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

    private static let longDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private var dateLabel: String {
        let fmt = Self.longDateFormatter
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
