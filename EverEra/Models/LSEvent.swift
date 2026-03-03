//
//  LSEvent.swift
//  EverEra
//
//  An occurrence in time anchored to an LSEntity.
//  Examples: Employment period, Lease term, Vehicle ownership, Project sprint.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - EventCategory

enum EventCategory: String, Codable, CaseIterable, Sendable {
    case employment   = "Employment"
    case housing      = "Housing"
    case education    = "Education"
    case ownership    = "Ownership"
    case health       = "Health"
    case travel       = "Travel"
    case financial    = "Financial"
    case milestone    = "Milestone"
    case other        = "Other"

    var systemImage: String {
        switch self {
        case .employment:   return "briefcase.fill"
        case .housing:      return "house.fill"
        case .education:    return "book.fill"
        case .ownership:    return "tag.fill"
        case .health:       return "heart.fill"
        case .travel:       return "airplane"
        case .financial:    return "dollarsign.circle.fill"
        case .milestone:    return "star.fill"
        case .other:        return "circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .employment:   return Color(red: 0.133, green: 0.773, blue: 0.369) // #22C55E
        case .housing:      return Color(red: 0.290, green: 0.565, blue: 0.851) // #4A90D9
        case .education:    return Color(red: 0.961, green: 0.620, blue: 0.043) // #F59E0B
        case .ownership:    return Color(red: 0.659, green: 0.333, blue: 0.969) // #A855F7
        case .health:       return Color(red: 0.937, green: 0.267, blue: 0.267) // #EF4444
        case .travel:       return Color(red: 0.024, green: 0.714, blue: 0.831) // #06B6D4
        case .financial:    return Color(red: 0.063, green: 0.725, blue: 0.506) // #10B981
        case .milestone:    return Color(red: 0.925, green: 0.282, blue: 0.600) // #EC4899
        case .other:        return Color(red: 0.545, green: 0.580, blue: 0.620) // #8B949E
        }
    }
}

// MARK: - LSEvent

@Model
final class LSEvent {
    #Unique<LSEvent>([\.id])
    #Index<LSEvent>([\.startDate])

    var id: UUID
    var title: String
    var category: EventCategory
    var notes: String

    var startDate: Date?
    var endDate: Date?

    // Back-reference to owning entity; SwiftData manages the inverse.
    var entity: LSEntity?

    @Relationship(deleteRule: .cascade, inverse: \LSDocument.event)
    var documents: [LSDocument] = []

    @Relationship(deleteRule: .cascade, inverse: \LSProperty.event)
    var properties: [LSProperty] = []

    init(
        id: UUID = UUID(),
        title: String,
        category: EventCategory,
        notes: String = "",
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
    }

    /// Look up a property by key name (case-insensitive).
    func property(named key: String) -> LSProperty? {
        properties.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }
    }

    /// Duration string for display ("Jan 2020 – Present", "2019 – 2022").
    var durationLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM yyyy"

        let start = startDate.map { fmt.string(from: $0) } ?? "?"
        let end   = endDate.map   { fmt.string(from: $0) } ?? "Present"
        return "\(start) – \(end)"
    }

    /// True when the event has no end date (ongoing).
    var isOngoing: Bool { endDate == nil }
}
