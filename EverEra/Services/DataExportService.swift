//
//  DataExportService.swift
//  EverEra
//
//  JSON backup and restore for the full EverEra data graph.
//  Documents are embedded as base64-encoded file data so the archive is portable.
//

import Foundation
import SwiftData

// MARK: - Codable export structs

struct EverEraArchive: Codable {
    var version: Int = 1
    var exportedAt: Date = Date()
    var entities: [EntityArchive]
}

struct EntityArchive: Codable {
    var id: UUID
    var name: String
    var type: String
    var notes: String
    var createdAt: Date
    var events: [EventArchive]
    var properties: [PropertyArchive]
}

struct EventArchive: Codable {
    var id: UUID
    var title: String
    var category: String
    var notes: String
    var startDate: Date?
    var endDate: Date?
    var documents: [DocumentArchive]
    var properties: [PropertyArchive]
}

struct PropertyArchive: Codable {
    var id: UUID
    var key: String
    var valueType: String
    var displayOrder: Int
    var isTemplateField: Bool
    var stringValue: String?
    var dateValue: Date?
    var numberValue: Double?
    var urlString: String?
}

struct DocumentArchive: Codable {
    var id: UUID
    var displayName: String
    var kind: String
    var ocrContent: String
    var inferredSummary: String
    var importedAt: Date
    /// Base64-encoded file data (nil if the file is missing on disk)
    var fileData: String?
    /// Original filename extension for restore
    var fileExtension: String?
}

// MARK: - DataExportService

@MainActor
final class DataExportService {

    // MARK: Export

    /// Serialises all entities and their relationships to a JSON `Data` blob.
    static func exportJSON(entities: [LSEntity]) throws -> Data {
        let archive = EverEraArchive(
            entities: entities.map { archiveEntity($0) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    private static func archiveEntity(_ entity: LSEntity) -> EntityArchive {
        EntityArchive(
            id: entity.id,
            name: entity.name,
            type: entity.type.rawValue,
            notes: entity.notes,
            createdAt: entity.createdAt,
            events: entity.events.map { archiveEvent($0) },
            properties: entity.properties.map { archiveProperty($0) }
        )
    }

    private static func archiveEvent(_ event: LSEvent) -> EventArchive {
        EventArchive(
            id: event.id,
            title: event.title,
            category: event.category.rawValue,
            notes: event.notes,
            startDate: event.startDate,
            endDate: event.endDate,
            documents: event.documents.map { archiveDocument($0) },
            properties: event.properties.map { archiveProperty($0) }
        )
    }

    private static func archiveProperty(_ prop: LSProperty) -> PropertyArchive {
        PropertyArchive(
            id: prop.id,
            key: prop.key,
            valueType: prop.valueType.rawValue,
            displayOrder: prop.displayOrder,
            isTemplateField: prop.isTemplateField,
            stringValue: prop.stringValue,
            dateValue: prop.dateValue,
            numberValue: prop.numberValue,
            urlString: prop.urlString
        )
    }

    private static func archiveDocument(_ doc: LSDocument) -> DocumentArchive {
        var fileData: String?
        var fileExt: String?
        if let url = doc.resolvedURL(),
           let data = try? Data(contentsOf: url) {
            fileData = data.base64EncodedString()
            fileExt = url.pathExtension
        }
        return DocumentArchive(
            id: doc.id,
            displayName: doc.displayName,
            kind: doc.kind.rawValue,
            ocrContent: doc.ocrContent,
            inferredSummary: doc.inferredSummary,
            importedAt: doc.importedAt,
            fileData: fileData,
            fileExtension: fileExt
        )
    }

    // MARK: Import

    /// Decodes a JSON archive and inserts all objects into the provided model context.
    /// Existing data is NOT cleared — this is an additive import.
    static func importJSON(_ data: Data, into context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(EverEraArchive.self, from: data)

        for entityArchive in archive.entities {
            let entity = LSEntity(
                id: entityArchive.id,
                name: entityArchive.name,
                type: EntityType(rawValue: entityArchive.type) ?? .other,
                notes: entityArchive.notes,
                createdAt: entityArchive.createdAt
            )
            context.insert(entity)

            for propArchive in entityArchive.properties {
                let prop = restoreProperty(propArchive)
                context.insert(prop)
                prop.entity = entity
            }

            for eventArchive in entityArchive.events {
                let event = LSEvent(
                    id: eventArchive.id,
                    title: eventArchive.title,
                    category: EventCategory(rawValue: eventArchive.category) ?? .other,
                    notes: eventArchive.notes,
                    startDate: eventArchive.startDate,
                    endDate: eventArchive.endDate
                )
                context.insert(event)
                event.entity = entity

                for propArchive in eventArchive.properties {
                    let prop = restoreProperty(propArchive)
                    context.insert(prop)
                    prop.event = event
                }

                for docArchive in eventArchive.documents {
                    let doc = LSDocument(
                        id: docArchive.id,
                        displayName: docArchive.displayName,
                        kind: DocumentKind(rawValue: docArchive.kind) ?? .other,
                        ocrContent: docArchive.ocrContent,
                        inferredSummary: docArchive.inferredSummary,
                        importedAt: docArchive.importedAt
                    )

                    // Restore embedded file data to the app container
                    if let b64 = docArchive.fileData,
                       let fileData = Data(base64Encoded: b64) {
                        let ext = docArchive.fileExtension ?? "bin"
                        let filename = "\(UUID().uuidString)_\(docArchive.displayName).\(ext)"
                        let dest = LSDocument.storageDirectory.appendingPathComponent(filename)
                        try? fileData.write(to: dest)
                        doc.storedFileName = filename
                    }

                    context.insert(doc)
                    doc.event = event
                }
            }
        }
    }

    private static func restoreProperty(_ archive: PropertyArchive) -> LSProperty {
        let prop = LSProperty(
            id: archive.id,
            key: archive.key,
            valueType: PropertyValueType(rawValue: archive.valueType) ?? .string,
            displayOrder: archive.displayOrder,
            isTemplateField: archive.isTemplateField
        )
        prop.stringValue = archive.stringValue
        prop.dateValue = archive.dateValue
        prop.numberValue = archive.numberValue
        prop.urlString = archive.urlString
        return prop
    }
}

// MARK: - EverEraDocument (FileDocument for fileExporter)

import SwiftUI
import UniformTypeIdentifiers

struct EverEraJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
