//
//  TimelineLayout.swift
//  EverEra
//
//  Pure value-type layout engine for the vertical timeline.
//  Ported from the HTML prototype's layoutTimeline() function.
//
//  Algorithm overview:
//    1. Collect every unique Date that appears as a startDate or endDate across
//       all events. Nil endDate → treated as "today".
//    2. Walk dates newest → oldest (top of scroll = newest).
//       For each date, reserve vertical space for start-cards above the date
//       line and end-cards below it.
//    3. Group dates into months; insert month-header rows.
//    4. Assign each event to the narrowest available lane using greedy
//       interval-graph colouring (no overlap within a lane).
//    5. Return a flat struct of pre-computed Y positions for everything.
//

import Foundation
import SwiftUI

// MARK: - Supporting value types

struct TimelineMonthRow: Identifiable {
    var id: String { "\(year)-\(month)" }
    let year: Int
    let month: Int          // 0-based (Jan = 0)
    let y: CGFloat          // top edge of this month's allocated space
    let height: CGFloat     // total vertical space consumed by this month
    let isJanuary: Bool
}

struct TimelineDateRow: Identifiable {
    var id: String { dateStr }
    let dateStr: String     // "YYYY-MM-DD"
    let date: Date
    let y: CGFloat          // exact Y of the horizontal date line
    let isToday: Bool
    let eventIDs: [UUID]    // all events whose start or end falls here
}

struct TimelineLaneSegment: Identifiable {
    let id: UUID            // == event.id
    let event: LSEvent
    let lane: Int           // 0-based horizontal lane index
    let startY: CGFloat     // Y of the start date line
    let endY: CGFloat       // Y of the end date line (or today line if ongoing)
    let ongoing: Bool
}

// MARK: - TimelineLayout

struct TimelineLayout {

    // MARK: Constants

    /// Vertical pixels allocated per unoccupied month (no events that month).
    static let emptyMonthHeight: CGFloat = 22
    /// Minimum height for a month that has events, so labels stay readable.
    static let minActiveMonthHeight: CGFloat = 22
    /// Gap added below the last card of each date row before the next row.
    static let dateRowBuffer: CGFloat = 10
    /// Default collapsed card height (above or below the date line).
    static let collapsedCardHeight: CGFloat = 68
    /// Summary-state card height.
    static let summaryCardHeight: CGFloat = 120
    /// Expanded/edit card height.
    static let expandedCardHeight: CGFloat = 480

    // MARK: Layout outputs

    let months: [TimelineMonthRow]
    let dateRows: [TimelineDateRow]
    let segments: [TimelineLaneSegment]
    let totalHeight: CGFloat
    let numLanes: Int
    let todayY: CGFloat
    let todayStr: String

    // MARK: - Static factory

    static func compute(
        events: [LSEvent],
        focusedEventID: UUID? = nil,
        expandedEventID: UUID? = nil
    ) -> TimelineLayout? {
        guard !events.isEmpty else { return nil }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayStr = Self.dateString(from: today)

        // ── 1. Collect all relevant dates ───────────────────────────────────
        // Build a map: monthKey → Set<dateStr>
        var monthToDateStrings: [Int: Set<String>] = [:]

        func monthKey(for date: Date) -> Int {
            let comps = calendar.dateComponents([.year, .month], from: date)
            return (comps.year ?? 0) * 12 + ((comps.month ?? 1) - 1)
        }

        func ensureMonth(_ mk: Int) {
            if monthToDateStrings[mk] == nil { monthToDateStrings[mk] = [] }
        }

        var minMK = monthKey(for: today)
        var maxMK = monthKey(for: today)

        for event in events {
            if let start = event.startDate {
                let mk = monthKey(for: start)
                minMK = min(minMK, mk)
                maxMK = max(maxMK, mk)
                ensureMonth(mk)
                monthToDateStrings[mk]!.insert(dateString(from: start))
            }
            let effectiveEnd = event.endDate ?? today
            let mk = monthKey(for: effectiveEnd)
            minMK = min(minMK, mk)
            maxMK = max(maxMK, mk)
            ensureMonth(mk)
            monthToDateStrings[mk]!.insert(dateString(from: effectiveEnd))
        }

        // Ensure every month in the range exists in the map
        for mk in (minMK - 1)...(maxMK + 1) { ensureMonth(mk) }
        minMK -= 1
        maxMK += 1

        // ── 2. Walk months newest → oldest, assign Y positions ─────────────
        // Newest month is at the top (smallest Y).
        var dateMeta: [String: (y: CGFloat, heightAbove: CGFloat, heightBelow: CGFloat)] = [:]
        var monthMeta: [(mk: Int, year: Int, month: Int, y: CGFloat, height: CGFloat)] = []
        var curY: CGFloat = 0

        for mk in stride(from: maxMK, through: minMK, by: -1) {
            let year = mk / 12
            let month = mk % 12

            let dateStrings = (monthToDateStrings[mk] ?? []).sorted(by: >)   // newest first
            let monthYStart = curY

            if dateStrings.isEmpty {
                curY += Self.emptyMonthHeight
            } else {
                curY += 6   // small top padding before first date in month
            }

            for ds in dateStrings {
                // Find events whose start or end (or today if ongoing) == ds
                let relevant = events.filter { ev in
                    let evStart = ev.startDate.map { Self.dateString(from: $0) } ?? ""
                    let evEnd   = (ev.endDate ?? today).let { Self.dateString(from: $0) }
                    return evStart == ds || evEnd == ds
                }

                var maxAbove: CGFloat = 0
                var maxBelow: CGFloat = 0

                for ev in relevant {
                    let evStartStr = ev.startDate.map { Self.dateString(from: $0) } ?? ""
                    let evEndStr   = Self.dateString(from: ev.endDate ?? today)
                    let h = cardHeight(for: ev,
                                       focusedID: focusedEventID,
                                       expandedID: expandedEventID)
                    if evStartStr == ds { maxAbove = max(maxAbove, h) }
                    if evEndStr == ds   { maxBelow = max(maxBelow, h) }
                }

                let dateLineY = curY + maxAbove
                dateMeta[ds] = (y: dateLineY, heightAbove: maxAbove, heightBelow: maxBelow)
                curY = dateLineY + maxBelow + Self.dateRowBuffer
            }

            let monthHeight = max(curY - monthYStart, Self.minActiveMonthHeight)
            monthMeta.append((mk: mk, year: year, month: month, y: monthYStart, height: monthHeight))
        }

        let totalHeight = curY

        // ── 3. Build output rows ────────────────────────────────────────────
        let monthRows: [TimelineMonthRow] = monthMeta.map { m in
            TimelineMonthRow(
                year: m.year,
                month: m.month,
                y: m.y,
                height: m.height,
                isJanuary: m.month == 0
            )
        }

        // Resolve Y for any date string; fall back to month-top if unregistered
        func yForDate(_ ds: String) -> CGFloat {
            if let meta = dateMeta[ds] { return meta.y }
            // parse month key from ds and use month Y
            if let date = Self.date(from: ds) {
                let mk = monthKey(for: date)
                return monthMeta.first(where: { $0.mk == mk })?.y ?? 0
            }
            return 0
        }

        var dateRows: [TimelineDateRow] = dateMeta.compactMap { ds, meta in
            guard let date = Self.date(from: ds) else { return nil }
            let eventIDs = events.compactMap { ev -> UUID? in
                let evStartStr = ev.startDate.map { Self.dateString(from: $0) } ?? ""
                let evEndStr   = Self.dateString(from: ev.endDate ?? today)
                guard evStartStr == ds || evEndStr == ds else { return nil }
                return ev.id
            }
            return TimelineDateRow(
                dateStr: ds,
                date: date,
                y: meta.y,
                isToday: ds == todayStr,
                eventIDs: eventIDs
            )
        }
        dateRows.sort { $0.y < $1.y }    // top of scroll = newest = smallest Y

        // ── 4. Lane assignment (greedy interval coloring) ───────────────────
        // Sort events by start date ascending for stable assignment
        let sorted = events
            .filter { $0.startDate != nil }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }

        struct Interval { var sk: Int; var ek: Int }
        var lanes: [[Interval]] = []
        var segments: [TimelineLaneSegment] = []

        for event in sorted {
            guard let start = event.startDate else { continue }
            let end = event.endDate ?? today
            let sk = monthKey(for: start)
            let ek = monthKey(for: end)

            var assigned = -1
            for (i, lane) in lanes.enumerated() {
                let overlaps = lane.contains { r in sk <= r.ek && ek >= r.sk }
                if !overlaps { assigned = i; break }
            }
            if assigned == -1 { assigned = lanes.count; lanes.append([]) }
            lanes[assigned].append(Interval(sk: sk, ek: ek))

            let startDS = Self.dateString(from: start)
            let endDS   = Self.dateString(from: end)

            segments.append(TimelineLaneSegment(
                id: event.id,
                event: event,
                lane: assigned,
                startY: yForDate(startDS),
                endY: yForDate(endDS),
                ongoing: event.endDate == nil
            ))
        }

        let numLanes = max(lanes.count, 1)
        let todayY = yForDate(todayStr)

        return TimelineLayout(
            months: monthRows,
            dateRows: dateRows,
            segments: segments,
            totalHeight: totalHeight,
            numLanes: numLanes,
            todayY: todayY,
            todayStr: todayStr
        )
    }

    // MARK: - Helpers

    private static func cardHeight(
        for event: LSEvent,
        focusedID: UUID?,
        expandedID: UUID?
    ) -> CGFloat {
        if event.id == expandedID { return expandedCardHeight }
        if event.id == focusedID  { return summaryCardHeight }
        return collapsedCardHeight
    }

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

private extension Optional {
    func `let`<T>(_ transform: (Wrapped) -> T) -> T? {
        guard let self else { return nil }
        return transform(self)
    }
}

extension Date {
    var dateString: String { TimelineLayout.dateString(from: self) }
}
