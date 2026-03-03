//
//  LSEntity.swift
//  EverEra
//
//  Persistent model representing a long-lived entity in the Life Graph
//  (Employer, Residence, Vehicle, Person, Project, etc.)
//

import Foundation
import SwiftData

// MARK: - EntityType

enum EntityType: String, Codable, CaseIterable, Sendable {
    case person       = "Person"
    case employer     = "Employer"
    case residence    = "Residence"
    case vehicle      = "Vehicle"
    case project      = "Project"
    case institution  = "Institution"
    case asset        = "Asset"
    case other        = "Other"

    var systemImage: String {
        switch self {
        case .person:       return "person.fill"
        case .employer:     return "building.2.fill"
        case .residence:    return "house.fill"
        case .vehicle:      return "car.fill"
        case .project:      return "folder.fill"
        case .institution:  return "graduationcap.fill"
        case .asset:        return "tag.fill"
        case .other:        return "circle.fill"
        }
    }
}

// MARK: - LSEntity

@Model
final class LSEntity {
    #Unique<LSEntity>([\.id])
    #Index<LSEntity>([\.name])

    var id: UUID
    var name: String
    var type: EntityType
    var notes: String
    var createdAt: Date

    // Optional location for spatial view (latitude / longitude)
    var locationLatitude: Double?
    var locationLongitude: Double?
    var locationLabel: String?

    @Relationship(deleteRule: .cascade, inverse: \LSEvent.entity)
    var events: [LSEvent] = []

    @Relationship(deleteRule: .cascade, inverse: \LSProperty.entity)
    var properties: [LSProperty] = []

    init(
        id: UUID = UUID(),
        name: String,
        type: EntityType,
        notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.notes = notes
        self.createdAt = createdAt
    }

    /// Earliest event start date, used to sort the entity on the timeline.
    var timelineStartDate: Date? {
        events.compactMap(\.startDate).min()
    }

    /// Most recent event end date (or nil if still active).
    var timelineEndDate: Date? {
        let ends = events.compactMap(\.endDate)
        return ends.isEmpty ? nil : ends.max()
    }

    /// Look up a property by key name (case-insensitive).
    func property(named key: String) -> LSProperty? {
        properties.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }
    }

    /// Returns true when at least one event has no end date (entity still active).
    var isActive: Bool {
        events.contains { $0.endDate == nil }
    }
}
