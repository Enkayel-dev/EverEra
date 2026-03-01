//
//  EverEraApp.swift
//  EverEra
//
//  App entry point.  Configures the SwiftData ModelContainer for the full
//  LifeGraph schema: LSEntity → LSEvent → LSDocument.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main
struct EverEraApp: App {

    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            LSEntity.self,
            LSEvent.self,
            LSDocument.self,
            LSProperty.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            EverEraCommands()
        }
    }
}

// MARK: - EverEraCommands

struct EverEraCommands: Commands {
    @Environment(\.modelContext) private var modelContext
    @Query private var entities: [LSEntity]

    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var exportDocument: EverEraJSONDocument?
    @State private var exportError: String?
    @State private var importError: String?

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Divider()

            Button("Export Archive…") {
                do {
                    let data = try DataExportService.exportJSON(entities: entities)
                    exportDocument = EverEraJSONDocument(data: data)
                    showingExporter = true
                } catch {
                    exportError = error.localizedDescription
                }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Import Archive…") {
                showingImporter = true
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }
    }
}
