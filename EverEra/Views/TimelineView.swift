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

// MARK: - Card role within the timeline

/// Describes an event card's temporal role in a given row.
/// This drives dot vertical alignment and connector-line clipping.
enum CardRole: Equatable {
    /// The event starts in this month/row — dot sits at the bottom of the card.
    case start
    /// The event ends in this month/row — dot sits at the top of the card.
    case end
    /// Ongoing event shown at today's row — treated the same as `.end`
    /// (dot at top, line continues downward into older months).
    case ongoing
    /// The event spans this month but starts/ends in another row — dot at mid-row,
    /// continuous line passes through the full row height.
    case passThrough
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

    /// Maps a MonthKey → all events whose start date falls in that month.
    private var eventsByMonth: [MonthKey: [LSEvent]] {
        var result: [MonthKey: [LSEvent]] = [:]
        for event in allEvents {
            guard let start = event.startDate else { continue }
            let mk = MonthKey(date: start)
            result[mk, default: []].append(event)
        }
        return result
    }

    /// Today's month key — used to place ongoing events as inline cards.
    private var todayMonthKey: MonthKey { MonthKey(date: Date()) }

    /// Returns the events to show as cards in a given month row.
    /// For today's month this includes all ongoing events (started earlier,
    /// no end date) so they appear as inline cards anchored to the present.
    private func eventsForRow(_ mk: MonthKey) -> [LSEvent] {
        var pool = eventsByMonth[mk] ?? []
        if mk == todayMonthKey {
            // Add ongoing events that didn't start this month
            let startedThisMonth = Set(pool.map { $0.id })
            let ongoing = allEvents.filter {
                $0.endDate == nil &&
                $0.startDate != nil &&
                !startedThisMonth.contains($0.id)
            }
            pool.append(contentsOf: ongoing)
        }
        return pool
    }

    /// Fixed lane count — one column per event category.
    private let numLanes: Int = EventCategory.laneCount

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

    /// For each row month, which events are passing through (started before, not yet ended).
    /// These need a continuous lane line even though they have no card in that row.
    private func passThroughEvents(for mk: MonthKey) -> [LSEvent] {
        let today = Date()
        return allEvents.filter { event in
            guard let start = event.startDate else { return false }
            let startMK = MonthKey(date: start)
            // Event started before this month
            guard startMK < mk else { return false }
            // Event is ongoing or ends in/after this month
            let endMK: MonthKey
            if let end = event.endDate {
                endMK = MonthKey(date: end)
            } else {
                endMK = MonthKey(date: today)
            }
            return endMK >= mk
        }
    }

    private var timelineContent: some View {
        GeometryReader { geo in
            let cardLeft = labelArea + CGFloat(numLanes) * laneWidth + cardGap
            let cardWidth = max(geo.size.width - cardLeft - 16, 200)

            ZStack(alignment: .topLeading) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            ForEach(timelineRows) { row in
                                switch row {
                                case .emptyMonth(let year, let month):
                                    let mk = MonthKey(year: year, month: month)
                                    // Today's month may be empty in the normal event index but
                                    // still has ongoing event cards to show.
                                    let todayEvents = eventsForRow(mk)
                                    if !todayEvents.isEmpty {
                                        let sorted = todayEvents.sorted {
                                            ($0.category.laneIndex, $0.startDate ?? .distantPast) <
                                            ($1.category.laneIndex, $1.startDate ?? .distantPast)
                                        }
                                        EventMonthRow(
                                            monthKey: mk,
                                            events: sorted,
                                            passThroughEvents: passThroughEvents(for: mk),
                                            numLanes: numLanes,
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
                                    } else {
                                        EmptyMonthRow(
                                            year: year,
                                            month: month,
                                            passThroughEvents: passThroughEvents(for: mk),
                                            numLanes: numLanes,
                                            laneWidth: laneWidth,
                                            labelArea: labelArea
                                        )
                                        .id(row.id)
                                    }

                                case .eventMonth(let year, let month, _):
                                    let mk = MonthKey(year: year, month: month)
                                    let monthEvents: [LSEvent] = {
                                        let pool = eventsForRow(mk)
                                        // Sort by category lane index so cards appear
                                        // in the same left-to-right order as the lane columns.
                                        return pool.sorted {
                                            ($0.category.laneIndex, $0.startDate ?? .distantPast) <
                                            ($1.category.laneIndex, $1.startDate ?? .distantPast)
                                        }
                                    }()
                                    EventMonthRow(
                                        monthKey: mk,
                                        events: monthEvents,
                                        passThroughEvents: passThroughEvents(for: mk),
                                        numLanes: numLanes,
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
                        .scrollTargetLayout()
                    }
                    .scrollPosition(id: $snappedRowID, anchor: .top)
                    .contentMargins(.top, 59, for: .scrollContent)
                    .contentMargins(.bottom, 300, for: .scrollContent)
                    .scrollBounceBehavior(.basedOnSize)
                    .onAppear {
                        scrollProxy = proxy
                        scrollToTodayAndPromote(proxy: proxy)
                    }
                    .onScrollPhaseChange { _, newPhase in
                        guard newPhase == .idle else { return }
                        snapDebounceTask?.cancel()
                        if let proxy = scrollProxy {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                proxy.scrollTo(snappedRowID, anchor: .top)
                            }
                        }
                        snapDebounceTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(280))
                            guard !Task.isCancelled else { return }
                            handleSnapChange(to: snappedRowID)
                        }
                    }
                }

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
        // Determine which events are at the new snapped month row
        var newSnapped: Set<UUID> = []
        var statesToUpdate: [UUID: CardState] = [:]

        // Resolve the month key from either an eventMonth or emptyMonth row ID.
        let snappedMK: MonthKey? = {
            guard let newID else { return nil }
            if let row = timelineRows.first(where: { $0.id == newID }) {
                switch row {
                case .eventMonth(let y, let m, _): return MonthKey(year: y, month: m)
                case .emptyMonth(let y, let m):    return MonthKey(year: y, month: m)
                }
            }
            return nil
        }()

        if let mk = snappedMK {
            // Only promote events whose start OR end date falls in this month.
            // Ongoing events that float into today's row from an earlier start month
            // should not be promoted when the user scrolls to a different month.
            let nativeEvents = eventsForRow(mk).filter { event in
                if let start = event.startDate, MonthKey(date: start) == mk { return true }
                if let end = event.endDate, MonthKey(date: end) == mk { return true }
                return false
            }
            for event in nativeEvents {
                newSnapped.insert(event.id)
                // Selected event stays expanded; others get summary
                if event.id == selectedEventID {
                    statesToUpdate[event.id] = .expanded
                } else if cardStates[event.id] == nil || cardStates[event.id] == .collapsed {
                    statesToUpdate[event.id] = .summary
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

    /// Select an event: programmatically scroll its month row to the top and expand.
    private func selectEvent(_ id: UUID, proxy: ScrollViewProxy) {
        guard let event = allEvents.first(where: { $0.id == id }),
              let start = event.startDate else { return }

        // Ongoing events appear as cards in today's month row, not their start month.
        let isOngoing = event.endDate == nil
        let cardMK = isOngoing ? todayMonthKey : MonthKey(date: start)
        // Today row may be rendered from an emptyMonth or eventMonth TimelineRow.
        let rowID: String = {
            let eventID = "month-\(cardMK.year)-\(cardMK.month)"
            if timelineRows.contains(where: { $0.id == eventID }) { return eventID }
            return "empty-\(cardMK.year)-\(cardMK.month)"
        }()

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
        case .eventMonth(let year, let month, _):
            return MonthKey(year: year, month: month).label
        }
    }

    // MARK: - Initial scroll to today

    /// On first appear: scroll to today's row and promote all ongoing events to
    /// summary state so the user immediately sees what is currently active.
    private func scrollToTodayAndPromote(proxy: ScrollViewProxy) {
        let mk = todayMonthKey
        let rowID: String = {
            let eventID = "month-\(mk.year)-\(mk.month)"
            if timelineRows.contains(where: { $0.id == eventID }) { return eventID }
            return "empty-\(mk.year)-\(mk.month)"
        }()

        Task { @MainActor in
            // Small delay so LazyVStack has laid out before we scroll.
            try? await Task.sleep(for: .milliseconds(80))
            proxy.scrollTo(rowID, anchor: .top)
            snappedRowID = rowID

            // After the scroll settles, promote ongoing event cards to summary.
            try? await Task.sleep(for: .milliseconds(350))
            let ongoing = allEvents.filter { $0.endDate == nil && $0.startDate != nil }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                for event in ongoing {
                    if cardStates[event.id] == nil || cardStates[event.id] == .collapsed {
                        cardStates[event.id] = .summary
                    }
                }
                snappedEventIDs = Set(ongoing.map { $0.id })
            }
        }
    }

    // MARK: - Cached formatters

    static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
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
    let passThroughEvents: [LSEvent]
    let numLanes: Int
    let laneWidth: CGFloat
    let labelArea: CGFloat

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
        .background(alignment: .topLeading) {
            LaneConnectorBackground(
                events: [],
                passThroughEvents: passThroughEvents,
                laneWidth: laneWidth,
                labelArea: labelArea,
                cardStates: [:],
                roles: [:],
                snappedEventIDs: []
            )
        }
    }
}

// MARK: - EventMonthRow

/// A row for a calendar month showing all events side-by-side, each getting
/// an equal share of the available card width.
private struct EventMonthRow: View {
    let monthKey: MonthKey
    let events: [LSEvent]          // all events in this month, sorted by category lane
    let passThroughEvents: [LSEvent] // events passing through this month (no card here)
    let numLanes: Int
    @Binding var cardStates: [UUID: CardState]
    let labelArea: CGFloat
    let laneWidth: CGFloat
    let cardWidth: CGFloat         // total card zone width
    let cardLeft: CGFloat
    let snappedEventIDs: Set<UUID>
    let onSelect: (UUID) -> Void
    let onCycleState: (UUID) -> Void
    let onDismiss: (UUID) -> Void
    let modelContext: ModelContext

    /// The height driven by the tallest card in the row.
    private var rowCardHeight: CGFloat {
        events.map { cardHeight(for: cardStates[$0.id] ?? .collapsed) }.max() ?? 68
    }

    /// Determines the card role for an event in this month row.
    private func cardRole(for event: LSEvent) -> CardRole {
        // If the event is ongoing (no end date) it is shown here as the "current" endpoint.
        if event.endDate == nil { return .ongoing }
        // If the event ends in this month it is an end card.
        if let end = event.endDate, MonthKey(date: end) == monthKey { return .end }
        // Otherwise it starts here (start date is in this month).
        return .start
    }

    var body: some View {
        let roles: [UUID: CardRole] = Dictionary(uniqueKeysWithValues: events.map { ($0.id, cardRole(for: $0)) })

        HStack(alignment: .top, spacing: 0) {
            // Left gutter: month label
            DateLabel(text: monthKey.label, isMonth: true)
                .frame(width: labelArea, alignment: .center)
                .padding(.top, 8)

            // Lane zone: colored dots for all events in this month
            LaneDotColumn(
                events: events,
                passThroughEvents: passThroughEvents,
                numLanes: numLanes,
                laneWidth: laneWidth,
                cardStates: cardStates,
                roles: roles,
                snappedEventIDs: snappedEventIDs
            )

            // Cards: side-by-side, each getting an equal share of cardWidth.
            // cardWidth is the total available width for all cards combined.
            let count = max(events.count, 1)
            let perCard = (cardWidth - CGFloat(count - 1) * 8) / CGFloat(count)

            HStack(alignment: .top, spacing: 8) {
                ForEach(events) { event in
                    let state = cardStates[event.id] ?? .collapsed
                    let role = roles[event.id] ?? .start
                    let color = event.category.color
                    EventCard(
                        event: event,
                        cardType: (role == .start) ? .start : .end,
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
                    .frame(width: perCard)
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
                passThroughEvents: passThroughEvents,
                laneWidth: laneWidth,
                labelArea: labelArea,
                cardStates: cardStates,
                roles: roles,
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

/// Draws colored dots in each lane, positioned vertically based on the event's
/// role: end/ongoing → top of card, start → bottom of card, passThrough → center.
/// Lane positions are fixed by category — employment is always lane 0, housing lane 1, etc.
private struct LaneDotColumn: View {
    let events: [LSEvent]
    let passThroughEvents: [LSEvent]
    let numLanes: Int
    let laneWidth: CGFloat
    let cardStates: [UUID: CardState]
    let roles: [UUID: CardRole]
    let snappedEventIDs: Set<UUID>

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<numLanes, id: \.self) { lane in
                // Category-based lookup: find an event whose category maps to this lane.
                let cardEvent = events.first(where: { $0.category.laneIndex == lane })

                ZStack(alignment: .center) {
                    if let event = cardEvent {
                        let isSnapped = snappedEventIDs.contains(event.id)
                        let color = event.category.color
                        let role = roles[event.id] ?? .start
                        let dotSize: CGFloat = isSnapped ? 10 : 7
                        let dotAlignment: Alignment = {
                            switch role {
                            case .end, .ongoing: return .top
                            case .start:         return .bottom
                            case .passThrough:   return .center
                            }
                        }()

                        ZStack(alignment: dotAlignment) {
                            Color.clear
                            if isSnapped { PulsingHalo(color: color) }
                            Circle()
                                .fill(color)
                                .frame(width: dotSize, height: dotSize)
                                .shadow(color: color.opacity(isSnapped ? 0.7 : 0), radius: isSnapped ? 6 : 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: laneWidth)
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - LaneConnectorBackground

/// Draws vertical lane connector lines behind each row, clipped so they run
/// dot-to-dot rather than always spanning the full row height.
///
/// Lane X positions are derived from event.category.laneIndex, so lines are
/// perfectly continuous across all rows regardless of which events share a month.
///
/// - pass-through events: full-height faint line (event is active but has no card here)
/// - end / ongoing events: line from row top → dot (dot is near top of card)
/// - start events: line from dot → row bottom (dot is near bottom of card)
private struct LaneConnectorBackground: View {
    let events: [LSEvent]
    let passThroughEvents: [LSEvent]
    let laneWidth: CGFloat
    let labelArea: CGFloat
    let cardStates: [UUID: CardState]
    let roles: [UUID: CardRole]
    let snappedEventIDs: Set<UUID>

    /// Vertical offset from the row edge to the dot centre.
    /// Row has .padding(.vertical, 4) on the outer HStack and .padding(.vertical, 4)
    /// on the card zone, so cards start ~8 pt from the background edge.
    private let edgeInset: CGFloat = 8
    private let dotRadius: CGFloat = 5  // half of max dot size (10)

    private func laneX(for event: LSEvent) -> CGFloat {
        labelArea + CGFloat(event.category.laneIndex) * laneWidth + laneWidth / 2
    }

    /// Returns the Y coordinate of the dot for `event` within the background rect.
    private func dotY(for event: LSEvent, height: CGFloat) -> CGFloat {
        let role = roles[event.id] ?? .start
        switch role {
        case .end, .ongoing:
            return edgeInset + dotRadius
        case .start:
            return height - edgeInset - dotRadius
        case .passThrough:
            return height / 2
        }
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height

            // Pass-through lines — full height, faint
            ForEach(passThroughEvents) { event in
                let x = laneX(for: event)
                let color = event.category.color
                Path { path in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: h))
                }
                .stroke(color.opacity(0.25), lineWidth: 1.5)
            }

            // Event card lines — clipped to dot position
            ForEach(events) { event in
                let x = laneX(for: event)
                let isSnapped = snappedEventIDs.contains(event.id)
                let color = event.category.color
                let role = roles[event.id] ?? .start
                let dotYPos = dotY(for: event, height: h)

                // Line segment: top of row → dot (end/ongoing) or dot → bottom (start)
                let lineStart: CGFloat = (role == .start) ? dotYPos : 0
                let lineEnd: CGFloat   = (role == .start) ? h       : dotYPos

                // Glow halo when snapped
                if isSnapped {
                    Path { path in
                        path.move(to: CGPoint(x: x, y: lineStart))
                        path.addLine(to: CGPoint(x: x, y: lineEnd))
                    }
                    .stroke(color.opacity(0.25), lineWidth: 6)
                    .blur(radius: 3)
                }

                Path { path in
                    path.move(to: CGPoint(x: x, y: lineStart))
                    path.addLine(to: CGPoint(x: x, y: lineEnd))
                }
                .stroke(color.opacity(isSnapped ? 0.75 : 0.3), lineWidth: isSnapped ? 2.5 : 2)
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
