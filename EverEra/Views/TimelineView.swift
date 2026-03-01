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

    // Derived flat list of all events from all entities
    private var allEvents: [LSEvent] {
        entities.flatMap { $0.events }
    }

    private var expandedID: UUID? {
        cardStates.first(where: { $0.value == .expanded })?.key
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
        // Auto-promote/demote cards when snap target changes.
        .onChange(of: snappedRowID) { oldID, newID in
            handleSnapChange(from: oldID, to: newID)
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
                                onCycleState: { cycleState(for: $0) },
                                onDismiss: { id in
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                        cardStates[id] = .collapsed
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
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $snappedRowID, anchor: .top)
            .contentMargins(.top, 60, for: .scrollContent)
            .contentMargins(.bottom, 300, for: .scrollContent)
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

    private func handleSnapChange(from oldID: String?, to newID: String?) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
            // Determine which events are at the new snapped date
            var newSnapped: Set<UUID> = []

            if let newID, case .eventDate(let dateStr, _) = timelineRows.first(where: { $0.id == newID }) {
                for event in (eventsByDate[dateStr] ?? []) {
                    let startStr = event.startDate.map { TimelineHelpers.dateString(from: $0) } ?? ""
                    if startStr == dateStr {
                        newSnapped.insert(event.id)
                        // Only promote if currently collapsed
                        if cardStates[event.id] == nil || cardStates[event.id] == .collapsed {
                            cardStates[event.id] = .summary
                        }
                    }
                }
            }

            // Revert previously snapped events that are no longer snapped
            for id in snappedEventIDs where !newSnapped.contains(id) {
                if cardStates[id] == .summary {
                    cardStates[id] = .collapsed
                }
            }
            snappedEventIDs = newSnapped
        }
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

    // MARK: - Cached formatters

    static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}

// MARK: - DateMagnifyLabel

/// A date/month label that scales up with Gaussian falloff near the snap focal
/// point at the top of the scroll view — dock-style magnification.
private struct DateMagnifyLabel: View {
    let text: String
    let isMonth: Bool

    /// Distance from viewport top to the focal point.
    private let focalOffsetY: CGFloat = 30

    var body: some View {
        Text(text)
            .font(.system(size: isMonth ? 10 : 12, weight: .bold, design: .rounded))
            .foregroundStyle(isMonth ? .secondary : .primary)
            .visualEffect { content, proxy in
                let scrollBounds = proxy.bounds(of: .scrollView(axis: .vertical))
                let labelMidY = proxy.frame(in: .global).midY
                let focalY = (scrollBounds?.minY ?? 0) + focalOffsetY
                let distance = abs(labelMidY - focalY)

                // Gaussian falloff
                let sigma: CGFloat = 80
                let mag = exp(-0.5 * pow(distance / sigma, 2))
                let scale = 1.0 + 1.2 * mag   // max 2.2× at focal point
                let opacity = 0.35 + 0.65 * mag

                return content
                    .scaleEffect(scale)
                    .opacity(opacity)
            }
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
            DateMagnifyLabel(text: monthLabel, isMonth: true)
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
            // Left gutter: magnifying date label
            DateMagnifyLabel(text: Self.dateFormatter.string(from: date), isMonth: false)
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
                        onTap: { onCycleState(event.id) },
                        onDismiss: { onDismiss(event.id) },
                        modelContext: modelContext
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: cardHeight(for: state))
                }
            }
            .frame(maxWidth: .infinity)
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
                        Circle()
                            .fill(event.category.color)
                            .frame(width: isSnapped ? 10 : 7, height: isSnapped ? 10 : 7)
                            .shadow(color: event.category.color.opacity(isSnapped ? 0.5 : 0), radius: 4)
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

                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                    .stroke(event.category.color.opacity(isSnapped ? 0.65 : 0.3), lineWidth: 2)
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
