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

// MARK: - Lens geometry constants

/// Constants governing the date-label lens effect and sticky header placement.
/// `lensY` is the focal point (in scroll-view coordinates) where date labels
/// reach maximum scale. The sticky pill sits just above it.
private enum LensGeometry {
    nonisolated static let lensY: CGFloat = 80
    nonisolated static let halfPillHeight: CGFloat = 14
    static var stickyPadding: CGFloat { lensY - halfPillHeight }
}

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
    /// The event starts and ends in the same month — dot centered vertically.
    case single
    /// Ongoing event shown at today's row — treated the same as `.end`
    /// (dot at top, line continues downward into older months).
    case ongoing
    /// The event spans this month but starts/ends in another row — dot at mid-row,
    /// continuous line passes through the full row height.
    case passThrough
}

// MARK: - Event placement

/// Pairs an event with its role in a specific timeline row.
struct EventPlacement: Identifiable {
    let event: LSEvent
    let role: CardRole
    var id: String { "\(event.id)-\(role)" }
}

// MARK: - Lane overlay geometry

/// Pre-computed geometry for one timeline row, consumed by LaneConnectorOverlay.
private struct LaneRowGeometry {
    let yOffset: CGFloat            // cumulative Y from top of LazyVStack content
    let height: CGFloat             // total rendered height of this row
    let placements: [EventPlacement]    // events with cards in this row
    let passThroughEvents: [LSEvent]    // events spanning this row without a card
}

// MARK: - Card height helper

/// Returns the card body height for a given presentation state (excludes row padding).
/// Shared by EventMonthRow layout and the lane geometry pre-computation.
private func cardHeight(for state: CardState) -> CGFloat {
    switch state {
    case .collapsed: return 68
    case .summary:   return 120
    case .expanded:  return 480
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

    /// Today's month key — used to place ongoing events as inline cards.
    private var todayMonthKey: MonthKey { MonthKey(date: Date()) }

    /// Returns placements (event + role) for a given month row.
    ///
    /// Each event can produce up to two placements per row:
    ///   - `.start` when the event's start date is in this month
    ///   - `.end` when the event's end date is in this month
    ///   - `.ongoing` when an ongoing event (no end date) appears at today's month
    ///
    /// Same-month events (start AND end in this month) produce both `.start` and `.end`.
    /// Results are sorted by lane index for consistent left-to-right card ordering.
    private func placementsForRow(_ mk: MonthKey) -> [EventPlacement] {
        var result: [EventPlacement] = []
        var seen: Set<UUID> = []

        for event in allEvents {
            guard let start = event.startDate else { continue }
            let startMK = MonthKey(date: start)

            if let end = event.endDate {
                // Completed event
                let endMK = MonthKey(date: end)
                if startMK == mk && endMK == mk {
                    // Same-month: both start and end cards
                    result.append(EventPlacement(event: event, role: .start))
                    result.append(EventPlacement(event: event, role: .end))
                    seen.insert(event.id)
                } else if startMK == mk {
                    result.append(EventPlacement(event: event, role: .start))
                    seen.insert(event.id)
                } else if endMK == mk {
                    result.append(EventPlacement(event: event, role: .end))
                    seen.insert(event.id)
                }
            } else {
                // Ongoing event (no end date)
                if startMK == mk && mk == todayMonthKey {
                    // Start month IS today's month — show as ongoing
                    result.append(EventPlacement(event: event, role: .ongoing))
                    seen.insert(event.id)
                } else if startMK == mk {
                    // Start month, ongoing extends to today
                    result.append(EventPlacement(event: event, role: .start))
                    seen.insert(event.id)
                } else if mk == todayMonthKey && !seen.contains(event.id) {
                    // Today's month — ongoing card for event that started earlier
                    result.append(EventPlacement(event: event, role: .ongoing))
                    seen.insert(event.id)
                }
            }
        }

        return result.sorted {
            ($0.event.category.laneIndex, $0.event.startDate ?? .distantPast) <
            ($1.event.category.laneIndex, $1.event.startDate ?? .distantPast)
        }
    }

    /// Returns just the events for a given month row (used by snap promotion logic).
    private func eventsForRow(_ mk: MonthKey) -> [LSEvent] {
        let placements = placementsForRow(mk)
        // Deduplicate — same event can appear twice (same-month start+end)
        var seen: Set<UUID> = []
        return placements.compactMap { p in
            guard !seen.contains(p.event.id) else { return nil }
            seen.insert(p.event.id)
            return p.event
        }
    }

    /// Fixed lane count — one column per event category.
    private let numLanes: Int = EventCategory.laneCount

    /// Pre-computed row geometry map used by LaneConnectorOverlay.
    /// Recomputed whenever timelineRows or cardStates change.
    private var laneGeometry: [LaneRowGeometry] {
        var rows: [LaneRowGeometry] = []
        var cumulativeY: CGFloat = 0

        for row in timelineRows {
            let mk: MonthKey
            let placements: [EventPlacement]
            let passThrough: [LSEvent]
            let height: CGFloat

            switch row {
            case .emptyMonth(let year, let month):
                mk = MonthKey(year: year, month: month)
                let rowPlacements = placementsForRow(mk)
                placements = rowPlacements
                passThrough = passThroughEvents(for: mk)
                // Mirror timelineContent: if emptyMonth has placements (e.g. ongoing
                // events), it renders as EventMonthRow — so compute its dynamic height.
                height = rowPlacements.isEmpty ? 40 : eventMonthRowHeight(rowPlacements)

            case .eventMonth(let year, let month, _):
                mk = MonthKey(year: year, month: month)
                placements = placementsForRow(mk)
                passThrough = passThroughEvents(for: mk)
                height = eventMonthRowHeight(placements)
            }

            rows.append(LaneRowGeometry(
                yOffset: cumulativeY,
                height: height,
                placements: placements,
                passThroughEvents: passThrough
            ))
            cumulativeY += height
        }
        return rows
    }

    /// Computes the total rendered height of an EventMonthRow from its placements.
    /// Mirrors the exact SwiftUI layout: tallest card group + 16pt padding
    /// (.padding(.vertical, 4) on both the outer HStack and the card HStack).
    private func eventMonthRowHeight(_ placements: [EventPlacement]) -> CGFloat {
        // Reproduce EventMonthRow.cardGroups: group by event ID, preserving order.
        var groups: [[EventPlacement]] = []
        var indexByID: [UUID: Int] = [:]
        for p in placements {
            if let idx = indexByID[p.event.id] {
                groups[idx].append(p)
            } else {
                indexByID[p.event.id] = groups.count
                groups.append([p])
            }
        }
        // Tallest card group determines the row height.
        let tallest = groups.map { group -> CGFloat in
            let state = cardStates[group[0].event.id] ?? .collapsed
            let ch = cardHeight(for: state)
            // Same-month start+end: two cards stacked with VStack(spacing: 4)
            return group.count >= 2 ? ch * 2 + 4 : ch
        }.max() ?? cardHeight(for: .collapsed)
        // Outer .padding(.vertical, 4) + inner card HStack .padding(.vertical, 4) = 16pt
        return tallest + 16
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

    /// Events that pass through `mk` without starting or ending in it.
    ///
    /// These need a continuous lane line even though they have no card in this row.
    /// The guard uses strict less-than (`startMK < mk`) because an event whose
    /// start month equals `mk` is a card-bearing row, not a pass-through.
    private func passThroughEvents(for mk: MonthKey) -> [LSEvent] {
        let today = Date()
        return allEvents.filter { event in
            guard let start = event.startDate else { return false }
            let startMK = MonthKey(date: start)
            // Must have started strictly before this month (not the start month)
            guard startMK < mk else { return false }
            if let end = event.endDate {
                let endMK = MonthKey(date: end)
                // Must end strictly after this month (not the end month either)
                return endMK > mk
            }
            // Ongoing: pass through if between start and today (exclusive of today's month)
            let todayMK = MonthKey(date: today)
            return todayMK > mk
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
                                    let rowPlacements = placementsForRow(mk)
                                    if !rowPlacements.isEmpty {
                                        EventMonthRow(
                                            monthKey: mk,
                                            placements: rowPlacements,
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
                                            month: month
                                        )
                                        .id(row.id)
                                    }

                                case .eventMonth(let year, let month, _):
                                    let mk = MonthKey(year: year, month: month)
                                    EventMonthRow(
                                        monthKey: mk,
                                        placements: placementsForRow(mk),
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
                        .background(alignment: .topLeading) {
                            LaneConnectorOverlay(
                                rowGeometry: laneGeometry,
                                laneWidth: laneWidth,
                                labelArea: labelArea,
                                snappedEventIDs: snappedEventIDs
                            )
                        }
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
                    .padding(.top, LensGeometry.stickyPadding)
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
        .accessibilityLabel("Add entity")
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
                let lensY: CGFloat = LensGeometry.lensY
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
/// Uses PhaseAnimator to continuously cycle between dim and bright phases —
/// the declarative modern replacement for the manual @State + onAppear +
/// withAnimation(.repeatForever) pattern. No manual state toggle needed.
private struct PulsingHalo: View {
    let color: Color

    var body: some View {
        PhaseAnimator([false, true]) { expanded in
            Circle()
                .fill(color.opacity(expanded ? 0.5 : 0.15))
                .frame(width: 18, height: 18)
                .blur(radius: 4)
        } animation: { _ in
            .easeInOut(duration: 1.4)
        }
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
            .accessibilityLabel(label.isEmpty ? "Date header" : label)
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

// MARK: - EventMonthRow

/// A row for a calendar month showing all events side-by-side, each getting
/// an equal share of the available card width.
/// Same-event placements (start + end in same month) are stacked vertically.
private struct EventMonthRow: View {
    let monthKey: MonthKey
    let placements: [EventPlacement] // all placements in this month, sorted by category lane
    let passThroughEvents: [LSEvent]  // events passing through this month (no card here)
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

    /// Group placements by event ID, preserving order of first appearance.
    /// Each group is an array of placements for the same event (1 or 2 for same-month).
    private var cardGroups: [[EventPlacement]] {
        var groups: [[EventPlacement]] = []
        var indexByID: [UUID: Int] = [:]
        for p in placements {
            if let idx = indexByID[p.event.id] {
                groups[idx].append(p)
            } else {
                indexByID[p.event.id] = groups.count
                groups.append([p])
            }
        }
        return groups
    }

    var body: some View {
        let groups = cardGroups
        let count = max(groups.count, 1)
        let perCard = (cardWidth - CGFloat(count - 1) * 8) / CGFloat(count)

        HStack(alignment: .top, spacing: 0) {
            // Left gutter: month label
            DateLabel(text: monthKey.label, isMonth: true)
                .frame(width: labelArea, alignment: .center)
                .padding(.top, 8)

            // Lane zone: colored dots for all placements in this month
            LaneDotColumn(
                placements: placements,
                passThroughEvents: passThroughEvents,
                numLanes: numLanes,
                laneWidth: laneWidth,
                cardStates: cardStates,
                snappedEventIDs: snappedEventIDs
            )

            // Cards: different events side-by-side, same-event placements stacked.
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    if group.count == 1 {
                        let p = group[0]
                        let state = cardStates[p.event.id] ?? .collapsed
                        placementCard(p, state: state)
                            .frame(width: perCard)
                            .frame(height: cardHeight(for: state))
                    } else {
                        // Same-month start+end: end on top, start on bottom
                        let sorted = group.sorted { a, _ in a.role == .end }
                        let state = cardStates[sorted[0].event.id] ?? .collapsed
                        VStack(spacing: 4) {
                            ForEach(sorted) { p in
                                placementCard(p, state: state)
                                    .frame(height: cardHeight(for: state))
                            }
                        }
                        .frame(width: perCard)
                    }
                }
            }
            .frame(width: cardWidth)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func placementCard(_ placement: EventPlacement, state: CardState) -> some View {
        let event = placement.event
        let role = placement.role
        let color = event.category.color
        EventCard(
            event: event,
            role: role,
            state: state,
            color: color,
            onTap: {
                if state == .collapsed {
                    if role == .start {
                        onSelect(event.id)
                    } else {
                        // End/ongoing cards expand in place without scrolling
                        onCycleState(event.id)
                    }
                } else {
                    onCycleState(event.id)
                }
            },
            onDismiss: { onDismiss(event.id) },
            modelContext: modelContext
        )
    }

}

// MARK: - LaneDotColumn

/// Draws colored dots in each lane, positioned vertically based on the placement's
/// role: end/ongoing → top of card, start → bottom of card, passThrough → center.
/// Lane positions are fixed by category — employment is always lane 0, housing lane 1, etc.
private struct LaneDotColumn: View {
    let placements: [EventPlacement]
    let passThroughEvents: [LSEvent]
    let numLanes: Int
    let laneWidth: CGFloat
    let cardStates: [UUID: CardState]
    let snappedEventIDs: Set<UUID>

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<numLanes, id: \.self) { lane in
                let lanePlacements = placements.filter { $0.event.category.laneIndex == lane }

                ZStack(alignment: .center) {
                    if lanePlacements.count == 1 {
                        let p = lanePlacements[0]
                        dotView(for: p.event, role: p.role)
                    } else if lanePlacements.count >= 2 {
                        // Same-month dual dots: end at top, start at bottom
                        ForEach(lanePlacements) { p in
                            dotView(for: p.event, role: p.role)
                        }
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

    @ViewBuilder
    private func dotView(for event: LSEvent, role: CardRole) -> some View {
        let isSnapped = snappedEventIDs.contains(event.id)
        let color = event.category.color
        let dotSize: CGFloat = isSnapped ? 10 : 7
        let dotAlignment: Alignment = {
            switch role {
            case .end, .ongoing:   return .top
            case .start:           return .bottom
            case .single:          return .center
            case .passThrough:     return .center
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
        .accessibilityLabel("\(event.category.rawValue) lane")
    }
}

// MARK: - LaneConnectorOverlay

/// Single-pass Canvas overlay placed as .background on the LazyVStack.
/// Draws ALL lane connector lines in one coordinate space — truly continuous
/// across row boundaries — rather than stitching per-row segments.
///
/// The Canvas receives the full LazyVStack content size (not just the viewport),
/// and CoreGraphics auto-clips drawing to the visible region for performance.
///
/// Dots continue to live in per-row LaneDotColumn views so that PulsingHalo
/// (a PhaseAnimator) can animate normally as a SwiftUI view.
private struct LaneConnectorOverlay: View {
    let rowGeometry: [LaneRowGeometry]
    let laneWidth: CGFloat
    let labelArea: CGFloat
    let snappedEventIDs: Set<UUID>

    private let edgeInset: CGFloat = 8
    private let dotRadius: CGFloat = 5

    private func laneX(for event: LSEvent) -> CGFloat {
        labelArea + CGFloat(event.category.laneIndex) * laneWidth + laneWidth / 2
    }

    /// Y position of a dot's centre within a row, in row-local coordinates.
    private func dotY(for role: CardRole, rowHeight: CGFloat) -> CGFloat {
        switch role {
        case .end, .ongoing:         return edgeInset + dotRadius
        case .start:                 return rowHeight - edgeInset - dotRadius
        case .single, .passThrough:  return rowHeight / 2
        }
    }

    var body: some View {
        Canvas { context, _ in
            for row in rowGeometry {
                let top = row.yOffset
                let h   = row.height

                // ── Pass-through lines: full row height, faint ──
                for event in row.passThroughEvents {
                    let x = laneX(for: event)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: top))
                    path.addLine(to: CGPoint(x: x, y: top + h))
                    context.stroke(path,
                                   with: .color(event.category.color.opacity(0.25)),
                                   lineWidth: 1.5)
                }

                // ── Placement connector lines ──
                let grouped = Dictionary(grouping: row.placements, by: { $0.event.id })
                for (eventID, group) in grouped {
                    guard let event = group.first?.event else { continue }
                    let x         = laneX(for: event)
                    let isSnapped = snappedEventIDs.contains(eventID)
                    let color     = event.category.color

                    let lineStart: CGFloat
                    let lineEnd: CGFloat

                    if group.count >= 2 {
                        // Same-month start+end: line between the two dots only
                        lineStart = top + dotY(for: .end,   rowHeight: h)
                        lineEnd   = top + dotY(for: .start, rowHeight: h)
                    } else {
                        let role    = group[0].role
                        let dotGlobalY = top + dotY(for: role, rowHeight: h)
                        switch role {
                        case .start:
                            // Top of row down to dot (connects to pass-through above)
                            lineStart = top; lineEnd = dotGlobalY
                        case .end, .ongoing:
                            // Dot down to bottom of row (connects to pass-through below)
                            lineStart = dotGlobalY; lineEnd = top + h
                        case .single:
                            continue    // no connector line for isolated single-month events
                        case .passThrough:
                            lineStart = top; lineEnd = top + h
                        }
                    }

                    var path = Path()
                    path.move(to: CGPoint(x: x, y: lineStart))
                    path.addLine(to: CGPoint(x: x, y: lineEnd))

                    if isSnapped {
                        // Soft glow halo behind the crisp line
                        var blurCtx = context
                        blurCtx.addFilter(.blur(radius: 3))
                        blurCtx.stroke(path,
                                       with: .color(color.opacity(0.25)),
                                       lineWidth: 6)
                    }
                    context.stroke(path,
                                   with: .color(color.opacity(isSnapped ? 0.75 : 0.3)),
                                   lineWidth: isSnapped ? 2.5 : 2)
                }
            }
        }
    }
}

// MARK: - EventCard

struct EventCard: View {

    @Bindable var event: LSEvent
    let role: CardRole
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(event.title), \(event.category.rawValue), \(event.durationLabel)")
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
                Text(roleLabel)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(dateLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(role == .start ? color : .secondary)
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
                                    ), in: (event.startDate ?? .distantPast)...,
                                       displayedComponents: .date)
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

    private var roleLabel: String {
        switch role {
        case .start:       return "Started"
        case .end:         return "Ended"
        case .ongoing:     return "Ongoing"
        case .single:      return ""
        case .passThrough: return ""
        }
    }

    private var dateLabel: String {
        let fmt = Self.longDateFormatter
        switch role {
        case .start, .ongoing:
            return event.startDate.map { fmt.string(from: $0) } ?? "?"
        case .end:
            return event.endDate.map { fmt.string(from: $0) } ?? "?"
        case .single:
            return event.startDate.map { fmt.string(from: $0) } ?? "?"
        case .passThrough:
            return ""
        }
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
