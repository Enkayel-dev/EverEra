//
//  TimelineLayout.swift
//  EverEra
//
//  Row-based timeline data model and lane assignment engine.
//
//  Responsibilities:
//    1. Build an ordered list of TimelineRow values (empty months + event dates)
//       walking from newest to oldest.
//    2. Assign each event to the narrowest available lane using greedy
//       interval-graph colouring (no overlap within a lane).
//    3. Provide date-string ↔ Date conversion helpers.
//

import Foundation
import SwiftUI

// MARK: - MonthKey

/// Lightweight comparable key for a calendar month.
struct MonthKey: Comparable, Hashable {
    let year: Int
    let month: Int  // 1-based (Jan = 1)

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(date: Date) {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        self.year = comps.year ?? 0
        self.month = comps.month ?? 1
    }

    /// The month immediately before this one.
    var previous: MonthKey {
        month == 1 ? MonthKey(year: year - 1, month: 12) : MonthKey(year: year, month: month - 1)
    }

    /// The month immediately after this one.
    var next: MonthKey {
        month == 12 ? MonthKey(year: year + 1, month: 1) : MonthKey(year: year, month: month + 1)
    }

    static func < (lhs: MonthKey, rhs: MonthKey) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    /// Short display label, e.g. "JAN 2025".
    var label: String {
        let names = ["JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"]
        let name = (month >= 1 && month <= 12) ? names[month - 1] : "?"
        return "\(name) \(year)"
    }

    /// Short month-only label, e.g. "JAN".
    var shortLabel: String {
        let names = ["JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"]
        return (month >= 1 && month <= 12) ? names[month - 1] : "?"
    }
}

// MARK: - TimelineRow

/// A single row in the timeline — either an event date (with one or more events)
/// or a month that has no events in it.
enum TimelineRow: Identifiable, Hashable {
    case emptyMonth(year: Int, month: Int)
    case eventDate(dateString: String, date: Date)

    var id: String {
        switch self {
        case .emptyMonth(let year, let month):
            return "empty-\(year)-\(month)"
        case .eventDate(let dateString, _):
            return "date-\(dateString)"
        }
    }

    // Hashable conformance (Date is already Hashable)
    static func == (lhs: TimelineRow, rhs: TimelineRow) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - TimelineLaneSegment (simplified — no Y positions)

/// Represents a single event's lane assignment for drawing connector segments.
struct TimelineLaneSegment: Identifiable {
    let id: UUID            // == event.id
    let event: LSEvent
    let lane: Int           // 0-based horizontal lane index
    let ongoing: Bool
}

// MARK: - Row Builder

/// Builds an ordered list of `TimelineRow` values from newest to oldest,
/// inserting `.emptyMonth` entries for any month gaps between events.
func buildTimelineRows(from events: [LSEvent]) -> [TimelineRow] {
    guard !events.isEmpty else { return [] }

    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    // Collect all unique dates and the month range they span.
    var datesByMonth: [MonthKey: Set<String>] = [:]
    var minMK = MonthKey(date: today)
    var maxMK = MonthKey(date: today)

    func register(_ date: Date) {
        let mk = MonthKey(date: date)
        datesByMonth[mk, default: []].insert(TimelineHelpers.dateString(from: date))
        minMK = min(minMK, mk)
        maxMK = max(maxMK, mk)
    }

    for event in events {
        if let start = event.startDate { register(start) }
        register(event.endDate ?? today)
    }

    // Pad one month on each side so the timeline feels roomy.
    minMK = minMK.previous
    maxMK = maxMK.next

    // Walk newest → oldest, emitting rows.
    var rows: [TimelineRow] = []
    var mk = maxMK
    while mk >= minMK {
        let dates = datesByMonth[mk] ?? []
        if dates.isEmpty {
            rows.append(.emptyMonth(year: mk.year, month: mk.month))
        } else {
            // Sort dates newest-first within the month.
            for ds in dates.sorted(by: >) {
                if let date = TimelineHelpers.date(from: ds) {
                    rows.append(.eventDate(dateString: ds, date: date))
                }
            }
        }
        mk = mk.previous
    }

    return rows
}

// MARK: - Lane Assignment

/// Greedy interval-graph colouring — assigns each event to the narrowest
/// available lane so that no two overlapping events share a lane.
///
/// Returns event-ID → lane-index map and the total number of lanes.
func assignLanes(events: [LSEvent]) -> (assignments: [UUID: Int], numLanes: Int) {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    // Sort events by start date ascending for stable assignment.
    let sorted = events
        .filter { $0.startDate != nil }
        .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }

    struct Interval { var sk: MonthKey; var ek: MonthKey }
    var lanes: [[Interval]] = []
    var assignments: [UUID: Int] = [:]

    for event in sorted {
        guard let start = event.startDate else { continue }
        let end = event.endDate ?? today
        let sk = MonthKey(date: start)
        let ek = MonthKey(date: end)

        var assigned = -1
        for (i, lane) in lanes.enumerated() {
            let overlaps = lane.contains { r in sk <= r.ek && ek >= r.sk }
            if !overlaps { assigned = i; break }
        }
        if assigned == -1 { assigned = lanes.count; lanes.append([]) }
        lanes[assigned].append(Interval(sk: sk, ek: ek))

        assignments[event.id] = assigned
    }

    return (assignments, max(lanes.count, 1))
}

/// Build `TimelineLaneSegment` array from events and pre-computed lane assignments.
func buildSegments(events: [LSEvent], laneAssignments: [UUID: Int]) -> [TimelineLaneSegment] {
    return events.compactMap { event in
        guard event.startDate != nil,
              let lane = laneAssignments[event.id] else { return nil }
        return TimelineLaneSegment(
            id: event.id,
            event: event,
            lane: lane,
            ongoing: event.endDate == nil
        )
    }
}

// MARK: - Helpers

enum TimelineHelpers {
    static func dateString(from date: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    static func date(from string: String) -> Date? {
        let parts = string.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        return Calendar.current.date(from: comps)
    }
}

// MARK: - Convenience

extension Date {
    var dateString: String { TimelineHelpers.dateString(from: self) }
}
