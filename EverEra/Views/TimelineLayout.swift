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

/// A single row in the timeline — either a month with one or more events
/// (all events in the same month share one row side-by-side) or an empty month.
enum TimelineRow: Identifiable, Hashable {
    case emptyMonth(year: Int, month: Int)
    /// All events whose start date falls in the same calendar month.
    case eventMonth(year: Int, month: Int, dateStrings: [String])

    var id: String {
        switch self {
        case .emptyMonth(let year, let month):
            return "empty-\(year)-\(month)"
        case .eventMonth(let year, let month, _):
            return "month-\(year)-\(month)"
        }
    }

    // Hashable conformance
    static func == (lhs: TimelineRow, rhs: TimelineRow) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Row Builder

/// Builds an ordered list of `TimelineRow` values from newest to oldest,
/// inserting `.emptyMonth` entries for any month gaps between events.
/// All events whose start date falls in the same calendar month share a single
/// `.eventMonth` row so they can be displayed side-by-side.
func buildTimelineRows(from events: [LSEvent]) -> [TimelineRow] {
    guard !events.isEmpty else { return [] }

    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    // Collect the unique start-date strings per month.
    var datesByMonth: [MonthKey: Set<String>] = [:]
    var minMK = MonthKey(date: today)
    var maxMK = MonthKey(date: today)

    for event in events {
        guard let start = event.startDate else { continue }
        let mk = MonthKey(date: start)
        let ds = TimelineHelpers.dateString(from: start)
        datesByMonth[mk, default: []].insert(ds)
        minMK = min(minMK, mk)
        maxMK = max(maxMK, mk)
    }

    // Pad one month on each side so the timeline feels roomy.
    minMK = minMK.previous
    maxMK = maxMK.next

    // Walk newest → oldest, emitting one row per month.
    var rows: [TimelineRow] = []
    var mk = maxMK
    while mk >= minMK {
        let dates = datesByMonth[mk] ?? []
        if dates.isEmpty {
            rows.append(.emptyMonth(year: mk.year, month: mk.month))
        } else {
            // Sort date strings newest-first so cards render newest-first (left).
            let sorted = dates.sorted(by: >)
            rows.append(.eventMonth(year: mk.year, month: mk.month, dateStrings: sorted))
        }
        mk = mk.previous
    }

    return rows
}

// MARK: - Category-Based Lane Assignment

/// Fixed lane index for each event category.
/// Categories are ordered left-to-right on the timeline; the order is stable
/// so connector lines remain perfectly vertical across all rows.
extension EventCategory {
    /// 0-based column index in the lane zone.
    var laneIndex: Int {
        switch self {
        case .employment:  return 0
        case .housing:     return 1
        case .education:   return 2
        case .ownership:   return 3
        case .health:      return 4
        case .travel:      return 5
        case .financial:   return 6
        case .milestone:   return 7
        case .other:       return 8
        }
    }

    /// Total number of lanes (one per category).
    static var laneCount: Int { EventCategory.allCases.count }
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
